import 'package:test/test.dart';
import 'package:mcp_ingest/mcp_ingest.dart';

void main() {
  group('DocumentMetadata', () {
    test('creates with required fields', () {
      const metadata = DocumentMetadata(
        mimeType: 'text/plain',
        sha256: 'abc123',
        fileSize: 1024,
      );
      expect(metadata.mimeType, equals('text/plain'));
      expect(metadata.sha256, equals('abc123'));
      expect(metadata.fileSize, equals(1024));
      expect(metadata.title, isNull);
      expect(metadata.author, isNull);
    });

    test('creates with all fields', () {
      final now = DateTime.now();
      final metadata = DocumentMetadata(
        mimeType: 'application/pdf',
        sha256: 'def456',
        fileSize: 2048,
        title: 'Test Document',
        author: 'Test Author',
        createdAt: now,
        modifiedAt: now,
        pageCount: 10,
        wordCount: 500,
        language: 'en',
        sourceUri: 'file:///test.pdf',
      );
      expect(metadata.title, equals('Test Document'));
      expect(metadata.author, equals('Test Author'));
      expect(metadata.pageCount, equals(10));
      expect(metadata.wordCount, equals(500));
      expect(metadata.language, equals('en'));
    });

    test('toJson and fromJson round-trip', () {
      final now = DateTime.parse('2024-01-15T10:30:00.000Z');
      final metadata = DocumentMetadata(
        mimeType: 'application/pdf',
        sha256: 'abc123',
        fileSize: 1024,
        title: 'Test',
        author: 'Author',
        createdAt: now,
        modifiedAt: now,
        pageCount: 5,
        wordCount: 200,
        language: 'en',
        sourceUri: 'file:///test.pdf',
        custom: {'custom': 'value'},
      );
      final json = metadata.toJson();
      final restored = DocumentMetadata.fromJson(json);
      expect(restored.mimeType, equals('application/pdf'));
      expect(restored.title, equals('Test'));
      expect(restored.author, equals('Author'));
      expect(restored.pageCount, equals(5));
      expect(restored.custom?['custom'], equals('value'));
    });

    test('fromJson with minimal data', () {
      final json = {'mimeType': 'text/plain'};
      final metadata = DocumentMetadata.fromJson(json);
      expect(metadata.mimeType, equals('text/plain'));
      expect(metadata.sha256, equals(''));
      expect(metadata.custom, isNull);
    });

    test('fromJson with null mimeType uses default', () {
      final json = <String, dynamic>{};
      final metadata = DocumentMetadata.fromJson(json);
      expect(metadata.mimeType, equals('application/octet-stream'));
    });

    test('copyWith preserves unchanged values', () {
      const original = DocumentMetadata(
        mimeType: 'text/plain',
        sha256: 'hash',
        fileSize: 100,
        title: 'Original',
      );
      final modified = original.copyWith(title: 'Modified');
      expect(modified.mimeType, equals('text/plain'));
      expect(modified.sha256, equals('hash'));
      expect(modified.title, equals('Modified'));
    });

    test('copyWith updates multiple fields', () {
      const original = DocumentMetadata(
        mimeType: 'text/plain',
        sha256: 'hash',
        fileSize: 100,
      );
      final modified = original.copyWith(
        mimeType: 'application/json',
        fileSize: 200,
        language: 'ko',
      );
      expect(modified.mimeType, equals('application/json'));
      expect(modified.fileSize, equals(200));
      expect(modified.language, equals('ko'));
    });
  });

  group('ExtractionProvenance', () {
    test('creates with required fields', () {
      final now = DateTime.now();
      final provenance = ExtractionProvenance(
        extractorId: 'text_v1',
        extractorVersion: '1.0.0',
        extractedAt: now,
        extractionDuration: const Duration(milliseconds: 100),
      );
      expect(provenance.extractorId, equals('text_v1'));
      expect(provenance.extractorVersion, equals('1.0.0'));
      expect(provenance.warnings, isNull);
    });

    test('creates with warnings', () {
      final provenance = ExtractionProvenance(
        extractorId: 'pdf_v1',
        extractorVersion: '1.0.0',
        extractedAt: DateTime.now(),
        extractionDuration: Duration.zero,
        warnings: ['Warning 1', 'Warning 2'],
      );
      expect(provenance.warnings!.length, equals(2));
    });

    test('toJson and fromJson round-trip', () {
      final now = DateTime.parse('2024-01-15T10:30:00.000Z');
      final provenance = ExtractionProvenance(
        extractorId: 'test_v1',
        extractorVersion: '2.0.0',
        extractedAt: now,
        extractionDuration: const Duration(milliseconds: 500),
        warnings: ['Warning'],
      );
      final json = provenance.toJson();
      final restored = ExtractionProvenance.fromJson(json);
      expect(restored.extractorId, equals('test_v1'));
      expect(restored.extractorVersion, equals('2.0.0'));
      expect(restored.extractionDuration.inMilliseconds, equals(500));
      expect(restored.warnings, contains('Warning'));
    });

    test('fromJson with no warnings', () {
      final json = {
        'extractorId': 'test',
        'extractorVersion': '1.0',
        'extractedAt': '2024-01-01T00:00:00.000Z',
      };
      final provenance = ExtractionProvenance.fromJson(json);
      expect(provenance.warnings, isNull);
      expect(provenance.extractionDuration, equals(Duration.zero));
    });
  });

  group('TextBlock', () {
    test('creates paragraph block', () {
      const block = TextBlock(
        id: 'p1',
        text: 'Hello World',
        type: TextBlockType.paragraph,
      );
      expect(block.id, equals('p1'));
      expect(block.text, equals('Hello World'));
      expect(block.type, equals(TextBlockType.paragraph));
      expect(block.headingLevel, isNull);
    });

    test('creates heading block with level', () {
      const block = TextBlock(
        id: 'h1',
        text: 'Chapter 1',
        type: TextBlockType.heading,
        headingLevel: 1,
      );
      expect(block.type, equals(TextBlockType.heading));
      expect(block.headingLevel, equals(1));
    });

    test('creates code block with language', () {
      const block = TextBlock(
        id: 'c1',
        text: 'print("hello")',
        type: TextBlockType.code,
        language: 'python',
      );
      expect(block.type, equals(TextBlockType.code));
      expect(block.language, equals('python'));
    });

    test('copyWith preserves values', () {
      const original = TextBlock(
        id: 'p1',
        text: 'Original',
        type: TextBlockType.paragraph,
      );
      final modified = original.copyWith(text: 'Modified');
      expect(modified.id, equals('p1'));
      expect(modified.text, equals('Modified'));
      expect(modified.type, equals(TextBlockType.paragraph));
    });
  });

  group('ImageBlock', () {
    test('creates with required fields', () {
      const block = ImageBlock(
        id: 'img1',
        assetRef: 'file:///image.png',
      );
      expect(block.id, equals('img1'));
      expect(block.assetRef, equals('file:///image.png'));
      expect(block.width, isNull);
      expect(block.height, isNull);
      expect(block.hasOcr, isFalse);
      expect(block.hasVision, isFalse);
    });

    test('creates with dimensions and OCR', () {
      const block = ImageBlock(
        id: 'img1',
        assetRef: 'mem://123',
        width: 800,
        height: 600,
        format: 'png',
        ocrText: 'Extracted text from image',
      );
      expect(block.width, equals(800));
      expect(block.height, equals(600));
      expect(block.format, equals('png'));
      expect(block.hasOcr, isTrue);
      expect(block.ocrText, equals('Extracted text from image'));
    });

    test('creates with vision description', () {
      const block = ImageBlock(
        id: 'img1',
        assetRef: 'mem://456',
        visionDescription: 'A photo of a cat',
      );
      expect(block.hasVision, isTrue);
      expect(block.visionDescription, equals('A photo of a cat'));
    });
  });

  group('AudioBlock', () {
    test('creates with required fields', () {
      const block = AudioBlock(
        id: 'audio1',
        assetRef: 'file:///audio.mp3',
      );
      expect(block.id, equals('audio1'));
      expect(block.assetRef, equals('file:///audio.mp3'));
      expect(block.duration, isNull);
      expect(block.transcript, isNull);
    });

    test('creates with transcript', () {
      const block = AudioBlock(
        id: 'audio1',
        assetRef: 'mem://789',
        duration: Duration(minutes: 5),
        format: 'mp3',
        sampleRate: 44100,
        transcript: 'Hello, this is a test recording.',
      );
      expect(block.duration, equals(const Duration(minutes: 5)));
      expect(block.format, equals('mp3'));
      expect(block.sampleRate, equals(44100));
      expect(block.transcript, isNotNull);
    });

    test('creates with transcript segments', () {
      const block = AudioBlock(
        id: 'audio1',
        assetRef: 'mem://audio',
        transcript: 'Hello World',
        segments: [
          TranscriptSegment(
            startTime: Duration.zero,
            endTime: Duration(milliseconds: 500),
            text: 'Hello',
            confidence: 0.95,
          ),
          TranscriptSegment(
            startTime: Duration(milliseconds: 600),
            endTime: Duration(milliseconds: 1000),
            text: 'World',
            confidence: 0.92,
            speaker: 'SPEAKER_00',
          ),
        ],
      );
      expect(block.segments?.length, equals(2));
      expect(block.segments?.first.text, equals('Hello'));
      expect(block.segments?.last.speaker, equals('SPEAKER_00'));
    });
  });

  group('TranscriptSegment', () {
    test('creates with Duration timestamps', () {
      const segment = TranscriptSegment(
        startTime: Duration(seconds: 1, milliseconds: 500),
        endTime: Duration(seconds: 3),
        text: 'Test segment',
        confidence: 0.88,
      );
      expect(segment.startTime, equals(const Duration(milliseconds: 1500)));
      expect(segment.endTime, equals(const Duration(seconds: 3)));
      expect(segment.text, equals('Test segment'));
      expect(segment.confidence, equals(0.88));
      expect(segment.speaker, isNull);
    });

    test('creates with speaker for diarization', () {
      const segment = TranscriptSegment(
        startTime: Duration.zero,
        endTime: Duration(seconds: 2),
        text: 'Speaker one talking',
        speaker: 'SPEAKER_01',
      );
      expect(segment.speaker, equals('SPEAKER_01'));
    });
  });

  group('TableBlock', () {
    test('creates with rows', () {
      const block = TableBlock(
        id: 'table1',
        rows: [
          TableRow(
            cells: [
              TableCell(text: 'Header 1', type: CellType.header),
              TableCell(text: 'Header 2', type: CellType.header),
            ],
            isHeader: true,
          ),
          TableRow(
            cells: [
              TableCell(text: 'Data 1'),
              TableCell(text: 'Data 2'),
            ],
          ),
        ],
        rowCount: 2,
        columnCount: 2,
      );
      expect(block.rows.length, equals(2));
      expect(block.rowCount, equals(2));
      expect(block.columnCount, equals(2));
      expect(block.rows.first.isHeader, isTrue);
    });

    test('toMarkdown generates markdown table', () {
      const block = TableBlock(
        id: 'table1',
        rows: [
          TableRow(cells: [TableCell(text: 'A'), TableCell(text: 'B')]),
          TableRow(cells: [TableCell(text: '1'), TableCell(text: '2')]),
        ],
        rowCount: 2,
        columnCount: 2,
      );
      final markdown = block.toMarkdown();
      expect(markdown, contains('| A | B |'));
      expect(markdown, contains('| 1 | 2 |'));
    });

    test('toCsv generates CSV', () {
      const block = TableBlock(
        id: 'table1',
        rows: [
          TableRow(cells: [TableCell(text: 'Name'), TableCell(text: 'Value')]),
          TableRow(cells: [TableCell(text: 'Test'), TableCell(text: '123')]),
        ],
        rowCount: 2,
        columnCount: 2,
      );
      final csv = block.toCsv();
      expect(csv, contains('Name,Value'));
      expect(csv, contains('Test,123'));
    });
  });

  group('ListBlock', () {
    test('creates unordered list', () {
      const block = ListBlock(
        id: 'list1',
        type: ListType.unordered,
        items: [
          ListItem(text: 'Item 1'),
          ListItem(text: 'Item 2'),
          ListItem(text: 'Item 3'),
        ],
      );
      expect(block.type, equals(ListType.unordered));
      expect(block.items.length, equals(3));
    });

    test('creates checklist', () {
      const block = ListBlock(
        id: 'list1',
        type: ListType.checklist,
        items: [
          ListItem(text: 'Task 1', checked: true),
          ListItem(text: 'Task 2', checked: false),
        ],
      );
      expect(block.type, equals(ListType.checklist));
      expect(block.items.first.checked, isTrue);
      expect(block.items.last.checked, isFalse);
    });
  });

  group('SourceLocation', () {
    test('creates with page number', () {
      const loc = SourceLocation(pageNumber: 5);
      expect(loc.pageNumber, equals(5));
      expect(loc.lineNumber, isNull);
    });

    test('creates with all fields', () {
      const loc = SourceLocation(
        pageNumber: 3,
        lineNumber: 42,
        charOffset: 1500,
        charLength: 100,
        bbox: BoundingBox(x: 0, y: 0, width: 100, height: 20),
        bboxUnit: 'pt',
      );
      expect(loc.pageNumber, equals(3));
      expect(loc.lineNumber, equals(42));
      expect(loc.charOffset, equals(1500));
      expect(loc.charLength, equals(100));
      expect(loc.bbox, isNotNull);
      expect(loc.bboxUnit, equals('pt'));
    });

    test('empty location has all nulls', () {
      const loc = SourceLocation.empty;
      expect(loc.pageNumber, isNull);
      expect(loc.lineNumber, isNull);
      expect(loc.charOffset, isNull);
    });

    test('toString formats correctly', () {
      const loc = SourceLocation(pageNumber: 1, lineNumber: 10);
      final str = loc.toString();
      expect(str, contains('page: 1'));
      expect(str, contains('line: 10'));
    });

    test('toJson and fromJson round-trip', () {
      const original = SourceLocation(
        pageNumber: 2,
        lineNumber: 15,
        charOffset: 500,
      );
      final json = original.toJson();
      final restored = SourceLocation.fromJson(json);
      expect(restored.pageNumber, equals(2));
      expect(restored.lineNumber, equals(15));
      expect(restored.charOffset, equals(500));
    });
  });

  group('BoundingBox (mcp_ingest)', () {
    test('creates with required fields', () {
      const bbox = BoundingBox(x: 10, y: 20, width: 100, height: 50);
      expect(bbox.x, equals(10));
      expect(bbox.y, equals(20));
      expect(bbox.width, equals(100));
      expect(bbox.height, equals(50));
    });

    test('toJson and fromJson round-trip', () {
      const original = BoundingBox(
        x: 5,
        y: 10,
        width: 200,
        height: 100,
      );
      final json = original.toJson();
      final restored = BoundingBox.fromJson(json);
      expect(restored.x, equals(5));
      expect(restored.y, equals(10));
      expect(restored.width, equals(200));
      expect(restored.height, equals(100));
    });
  });

  group('NormalizedDocument', () {
    test('creates with required fields', () {
      final doc = NormalizedDocument(
        id: 'doc1',
        metadata: const DocumentMetadata(
          mimeType: 'text/plain',
          sha256: 'hash123',
          fileSize: 100,
        ),
        parts: const [
          TextBlock(id: 'p1', text: 'Hello World'),
        ],
        structure: DocumentStructure.empty,
        provenance: ExtractionProvenance(
          extractorId: 'test_v1',
          extractorVersion: '1.0.0',
          extractedAt: DateTime.now(),
          extractionDuration: const Duration(milliseconds: 50),
        ),
      );
      expect(doc.id, equals('doc1'));
      expect(doc.parts.length, equals(1));
      expect(doc.fullText, equals('Hello World'));
    });

    test('fullText concatenates all text parts', () {
      final doc = NormalizedDocument(
        id: 'doc1',
        metadata: const DocumentMetadata(
          mimeType: 'text/plain',
          sha256: 'hash',
          fileSize: 50,
        ),
        parts: const [
          TextBlock(id: 'p1', text: 'First'),
          TextBlock(id: 'p2', text: 'Second'),
          TextBlock(id: 'p3', text: 'Third'),
        ],
        structure: DocumentStructure.empty,
        provenance: ExtractionProvenance(
          extractorId: 'test',
          extractorVersion: '1.0',
          extractedAt: DateTime.now(),
          extractionDuration: Duration.zero,
        ),
      );
      expect(doc.fullText, equals('First\n\nSecond\n\nThird'));
    });

    test('textBlocks filters only TextBlock parts', () {
      final doc = NormalizedDocument(
        id: 'doc1',
        metadata: const DocumentMetadata(
          mimeType: 'text/html',
          sha256: 'hash',
          fileSize: 200,
        ),
        parts: const [
          TextBlock(id: 'p1', text: 'Text'),
          ImageBlock(id: 'img1', assetRef: 'ref'),
          TextBlock(id: 'p2', text: 'More text'),
        ],
        structure: DocumentStructure.empty,
        provenance: ExtractionProvenance(
          extractorId: 'html',
          extractorVersion: '1.0',
          extractedAt: DateTime.now(),
          extractionDuration: Duration.zero,
        ),
      );
      expect(doc.textBlocks.length, equals(2));
    });
  });

  group('Chunk', () {
    test('creates with required fields', () {
      const chunk = Chunk(
        id: 'chunk1',
        text: 'Chunk content',
        sourceSpans: [
          ChunkSpan(partId: 'p1', startOffset: 0, endOffset: 13),
        ],
        location: SourceLocation(pageNumber: 1),
        index: 0,
        totalChunks: 1,
      );
      expect(chunk.id, equals('chunk1'));
      expect(chunk.text, equals('Chunk content'));
      expect(chunk.index, equals(0));
      expect(chunk.totalChunks, equals(1));
    });

    test('creates with source spans', () {
      const chunk = Chunk(
        id: 'chunk1',
        text: 'Content from multiple parts',
        sourceSpans: [
          ChunkSpan(partId: 'p1', startOffset: 0, endOffset: 10),
          ChunkSpan(partId: 'p2', startOffset: 0, endOffset: 17),
        ],
        location: SourceLocation(pageNumber: 1),
        index: 0,
        totalChunks: 1,
      );
      expect(chunk.sourceSpans.length, equals(2));
      expect(chunk.sourcePartIds.length, equals(2));
      expect(chunk.crossesParts, isTrue);
    });

    test('length returns text length', () {
      const chunk = Chunk(
        id: 'c1',
        text: 'Hello',
        sourceSpans: [
          ChunkSpan(partId: 'p1', startOffset: 0, endOffset: 5),
        ],
        location: SourceLocation.empty,
        index: 0,
        totalChunks: 1,
      );
      expect(chunk.length, equals(5));
    });

    test('fullText includes context prefix', () {
      const chunk = Chunk(
        id: 'c1',
        text: 'Main content',
        sourceSpans: [
          ChunkSpan(partId: 'p1', startOffset: 0, endOffset: 12),
        ],
        location: SourceLocation.empty,
        index: 0,
        totalChunks: 1,
        contextPrefix: 'Chapter 1: Introduction',
      );
      expect(chunk.fullText, equals('Chapter 1: Introduction\n\nMain content'));
    });

    test('ChunkSpan length calculates correctly', () {
      const span = ChunkSpan(partId: 'p1', startOffset: 10, endOffset: 30);
      expect(span.length, equals(20));
    });

    test('toJson and fromJson round-trip', () {
      const original = Chunk(
        id: 'chunk1',
        text: 'Test text',
        sourceSpans: [
          ChunkSpan(partId: 'p1', startOffset: 0, endOffset: 9),
        ],
        location: SourceLocation(pageNumber: 2, lineNumber: 5),
        index: 3,
        totalChunks: 10,
        contextPrefix: 'Context',
      );
      final json = original.toJson();
      final restored = Chunk.fromJson(json);
      expect(restored.id, equals('chunk1'));
      expect(restored.text, equals('Test text'));
      expect(restored.index, equals(3));
      expect(restored.totalChunks, equals(10));
      expect(restored.contextPrefix, equals('Context'));
      expect(restored.sourceSpans.length, equals(1));
    });
  });

  group('NormalizedDocument extended', () {
    late NormalizedDocument testDoc;

    setUp(() {
      testDoc = NormalizedDocument(
        id: 'doc1',
        metadata: const DocumentMetadata(
          mimeType: 'text/html',
          sha256: 'hash',
          fileSize: 500,
        ),
        parts: const [
          TextBlock(id: 'p1', text: 'Paragraph one'),
          TableBlock(
            id: 't1',
            rows: [
              TableRow(cells: [TableCell(text: 'A'), TableCell(text: 'B')]),
            ],
            rowCount: 1,
            columnCount: 2,
          ),
          ImageBlock(id: 'img1', assetRef: 'ref1'),
          AudioBlock(id: 'audio1', assetRef: 'ref2'),
          KeyValueBlock(id: 'kv1', key: 'Name', value: 'Test'),
          ListBlock(
            id: 'list1',
            type: ListType.unordered,
            items: [ListItem(text: 'Item')],
          ),
        ],
        structure: DocumentStructure.empty,
        provenance: ExtractionProvenance(
          extractorId: 'test',
          extractorVersion: '1.0',
          extractedAt: DateTime.now(),
          extractionDuration: Duration.zero,
        ),
      );
    });

    test('characterCount returns full text length', () {
      expect(testDoc.characterCount, greaterThan(0));
    });

    test('partCount returns total parts', () {
      expect(testDoc.partCount, equals(6));
    });

    test('tableBlocks returns only table blocks', () {
      expect(testDoc.tableBlocks.length, equals(1));
      expect(testDoc.tableBlocks.first.id, equals('t1'));
    });

    test('imageBlocks returns only image blocks', () {
      expect(testDoc.imageBlocks.length, equals(1));
      expect(testDoc.imageBlocks.first.id, equals('img1'));
    });

    test('audioBlocks returns only audio blocks', () {
      expect(testDoc.audioBlocks.length, equals(1));
      expect(testDoc.audioBlocks.first.id, equals('audio1'));
    });

    test('keyValueBlocks returns only key-value blocks', () {
      expect(testDoc.keyValueBlocks.length, equals(1));
      expect(testDoc.keyValueBlocks.first.key, equals('Name'));
    });

    test('findPart returns part by ID', () {
      final part = testDoc.findPart('p1');
      expect(part, isNotNull);
      expect(part, isA<TextBlock>());
    });

    test('findPart returns null for unknown ID', () {
      final part = testDoc.findPart('unknown');
      expect(part, isNull);
    });

    test('copyWithParts creates new document with updated parts', () {
      final newParts = [const TextBlock(id: 'new', text: 'New content')];
      final newDoc = testDoc.copyWithParts(newParts);
      expect(newDoc.parts.length, equals(1));
      expect(newDoc.id, equals(testDoc.id));
    });

    test('updatePart replaces specific part', () {
      final newDoc = testDoc.updatePart(
        'p1',
        const TextBlock(id: 'p1', text: 'Updated'),
      );
      final updated = newDoc.findPart('p1') as TextBlock;
      expect(updated.text, equals('Updated'));
    });

    test('partsOfType returns filtered parts', () {
      final textParts = testDoc.partsOfType<TextBlock>();
      expect(textParts.length, equals(1));
    });
  });

  group('DocumentStructure', () {
    test('empty structure has no nodes', () {
      const structure = DocumentStructure.empty;
      expect(structure.nodes, isEmpty);
      expect(structure.flatPartIds, isEmpty);
    });

    test('flatPartIds collects all part IDs', () {
      const structure = DocumentStructure(
        nodes: [
          StructureNode(
            id: 'ch1',
            type: StructureType.chapter,
            title: 'Chapter 1',
            partIds: ['p1', 'p2'],
            children: [
              StructureNode(
                id: 'sec1',
                type: StructureType.section,
                title: 'Section 1.1',
                partIds: ['p3'],
              ),
            ],
          ),
          StructureNode(
            id: 'ch2',
            type: StructureType.chapter,
            title: 'Chapter 2',
            partIds: ['p4'],
          ),
        ],
      );
      expect(structure.flatPartIds, containsAll(['p1', 'p2', 'p3', 'p4']));
    });

    test('findNode returns node by ID', () {
      const structure = DocumentStructure(
        nodes: [
          StructureNode(
            id: 'root',
            type: StructureType.document,
            children: [
              StructureNode(id: 'child', type: StructureType.section),
            ],
          ),
        ],
      );
      expect(structure.findNode('root'), isNotNull);
      expect(structure.findNode('child'), isNotNull);
      expect(structure.findNode('unknown'), isNull);
    });

    test('getNode is alias for findNode', () {
      const structure = DocumentStructure(
        nodes: [
          StructureNode(id: 'n1', type: StructureType.section),
        ],
      );
      expect(structure.getNode('n1'), equals(structure.findNode('n1')));
    });

    test('findSectionForPart returns section title', () {
      const structure = DocumentStructure(
        nodes: [
          StructureNode(
            id: 'ch1',
            type: StructureType.chapter,
            title: 'Chapter One',
            partIds: ['p1'],
          ),
        ],
      );
      expect(structure.findSectionForPart('p1'), equals('Chapter One'));
      expect(structure.findSectionForPart('unknown'), isNull);
    });

    test('findSectionForPart searches nested children', () {
      const structure = DocumentStructure(
        nodes: [
          StructureNode(
            id: 'ch1',
            type: StructureType.chapter,
            title: 'Chapter',
            children: [
              StructureNode(
                id: 'sec1',
                type: StructureType.section,
                title: 'Section',
                partIds: ['p1'],
              ),
            ],
          ),
        ],
      );
      expect(structure.findSectionForPart('p1'), equals('Section'));
    });

    test('getSectionPath returns hierarchical path', () {
      const structure = DocumentStructure(
        nodes: [
          StructureNode(
            id: 'ch1',
            type: StructureType.chapter,
            title: 'Chapter 1',
            children: [
              StructureNode(
                id: 'sec1',
                type: StructureType.section,
                title: 'Section 1.1',
                partIds: ['p1'],
              ),
            ],
          ),
        ],
      );
      final path = structure.getSectionPath('p1');
      expect(path, equals(['Chapter 1', 'Section 1.1']));
    });

    test('getSectionPath returns empty for unknown part', () {
      const structure = DocumentStructure.empty;
      expect(structure.getSectionPath('unknown'), isEmpty);
    });

    test('toJson and fromJson round-trip', () {
      const original = DocumentStructure(
        nodes: [
          StructureNode(
            id: 'ch1',
            type: StructureType.chapter,
            title: 'Test Chapter',
            level: 1,
            partIds: ['p1'],
          ),
        ],
      );
      final json = original.toJson();
      final restored = DocumentStructure.fromJson(json);
      expect(restored.nodes.length, equals(1));
      expect(restored.nodes.first.title, equals('Test Chapter'));
    });

    test('fromJson with empty nodes', () {
      final json = <String, dynamic>{};
      final structure = DocumentStructure.fromJson(json);
      expect(structure.nodes, isEmpty);
    });
  });

  group('StructureNode', () {
    test('creates with defaults', () {
      const node = StructureNode(
        id: 'n1',
        type: StructureType.section,
      );
      expect(node.level, equals(0));
      expect(node.partIds, isEmpty);
      expect(node.children, isEmpty);
      expect(node.title, isNull);
    });

    test('toJson and fromJson round-trip', () {
      const original = StructureNode(
        id: 'ch1',
        type: StructureType.chapter,
        title: 'Chapter',
        level: 1,
        partIds: ['p1', 'p2'],
        children: [
          StructureNode(id: 'sec1', type: StructureType.section),
        ],
      );
      final json = original.toJson();
      final restored = StructureNode.fromJson(json);
      expect(restored.id, equals('ch1'));
      expect(restored.type, equals(StructureType.chapter));
      expect(restored.title, equals('Chapter'));
      expect(restored.level, equals(1));
      expect(restored.partIds, containsAll(['p1', 'p2']));
      expect(restored.children.length, equals(1));
    });

    test('fromJson with unknown type falls back to section', () {
      final json = {
        'id': 'n1',
        'type': 'unknown_type',
      };
      final node = StructureNode.fromJson(json);
      expect(node.type, equals(StructureType.section));
    });
  });

  group('TextSpan', () {
    test('creates with required fields', () {
      const span = TextSpan(
        start: 0,
        end: 10,
        type: TextSpanType.bold,
      );
      expect(span.start, equals(0));
      expect(span.end, equals(10));
      expect(span.type, equals(TextSpanType.bold));
      expect(span.value, isNull);
    });

    test('creates link with URL value', () {
      const span = TextSpan(
        start: 5,
        end: 15,
        type: TextSpanType.link,
        value: 'https://example.com',
      );
      expect(span.type, equals(TextSpanType.link));
      expect(span.value, equals('https://example.com'));
    });

    test('length calculates correctly', () {
      const span = TextSpan(start: 10, end: 25, type: TextSpanType.italic);
      expect(span.length, equals(15));
    });

    test('toJson and fromJson round-trip', () {
      const original = TextSpan(
        start: 0,
        end: 5,
        type: TextSpanType.code,
        value: 'note',
      );
      final json = original.toJson();
      final restored = TextSpan.fromJson(json);
      expect(restored.start, equals(0));
      expect(restored.end, equals(5));
      expect(restored.type, equals(TextSpanType.code));
      expect(restored.value, equals('note'));
    });
  });

  group('TableCell', () {
    test('creates with defaults', () {
      const cell = TableCell(text: 'Value');
      expect(cell.text, equals('Value'));
      expect(cell.rowSpan, equals(1));
      expect(cell.colSpan, equals(1));
      expect(cell.type, equals(CellType.data));
      expect(cell.isHeader, isFalse);
    });

    test('creates header cell', () {
      const cell = TableCell(text: 'Header', type: CellType.header);
      expect(cell.isHeader, isTrue);
    });

    test('creates with spans', () {
      const cell = TableCell(
        text: 'Merged',
        rowSpan: 2,
        colSpan: 3,
      );
      expect(cell.rowSpan, equals(2));
      expect(cell.colSpan, equals(3));
    });

    test('toJson and fromJson round-trip', () {
      const original = TableCell(
        text: 'Data',
        rowSpan: 2,
        colSpan: 1,
        type: CellType.header,
        dataType: 'number',
      );
      final json = original.toJson();
      final restored = TableCell.fromJson(json);
      expect(restored.text, equals('Data'));
      expect(restored.rowSpan, equals(2));
      expect(restored.type, equals(CellType.header));
      expect(restored.dataType, equals('number'));
    });

    test('fromJson with isHeader flag', () {
      final json = {
        'text': 'Header',
        'isHeader': true,
      };
      final cell = TableCell.fromJson(json);
      expect(cell.type, equals(CellType.header));
    });

    test('fromJson with content instead of text', () {
      final json = {'content': 'Content value'};
      final cell = TableCell.fromJson(json);
      expect(cell.text, equals('Content value'));
    });
  });

  group('TableRow', () {
    test('creates with cells', () {
      const row = TableRow(
        cells: [
          TableCell(text: 'A'),
          TableCell(text: 'B'),
        ],
      );
      expect(row.cells.length, equals(2));
      expect(row.isHeader, isFalse);
    });

    test('creates header row', () {
      const row = TableRow(
        cells: [TableCell(text: 'H1')],
        isHeader: true,
      );
      expect(row.isHeader, isTrue);
    });

    test('toJson and fromJson round-trip', () {
      const original = TableRow(
        cells: [TableCell(text: 'Cell1'), TableCell(text: 'Cell2')],
        isHeader: true,
      );
      final json = original.toJson();
      final restored = TableRow.fromJson(json);
      expect(restored.cells.length, equals(2));
      expect(restored.isHeader, isTrue);
    });

    test('fromJson with empty cells', () {
      final json = <String, dynamic>{};
      final row = TableRow.fromJson(json);
      expect(row.cells, isEmpty);
    });
  });

  group('TableBlock extended', () {
    test('toMarkdown handles empty table', () {
      const block = TableBlock(
        id: 't1',
        rows: [],
        rowCount: 0,
        columnCount: 0,
      );
      expect(block.toMarkdown(), isEmpty);
    });

    test('toCsv handles empty table', () {
      const block = TableBlock(
        id: 't1',
        rows: [],
        rowCount: 0,
        columnCount: 0,
      );
      expect(block.toCsv(), isEmpty);
    });

    test('toCsv escapes special characters', () {
      const block = TableBlock(
        id: 't1',
        rows: [
          TableRow(cells: [
            TableCell(text: 'Value with, comma'),
            TableCell(text: 'Value with "quotes"'),
          ]),
        ],
        rowCount: 1,
        columnCount: 2,
      );
      final csv = block.toCsv();
      expect(csv, contains('"Value with, comma"'));
      expect(csv, contains('"Value with ""quotes"""'));
    });

    test('copyWith preserves values', () {
      const original = TableBlock(
        id: 't1',
        rows: [TableRow(cells: [TableCell(text: 'A')])],
        rowCount: 1,
        columnCount: 1,
        caption: 'Original',
      );
      final modified = original.copyWith(caption: 'Modified');
      expect(modified.id, equals('t1'));
      expect(modified.caption, equals('Modified'));
    });
  });

  group('ListItem', () {
    test('creates with text', () {
      const item = ListItem(text: 'Item text');
      expect(item.text, equals('Item text'));
      expect(item.checked, isNull);
      expect(item.children, isNull);
    });

    test('creates checklist item', () {
      const item = ListItem(text: 'Task', checked: true);
      expect(item.checked, isTrue);
    });

    test('creates with nested children', () {
      const item = ListItem(
        text: 'Parent',
        children: [
          ListItem(text: 'Child 1'),
          ListItem(text: 'Child 2'),
        ],
      );
      expect(item.children?.length, equals(2));
    });

    test('toJson and fromJson round-trip', () {
      const original = ListItem(
        text: 'Task',
        checked: false,
        children: [ListItem(text: 'Subtask')],
      );
      final json = original.toJson();
      final restored = ListItem.fromJson(json);
      expect(restored.text, equals('Task'));
      expect(restored.checked, isFalse);
      expect(restored.children?.length, equals(1));
    });

    test('fromJson with content instead of text', () {
      final json = {'content': 'Content value'};
      final item = ListItem.fromJson(json);
      expect(item.text, equals('Content value'));
    });
  });

  group('ListBlock extended', () {
    test('creates ordered list with start number', () {
      const block = ListBlock(
        id: 'list1',
        type: ListType.ordered,
        items: [ListItem(text: 'First')],
        startNumber: 5,
      );
      expect(block.type, equals(ListType.ordered));
      expect(block.startNumber, equals(5));
    });

    test('copyWith preserves values', () {
      const original = ListBlock(
        id: 'list1',
        type: ListType.unordered,
        items: [ListItem(text: 'Item')],
      );
      final modified = original.copyWith(type: ListType.ordered);
      expect(modified.id, equals('list1'));
      expect(modified.type, equals(ListType.ordered));
    });
  });

  group('KeyValueBlock', () {
    test('creates with defaults', () {
      const block = KeyValueBlock(
        id: 'kv1',
        key: 'Name',
        value: 'John Doe',
      );
      expect(block.key, equals('Name'));
      expect(block.value, equals('John Doe'));
      expect(block.confidence, equals(0.8));
    });

    test('copyWith preserves values', () {
      const original = KeyValueBlock(
        id: 'kv1',
        key: 'Field',
        value: 'Original',
        confidence: 0.9,
      );
      final modified = original.copyWith(value: 'Modified');
      expect(modified.key, equals('Field'));
      expect(modified.value, equals('Modified'));
      expect(modified.confidence, equals(0.9));
    });
  });

  group('ImageBlock extended', () {
    test('copyWith preserves values', () {
      const original = ImageBlock(
        id: 'img1',
        assetRef: 'ref',
        width: 800,
        height: 600,
      );
      final modified = original.copyWith(ocrText: 'Extracted text');
      expect(modified.width, equals(800));
      expect(modified.ocrText, equals('Extracted text'));
      expect(modified.hasOcr, isTrue);
    });
  });

  group('AudioBlock extended', () {
    test('copyWith preserves values', () {
      const original = AudioBlock(
        id: 'audio1',
        assetRef: 'ref',
        duration: Duration(minutes: 5),
      );
      final modified = original.copyWith(transcript: 'Transcribed text');
      expect(modified.duration, equals(const Duration(minutes: 5)));
      expect(modified.transcript, equals('Transcribed text'));
    });
  });
}
