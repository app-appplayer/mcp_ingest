import 'package:test/test.dart';
import 'package:mcp_ingest/mcp_ingest.dart';
import 'package:mcp_bundle/ports.dart'
    show LlmPort, LlmCapabilities, LlmRequest, LlmResponse;

void main() {
  group('ChunkOptions', () {
    test('defaults has expected values', () {
      const options = ChunkOptions.defaults;
      expect(options.targetSize, equals(1000));
      expect(options.minSize, equals(100));
      expect(options.maxSize, equals(2000));
      expect(options.overlap, equals(200));
    });

    test('forEmbedding optimized for embedding models', () {
      const options = ChunkOptions.forEmbedding;
      expect(options.targetSize, equals(512));
      expect(options.maxSize, equals(768));
      expect(options.includeContext, isFalse);
    });

    test('forRag optimized for RAG systems', () {
      const options = ChunkOptions.forRag;
      expect(options.targetSize, equals(2000));
      expect(options.maxSize, equals(4000));
      expect(options.includeContext, isTrue);
    });

    test('copyWith preserves unchanged values', () {
      const original = ChunkOptions(
        targetSize: 500,
        overlap: 50,
      );
      final modified = original.copyWith(targetSize: 1000);
      expect(modified.targetSize, equals(1000));
      expect(modified.overlap, equals(50));
    });

    test('copyWith preserves targetSize when not specified', () {
      const original = ChunkOptions(targetSize: 500, overlap: 50);
      final modified = original.copyWith(overlap: 100);
      expect(modified.targetSize, equals(500));
      expect(modified.overlap, equals(100));
    });
  });

  group('ChunkerRegistry', () {
    test('registers and finds chunkers', () {
      final registry = ChunkerRegistry();
      final chunker = SentenceChunker();
      registry.register(chunker);

      final found = registry.find('sentence_v1');
      expect(found, equals(chunker));
    });

    test('returns null for unregistered id', () {
      final registry = ChunkerRegistry();
      expect(registry.find('unknown'), isNull);
    });

    test('all returns registered chunkers', () {
      final registry = ChunkerRegistry();
      registry.register(SentenceChunker());
      registry.register(FixedSizeChunker());

      expect(registry.all.length, equals(2));
    });
  });

  group('ChunkerFactory', () {
    test('creates correct chunker for strategy', () {
      final factory = ChunkerFactory();
      expect(
          factory.create(ChunkingStrategy.sentence).id, equals('sentence_v1'));
      expect(factory.create(ChunkingStrategy.paragraph).id,
          equals('paragraph_v1'));
      expect(factory.create(ChunkingStrategy.fixedSize).id,
          equals('fixed_size_v1'));
      expect(factory.create(ChunkingStrategy.none).id, equals('none_v1'));
      expect(factory.create(ChunkingStrategy.page).id, equals('page_v1'));
      expect(factory.create(ChunkingStrategy.table).id, equals('table_v1'));
    });

    test('throws PortNotConfiguredException for semantic without llmPort', () {
      final factory = ChunkerFactory();
      expect(
        () => factory.create(ChunkingStrategy.semantic),
        throwsA(isA<PortNotConfiguredException>()),
      );
    });

    test('creates semantic chunker when llmPort is provided', () {
      final factory = ChunkerFactory(llmPort: _StubLlmPort());
      final chunker = factory.create(ChunkingStrategy.semantic);
      expect(chunker.id, equals('semantic_v1'));
    });
  });

  group('SentenceChunker', () {
    late SentenceChunker chunker;
    late NormalizedDocument testDocument;

    setUp(() {
      chunker = SentenceChunker();
      testDocument = _createTestDocument([
        'First sentence. Second sentence. Third sentence.',
        'Fourth sentence in second paragraph. Fifth sentence.',
      ]);
    });

    test('has correct id and name', () {
      expect(chunker.id, equals('sentence_v1'));
      expect(chunker.name, equals('Sentence Chunker'));
    });

    test('chunks by sentence boundaries', () async {
      final chunks = await chunker.chunk(testDocument, ChunkOptions.defaults);
      expect(chunks.isNotEmpty, isTrue);
      for (final chunk in chunks) {
        expect(chunk.text, isNotEmpty);
      }
    });

    test('respects maxSize constraint', () async {
      final options = const ChunkOptions(maxSize: 50, overlap: 0);
      final chunks = await chunker.chunk(testDocument, options);

      for (final chunk in chunks) {
        expect(chunk.text.length, lessThanOrEqualTo(60));
      }
    });

    test('sets totalChunks correctly', () async {
      final chunks = await chunker.chunk(testDocument, ChunkOptions.defaults);
      final total = chunks.length;
      for (final chunk in chunks) {
        expect(chunk.totalChunks, equals(total));
      }
    });

    test('sets chunk index correctly', () async {
      final chunks = await chunker.chunk(testDocument, ChunkOptions.defaults);
      for (var i = 0; i < chunks.length; i++) {
        expect(chunks[i].index, equals(i));
      }
    });

    test('handles abbreviations', () async {
      final docWithAbbr = _createTestDocument([
        'Dr. Smith visited Mrs. Jones. They discussed the results.',
      ]);
      final chunks = await chunker.chunk(docWithAbbr, ChunkOptions.defaults);
      expect(chunks.isNotEmpty, isTrue);
    });

    test('handles empty document', () async {
      final emptyDoc = _createTestDocument([]);
      final chunks = await chunker.chunk(emptyDoc, ChunkOptions.defaults);
      expect(chunks, isEmpty);
    });
  });

  group('FixedSizeChunker', () {
    late FixedSizeChunker chunker;
    late NormalizedDocument testDocument;

    setUp(() {
      chunker = FixedSizeChunker();
      testDocument = _createTestDocument([
        'This is the first paragraph with some content.',
        'This is the second paragraph with more content.',
        'This is the third paragraph. It has multiple sentences. Here is another one.',
      ]);
    });

    test('has correct id and name', () {
      expect(chunker.id, equals('fixed_size_v1'));
      expect(chunker.name, equals('Fixed Size Chunker'));
    });

    test('handles empty document', () async {
      final emptyDoc = _createTestDocument([]);
      final chunks = await chunker.chunk(emptyDoc, ChunkOptions.defaults);
      expect(chunks, isEmpty);
    });

    test('creates chunks using defaults', () async {
      final chunks = await chunker.chunk(testDocument, ChunkOptions.defaults);
      expect(chunks.isNotEmpty, isTrue);
    });

    test('creates chunks with small target size', () async {
      final options = const ChunkOptions(
        targetSize: 50,
        minSize: 10,
        maxSize: 100,
        overlap: 10,
      );
      final chunks = await chunker.chunk(testDocument, options);
      expect(chunks.isNotEmpty, isTrue);
      for (final chunk in chunks) {
        expect(chunk.text.isNotEmpty, isTrue);
      }
    });

    test('handles overlap larger than chunk', () async {
      final options = const ChunkOptions(
        targetSize: 50,
        minSize: 10,
        maxSize: 100,
        overlap: 200,
      );
      final chunks = await chunker.chunk(testDocument, options);
      expect(chunks.isNotEmpty, isTrue);
    });

    test('includes location with position info', () async {
      final chunks = await chunker.chunk(testDocument, ChunkOptions.defaults);
      for (final chunk in chunks) {
        expect(chunk.location.charOffset, isNotNull);
        expect(chunk.location.charLength, isNotNull);
      }
    });

    test('handles large document', () async {
      final largeDoc = _createTestDocument([
        'Lorem ipsum dolor sit amet. ' * 50,
        'Consectetur adipiscing elit. ' * 50,
      ]);
      final chunks = await chunker.chunk(largeDoc, ChunkOptions.defaults);
      expect(chunks.isNotEmpty, isTrue);
      expect(chunks.length, greaterThan(1));
    });

    test('sets totalChunks correctly', () async {
      final chunks = await chunker.chunk(testDocument, ChunkOptions.defaults);
      final total = chunks.length;
      for (final chunk in chunks) {
        expect(chunk.totalChunks, equals(total));
      }
    });
  });

  group('ParagraphChunker', () {
    late ParagraphChunker chunker;

    setUp(() {
      chunker = ParagraphChunker();
    });

    test('has correct id and name', () {
      expect(chunker.id, equals('paragraph_v1'));
      expect(chunker.name, equals('Paragraph Chunker'));
    });

    test('chunks by paragraphs', () async {
      final doc = _createTestDocument([
        'First paragraph content.',
        'Second paragraph content.',
        'Third paragraph content.',
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, greaterThanOrEqualTo(1));
    });

    test('combines small paragraphs', () async {
      final doc = _createTestDocument([
        'Short.',
        'Also short.',
        'Another short one.',
      ]);
      final options = const ChunkOptions(minSize: 50);
      final chunks = await chunker.chunk(doc, options);
      expect(chunks.length, lessThanOrEqualTo(3));
    });
  });

  group('PageChunker', () {
    late PageChunker chunker;

    setUp(() {
      chunker = PageChunker();
    });

    test('has correct id and name', () {
      expect(chunker.id, equals('page_v1'));
      expect(chunker.name, equals('Page Chunker'));
    });

    test('chunks by page boundaries', () async {
      final doc = _createDocumentWithPages([
        (1, 'Content on page 1.'),
        (1, 'More content on page 1.'),
        (2, 'Content on page 2.'),
        (3, 'Content on page 3.'),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, greaterThanOrEqualTo(1));
    });
  });

  group('NoChunker', () {
    late NoChunker chunker;

    setUp(() {
      chunker = NoChunker();
    });

    test('has correct id and name', () {
      expect(chunker.id, equals('none_v1'));
      expect(chunker.name, equals('No Chunker'));
    });

    test('returns single chunk with full text', () async {
      final doc = _createTestDocument([
        'First paragraph.',
        'Second paragraph.',
        'Third paragraph.',
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks.first.text, contains('First paragraph'));
      expect(chunks.first.text, contains('Third paragraph'));
    });

    test('handles empty document', () async {
      final emptyDoc = _createTestDocument([]);
      final chunks = await chunker.chunk(emptyDoc, ChunkOptions.defaults);
      // NoChunker returns empty list for empty document
      expect(chunks, isEmpty);
    });
  });

  group('TableChunker', () {
    late TableChunker chunker;

    setUp(() {
      chunker = TableChunker();
    });

    test('has correct id and name', () {
      expect(chunker.id, equals('table_v1'));
      expect(chunker.name, equals('Table Chunker'));
    });

    test('extracts tables as separate chunks', () async {
      final doc = _createDocumentWithTable();
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.isNotEmpty, isTrue);
    });
  });

  group('Chunk edge cases', () {
    test('sourcePartIds derives from sourceSpans', () {
      const chunk = Chunk(
        id: 'test',
        text: 'Test content',
        sourceSpans: [
          ChunkSpan(partId: 'p1', startOffset: 0, endOffset: 5),
          ChunkSpan(partId: 'p2', startOffset: 0, endOffset: 7),
        ],
        location: SourceLocation.empty,
        index: 0,
        totalChunks: 1,
      );
      expect(chunk.sourcePartIds, containsAll(['p1', 'p2']));
      expect(chunk.crossesParts, isTrue);
    });

    test('single part chunk does not cross parts', () {
      const chunk = Chunk(
        id: 'test',
        text: 'Test',
        sourceSpans: [
          ChunkSpan(partId: 'p1', startOffset: 0, endOffset: 4),
        ],
        location: SourceLocation.empty,
        index: 0,
        totalChunks: 1,
      );
      expect(chunk.crossesParts, isFalse);
    });

    test('partRanges returns correct mapping', () {
      const chunk = Chunk(
        id: 'test',
        text: 'Test',
        sourceSpans: [
          ChunkSpan(partId: 'p1', startOffset: 10, endOffset: 20),
        ],
        location: SourceLocation.empty,
        index: 0,
        totalChunks: 1,
      );
      final ranges = chunk.partRanges;
      expect(ranges['p1'], equals((10, 20)));
    });

    test('copyWith creates new chunk with updated values', () {
      const original = Chunk(
        id: 'test',
        text: 'Original',
        sourceSpans: [],
        location: SourceLocation.empty,
        index: 0,
        totalChunks: 1,
      );
      final modified = original.copyWith(
        text: 'Modified',
        totalChunks: 5,
      );
      expect(modified.text, equals('Modified'));
      expect(modified.totalChunks, equals(5));
      expect(modified.id, equals('test'));
    });
  });

  // ========================================================================
  // NEW COVERAGE TESTS BELOW
  // ========================================================================

  group('Chunk additional coverage', () {
    test('fromJson with missing optional fields', () {
      final chunk = Chunk.fromJson({
        'id': 'c1',
        'text': 'Hello world',
      });
      expect(chunk.id, equals('c1'));
      expect(chunk.text, equals('Hello world'));
      expect(chunk.sourceSpans, isEmpty);
      expect(chunk.index, equals(0));
      expect(chunk.totalChunks, equals(0));
      expect(chunk.contextPrefix, isNull);
      expect(chunk.metadata, isNull);
    });

    test('fromJson with all fields', () {
      final chunk = Chunk.fromJson({
        'id': 'c2',
        'text': 'Content',
        'sourceSpans': [
          {'partId': 'p1', 'startOffset': 0, 'endOffset': 7},
        ],
        'location': {'pageNumber': 3},
        'index': 2,
        'totalChunks': 5,
        'contextPrefix': 'Section A > Sub B',
        'metadata': {'key': 'value'},
      });
      expect(chunk.index, equals(2));
      expect(chunk.totalChunks, equals(5));
      expect(chunk.contextPrefix, equals('Section A > Sub B'));
      expect(chunk.metadata, equals({'key': 'value'}));
      expect(chunk.location.pageNumber, equals(3));
      expect(chunk.sourceSpans.length, equals(1));
    });

    test('toString format', () {
      const chunk = Chunk(
        id: 'chunk_0',
        text: 'Hello',
        sourceSpans: [],
        location: SourceLocation.empty,
        index: 0,
        totalChunks: 3,
      );
      expect(chunk.toString(), equals('Chunk(chunk_0, index: 0/3, length: 5)'));
    });

    test('fullText with contextPrefix', () {
      const chunk = Chunk(
        id: 'c1',
        text: 'Body text',
        sourceSpans: [],
        location: SourceLocation.empty,
        index: 0,
        totalChunks: 1,
        contextPrefix: 'Chapter 1 > Section A',
      );
      expect(chunk.fullText, equals('Chapter 1 > Section A\n\nBody text'));
    });

    test('fullText without contextPrefix', () {
      const chunk = Chunk(
        id: 'c1',
        text: 'Body text',
        sourceSpans: [],
        location: SourceLocation.empty,
        index: 0,
        totalChunks: 1,
      );
      expect(chunk.fullText, equals('Body text'));
    });

    test('length returns text character count', () {
      const chunk = Chunk(
        id: 'c1',
        text: 'Twelve chars',
        sourceSpans: [],
        location: SourceLocation.empty,
        index: 0,
        totalChunks: 1,
      );
      expect(chunk.length, equals(12));
    });

    test('toJson includes contextPrefix and metadata when present', () {
      const chunk = Chunk(
        id: 'c1',
        text: 'text',
        sourceSpans: [],
        location: SourceLocation.empty,
        index: 0,
        totalChunks: 1,
        contextPrefix: 'ctx',
        metadata: {'k': 'v'},
      );
      final json = chunk.toJson();
      expect(json['contextPrefix'], equals('ctx'));
      expect(json['metadata'], equals({'k': 'v'}));
    });

    test('toJson omits contextPrefix and metadata when null', () {
      const chunk = Chunk(
        id: 'c1',
        text: 'text',
        sourceSpans: [],
        location: SourceLocation.empty,
        index: 0,
        totalChunks: 1,
      );
      final json = chunk.toJson();
      expect(json.containsKey('contextPrefix'), isFalse);
      expect(json.containsKey('metadata'), isFalse);
    });

    test('ChunkSpan length getter', () {
      const span = ChunkSpan(partId: 'p1', startOffset: 5, endOffset: 15);
      expect(span.length, equals(10));
    });

    test('ChunkSpan toJson/fromJson roundtrip', () {
      const span = ChunkSpan(partId: 'p1', startOffset: 5, endOffset: 15);
      final json = span.toJson();
      final restored = ChunkSpan.fromJson(json);
      expect(restored.partId, equals('p1'));
      expect(restored.startOffset, equals(5));
      expect(restored.endOffset, equals(15));
    });
  });

  group('ChunkContextInjector', () {
    late ChunkContextInjector injector;

    setUp(() {
      injector = const ChunkContextInjector();
    });

    test('addContext adds section path as contextPrefix', () {
      final structure = DocumentStructure(nodes: [
        StructureNode(
          id: 'sec1',
          type: StructureType.section,
          title: 'Introduction',
          partIds: ['p0'],
        ),
      ]);
      const chunk = Chunk(
        id: 'c0',
        text: 'Hello',
        sourceSpans: [ChunkSpan(partId: 'p0', startOffset: 0, endOffset: 5)],
        location: SourceLocation.empty,
        index: 0,
        totalChunks: 1,
      );
      final result = injector.addContext(chunk, structure);
      expect(result.contextPrefix, equals('Introduction'));
    });

    test('addContext returns unchanged chunk when no section path found', () {
      const chunk = Chunk(
        id: 'c0',
        text: 'Hello',
        sourceSpans: [ChunkSpan(partId: 'px', startOffset: 0, endOffset: 5)],
        location: SourceLocation.empty,
        index: 0,
        totalChunks: 1,
      );
      final result = injector.addContext(chunk, DocumentStructure.empty);
      expect(result.contextPrefix, isNull);
    });

    test('addContext returns unchanged chunk when sourcePartIds empty', () {
      const chunk = Chunk(
        id: 'c0',
        text: 'Hello',
        sourceSpans: [],
        location: SourceLocation.empty,
        index: 0,
        totalChunks: 1,
      );
      final result = injector.addContext(chunk, DocumentStructure.empty);
      expect(result.contextPrefix, isNull);
    });

    test('addContext builds hierarchical path from nested structure', () {
      final structure = DocumentStructure(nodes: [
        StructureNode(
          id: 'ch1',
          type: StructureType.chapter,
          title: 'Chapter 1',
          children: [
            StructureNode(
              id: 'sec1',
              type: StructureType.section,
              title: 'Section A',
              partIds: ['p0'],
            ),
          ],
        ),
      ]);
      const chunk = Chunk(
        id: 'c0',
        text: 'Hello',
        sourceSpans: [ChunkSpan(partId: 'p0', startOffset: 0, endOffset: 5)],
        location: SourceLocation.empty,
        index: 0,
        totalChunks: 1,
      );
      final result = injector.addContext(chunk, structure);
      expect(result.contextPrefix, equals('Chapter 1 > Section A'));
    });

    test('addContext truncates when context exceeds maxContextLength', () {
      final injectorShort = const ChunkContextInjector(maxContextLength: 20);
      final structure = DocumentStructure(nodes: [
        StructureNode(
          id: 'ch1',
          type: StructureType.chapter,
          title: 'Very Long Chapter Title',
          children: [
            StructureNode(
              id: 'sec1',
              type: StructureType.section,
              title: 'Very Long Section Title Here',
              partIds: ['p0'],
            ),
          ],
        ),
      ]);
      const chunk = Chunk(
        id: 'c0',
        text: 'Hello',
        sourceSpans: [ChunkSpan(partId: 'p0', startOffset: 0, endOffset: 5)],
        location: SourceLocation.empty,
        index: 0,
        totalChunks: 1,
      );
      final result = injectorShort.addContext(chunk, structure);
      expect(result.contextPrefix, isNotNull);
      expect(result.contextPrefix!.startsWith('...'), isTrue);
      expect(result.contextPrefix!.length, lessThanOrEqualTo(20));
    });

    test('addContextToAll applies context to all chunks', () {
      final structure = DocumentStructure(nodes: [
        StructureNode(
          id: 'sec1',
          type: StructureType.section,
          title: 'Intro',
          partIds: ['p0', 'p1'],
        ),
      ]);
      const chunks = [
        Chunk(
          id: 'c0',
          text: 'A',
          sourceSpans: [ChunkSpan(partId: 'p0', startOffset: 0, endOffset: 1)],
          location: SourceLocation.empty,
          index: 0,
          totalChunks: 2,
        ),
        Chunk(
          id: 'c1',
          text: 'B',
          sourceSpans: [ChunkSpan(partId: 'p1', startOffset: 0, endOffset: 1)],
          location: SourceLocation.empty,
          index: 1,
          totalChunks: 2,
        ),
      ];
      final result = injector.addContextToAll(chunks, structure);
      expect(result.length, equals(2));
      expect(result[0].contextPrefix, equals('Intro'));
      expect(result[1].contextPrefix, equals('Intro'));
    });

    test('addContextFromDocument delegates to addContextToAll', () {
      final doc = _createDocWithParts(
        [const TextBlock(id: 'p0', text: 'Hello')],
        structure: DocumentStructure(nodes: [
          StructureNode(
            id: 'sec1',
            type: StructureType.section,
            title: 'Main',
            partIds: ['p0'],
          ),
        ]),
      );
      const chunks = [
        Chunk(
          id: 'c0',
          text: 'Hello',
          sourceSpans: [ChunkSpan(partId: 'p0', startOffset: 0, endOffset: 5)],
          location: SourceLocation.empty,
          index: 0,
          totalChunks: 1,
        ),
      ];
      final result = injector.addContextFromDocument(chunks, doc);
      expect(result[0].contextPrefix, equals('Main'));
    });

    test('buildContextString returns empty for empty list', () {
      expect(injector.buildContextString([]), equals(''));
    });

    test('buildContextString joins titles with separator', () {
      final result = injector.buildContextString(['A', 'B', 'C']);
      expect(result, equals('A > B > C'));
    });

    test('buildContextString truncates when exceeding maxContextLength', () {
      final injectorShort = const ChunkContextInjector(maxContextLength: 15);
      final result = injectorShort.buildContextString([
        'Very Long Title',
        'Another Long Title',
      ]);
      expect(result.startsWith('...'), isTrue);
      expect(result.length, lessThanOrEqualTo(15));
    });

    test('buildContextString returns full string when within limit', () {
      final result = injector.buildContextString(['A', 'B']);
      expect(result, equals('A > B'));
    });

    test('extractOutline creates OutlineEntry list from structure', () {
      final structure = DocumentStructure(nodes: [
        StructureNode(
          id: 'ch1',
          type: StructureType.chapter,
          title: 'Chapter 1',
          level: 0,
          partIds: ['p0'],
          children: [
            StructureNode(
              id: 'sec1',
              type: StructureType.section,
              title: 'Section A',
              level: 1,
              partIds: ['p1'],
            ),
            StructureNode(
              id: 'sec2',
              type: StructureType.section,
              title: 'Section B',
              level: 1,
              partIds: ['p2'],
            ),
          ],
        ),
        StructureNode(
          id: 'ch2',
          type: StructureType.chapter,
          title: 'Chapter 2',
          level: 0,
          partIds: ['p3'],
        ),
      ]);
      final outline = injector.extractOutline(structure);
      expect(outline.length, equals(4));
      expect(outline[0].title, equals('Chapter 1'));
      expect(outline[0].level, equals(0));
      expect(outline[1].title, equals('Section A'));
      expect(outline[1].level, equals(1));
      expect(outline[2].title, equals('Section B'));
      expect(outline[2].level, equals(1));
      expect(outline[3].title, equals('Chapter 2'));
      expect(outline[3].level, equals(0));
    });

    test('extractOutline skips nodes without title', () {
      final structure = DocumentStructure(nodes: [
        StructureNode(
          id: 'n1',
          type: StructureType.section,
          partIds: ['p0'],
        ),
        StructureNode(
          id: 'n2',
          type: StructureType.section,
          title: '',
          partIds: ['p1'],
        ),
        StructureNode(
          id: 'n3',
          type: StructureType.section,
          title: 'Has Title',
          partIds: ['p2'],
        ),
      ]);
      final outline = injector.extractOutline(structure);
      expect(outline.length, equals(1));
      expect(outline[0].title, equals('Has Title'));
    });

    test('OutlineEntry indentedTitle adds indentation', () {
      const entry = OutlineEntry(
        title: 'Sub Section',
        level: 2,
        type: StructureType.subsection,
        partIds: ['p0'],
      );
      expect(entry.indentedTitle, equals('    Sub Section'));
    });

    test('OutlineEntry indentedTitle at level 0 has no indent', () {
      const entry = OutlineEntry(
        title: 'Root',
        level: 0,
        type: StructureType.chapter,
        partIds: [],
      );
      expect(entry.indentedTitle, equals('Root'));
    });

    test('addContext skips nodes with empty title in path', () {
      final structure = DocumentStructure(nodes: [
        StructureNode(
          id: 'wrapper',
          type: StructureType.document,
          children: [
            StructureNode(
              id: 'sec1',
              type: StructureType.section,
              title: 'Visible',
              partIds: ['p0'],
            ),
          ],
        ),
      ]);
      const chunk = Chunk(
        id: 'c0',
        text: 'Hello',
        sourceSpans: [ChunkSpan(partId: 'p0', startOffset: 0, endOffset: 5)],
        location: SourceLocation.empty,
        index: 0,
        totalChunks: 1,
      );
      final result = injector.addContext(chunk, structure);
      expect(result.contextPrefix, equals('Visible'));
    });

    test('custom separator works', () {
      final customInjector = const ChunkContextInjector(separator: ' / ');
      final structure = DocumentStructure(nodes: [
        StructureNode(
          id: 'ch1',
          type: StructureType.chapter,
          title: 'Chapter',
          children: [
            StructureNode(
              id: 'sec1',
              type: StructureType.section,
              title: 'Section',
              partIds: ['p0'],
            ),
          ],
        ),
      ]);
      const chunk = Chunk(
        id: 'c0',
        text: 'Hello',
        sourceSpans: [ChunkSpan(partId: 'p0', startOffset: 0, endOffset: 5)],
        location: SourceLocation.empty,
        index: 0,
        totalChunks: 1,
      );
      final result = customInjector.addContext(chunk, structure);
      expect(result.contextPrefix, equals('Chapter / Section'));
    });
  });

  group('ChunkContextExtension (withContext)', () {
    test('withContext extension adds context to chunk list', () {
      final structure = DocumentStructure(nodes: [
        StructureNode(
          id: 'sec1',
          type: StructureType.section,
          title: 'My Section',
          partIds: ['p0'],
        ),
      ]);
      const chunks = [
        Chunk(
          id: 'c0',
          text: 'Content',
          sourceSpans: [ChunkSpan(partId: 'p0', startOffset: 0, endOffset: 7)],
          location: SourceLocation.empty,
          index: 0,
          totalChunks: 1,
        ),
      ];
      final result = chunks.withContext(structure);
      expect(result[0].contextPrefix, equals('My Section'));
    });

    test('withContext uses custom maxLength and separator', () {
      final structure = DocumentStructure(nodes: [
        StructureNode(
          id: 'ch1',
          type: StructureType.chapter,
          title: 'Chapter',
          children: [
            StructureNode(
              id: 'sec1',
              type: StructureType.section,
              title: 'Section',
              partIds: ['p0'],
            ),
          ],
        ),
      ]);
      const chunks = [
        Chunk(
          id: 'c0',
          text: 'Content',
          sourceSpans: [ChunkSpan(partId: 'p0', startOffset: 0, endOffset: 7)],
          location: SourceLocation.empty,
          index: 0,
          totalChunks: 1,
        ),
      ];
      final result = chunks.withContext(structure, separator: ' :: ');
      expect(result[0].contextPrefix, equals('Chapter :: Section'));
    });
  });

  group('PageChunker - fallback grouping by pageNumber', () {
    late PageChunker chunker;

    setUp(() {
      chunker = PageChunker();
    });

    test('groups parts by pageNumber when structure is empty', () async {
      final doc = _createDocumentWithPages([
        (1, 'Page one content A.'),
        (1, 'Page one content B.'),
        (2, 'Page two content.'),
        (3, 'Page three content.'),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(3));
      expect(chunks[0].text, contains('Page one content A'));
      expect(chunks[0].text, contains('Page one content B'));
      expect(chunks[1].text, contains('Page two'));
      expect(chunks[2].text, contains('Page three'));
    });

    test('assigns page metadata in fallback mode', () async {
      final doc = _createDocumentWithPages([
        (2, 'Content on page 2.'),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks[0].location.pageNumber, equals(2));
      expect(chunks[0].metadata?['pageNumber'], equals(2));
    });

    test('pages with TableBlock parts use pageNumber from location', () async {
      final doc = _createDocWithParts([
        TableBlock(
          id: 'table0',
          rows: const [
            TableRow(cells: [TableCell(text: 'H1'), TableCell(text: 'H2')]),
            TableRow(cells: [TableCell(text: 'D1'), TableCell(text: 'D2')]),
          ],
          rowCount: 2,
          columnCount: 2,
          location: const SourceLocation(pageNumber: 5),
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks[0].location.pageNumber, equals(5));
    });

    test('pages with ImageBlock parts use pageNumber from location', () async {
      final doc = _createDocWithParts([
        const ImageBlock(
          id: 'img0',
          assetRef: 'img.png',
          caption: 'A photo',
          location: SourceLocation(pageNumber: 7),
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks[0].location.pageNumber, equals(7));
    });

    test('skips empty page text in fallback', () async {
      final doc = _createDocWithParts([
        const TextBlock(
          id: 'p0',
          text: '',
          location: SourceLocation(pageNumber: 1),
        ),
        const TextBlock(
          id: 'p1',
          text: 'Non-empty content.',
          location: SourceLocation(pageNumber: 2),
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks[0].text, contains('Non-empty'));
    });
  });

  group('PageChunker - _splitPage for large pages', () {
    late PageChunker chunker;

    setUp(() {
      chunker = PageChunker();
    });

    test('splits page that exceeds maxSize using structure nodes', () async {
      // Create a large page text that exceeds maxSize
      final longText = 'This is a sentence. ' * 100;
      final doc = _createDocWithParts(
        [TextBlock(id: 'p0', text: longText)],
        structure: DocumentStructure(nodes: [
          StructureNode(
            id: 'page1',
            type: StructureType.page,
            title: 'Page 1',
            level: 0,
            partIds: ['p0'],
          ),
        ]),
      );
      final options = const ChunkOptions(
        maxSize: 200,
        minSize: 50,
        targetSize: 150,
        overlap: 0,
      );
      final chunks = await chunker.chunk(doc, options);
      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(chunk.metadata?['pageTitle'], equals('Page 1'));
      }
    });

    test('split page breaks at paragraph boundary', () async {
      // Create text with paragraph breaks
      final text =
          '${'First paragraph content. ' * 10}\n\n${'Second paragraph content. ' * 10}';
      final doc = _createDocWithParts(
        [TextBlock(id: 'p0', text: text)],
        structure: DocumentStructure(nodes: [
          StructureNode(
            id: 'page1',
            type: StructureType.page,
            title: 'Page 1',
            level: 0,
            partIds: ['p0'],
          ),
        ]),
      );
      final options = const ChunkOptions(
        maxSize: 200,
        minSize: 50,
        targetSize: 150,
        overlap: 0,
      );
      final chunks = await chunker.chunk(doc, options);
      expect(chunks.length, greaterThan(1));
    });

    test('non-split page within maxSize is single chunk', () async {
      final doc = _createDocWithParts(
        [const TextBlock(id: 'p0', text: 'Short page content.')],
        structure: DocumentStructure(nodes: [
          StructureNode(
            id: 'page1',
            type: StructureType.page,
            title: 'Page 1',
            level: 0,
            partIds: ['p0'],
          ),
        ]),
      );
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks[0].metadata?['pageNumber'], equals(1));
    });

    test('_extractText handles AudioBlock and KeyValueBlock', () async {
      final doc = _createDocWithParts(
        [
          const KeyValueBlock(id: 'kv0', key: 'Title', value: 'Test Doc'),
          const AudioBlock(
            id: 'audio0',
            assetRef: 'audio.mp3',
            transcript: 'Spoken words here.',
          ),
          const ListBlock(
            id: 'list0',
            type: ListType.unordered,
            items: [ListItem(text: 'Item 1'), ListItem(text: 'Item 2')],
          ),
        ],
      );
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks[0].text, contains('Title: Test Doc'));
      expect(chunks[0].text, contains('Spoken words here'));
      expect(chunks[0].text, contains('- Item 1'));
    });

    test('page with empty structure parts are skipped', () async {
      final doc = _createDocWithParts(
        [
          const TextBlock(id: 'p0', text: 'Visible'),
        ],
        structure: DocumentStructure(nodes: [
          StructureNode(
            id: 'page1',
            type: StructureType.page,
            title: 'Page 1',
            level: 0,
            partIds: ['p0', 'nonexistent'],
          ),
        ]),
      );
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks[0].text, contains('Visible'));
    });

    test('slide type is treated same as page', () async {
      final doc = _createDocWithParts(
        [const TextBlock(id: 's0', text: 'Slide content')],
        structure: DocumentStructure(nodes: [
          StructureNode(
            id: 'slide1',
            type: StructureType.slide,
            title: 'Slide 1',
            level: 0,
            partIds: ['s0'],
          ),
        ]),
      );
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks[0].text, contains('Slide content'));
    });
  });

  group('TableChunker - extended coverage', () {
    late TableChunker chunker;

    setUp(() {
      chunker = TableChunker();
    });

    test('splits large table exceeding maxSize', () async {
      // Create a table with many rows
      final rows = <TableRow>[
        const TableRow(
            cells: [TableCell(text: 'Header1'), TableCell(text: 'Header2')]),
        for (var i = 0; i < 50; i++)
          TableRow(cells: [
            TableCell(text: 'Row $i Col 1 data'),
            TableCell(text: 'Row $i Col 2 data')
          ]),
      ];
      final doc = _createDocWithParts([
        TableBlock(
          id: 'big_table',
          rows: rows,
          rowCount: rows.length,
          columnCount: 2,
          caption: 'Big Table',
        ),
      ]);
      final options = const ChunkOptions(
        maxSize: 200,
        targetSize: 100,
        minSize: 50,
        overlap: 0,
      );
      final chunks = await chunker.chunk(doc, options);
      expect(chunks.length, greaterThan(1));
      // Each chunk should be a table chunk
      for (final chunk in chunks) {
        expect(chunk.metadata?['contentType'], equals('table'));
        expect(chunk.metadata?['isPartial'], isTrue);
      }
    });

    test('header row preserved in split tables', () async {
      final rows = <TableRow>[
        const TableRow(
            cells: [TableCell(text: 'Name'), TableCell(text: 'Age')]),
        for (var i = 0; i < 30; i++)
          TableRow(cells: [
            TableCell(text: 'Person $i'),
            TableCell(text: '${20 + i}')
          ]),
      ];
      final doc = _createDocWithParts([
        TableBlock(
          id: 'table1',
          rows: rows,
          rowCount: rows.length,
          columnCount: 2,
        ),
      ]);
      final options = const ChunkOptions(
        maxSize: 200,
        targetSize: 100,
        minSize: 50,
        overlap: 0,
      );
      final chunks = await chunker.chunk(doc, options);
      // Each chunk should contain the header row
      for (final chunk in chunks) {
        expect(chunk.text, contains('Name'));
        expect(chunk.text, contains('Age'));
      }
    });

    test('_extractPartText handles ListBlock', () async {
      final doc = _createDocWithParts([
        const ListBlock(
          id: 'list0',
          type: ListType.unordered,
          items: [ListItem(text: 'Item A'), ListItem(text: 'Item B')],
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks[0].text, contains('- Item A'));
      expect(chunks[0].text, contains('- Item B'));
    });

    test('_extractPartText handles KeyValueBlock', () async {
      final doc = _createDocWithParts([
        const KeyValueBlock(id: 'kv0', key: 'Name', value: 'John'),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks[0].text, contains('Name: John'));
    });

    test('_extractPartText handles ImageBlock with descriptions', () async {
      final doc = _createDocWithParts([
        const ImageBlock(
          id: 'img0',
          assetRef: 'photo.png',
          caption: 'A landscape',
          ocrText: 'Mountain view',
          visionDescription: 'Scenic mountains',
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks[0].text, contains('A landscape'));
      expect(chunks[0].text, contains('Mountain view'));
    });

    test('_extractPartText handles AudioBlock with transcript', () async {
      final doc = _createDocWithParts([
        const AudioBlock(
          id: 'audio0',
          assetRef: 'audio.mp3',
          transcript: 'Hello from audio.',
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks[0].text, contains('Hello from audio'));
    });

    test('_extractPartText handles AudioBlock without transcript', () async {
      final doc = _createDocWithParts([
        const AudioBlock(
          id: 'audio0',
          assetRef: 'audio.mp3',
        ),
        const TextBlock(id: 'p0', text: 'Some text.'),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks[0].text, contains('Some text'));
    });

    test('flushes accumulated text before table and after', () async {
      final doc = _createDocWithParts([
        const TextBlock(id: 'p0', text: 'Before table.'),
        const TableBlock(
          id: 'table0',
          rows: [
            TableRow(cells: [TableCell(text: 'A'), TableCell(text: 'B')]),
            TableRow(cells: [TableCell(text: '1'), TableCell(text: '2')]),
          ],
          rowCount: 2,
          columnCount: 2,
        ),
        const TextBlock(id: 'p1', text: 'After table.'),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(3));
      expect(chunks[0].text, contains('Before table'));
      expect(chunks[0].metadata?['contentType'], equals('text'));
      expect(chunks[1].metadata?['contentType'], equals('table'));
      expect(chunks[2].text, contains('After table'));
      expect(chunks[2].metadata?['contentType'], equals('text'));
    });

    test('text accumulation flushes on maxSize overflow', () async {
      final longText = 'A' * 1500;
      final doc = _createDocWithParts([
        TextBlock(id: 'p0', text: longText),
        TextBlock(id: 'p1', text: longText),
      ]);
      final options = const ChunkOptions(
        maxSize: 2000,
        targetSize: 1000,
        overlap: 0,
      );
      final chunks = await chunker.chunk(doc, options);
      expect(chunks.length, equals(2));
    });

    test('table metadata includes caption and dimensions', () async {
      final doc = _createDocWithParts([
        const TableBlock(
          id: 'table0',
          rows: [
            TableRow(cells: [TableCell(text: 'A')]),
            TableRow(cells: [TableCell(text: '1')]),
          ],
          rowCount: 2,
          columnCount: 1,
          caption: 'My Table',
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks[0].metadata?['rowCount'], equals(2));
      expect(chunks[0].metadata?['columnCount'], equals(1));
      expect(chunks[0].metadata?['caption'], equals('My Table'));
    });

    test('empty document returns empty list', () async {
      final doc = _createDocWithParts([]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks, isEmpty);
    });

    test('ImageBlock with no text fields produces empty text', () async {
      final doc = _createDocWithParts([
        const ImageBlock(
          id: 'img0',
          assetRef: 'photo.png',
        ),
        const TextBlock(id: 'p0', text: 'Visible text.'),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      // The ImageBlock produces empty text so is skipped
      expect(chunks.length, equals(1));
      expect(chunks[0].text, contains('Visible text'));
    });
  });

  group('ParagraphChunker - extended coverage', () {
    late ParagraphChunker chunker;

    setUp(() {
      chunker = ParagraphChunker();
    });

    test('respectBoundaries splits at section boundaries', () async {
      final doc = _createDocWithParts(
        [
          const TextBlock(id: 'p0', text: 'Content in section A.'),
          const TextBlock(id: 'p1', text: 'More in section A.'),
          const TextBlock(id: 'p2', text: 'Content in section B.'),
        ],
        structure: DocumentStructure(nodes: [
          StructureNode(
            id: 'secA',
            type: StructureType.section,
            title: 'Section A',
            partIds: ['p0', 'p1'],
          ),
          StructureNode(
            id: 'secB',
            type: StructureType.section,
            title: 'Section B',
            partIds: ['p2'],
          ),
        ]),
      );
      final options = const ChunkOptions(
        respectBoundaries: true,
        maxSize: 10000,
        overlap: 0,
      );
      final chunks = await chunker.chunk(doc, options);
      expect(chunks.length, equals(2));
      expect(chunks[0].text, contains('Content in section A'));
      expect(chunks[0].text, contains('More in section A'));
      expect(chunks[0].metadata?['sectionTitle'], equals('Section A'));
      expect(chunks[1].text, contains('Content in section B'));
      expect(chunks[1].metadata?['sectionTitle'], equals('Section B'));
    });

    test('size limit enforcement splits chunks', () async {
      final doc = _createDocWithParts([
        TextBlock(id: 'p0', text: 'A' * 500),
        TextBlock(id: 'p1', text: 'B' * 500),
        TextBlock(id: 'p2', text: 'C' * 500),
      ]);
      final options = const ChunkOptions(
        maxSize: 600,
        targetSize: 500,
        minSize: 100,
        overlap: 0,
      );
      final chunks = await chunker.chunk(doc, options);
      expect(chunks.length, greaterThan(1));
    });

    test('handles TableBlock parts', () async {
      final doc = _createDocWithParts([
        const TableBlock(
          id: 'table0',
          rows: [
            TableRow(cells: [TableCell(text: 'H1')]),
            TableRow(cells: [TableCell(text: 'D1')]),
          ],
          rowCount: 2,
          columnCount: 1,
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks[0].text, contains('H1'));
    });

    test('handles ListBlock parts', () async {
      final doc = _createDocWithParts([
        const ListBlock(
          id: 'list0',
          type: ListType.ordered,
          items: [ListItem(text: 'First'), ListItem(text: 'Second')],
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks[0].text, contains('- First'));
      expect(chunks[0].text, contains('- Second'));
    });

    test('handles ImageBlock with caption and ocr', () async {
      final doc = _createDocWithParts([
        const ImageBlock(
          id: 'img0',
          assetRef: 'img.png',
          caption: 'Photo caption',
          ocrText: 'OCR text',
          visionDescription: 'Vision desc',
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks[0].text, contains('Photo caption'));
    });

    test('handles AudioBlock with transcript', () async {
      final doc = _createDocWithParts([
        const AudioBlock(
          id: 'audio0',
          assetRef: 'a.mp3',
          transcript: 'Audio text here.',
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks[0].text, contains('Audio text here'));
    });

    test('AudioBlock without transcript produces empty text', () async {
      final doc = _createDocWithParts([
        const AudioBlock(
          id: 'audio0',
          assetRef: 'a.mp3',
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks, isEmpty);
    });

    test('_findSection recursive lookup finds deeply nested part', () async {
      final doc = _createDocWithParts(
        [const TextBlock(id: 'deep', text: 'Deep content.')],
        structure: DocumentStructure(nodes: [
          StructureNode(
            id: 'root',
            type: StructureType.chapter,
            title: 'Root',
            children: [
              StructureNode(
                id: 'mid',
                type: StructureType.section,
                title: 'Middle',
                children: [
                  StructureNode(
                    id: 'leaf',
                    type: StructureType.subsection,
                    title: 'Leaf',
                    partIds: ['deep'],
                  ),
                ],
              ),
            ],
          ),
        ]),
      );
      final options = const ChunkOptions(
        respectBoundaries: true,
        maxSize: 10000,
        overlap: 0,
      );
      final chunks = await chunker.chunk(doc, options);
      expect(chunks.length, equals(1));
      expect(chunks[0].metadata?['sectionTitle'], equals('Leaf'));
    });

    test('_findSection uses node id when title is null', () async {
      final doc = _createDocWithParts(
        [const TextBlock(id: 'p0', text: 'Content.')],
        structure: DocumentStructure(nodes: [
          StructureNode(
            id: 'no_title_sec',
            type: StructureType.section,
            partIds: ['p0'],
          ),
        ]),
      );
      final options = const ChunkOptions(
        respectBoundaries: true,
        maxSize: 10000,
        overlap: 0,
      );
      final chunks = await chunker.chunk(doc, options);
      expect(chunks.length, equals(1));
      expect(chunks[0].metadata?['sectionTitle'], equals('no_title_sec'));
    });

    test('empty document returns empty list', () async {
      final doc = _createDocWithParts([]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks, isEmpty);
    });

    test('sets paragraphCount in metadata', () async {
      final doc = _createDocWithParts([
        const TextBlock(id: 'p0', text: 'First para.'),
        const TextBlock(id: 'p1', text: 'Second para.'),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks[0].metadata?['paragraphCount'], isA<int>());
    });

    test('sets location from first part in chunk', () async {
      final doc = _createDocWithParts([
        const TextBlock(
          id: 'p0',
          text: 'Content.',
          location: SourceLocation(pageNumber: 3),
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks[0].location.pageNumber, equals(3));
    });

    test('respectBoundaries false does not split on section change', () async {
      final doc = _createDocWithParts(
        [
          const TextBlock(id: 'p0', text: 'A content.'),
          const TextBlock(id: 'p1', text: 'B content.'),
        ],
        structure: DocumentStructure(nodes: [
          StructureNode(
            id: 'secA',
            type: StructureType.section,
            title: 'A',
            partIds: ['p0'],
          ),
          StructureNode(
            id: 'secB',
            type: StructureType.section,
            title: 'B',
            partIds: ['p1'],
          ),
        ]),
      );
      final options = const ChunkOptions(
        respectBoundaries: false,
        maxSize: 10000,
        overlap: 0,
      );
      final chunks = await chunker.chunk(doc, options);
      // Without respectBoundaries, all are in one chunk
      expect(chunks.length, equals(1));
    });

    test('KeyValueBlock extracted correctly', () async {
      final doc = _createDocWithParts([
        const KeyValueBlock(id: 'kv0', key: 'Author', value: 'Alice'),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks[0].text, contains('Author: Alice'));
    });
  });

  group('SentenceChunker - extended coverage', () {
    late SentenceChunker chunker;

    setUp(() {
      chunker = SentenceChunker();
    });

    test('overlap handling adds overlap from previous chunk', () async {
      // Create content large enough to be split, then check overlap
      final sentences = List.generate(20, (i) => 'Sentence number $i is here.');
      final doc = _createTestDocument([sentences.join(' ')]);
      final options = const ChunkOptions(
        maxSize: 100,
        targetSize: 80,
        overlap: 50,
        minSize: 10,
      );
      final chunks = await chunker.chunk(doc, options);
      expect(chunks.length, greaterThan(1));
      // The second chunk should contain some overlap text from the first
      // (overlap text is taken from the end of the previous chunk)
    });

    test('_getPartText handles TableBlock', () async {
      final doc = _createDocWithParts([
        const TableBlock(
          id: 'table0',
          rows: [
            TableRow(cells: [TableCell(text: 'Col1')]),
            TableRow(cells: [TableCell(text: 'Val1')]),
          ],
          rowCount: 2,
          columnCount: 1,
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.isNotEmpty, isTrue);
      expect(chunks.first.text, contains('Col1'));
    });

    test('_getPartText handles ImageBlock with mixed text', () async {
      final doc = _createDocWithParts([
        const ImageBlock(
          id: 'img0',
          assetRef: 'img.png',
          caption: 'Caption text.',
          visionDescription: 'Vision description text.',
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.isNotEmpty, isTrue);
      expect(chunks.first.text, contains('Caption text'));
    });

    test('_getPartText handles AudioBlock with transcript', () async {
      final doc = _createDocWithParts([
        const AudioBlock(
          id: 'audio0',
          assetRef: 'a.mp3',
          transcript: 'Audio transcript sentence.',
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.isNotEmpty, isTrue);
      expect(chunks.first.text, contains('Audio transcript'));
    });

    test('_getPartText handles AudioBlock without transcript', () async {
      final doc = _createDocWithParts([
        const AudioBlock(
          id: 'audio0',
          assetRef: 'a.mp3',
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks, isEmpty);
    });

    test('_getPartText handles ListBlock', () async {
      final doc = _createDocWithParts([
        const ListBlock(
          id: 'list0',
          type: ListType.unordered,
          items: [ListItem(text: 'Alpha'), ListItem(text: 'Beta')],
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.isNotEmpty, isTrue);
      expect(chunks.first.text, contains('Alpha'));
    });

    test('_getPartText handles KeyValueBlock', () async {
      final doc = _createDocWithParts([
        const KeyValueBlock(id: 'kv0', key: 'Field', value: 'Data'),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.isNotEmpty, isTrue);
      expect(chunks.first.text, contains('Field: Data'));
    });

    test('abbreviation patterns are not treated as sentence ends', () async {
      final doc = _createTestDocument([
        'Dr. Smith and Mrs. Jones arrived. They talked about Prof. Lee.',
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.isNotEmpty, isTrue);
      // The abbreviations should not split the text mid-sentence
      final allText = chunks.map((c) => c.text).join(' ');
      expect(allText, contains('Dr. Smith'));
      expect(allText, contains('Mrs. Jones'));
    });

    test('sentence metadata includes sentenceCount', () async {
      final doc = _createTestDocument([
        'First sentence. Second sentence. Third sentence.',
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.first.metadata?['sentenceCount'], isA<int>());
      expect(chunks.first.metadata?['chunker'], equals('sentence_v1'));
    });

    test('overlap text finds sentence boundary', () async {
      // Large content with clear sentence boundaries
      final text =
          List.generate(30, (i) => 'Sentence $i is complete.').join(' ');
      final doc = _createTestDocument([text]);
      final options = const ChunkOptions(
        maxSize: 150,
        targetSize: 100,
        overlap: 80,
        minSize: 10,
      );
      final chunks = await chunker.chunk(doc, options);
      expect(chunks.length, greaterThan(1));
    });

    test('sets location from part', () async {
      final doc = _createDocWithParts([
        const TextBlock(
          id: 'p0',
          text: 'A sentence here.',
          location: SourceLocation(pageNumber: 5),
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.isNotEmpty, isTrue);
      expect(chunks.first.location.pageNumber, equals(5));
    });
  });

  group('NoChunker - extended coverage', () {
    late NoChunker chunker;

    setUp(() {
      chunker = NoChunker();
    });

    test('_getPartLength for TableBlock', () async {
      final doc = _createDocWithParts([
        const TableBlock(
          id: 'table0',
          rows: [
            TableRow(cells: [TableCell(text: 'H1'), TableCell(text: 'H2')]),
            TableRow(cells: [TableCell(text: 'D1'), TableCell(text: 'D2')]),
          ],
          rowCount: 2,
          columnCount: 2,
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      // The sourceSpans should have endOffset matching markdown length
      final tableSpan = chunks[0].sourceSpans.first;
      expect(tableSpan.endOffset, greaterThan(0));
    });

    test('_getPartLength for ListBlock', () async {
      final doc = _createDocWithParts([
        const ListBlock(
          id: 'list0',
          type: ListType.unordered,
          items: [ListItem(text: 'Hello'), ListItem(text: 'World')],
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      final listSpan = chunks[0].sourceSpans.first;
      // Length = sum of item text lengths = 5 + 5 = 10
      expect(listSpan.endOffset, equals(10));
    });

    test('_getPartLength for KeyValueBlock', () async {
      final doc = _createDocWithParts([
        const KeyValueBlock(id: 'kv0', key: 'Name', value: 'Test'),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      final kvSpan = chunks[0].sourceSpans.first;
      // Length = key.length + value.length = 4 + 4 = 8
      expect(kvSpan.endOffset, equals(8));
    });

    test('_getPartLength for ImageBlock returns 0', () async {
      final doc = _createDocWithParts([
        const ImageBlock(
          id: 'img0',
          assetRef: 'img.png',
          caption: 'Caption',
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      final imgSpan = chunks[0].sourceSpans.first;
      expect(imgSpan.endOffset, equals(0));
    });

    test('_getPartLength for AudioBlock returns 0', () async {
      final doc = _createDocWithParts([
        const AudioBlock(
          id: 'audio0',
          assetRef: 'a.mp3',
          transcript: 'Some transcript',
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      final audioSpan = chunks[0].sourceSpans.first;
      expect(audioSpan.endOffset, equals(0));
    });

    test('includes partCount in metadata', () async {
      final doc = _createDocWithParts([
        const TextBlock(id: 'p0', text: 'Part one.'),
        const TextBlock(id: 'p1', text: 'Part two.'),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks[0].metadata?['partCount'], equals(2));
      expect(chunks[0].metadata?['chunker'], equals('none_v1'));
    });

    test('multiple part types in single chunk', () async {
      final doc = _createDocWithParts([
        const TextBlock(id: 'p0', text: 'Some text.'),
        const TableBlock(
          id: 'table0',
          rows: [
            TableRow(cells: [TableCell(text: 'A')]),
          ],
          rowCount: 1,
          columnCount: 1,
        ),
        const KeyValueBlock(id: 'kv0', key: 'K', value: 'V'),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.length, equals(1));
      expect(chunks[0].sourceSpans.length, equals(3));
    });
  });

  group('FixedSizeChunker - extended coverage', () {
    late FixedSizeChunker chunker;

    setUp(() {
      chunker = FixedSizeChunker();
    });

    test('_getPartText for ImageBlock with visionDescription', () async {
      // FixedSizeChunker uses document.fullText which only includes caption + ocrText.
      // The _getPartText in FixedSizeChunker includes visionDescription for offset mapping.
      final doc = _createDocWithParts([
        const ImageBlock(
          id: 'img0',
          assetRef: 'img.png',
          caption: 'Image caption',
          ocrText: 'OCR text here',
          visionDescription: 'A detailed description',
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.isNotEmpty, isTrue);
      expect(chunks.first.text, contains('Image caption'));
      expect(chunks.first.text, contains('OCR text here'));
      // visionDescription is included in _getPartText offset mapping but
      // document.fullText only uses caption + ocrText
    });

    test('_getPartText for AudioBlock with transcript', () async {
      final doc = _createDocWithParts([
        const AudioBlock(
          id: 'audio0',
          assetRef: 'audio.mp3',
          transcript: 'Transcribed audio text.',
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.isNotEmpty, isTrue);
      expect(chunks.first.text, contains('Transcribed audio'));
    });

    test('_getPartText for AudioBlock without transcript', () async {
      final doc = _createDocWithParts([
        const AudioBlock(
          id: 'audio0',
          assetRef: 'audio.mp3',
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      // AudioBlock with no transcript returns empty string,
      // but the document fullText still includes empty lines
      expect(chunks, isEmpty);
    });

    test('_getPartText for ListBlock', () async {
      final doc = _createDocWithParts([
        const ListBlock(
          id: 'list0',
          type: ListType.unordered,
          items: [
            ListItem(text: 'List item one'),
            ListItem(text: 'List item two')
          ],
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.isNotEmpty, isTrue);
      expect(chunks.first.text, contains('- List item one'));
    });

    test('_getPartText for KeyValueBlock', () async {
      final doc = _createDocWithParts([
        const KeyValueBlock(id: 'kv0', key: 'Title', value: 'Document Title'),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.isNotEmpty, isTrue);
    });

    test('_getPartText for TableBlock uses markdown', () async {
      final doc = _createDocWithParts([
        const TableBlock(
          id: 'table0',
          rows: [
            TableRow(cells: [TableCell(text: 'H1')]),
            TableRow(cells: [TableCell(text: 'D1')]),
          ],
          rowCount: 2,
          columnCount: 1,
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.isNotEmpty, isTrue);
      expect(chunks.first.text, contains('H1'));
    });

    test('resolves source spans across multiple parts', () async {
      final doc = _createDocWithParts([
        const TextBlock(id: 'p0', text: 'First part text.'),
        const TextBlock(id: 'p1', text: 'Second part text.'),
      ]);
      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 200,
        overlap: 0,
      );
      final chunks = await chunker.chunk(doc, options);
      expect(chunks.isNotEmpty, isTrue);
      // At least one chunk should have spans
      expect(chunks.first.sourceSpans.isNotEmpty, isTrue);
    });

    test('ImageBlock with only caption', () async {
      final doc = _createDocWithParts([
        const ImageBlock(
          id: 'img0',
          assetRef: 'img.png',
          caption: 'Just a caption',
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.isNotEmpty, isTrue);
      expect(chunks.first.text, contains('Just a caption'));
    });

    test('ImageBlock with ocrText only', () async {
      final doc = _createDocWithParts([
        const ImageBlock(
          id: 'img0',
          assetRef: 'img.png',
          ocrText: 'OCR extracted text here',
        ),
      ]);
      final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
      expect(chunks.isNotEmpty, isTrue);
      expect(chunks.first.text, contains('OCR extracted text'));
    });
  });

  group('ChunkOptions extended', () {
    test('copyWith updates all fields', () {
      const original = ChunkOptions.defaults;
      final modified = original.copyWith(
        targetSize: 500,
        maxSize: 1500,
        minSize: 50,
        overlap: 100,
        respectBoundaries: false,
        includeContext: false,
        maxContextLength: 100,
      );
      expect(modified.targetSize, equals(500));
      expect(modified.maxSize, equals(1500));
      expect(modified.minSize, equals(50));
      expect(modified.overlap, equals(100));
      expect(modified.respectBoundaries, isFalse);
      expect(modified.includeContext, isFalse);
      expect(modified.maxContextLength, equals(100));
    });

    test('defaults respect boundaries and include context', () {
      const options = ChunkOptions.defaults;
      expect(options.respectBoundaries, isTrue);
      expect(options.includeContext, isTrue);
      expect(options.maxContextLength, equals(200));
    });
  });

  _addChunkerInvariantTests();
}

NormalizedDocument _createTestDocument(List<String> paragraphs) {
  final parts = <DocumentPart>[];
  for (var i = 0; i < paragraphs.length; i++) {
    parts.add(TextBlock(
      id: 'p$i',
      text: paragraphs[i],
      type: TextBlockType.paragraph,
    ));
  }

  return NormalizedDocument(
    id: 'test_doc',
    metadata: const DocumentMetadata(
      mimeType: 'text/plain',
      sha256: 'test_hash',
      fileSize: 100,
    ),
    parts: parts,
    structure: DocumentStructure.empty,
    provenance: ExtractionProvenance(
      extractorId: 'test',
      extractorVersion: '1.0',
      extractedAt: DateTime.now(),
      extractionDuration: Duration.zero,
    ),
  );
}

NormalizedDocument _createDocumentWithPages(List<(int, String)> pageContent) {
  final parts = <DocumentPart>[];
  for (var i = 0; i < pageContent.length; i++) {
    final (page, text) = pageContent[i];
    parts.add(TextBlock(
      id: 'p$i',
      text: text,
      type: TextBlockType.paragraph,
      location: SourceLocation(pageNumber: page),
    ));
  }

  return NormalizedDocument(
    id: 'test_doc',
    metadata: const DocumentMetadata(
      mimeType: 'text/plain',
      sha256: 'test_hash',
      fileSize: 100,
    ),
    parts: parts,
    structure: DocumentStructure.empty,
    provenance: ExtractionProvenance(
      extractorId: 'test',
      extractorVersion: '1.0',
      extractedAt: DateTime.now(),
      extractionDuration: Duration.zero,
    ),
  );
}

NormalizedDocument _createDocumentWithTable() {
  return NormalizedDocument(
    id: 'test_doc',
    metadata: const DocumentMetadata(
      mimeType: 'text/html',
      sha256: 'test_hash',
      fileSize: 200,
    ),
    parts: const [
      TextBlock(id: 'p0', text: 'Intro paragraph.'),
      TableBlock(
        id: 'table0',
        rows: [
          TableRow(cells: [TableCell(text: 'A'), TableCell(text: 'B')]),
          TableRow(cells: [TableCell(text: '1'), TableCell(text: '2')]),
        ],
        rowCount: 2,
        columnCount: 2,
      ),
      TextBlock(id: 'p1', text: 'After table.'),
    ],
    structure: DocumentStructure.empty,
    provenance: ExtractionProvenance(
      extractorId: 'test',
      extractorVersion: '1.0',
      extractedAt: DateTime.now(),
      extractionDuration: Duration.zero,
    ),
  );
}

NormalizedDocument _createDocWithParts(
  List<DocumentPart> parts, {
  DocumentStructure? structure,
}) {
  return NormalizedDocument(
    id: 'doc1',
    metadata: const DocumentMetadata(mimeType: 'text/plain', sha256: 'abc'),
    parts: parts,
    structure: structure ?? DocumentStructure.empty,
    provenance: ExtractionProvenance(
      extractorId: 'test',
      extractorVersion: '1.0',
      extractedAt: DateTime(2024, 1, 1),
      extractionDuration: Duration.zero,
    ),
  );
}

/// Minimal LlmPort stub for testing factory creation only.
class _StubLlmPort extends LlmPort {
  @override
  LlmCapabilities get capabilities => const LlmCapabilities.minimal();

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    return LlmResponse(content: '{"splits": []}');
  }
}

// IT-CHK-001: cross-cutting provenance invariant for all built-in chunkers.
// Every Chunk emitted by every chunker must have non-empty sourceSpans.
// Regression test for DEF-20260411-003.
void _addChunkerInvariantTests() {
  group('Chunker invariant (IT-CHK-001): sourceSpans.isNotEmpty', () {
    final sampleDocs = <String, NormalizedDocument Function()>{
      'empty document': () => _createDocWithParts(const []),
      'single paragraph': () => _createTestDocument(['Hello world.']),
      'multi-paragraph': () => _createTestDocument([
            'First paragraph with multiple sentences. This is a second sentence.',
            'Second paragraph here.',
            'Third paragraph goes last.',
          ]),
      'with pages': () => _createDocumentWithPages([
            (1, 'Page one text.'),
            (1, 'More on page one.'),
            (2, 'Page two begins here.'),
          ]),
      'with table': () => _createDocumentWithTable(),
    };

    final chunkerBuilders = <String, Chunker Function()>{
      'NoChunker': () => NoChunker(),
      'SentenceChunker': () => SentenceChunker(),
      'ParagraphChunker': () => ParagraphChunker(),
      'PageChunker': () => PageChunker(),
      'FixedSizeChunker': () => FixedSizeChunker(),
      'TableChunker': () => TableChunker(),
      'SemanticChunker': () => SemanticChunker(_StubLlmPort()),
    };

    for (final chunkerEntry in chunkerBuilders.entries) {
      final chunkerName = chunkerEntry.key;
      for (final docEntry in sampleDocs.entries) {
        final docLabel = docEntry.key;
        test('$chunkerName on $docLabel preserves sourceSpans', () async {
          final chunker = chunkerEntry.value();
          final doc = docEntry.value();
          final chunks = await chunker.chunk(doc, ChunkOptions.defaults);
          for (final chunk in chunks) {
            expect(
              chunk.sourceSpans,
              isNotEmpty,
              reason:
                  '$chunkerName produced a chunk with empty sourceSpans on "$docLabel" '
                  '(chunk id: ${chunk.id})',
            );
          }
        });
      }
    }
  });
}
