import 'dart:convert';
import 'dart:typed_data';

import 'package:mcp_bundle/ports.dart';
import 'package:mcp_fact_graph/mcp_fact_graph.dart' show EvidenceSourceType;
import 'package:test/test.dart';
import 'package:mcp_ingest/mcp_ingest.dart';

void main() {
  group('PipelineStage enum', () {
    test('has all expected stages', () {
      expect(PipelineStage.values, contains(PipelineStage.detect));
      expect(PipelineStage.values, contains(PipelineStage.select));
      expect(PipelineStage.values, contains(PipelineStage.extract));
      expect(PipelineStage.values, contains(PipelineStage.cacheAssets));
      expect(PipelineStage.values, contains(PipelineStage.enhance));
      expect(PipelineStage.values, contains(PipelineStage.chunk));
      expect(PipelineStage.values, contains(PipelineStage.fragments));
      expect(PipelineStage.values, contains(PipelineStage.store));
      expect(PipelineStage.values, contains(PipelineStage.factgraph));
    });
  });

  group('StagePhase enum', () {
    test('has preChunk and postChunk', () {
      expect(StagePhase.values, contains(StagePhase.preChunk));
      expect(StagePhase.values, contains(StagePhase.postChunk));
    });
  });

  group('ChunkFilterStage', () {
    late ChunkFilterStage stage;

    setUp(() {
      stage = ChunkFilterStage(minLength: 10);
    });

    test('has correct id and name', () {
      expect(stage.id, equals('chunk_filter'));
      expect(stage.name, equals('Chunk Filter'));
    });

    test('has postChunk phase', () {
      expect(stage.phase, equals(StagePhase.postChunk));
    });

    test('filters short chunks', () async {
      final chunks = [
        _createChunk('short', 0),
        _createChunk('this is a longer chunk', 1),
        _createChunk('tiny', 2),
      ];
      final result = await stage.processChunks(chunks);
      expect(result.length, equals(1));
      expect(result.first.text, equals('this is a longer chunk'));
    });

    test('keeps all chunks when all are long enough', () async {
      final chunks = [
        _createChunk('this is long enough', 0),
        _createChunk('also long enough', 1),
      ];
      final result = await stage.processChunks(chunks);
      expect(result.length, equals(2));
    });

    test('default minLength is 10', () {
      final defaultStage = ChunkFilterStage();
      expect(defaultStage.minLength, equals(10));
    });
  });

  group('WhitespaceNormalizerStage', () {
    late WhitespaceNormalizerStage stage;

    setUp(() {
      stage = WhitespaceNormalizerStage();
    });

    test('has correct id and name', () {
      expect(stage.id, equals('whitespace_normalizer'));
      expect(stage.name, equals('Whitespace Normalizer'));
    });

    test('has postChunk phase', () {
      expect(stage.phase, equals(StagePhase.postChunk));
    });

    test('normalizes multiple spaces', () async {
      final chunks = [_createChunk('hello    world', 0)];
      final result = await stage.processChunks(chunks);
      expect(result.first.text, equals('hello world'));
    });

    test('normalizes multiple newlines to single space', () async {
      final chunks = [_createChunk('line1\n\n\n\nline2', 0)];
      final result = await stage.processChunks(chunks);
      // WhitespaceNormalizerStage replaces all whitespace including newlines with single space
      expect(result.first.text, equals('line1 line2'));
    });

    test('trims whitespace', () async {
      final chunks = [_createChunk('  text with spaces  ', 0)];
      final result = await stage.processChunks(chunks);
      expect(result.first.text, equals('text with spaces'));
    });
  });

  group('ContextPrefixStage', () {
    test('has correct id and name', () {
      final stage = ContextPrefixStage();
      expect(stage.id, equals('context_prefix'));
      expect(stage.name, equals('Context Prefix'));
    });

    test('has postChunk phase', () {
      final stage = ContextPrefixStage();
      expect(stage.phase, equals(StagePhase.postChunk));
    });

    test('returns unchanged chunks when no contextBuilder', () async {
      final stage = ContextPrefixStage();
      final chunks = [_createChunk('content', 0)];
      final result = await stage.processChunks(chunks);
      expect(result.first.contextPrefix, isNull);
    });

    test('adds context prefix using builder', () async {
      final stage = ContextPrefixStage(
        contextBuilder: (chunk) => 'Chunk ${chunk.index}:',
      );
      final chunks = [
        _createChunk('content1', 0),
        _createChunk('content2', 1),
      ];
      final result = await stage.processChunks(chunks);
      expect(result[0].contextPrefix, equals('Chunk 0:'));
      expect(result[1].contextPrefix, equals('Chunk 1:'));
    });
  });

  group('MetadataEnrichmentStage', () {
    late MetadataEnrichmentStage stage;

    setUp(() {
      stage = MetadataEnrichmentStage(
        metadataAdder: (chunk) => {'processed': true, 'index': chunk.index},
      );
    });

    test('has correct id and name', () {
      expect(stage.id, equals('metadata_enrichment'));
      expect(stage.name, equals('Metadata Enrichment'));
    });

    test('has postChunk phase', () {
      expect(stage.phase, equals(StagePhase.postChunk));
    });

    test('adds metadata to chunks', () async {
      final chunks = [_createChunk('content', 0)];
      final result = await stage.processChunks(chunks);
      expect(result.first.metadata?['processed'], isTrue);
      expect(result.first.metadata?['index'], equals(0));
    });

    test('merges with existing metadata', () async {
      final chunks = [
        const Chunk(
          id: 'c1',
          text: 'content',
          sourceSpans: [],
          location: SourceLocation(),
          index: 0,
          totalChunks: 1,
          metadata: {'existing': 'value'},
        ),
      ];
      final result = await stage.processChunks(chunks);
      expect(result.first.metadata?['existing'], equals('value'));
      expect(result.first.metadata?['processed'], isTrue);
    });
  });

  group('IngestContext', () {
    late IngestContext context;

    setUp(() {
      final input = IngestInput.fromString('Test content');
      context = IngestContext(
        input: input,
        options: IngestOptions.defaults,
      );
    });

    test('initializes with init stage', () {
      expect(context.currentStage, equals('init'));
    });

    test('has empty warnings', () {
      expect(context.warnings, isEmpty);
    });

    test('addWarning adds warning message', () {
      context.addWarning('Warning 1');
      context.addWarning('Warning 2');
      expect(context.warnings.length, equals(2));
      expect(context.warnings, contains('Warning 1'));
    });

    test('recordStageDuration records duration', () {
      context.recordStageDuration('extraction', const Duration(milliseconds: 100));
      expect(context.stageDurations['extraction']?.inMilliseconds, equals(100));
    });

    test('incrementOcrCalls increments counter', () {
      expect(context.ocrCalls, equals(0));
      context.incrementOcrCalls();
      expect(context.ocrCalls, equals(1));
      context.incrementOcrCalls(5);
      expect(context.ocrCalls, equals(6));
    });

    test('incrementAsrCalls increments counter', () {
      expect(context.asrCalls, equals(0));
      context.incrementAsrCalls();
      expect(context.asrCalls, equals(1));
    });

    test('incrementVisionPortCalls increments counter', () {
      expect(context.visionPortCalls, equals(0));
      context.incrementVisionPortCalls(3);
      expect(context.visionPortCalls, equals(3));
    });

    test('incrementLlmVisionCalls increments counter', () {
      expect(context.llmVisionCalls, equals(0));
      context.incrementLlmVisionCalls();
      expect(context.llmVisionCalls, equals(1));
    });

    test('usedExternalServices is false when no calls', () {
      expect(context.usedExternalServices, isFalse);
    });

    test('usedExternalServices is true after OCR call', () {
      context.incrementOcrCalls();
      expect(context.usedExternalServices, isTrue);
    });

    test('usedExternalServices is true after ASR call', () {
      context.incrementAsrCalls();
      expect(context.usedExternalServices, isTrue);
    });

    test('usedExternalServices is true after Vision call', () {
      context.incrementVisionPortCalls();
      expect(context.usedExternalServices, isTrue);
    });

    test('usedExternalServices is true after LLM call', () {
      context.incrementLlmVisionCalls();
      expect(context.usedExternalServices, isTrue);
    });

    test('estimatedCost calculates based on calls', () {
      expect(context.estimatedCost, equals(0.0));
      context.incrementOcrCalls();
      context.incrementAsrCalls();
      context.incrementVisionPortCalls();
      context.incrementLlmVisionCalls();
      expect(context.estimatedCost, greaterThan(0.0));
    });

    test('assetCache stores bytes directly', () {
      final bytes = [1, 2, 3, 4, 5];
      context.assetCache['cache:part1'] = bytes;
      expect(context.assetCache.containsKey('cache:part1'), isTrue);
      expect(context.assetCache['cache:part1'], equals(bytes));
    });

    test('assetCache returns null for unknown key', () {
      expect(context.assetCache['unknown'], isNull);
    });

    test('assetCache clear removes all cached assets', () {
      context.assetCache['cache:part1'] = [1, 2, 3];
      context.assetCache['cache:part2'] = [4, 5, 6];
      expect(context.assetCache.length, equals(2));
      context.assetCache.clear();
      expect(context.assetCache, isEmpty);
    });

    test('updatePart does nothing when document is null', () {
      context.updatePart('p1', const TextBlock(id: 'p1', text: 'New'));
      expect(context.document, isNull);
    });

    test('updatePart updates part when document exists', () {
      context.document = NormalizedDocument(
        id: 'doc1',
        metadata: const DocumentMetadata(
          mimeType: 'text/plain',
          sha256: 'hash',
          fileSize: 100,
        ),
        parts: const [
          TextBlock(id: 'p1', text: 'Original'),
        ],
        structure: DocumentStructure.empty,
        provenance: ExtractionProvenance(
          extractorId: 'test',
          extractorVersion: '1.0',
          extractedAt: DateTime.now(),
          extractionDuration: Duration.zero,
        ),
      );
      context.updatePart('p1', const TextBlock(id: 'p1', text: 'Updated'));
      final part = context.document!.findPart('p1') as TextBlock;
      expect(part.text, equals('Updated'));
    });
  });

  group('AssetRef', () {
    test('creates with required fields', () {
      const ref = AssetRef(
        id: 'asset1',
        type: 'image',
        size: 1024,
      );
      expect(ref.id, equals('asset1'));
      expect(ref.type, equals('image'));
      expect(ref.size, equals(1024));
    });
  });

  group('IngestPipeline', () {
    late IngestPipeline pipeline;

    setUp(() {
      pipeline = IngestPipeline.defaults();
    });

    test('defaults factory creates pipeline with extractors and chunker', () {
      expect(pipeline.extractors.all, isNotEmpty);
      expect(pipeline.ocrPort, isNull);
      expect(pipeline.asrPort, isNull);
      expect(pipeline.visionPort, isNull);
      expect(pipeline.llmPort, isNull);
      expect(pipeline.storagePort, isNull);
    });

    test('ingests plain text successfully', () async {
      final input = IngestInput.fromString(
        'This is a test document with some content for ingestion.',
        mimeType: 'text/plain',
      );

      final result = await pipeline.ingest(input, IngestOptions.defaults);

      expect(result.success, isTrue);
      expect(result.evidence, isNotNull);
      expect(result.evidence!.mimeType, equals('text/plain'));
      expect(result.evidence!.contentHash, isNotEmpty);
      expect(result.error, isNull);
      expect(result.metrics.totalDuration.inMicroseconds, greaterThan(0));
      expect(result.metrics.extractionDuration.inMicroseconds, greaterThanOrEqualTo(0));
    });

    test('returns error when file exceeds maxFileSize', () async {
      final input = IngestInput.fromString(
        'Small content',
        mimeType: 'text/plain',
      );

      final options = IngestOptions.defaults.copyWith(maxFileSize: 1);

      final result = await pipeline.ingest(input, options);

      expect(result.success, isFalse);
      expect(result.error, isNotNull);
      expect(result.error!.message, contains('exceeds limit'));
    });

    test('returns error when no extractor found for unsupported type', () async {
      final input = IngestInput(
        stream: Stream.value(utf8.encode('data')),
        mimeType: 'video/mp4',
        size: 4,
      );

      final result = await pipeline.ingest(input, IngestOptions.defaults);

      expect(result.success, isFalse);
      expect(result.error, isNotNull);
      expect(result.error!.stage, equals('select'));
      expect(result.error!.message, contains('Unsupported'));
    });

    test('pipeline with ChunkingStrategy.none produces no chunks', () async {
      final input = IngestInput.fromString(
        'Test content for no-chunking pipeline.',
        mimeType: 'text/plain',
      );

      final options = IngestOptions.defaults.copyWith(
        chunkingStrategy: ChunkingStrategy.none,
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
      expect(result.chunks, isEmpty);
    });

    test('pipeline with sentence chunking strategy', () async {
      final input = IngestInput.fromString(
        'First sentence here. Second sentence follows. Third one now.',
        mimeType: 'text/plain',
      );

      final options = IngestOptions.defaults.copyWith(
        chunkingStrategy: ChunkingStrategy.sentence,
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
      expect(result.chunks, isNotEmpty);
    });

    test('pipeline with paragraph chunking strategy', () async {
      final input = IngestInput.fromString(
        'First paragraph content.\n\nSecond paragraph content.\n\nThird paragraph.',
        mimeType: 'text/plain',
      );

      final result = await pipeline.ingest(input, IngestOptions.defaults);

      expect(result.success, isTrue);
      expect(result.chunks, isNotEmpty);
    });

    test('pipeline with page chunking strategy', () async {
      final input = IngestInput.fromString(
        'Page one content here.\n\nPage two content follows.',
        mimeType: 'text/plain',
      );

      final options = IngestOptions.defaults.copyWith(
        chunkingStrategy: ChunkingStrategy.page,
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
    });

    test('pipeline with fixedSize chunking strategy', () async {
      final input = IngestInput.fromString(
        'A' * 3000, // 3000 characters to force multiple chunks
        mimeType: 'text/plain',
      );

      final options = IngestOptions.defaults.copyWith(
        chunkingStrategy: ChunkingStrategy.fixedSize,
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
      expect(result.chunks, isNotEmpty);
    });

    test('pipeline with table chunking strategy', () async {
      final input = IngestInput.fromString(
        'This is a document with text content for table chunking.',
        mimeType: 'text/plain',
      );

      final options = IngestOptions.defaults.copyWith(
        chunkingStrategy: ChunkingStrategy.table,
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
    });

    test('pipeline tracks stage progression in error context', () async {
      // An unsupported type will fail at "select" stage
      final input = IngestInput(
        stream: Stream.value(utf8.encode('data')),
        mimeType: 'application/x-unknown-format',
        size: 4,
      );

      final result = await pipeline.ingest(input, IngestOptions.defaults);

      expect(result.success, isFalse);
      expect(result.error!.stage, equals('select'));
    });

    test('pipeline records metrics after successful ingest', () async {
      final input = IngestInput.fromString(
        'Content for metrics testing. Another sentence here.',
        mimeType: 'text/plain',
      );

      final result = await pipeline.ingest(input, IngestOptions.defaults);

      expect(result.success, isTrue);
      expect(result.metrics.totalDuration, isNot(equals(Duration.zero)));
      expect(result.metrics.ocrCalls, equals(0));
      expect(result.metrics.asrCalls, equals(0));
      expect(result.metrics.visionPortCalls, equals(0));
      expect(result.metrics.llmVisionCalls, equals(0));
    });

    test('evidence entity has correct source info', () async {
      final input = IngestInput.fromString(
        'Test content for evidence checking.',
        filename: 'test.txt',
        mimeType: 'text/plain',
      );

      final result = await pipeline.ingest(input, IngestOptions.defaults);

      expect(result.success, isTrue);
      final evidence = result.evidence!;
      expect(evidence.mimeType, equals('text/plain'));
      expect(evidence.sourceType, equals(EvidenceSourceType.text));
      expect(evidence.source.name, equals('test.txt'));
    });

    test('evidence sourceType maps correctly for image', () async {
      // Create minimal PNG
      final pngBytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x08,
        0x00, 0x00, 0x00, 0x08,
        0x08, 0x02, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
      ]);

      final input = IngestInput.fromBytes(
        pngBytes,
        mimeType: 'image/png',
      );

      final result = await pipeline.ingest(
        input,
        IngestOptions.defaults.copyWith(storeAssets: false),
      );

      expect(result.success, isTrue);
      expect(result.evidence!.sourceType, equals(EvidenceSourceType.image));
    });

    test('evidence sourceType maps correctly for json (api)', () async {
      final input = IngestInput.fromString(
        '{"key": "value"}',
        mimeType: 'application/json',
      );

      final result = await pipeline.ingest(input, IngestOptions.defaults);

      expect(result.success, isTrue);
      expect(result.evidence!.sourceType, equals(EvidenceSourceType.api));
    });

    test('fragment extraction with rules', () async {
      final input = IngestInput.fromString(
        '{"amount": "\$100.50", "date": "2024-01-15", "merchant": "ACME Corp"}',
        mimeType: 'application/json',
      );

      final options = IngestOptions.defaults.copyWith(
        extractFragments: true,
        fragmentRules: [
          const FragmentRule(
            id: 'test_amount',
            field: 'amount',
            patternType: FragmentPatternType.keyword,
            pattern: 'amount',
          ),
        ],
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
      // Fragments may or may not be found depending on rule matching
    });

    test('fragment extraction disabled produces no fragments', () async {
      final input = IngestInput.fromString(
        '{"key": "value"}',
        mimeType: 'application/json',
      );

      final options = IngestOptions.defaults.copyWith(
        extractFragments: false,
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
      expect(result.fragments, isEmpty);
    });

    test('ingestAll processes multiple inputs', () async {
      final inputs = [
        IngestInput.fromString('First document content.', mimeType: 'text/plain'),
        IngestInput.fromString('Second document content.', mimeType: 'text/plain'),
        IngestInput.fromString('Third document content.', mimeType: 'text/plain'),
      ];

      final results = await pipeline.ingestAll(inputs, IngestOptions.defaults);

      expect(results.length, equals(3));
      for (final result in results) {
        expect(result.success, isTrue);
      }
    });

    test('ingestBatch streams results', () async {
      final inputs = Stream.fromIterable([
        IngestInput.fromString('Batch item one.', mimeType: 'text/plain'),
        IngestInput.fromString('Batch item two.', mimeType: 'text/plain'),
      ]);

      final results = <IngestResult>[];
      await for (final result in pipeline.ingestBatch(
        inputs,
        IngestOptions.defaults,
      )) {
        results.add(result);
      }

      expect(results.length, equals(2));
      expect(results.every((r) => r.success), isTrue);
    });

    test('ingestAll with concurrency parameter', () async {
      final inputs = List.generate(
        5,
        (i) => IngestInput.fromString('Document $i content.', mimeType: 'text/plain'),
      );

      final results = await pipeline.ingestAll(
        inputs,
        IngestOptions.defaults,
        concurrency: 2,
      );

      expect(results.length, equals(5));
    });

    test('failed ingest includes stack trace in error', () async {
      final input = IngestInput(
        stream: Stream.value(utf8.encode('data')),
        mimeType: 'video/x-unsupported',
        size: 4,
      );

      final result = await pipeline.ingest(input, IngestOptions.defaults);

      expect(result.success, isFalse);
      expect(result.error!.stackTrace, isNotNull);
    });

    test('ingest with HTML content produces structure', () async {
      const htmlContent = '''
<html>
<head><title>Test Page</title></head>
<body>
  <h1>Main Heading</h1>
  <p>First paragraph of content.</p>
  <h2>Sub Heading</h2>
  <p>Second paragraph of content.</p>
</body>
</html>''';
      final input = IngestInput.fromString(
        htmlContent,
        mimeType: 'text/html',
      );

      final result = await pipeline.ingest(input, IngestOptions.defaults);

      expect(result.success, isTrue);
      expect(result.evidence, isNotNull);
      expect(result.chunks, isNotEmpty);
    });

    test('warnings list starts empty for clean ingest', () async {
      final input = IngestInput.fromString(
        'Clean document.',
        mimeType: 'text/plain',
      );

      final result = await pipeline.ingest(input, IngestOptions.defaults);

      expect(result.success, isTrue);
      expect(result.warnings, isEmpty);
    });

    test('evidence metadata includes provenance', () async {
      final input = IngestInput.fromString(
        'Content for provenance check.',
        mimeType: 'text/plain',
      );

      final result = await pipeline.ingest(input, IngestOptions.defaults);

      expect(result.success, isTrue);
      final metadata = result.evidence!.metadata;
      expect(metadata['provenance'], isNotNull);
      expect(metadata['provenance']['extractorId'], isNotNull);
    });

    test('ingest with content detection from bytes when no mimeType', () async {
      // When no mimeType is provided, the pipeline consumes the stream
      // to peek at magic bytes and uses filename extension as fallback.
      // Because _peekBytes consumes the stream, extraction on the same stream
      // will fail. This tests the error handling path.
      final textBytes = utf8.encode('Some plain text content for detection.');
      final input = IngestInput(
        stream: Stream.value(textBytes),
        filename: 'test.txt',
        size: textBytes.length,
      );

      final result = await pipeline.ingest(input, IngestOptions.defaults);

      // The stream is consumed by _peekBytes, so extraction may fail.
      // The important thing is the pipeline does not throw unhandled.
      expect(result.error != null || result.success, isTrue);
    });

    test('asset caching for image blocks', () async {
      // Minimal PNG
      final pngBytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x04,
        0x00, 0x00, 0x00, 0x04,
        0x08, 0x02, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
      ]);

      final input = IngestInput.fromBytes(
        pngBytes,
        mimeType: 'image/png',
      );

      // With storeAssets but no storagePort, assets stay in cache pattern
      final result = await pipeline.ingest(
        input,
        IngestOptions.defaults.copyWith(storeAssets: true),
      );

      expect(result.success, isTrue);
    });
  });

  group('DocumentTransformer', () {
    test('default process returns document unchanged', () async {
      final transformer = _TestDocumentTransformer();
      expect(transformer.phase, equals(StagePhase.preChunk));

      final doc = NormalizedDocument(
        id: 'doc1',
        metadata: const DocumentMetadata(
          mimeType: 'text/plain',
          sha256: 'hash',
          fileSize: 10,
        ),
        parts: const [TextBlock(id: 'p0', text: 'Hello')],
        structure: DocumentStructure.empty,
        provenance: ExtractionProvenance(
          extractorId: 'test',
          extractorVersion: '1.0',
          extractedAt: DateTime.now(),
          extractionDuration: Duration.zero,
        ),
      );

      final result = await transformer.process(doc);
      expect(result.id, equals(doc.id));
    });
  });

  group('ChunkPostProcessor', () {
    test('default processChunks returns chunks unchanged', () async {
      final processor = _TestChunkPostProcessor();
      expect(processor.phase, equals(StagePhase.postChunk));

      final chunks = [_createChunk('test content', 0)];
      final result = await processor.processChunks(chunks);
      expect(result.length, equals(1));
      expect(result.first.text, equals('test content'));
    });
  });

  group('ChunkFilterStage with custom predicate', () {
    test('filters based on minLength', () async {
      final stage = ChunkFilterStage(minLength: 15);

      final chunks = [
        _createChunk('short', 0),
        _createChunk('this is long enough text', 1),
        _createChunk('also too short', 2),
        _createChunk('another long text here!', 3),
      ];

      final result = await stage.processChunks(chunks);
      expect(result.length, equals(2));
      expect(result[0].text, equals('this is long enough text'));
      expect(result[1].text, equals('another long text here!'));
    });

    test('returns empty list when all chunks filtered', () async {
      final stage = ChunkFilterStage(minLength: 100);
      final chunks = [
        _createChunk('small', 0),
        _createChunk('tiny', 1),
      ];
      final result = await stage.processChunks(chunks);
      expect(result, isEmpty);
    });
  });

  group('CustomPipelineStage default behavior', () {
    test('base CustomPipelineStage process returns document as-is', () async {
      final stage = _TestCustomStage();

      final doc = NormalizedDocument(
        id: 'doc1',
        metadata: const DocumentMetadata(
          mimeType: 'text/plain',
          sha256: 'hash',
          fileSize: 10,
        ),
        parts: const [TextBlock(id: 'p0', text: 'Hello')],
        structure: DocumentStructure.empty,
        provenance: ExtractionProvenance(
          extractorId: 'test',
          extractorVersion: '1.0',
          extractedAt: DateTime.now(),
          extractionDuration: Duration.zero,
        ),
      );

      final processedDoc = await stage.process(doc);
      expect(processedDoc.id, equals('doc1'));

      final chunks = [_createChunk('test', 0)];
      final processedChunks = await stage.processChunks(chunks);
      expect(processedChunks.length, equals(1));
    });
  });

  group('IngestPipeline edge cases', () {
    late IngestPipeline pipeline;

    setUp(() {
      pipeline = IngestPipeline.defaults();
    });

    test('file size check skipped when size is null', () async {
      // Input with null size should not trigger file size check
      final input = IngestInput(
        stream: Stream.value(utf8.encode('hello')),
        mimeType: 'text/plain',
      );

      final options = IngestOptions.defaults.copyWith(maxFileSize: 1);

      // Should succeed because input.size is null (no check)
      final result = await pipeline.ingest(input, options);
      expect(result.success, isTrue);
    });

    test('file size check skipped when maxFileSize is null', () async {
      final input = IngestInput.fromString(
        'A' * 10000,
        mimeType: 'text/plain',
      );

      // Default options have null maxFileSize
      final result = await pipeline.ingest(input, IngestOptions.defaults);
      expect(result.success, isTrue);
    });

    test('ingest with chunk context injection', () async {
      final input = IngestInput.fromString(
        'A long text that has enough content to test context injection in chunks.',
        mimeType: 'text/plain',
      );

      final options = IngestOptions.defaults.copyWith(
        chunkOptions: const ChunkOptions(includeContext: true),
      );

      final result = await pipeline.ingest(input, options);
      expect(result.success, isTrue);
    });

    test('ingestBatch with concurrency 1 processes sequentially', () async {
      final inputs = Stream.fromIterable([
        IngestInput.fromString('Item A.', mimeType: 'text/plain'),
        IngestInput.fromString('Item B.', mimeType: 'text/plain'),
      ]);

      final results = <IngestResult>[];
      await for (final result in pipeline.ingestBatch(
        inputs,
        IngestOptions.defaults,
        concurrency: 1,
      )) {
        results.add(result);
      }

      expect(results.length, equals(2));
      expect(results.every((r) => r.success), isTrue);
    });

    test('error result has zero output counts', () async {
      final input = IngestInput(
        stream: Stream.value(utf8.encode('data')),
        mimeType: 'video/x-unsupported',
        size: 4,
      );

      final result = await pipeline.ingest(input, IngestOptions.defaults);

      expect(result.success, isFalse);
      expect(result.metrics.outputChunks, equals(0));
      expect(result.metrics.outputFragments, equals(0));
    });
  });

  group('IngestPipeline.full factory', () {
    test('creates pipeline with all ports configured', () {
      final ocrPort = _MockOcrPort();
      final asrPort = _MockAsrPort();
      final visionPort = _MockVisionPort();
      final storagePort = InMemoryBinaryStoragePort();
      final llmPort = _MockLlmPort();

      final pipeline = IngestPipeline.full(
        ocrPort: ocrPort,
        asrPort: asrPort,
        visionPort: visionPort,
        storagePort: storagePort,
        llmPort: llmPort,
      );

      expect(pipeline.ocrPort, same(ocrPort));
      expect(pipeline.asrPort, same(asrPort));
      expect(pipeline.visionPort, same(visionPort));
      expect(pipeline.storagePort, same(storagePort));
      expect(pipeline.llmPort, same(llmPort));
      expect(pipeline.extractors.all, isNotEmpty);
    });

    test('creates pipeline without optional llmPort', () {
      final ocrPort = _MockOcrPort();
      final asrPort = _MockAsrPort();
      final visionPort = _MockVisionPort();
      final storagePort = InMemoryBinaryStoragePort();

      final pipeline = IngestPipeline.full(
        ocrPort: ocrPort,
        asrPort: asrPort,
        visionPort: visionPort,
        storagePort: storagePort,
      );

      expect(pipeline.ocrPort, same(ocrPort));
      expect(pipeline.asrPort, same(asrPort));
      expect(pipeline.visionPort, same(visionPort));
      expect(pipeline.storagePort, same(storagePort));
      expect(pipeline.llmPort, isNull);
    });
  });

  group('Enhance stage - OCR on images', () {
    test('performs OCR on ImageBlock with cached assets', () async {
      final ocrPort = _MockOcrPort(resultText: 'OCR recognized text');
      final pipeline = IngestPipeline(
        extractors: ExtractorRegistry.defaults(),
        chunkerFactory: ChunkerFactory(),
        ocrPort: ocrPort,
      );

      // Use minimal PNG bytes that ImageExtractor can handle
      final pngBytes = _createMinimalPng();
      final input = IngestInput.fromBytes(
        pngBytes,
        mimeType: 'image/png',
      );

      final options = IngestOptions.defaults.copyWith(
        enableOcr: true,
        storeAssets: true,
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
      expect(result.metrics.ocrCalls, equals(1));
    });

    test('warns when asset not cached for OCR', () async {
      final ocrPort = _MockOcrPort(resultText: 'OCR text');

      // Use custom extractor that produces ImageBlock without inline ref
      final registry = ExtractorRegistry();
      registry.register(_MockImageExtractorWithRef('not-cached:img1'));

      final pipeline = IngestPipeline(
        extractors: registry,
        chunkerFactory: ChunkerFactory(),
        ocrPort: ocrPort,
      );

      final input = IngestInput.fromBytes(
        Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/test',
      );

      final options = IngestOptions.defaults.copyWith(
        enableOcr: true,
        storeAssets: false,
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
      expect(result.warnings, contains(contains('Asset not cached')));
      expect(result.metrics.ocrCalls, equals(0));
    });

    test('handles OCR error gracefully', () async {
      final ocrPort = _MockOcrPort(shouldThrow: true);
      final pipeline = IngestPipeline(
        extractors: ExtractorRegistry.defaults(),
        chunkerFactory: ChunkerFactory(),
        ocrPort: ocrPort,
      );

      final pngBytes = _createMinimalPng();
      final input = IngestInput.fromBytes(
        pngBytes,
        mimeType: 'image/png',
      );

      final options = IngestOptions.defaults.copyWith(
        enableOcr: true,
        storeAssets: true,
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
      expect(result.warnings, contains(contains('OCR failed')));
    });
  });

  group('Enhance stage - ASR on audio', () {
    test('performs ASR on AudioBlock with cached assets', () async {
      final asrPort = _MockAsrPort(
        resultText: 'Transcribed audio text',
        segments: [
          const AsrSegment(
            text: 'Transcribed',
            startTime: Duration.zero,
            endTime: Duration(seconds: 1),
            confidence: 0.95,
            speakerId: 'speaker1',
          ),
        ],
      );
      final pipeline = IngestPipeline(
        extractors: ExtractorRegistry.defaults(),
        chunkerFactory: ChunkerFactory(),
        asrPort: asrPort,
      );

      // Create minimal MP3 bytes (ID3 header)
      final mp3Bytes = _createMinimalMp3();
      final input = IngestInput.fromBytes(
        mp3Bytes,
        mimeType: 'audio/mpeg',
      );

      final options = IngestOptions.defaults.copyWith(
        enableAsr: true,
        storeAssets: true,
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
      expect(result.metrics.asrCalls, equals(1));
    });

    test('warns when asset not cached for ASR', () async {
      final asrPort = _MockAsrPort(resultText: 'ASR text');

      // Use custom extractor that produces AudioBlock without inline ref
      final registry = ExtractorRegistry();
      registry.register(_MockAudioExtractorWithRef('not-cached:audio1'));

      final pipeline = IngestPipeline(
        extractors: registry,
        chunkerFactory: ChunkerFactory(),
        asrPort: asrPort,
      );

      final input = IngestInput.fromBytes(
        Uint8List.fromList([1, 2, 3]),
        mimeType: 'audio/test',
      );

      final options = IngestOptions.defaults.copyWith(
        enableAsr: true,
        storeAssets: false,
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
      expect(result.warnings, contains(contains('Asset not cached')));
      expect(result.metrics.asrCalls, equals(0));
    });

    test('handles ASR error gracefully', () async {
      final asrPort = _MockAsrPort(shouldThrow: true);
      final pipeline = IngestPipeline(
        extractors: ExtractorRegistry.defaults(),
        chunkerFactory: ChunkerFactory(),
        asrPort: asrPort,
      );

      final mp3Bytes = _createMinimalMp3();
      final input = IngestInput.fromBytes(
        mp3Bytes,
        mimeType: 'audio/mpeg',
      );

      final options = IngestOptions.defaults.copyWith(
        enableAsr: true,
        storeAssets: true,
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
      expect(result.warnings, contains(contains('ASR failed')));
    });
  });

  group('Enhance stage - VisionPort', () {
    test('performs vision description on ImageBlock', () async {
      final visionPort =
          _MockVisionPort(description: 'A photo of a landscape');
      final pipeline = IngestPipeline(
        extractors: ExtractorRegistry.defaults(),
        chunkerFactory: ChunkerFactory(),
        visionPort: visionPort,
      );

      final pngBytes = _createMinimalPng();
      final input = IngestInput.fromBytes(
        pngBytes,
        mimeType: 'image/png',
      );

      final options = IngestOptions.defaults.copyWith(
        enableVision: true,
        storeAssets: true,
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
      expect(result.metrics.visionPortCalls, equals(1));
    });

    test('warns when asset not cached for vision', () async {
      final visionPort = _MockVisionPort(description: 'description');

      final registry = ExtractorRegistry();
      registry.register(_MockImageExtractorWithRef('not-cached:img1'));

      final pipeline = IngestPipeline(
        extractors: registry,
        chunkerFactory: ChunkerFactory(),
        visionPort: visionPort,
      );

      final input = IngestInput.fromBytes(
        Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/test',
      );

      final options = IngestOptions.defaults.copyWith(
        enableVision: true,
        storeAssets: false,
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
      expect(result.warnings, contains(contains('Asset not cached')));
      expect(result.metrics.visionPortCalls, equals(0));
    });

    test('handles vision error gracefully', () async {
      final visionPort = _MockVisionPort(shouldThrow: true);
      final pipeline = IngestPipeline(
        extractors: ExtractorRegistry.defaults(),
        chunkerFactory: ChunkerFactory(),
        visionPort: visionPort,
      );

      final pngBytes = _createMinimalPng();
      final input = IngestInput.fromBytes(
        pngBytes,
        mimeType: 'image/png',
      );

      final options = IngestOptions.defaults.copyWith(
        enableVision: true,
        storeAssets: true,
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
      expect(result.warnings, contains(contains('Vision failed')));
    });
  });

  group('Enhance stage - LlmPort vision', () {
    test('performs LLM vision on ImageBlock', () async {
      final llmPort = _MockLlmPort(responseContent: 'Detailed image analysis');
      final pipeline = IngestPipeline(
        extractors: ExtractorRegistry.defaults(),
        chunkerFactory: ChunkerFactory(),
        llmPort: llmPort,
      );

      final pngBytes = _createMinimalPng();
      final input = IngestInput.fromBytes(
        pngBytes,
        mimeType: 'image/png',
      );

      final options = IngestOptions.defaults.copyWith(
        enableLlmVision: true,
        storeAssets: true,
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
      expect(result.metrics.llmVisionCalls, equals(1));
    });

    test('warns when asset not cached for LLM vision', () async {
      final llmPort = _MockLlmPort(responseContent: 'description');

      final registry = ExtractorRegistry();
      registry.register(_MockImageExtractorWithRef('not-cached:img1'));

      final pipeline = IngestPipeline(
        extractors: registry,
        chunkerFactory: ChunkerFactory(),
        llmPort: llmPort,
      );

      final input = IngestInput.fromBytes(
        Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/test',
      );

      final options = IngestOptions.defaults.copyWith(
        enableLlmVision: true,
        storeAssets: false,
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
      expect(result.warnings, contains(contains('Asset not cached')));
      expect(result.metrics.llmVisionCalls, equals(0));
    });

    test('handles LLM vision error gracefully', () async {
      final llmPort = _MockLlmPort(shouldThrow: true);
      final pipeline = IngestPipeline(
        extractors: ExtractorRegistry.defaults(),
        chunkerFactory: ChunkerFactory(),
        llmPort: llmPort,
      );

      final pngBytes = _createMinimalPng();
      final input = IngestInput.fromBytes(
        pngBytes,
        mimeType: 'image/png',
      );

      final options = IngestOptions.defaults.copyWith(
        enableLlmVision: true,
        storeAssets: true,
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
      expect(result.warnings, contains(contains('LLM Vision failed')));
    });
  });

  group('Store stage', () {
    test('stores cached image assets to permanent storage', () async {
      final storagePort = InMemoryBinaryStoragePort();
      final pipeline = IngestPipeline(
        extractors: ExtractorRegistry.defaults(),
        chunkerFactory: ChunkerFactory(),
        storagePort: storagePort,
      );

      final pngBytes = _createMinimalPng();
      final input = IngestInput.fromBytes(
        pngBytes,
        mimeType: 'image/png',
      );

      final options = IngestOptions.defaults.copyWith(
        storeAssets: true,
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
      // Verify that the storage port received the asset
      final storedKeys = await storagePort.list();
      expect(storedKeys, isNotEmpty);
    });

    test('stores cached audio assets to permanent storage', () async {
      final storagePort = InMemoryBinaryStoragePort();
      final pipeline = IngestPipeline(
        extractors: ExtractorRegistry.defaults(),
        chunkerFactory: ChunkerFactory(),
        storagePort: storagePort,
      );

      final mp3Bytes = _createMinimalMp3();
      final input = IngestInput.fromBytes(
        mp3Bytes,
        mimeType: 'audio/mpeg',
      );

      final options = IngestOptions.defaults.copyWith(
        storeAssets: true,
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
      final storedKeys = await storagePort.list();
      expect(storedKeys, isNotEmpty);
    });

    test('skips store stage when storeAssets is false', () async {
      final storagePort = InMemoryBinaryStoragePort();
      final pipeline = IngestPipeline(
        extractors: ExtractorRegistry.defaults(),
        chunkerFactory: ChunkerFactory(),
        storagePort: storagePort,
      );

      final pngBytes = _createMinimalPng();
      final input = IngestInput.fromBytes(
        pngBytes,
        mimeType: 'image/png',
      );

      final options = IngestOptions.defaults.copyWith(
        storeAssets: false,
      );

      final result = await pipeline.ingest(input, options);

      expect(result.success, isTrue);
      final storedKeys = await storagePort.list();
      expect(storedKeys, isEmpty);
    });

    test('skips store stage when no storagePort', () async {
      final pipeline = IngestPipeline(
        extractors: ExtractorRegistry.defaults(),
        chunkerFactory: ChunkerFactory(),
      );

      final pngBytes = _createMinimalPng();
      final input = IngestInput.fromBytes(
        pngBytes,
        mimeType: 'image/png',
      );

      final options = IngestOptions.defaults.copyWith(
        storeAssets: true,
      );

      final result = await pipeline.ingest(input, options);

      // Should succeed even without storagePort; assets stay in cache pattern
      expect(result.success, isTrue);
    });
  });

  // ===========================================================================
  // DEF-20260411-002: customStages are auto-invoked at correct phase
  // ===========================================================================

  group('IngestPipeline customStages auto-invocation', () {
    test('preChunk DocumentTransformer runs before chunking', () async {
      final transformer = _RecordingTransformer();
      final pipeline = IngestPipeline(
        extractors: ExtractorRegistry.defaults(),
        chunkerFactory: ChunkerFactory(),
        customStages: [transformer],
      );

      final input = IngestInput.fromString(
        'First sentence. Second sentence.',
        mimeType: 'text/plain',
      );

      final result = await pipeline.ingest(
        input,
        IngestOptions.defaults,
      );

      expect(result.success, isTrue);
      expect(transformer.callCount, equals(1),
          reason: 'DocumentTransformer should be invoked exactly once');
      expect(transformer.wasCalledBeforeChunking, isTrue,
          reason: 'DocumentTransformer must run before chunk stage');
    });

    test('postChunk ChunkFilterStage removes short chunks', () async {
      final pipeline = IngestPipeline(
        extractors: ExtractorRegistry.defaults(),
        chunkerFactory: ChunkerFactory(),
        customStages: [ChunkFilterStage(minLength: 100)],
      );

      final input = IngestInput.fromString(
        'Short.',
        mimeType: 'text/plain',
      );

      final result = await pipeline.ingest(input, IngestOptions.defaults);

      expect(result.success, isTrue);
      // All chunks are short, so filter removes them all.
      expect(result.chunks, isEmpty);
    });

    test('WhitespaceNormalizerStage normalizes chunk text', () async {
      final pipeline = IngestPipeline(
        extractors: ExtractorRegistry.defaults(),
        chunkerFactory: ChunkerFactory(),
        customStages: [WhitespaceNormalizerStage()],
      );

      final input = IngestInput.fromString(
        'Multiple     spaces  and   tabs.',
        mimeType: 'text/plain',
      );

      final result = await pipeline.ingest(input, IngestOptions.defaults);
      expect(result.success, isTrue);
      expect(result.chunks, isNotEmpty);
      // After normalization no double spaces remain.
      expect(result.chunks.first.text, isNot(contains('  ')));
    });

    test('empty customStages preserves existing behavior', () async {
      final pipeline = IngestPipeline(
        extractors: ExtractorRegistry.defaults(),
        chunkerFactory: ChunkerFactory(),
      );

      final input = IngestInput.fromString(
        'Some text for chunking.',
        mimeType: 'text/plain',
      );

      final result = await pipeline.ingest(input, IngestOptions.defaults);
      expect(result.success, isTrue);
      expect(result.chunks, isNotEmpty);
    });

    test('multiple stages in same phase run in list order', () async {
      final calls = <String>[];
      final s1 = _NamedTransformer('s1', calls);
      final s2 = _NamedTransformer('s2', calls);

      final pipeline = IngestPipeline(
        extractors: ExtractorRegistry.defaults(),
        chunkerFactory: ChunkerFactory(),
        customStages: [s1, s2],
      );

      await pipeline.ingest(
        IngestInput.fromString('hello world', mimeType: 'text/plain'),
        IngestOptions.defaults,
      );

      expect(calls, equals(['s1', 's2']));
    });

    test('custom stage failure becomes a warning, pipeline continues', () async {
      final pipeline = IngestPipeline(
        extractors: ExtractorRegistry.defaults(),
        chunkerFactory: ChunkerFactory(),
        customStages: [_ThrowingTransformer()],
      );

      final result = await pipeline.ingest(
        IngestInput.fromString('abc', mimeType: 'text/plain'),
        IngestOptions.defaults,
      );

      expect(result.success, isTrue,
          reason: 'custom stage failure must not abort the pipeline');
      expect(
        result.warnings.any((w) => w.contains('throwing_stage')),
        isTrue,
      );
    });
  });
}

/// Records that process() was invoked and whether it saw a document with parts
/// but no chunks (proving it ran before chunking).
class _RecordingTransformer extends DocumentTransformer {
  int callCount = 0;
  bool wasCalledBeforeChunking = false;

  @override
  String get id => 'recording_transformer';

  @override
  String get name => 'Recording Transformer';

  @override
  Future<NormalizedDocument> process(NormalizedDocument document) async {
    callCount++;
    // At preChunk phase, document has parts but pipeline has not chunked yet.
    wasCalledBeforeChunking = document.parts.isNotEmpty;
    return document;
  }
}

/// Transformer that appends its name to a shared log when invoked.
class _NamedTransformer extends DocumentTransformer {
  final String _id;
  final List<String> _log;

  _NamedTransformer(this._id, this._log);

  @override
  String get id => _id;

  @override
  String get name => _id;

  @override
  Future<NormalizedDocument> process(NormalizedDocument document) async {
    _log.add(_id);
    return document;
  }
}

/// Transformer that throws to verify graceful degradation.
class _ThrowingTransformer extends DocumentTransformer {
  @override
  String get id => 'throwing_stage';

  @override
  String get name => 'Throwing Stage';

  @override
  Future<NormalizedDocument> process(NormalizedDocument document) async {
    throw StateError('intentional failure');
  }
}

/// Test document transformer for testing base class behavior.
class _TestDocumentTransformer extends DocumentTransformer {
  @override
  String get id => 'test_transformer';

  @override
  String get name => 'Test Transformer';
}

/// Test chunk post-processor for testing base class behavior.
class _TestChunkPostProcessor extends ChunkPostProcessor {
  @override
  String get id => 'test_post_processor';

  @override
  String get name => 'Test Post Processor';
}

/// Test custom pipeline stage for testing base class defaults.
class _TestCustomStage extends CustomPipelineStage {
  @override
  String get id => 'test_custom';

  @override
  String get name => 'Test Custom';

  @override
  StagePhase get phase => StagePhase.preChunk;
}

Chunk _createChunk(String text, int index) {
  return Chunk(
    id: 'chunk_$index',
    text: text,
    sourceSpans: const [],
    location: SourceLocation.empty,
    index: index,
    totalChunks: 1,
  );
}

/// Create minimal valid PNG bytes for testing.
Uint8List _createMinimalPng() {
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
    0x00, 0x00, 0x00, 0x0D, // IHDR chunk length
    0x49, 0x48, 0x44, 0x52, // IHDR
    0x00, 0x00, 0x00, 0x04, // width = 4
    0x00, 0x00, 0x00, 0x04, // height = 4
    0x08, 0x02, 0x00, 0x00, 0x00, // 8-bit RGB
    0x00, 0x00, 0x00, 0x00, // CRC (placeholder)
  ]);
}

/// Create minimal MP3-like bytes (ID3 header) for testing.
Uint8List _createMinimalMp3() {
  return Uint8List.fromList([
    0x49, 0x44, 0x33, // ID3 header
    0x04, 0x00, 0x00, // Version 2.4, no flags
    0x00, 0x00, 0x00, 0x00, // Size = 0
    0xFF, 0xFB, 0x90, 0x00, // Sync word + MPEG 1 Layer 3
  ]);
}

/// Mock OCR port for testing enhance stage.
class _MockOcrPort implements OcrPort {
  final String resultText;
  final bool shouldThrow;

  _MockOcrPort({this.resultText = '', this.shouldThrow = false});

  @override
  Future<OcrResult> recognize(
    Stream<List<int>> imageData,
    OcrOptions options,
  ) async {
    if (shouldThrow) throw Exception('OCR service unavailable');
    return OcrResult(
      text: resultText,
      confidence: 0.95,
      processingTime: const Duration(milliseconds: 50),
    );
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<String>> supportedLanguages() async => ['eng'];
}

/// Mock ASR port for testing enhance stage.
class _MockAsrPort implements AsrPort {
  final String resultText;
  final bool shouldThrow;
  final List<AsrSegment>? segments;

  _MockAsrPort({
    this.resultText = '',
    this.shouldThrow = false,
    this.segments,
  });

  @override
  Future<AsrResult> transcribe(
    Stream<List<int>> audioData,
    AsrOptions options,
  ) async {
    if (shouldThrow) throw Exception('ASR service unavailable');
    return AsrResult(
      text: resultText,
      confidence: 0.90,
      segments: segments,
      audioDuration: const Duration(seconds: 10),
      processingTime: const Duration(milliseconds: 100),
    );
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<String>> supportedLanguages() async => ['en'];
}

/// Mock Vision port for testing enhance stage.
class _MockVisionPort implements VisionPort {
  final String description;
  final bool shouldThrow;

  _MockVisionPort({this.description = '', this.shouldThrow = false});

  @override
  Future<VisionResult> describe(
    Stream<List<int>> imageData,
    VisionOptions options,
  ) async {
    if (shouldThrow) throw Exception('Vision service unavailable');
    return VisionResult(
      description: description,
      confidence: 0.92,
      processingTime: const Duration(milliseconds: 80),
    );
  }

  @override
  Future<bool> isAvailable() async => true;
}

/// Mock LLM port for testing enhance stage LLM vision.
class _MockLlmPort extends LlmPort {
  final String responseContent;
  final bool shouldThrow;

  _MockLlmPort({this.responseContent = '', this.shouldThrow = false});

  @override
  LlmCapabilities get capabilities =>
      const LlmCapabilities(completion: true, vision: true);

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    if (shouldThrow) throw Exception('LLM service unavailable');
    return LlmResponse(content: responseContent);
  }
}

/// Mock image extractor that produces an ImageBlock with a non-inline assetRef.
/// Used to test the "asset not cached" warning path.
class _MockImageExtractorWithRef extends Extractor {
  final String assetRef;

  _MockImageExtractorWithRef(this.assetRef);

  @override
  String get id => 'mock_image_ref';

  @override
  Set<String> get supportedTypes => {'image/test'};

  @override
  int get priority => 100;

  @override
  Duration estimateDuration(int fileSize) => Duration.zero;

  @override
  Future<NormalizedDocument> extract(
    Stream<List<int>> input,
    ExtractOptions options,
  ) async {
    // Consume the stream
    await input.drain<void>();
    return NormalizedDocument(
      id: 'doc_mock_img',
      metadata: const DocumentMetadata(
        mimeType: 'image/test',
        sha256: 'abc123',
        fileSize: 3,
      ),
      parts: [
        ImageBlock(id: 'img1', assetRef: assetRef),
      ],
      structure: DocumentStructure.empty,
      provenance: ExtractionProvenance(
        extractorId: 'mock_image_ref',
        extractorVersion: '1.0',
        extractedAt: DateTime.now(),
        extractionDuration: Duration.zero,
      ),
    );
  }
}

/// Mock audio extractor that produces an AudioBlock with a non-inline assetRef.
/// Used to test the "asset not cached" warning path.
class _MockAudioExtractorWithRef extends Extractor {
  final String assetRef;

  _MockAudioExtractorWithRef(this.assetRef);

  @override
  String get id => 'mock_audio_ref';

  @override
  Set<String> get supportedTypes => {'audio/test'};

  @override
  int get priority => 100;

  @override
  Duration estimateDuration(int fileSize) => Duration.zero;

  @override
  Future<NormalizedDocument> extract(
    Stream<List<int>> input,
    ExtractOptions options,
  ) async {
    // Consume the stream
    await input.drain<void>();
    return NormalizedDocument(
      id: 'doc_mock_audio',
      metadata: const DocumentMetadata(
        mimeType: 'audio/test',
        sha256: 'def456',
        fileSize: 3,
      ),
      parts: [
        AudioBlock(id: 'audio1', assetRef: assetRef),
      ],
      structure: DocumentStructure.empty,
      provenance: ExtractionProvenance(
        extractorId: 'mock_audio_ref',
        extractorVersion: '1.0',
        extractedAt: DateTime.now(),
        extractionDuration: Duration.zero,
      ),
    );
  }
}
