import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:mcp_ingest/mcp_ingest.dart';

void main() {
  group('ContentType', () {
    test('detects PDF from magic bytes', () {
      final bytes = [0x25, 0x50, 0x44, 0x46, 0x2D]; // %PDF-

      final result = ContentTypeDetector.detect(bytes, 'test.pdf');

      expect(result!.mimeType, 'application/pdf');
    });

    test('detects PNG from magic bytes', () {
      final bytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

      final result = ContentTypeDetector.detect(bytes, null);

      expect(result!.mimeType, 'image/png');
    });

    test('falls back to extension', () {
      final result = ContentTypeDetector.detectFromFilename('document.docx');

      expect(result.mimeType, contains('wordprocessingml'));
    });
  });

  group('IngestOptions', () {
    test('defaults are reasonable', () {
      const options = IngestOptions.defaults;

      expect(options.enableOcr, false);
      expect(options.enableAsr, false);
      expect(options.chunkingStrategy, ChunkingStrategy.paragraph);
      expect(options.chunkOptions.targetSize, 1000);
    });

    test('builder creates correct options', () {
      final options = IngestOptionsBuilder()
          .enableOcr()
          .chunkBy(ChunkingStrategy.sentence)
          .chunkOptions(const ChunkOptions(targetSize: 500))
          .build();

      expect(options.enableOcr, true);
      expect(options.chunkingStrategy, ChunkingStrategy.sentence);
      expect(options.chunkOptions.targetSize, 500);
    });
  });

  group('IngestInput', () {
    test('creates from string', () {
      final input = IngestInput.fromString('Hello, world!');

      expect(input.mimeType, 'text/plain');
      expect(input.size, greaterThan(0));
    });

    test('creates from bytes', () {
      final bytes = [72, 101, 108, 108, 111]; // "Hello"
      final input = IngestInput.fromBytes(
        Uint8List.fromList(bytes),
        mimeType: 'text/plain',
      );

      expect(input.mimeType, 'text/plain');
      expect(input.size, 5);
    });
  });

  group('TextExtractor', () {
    test('extracts plain text', () async {
      final extractor = TextExtractor();
      final input = 'First paragraph.\n\nSecond paragraph.';

      final result = await extractor.extract(
        Stream.value(input.codeUnits),
        ExtractOptions.defaults,
      );

      expect(result.parts.length, greaterThan(0));
      expect(result.fullText, contains('First paragraph'));
    });

    test('extracts markdown with headings', () async {
      final extractor = TextExtractor();
      final input = '# Title\n\nParagraph text.\n\n## Section\n\nMore text.';

      final result = await extractor.extract(
        Stream.value(input.codeUnits),
        const ExtractOptions(custom: {'isMarkdown': true}),
      );

      expect(
          result.parts.whereType<TextBlock>().any(
                (b) => b.type == TextBlockType.heading,
              ),
          true);
    });
  });

  group('Chunkers', () {
    late NormalizedDocument testDocument;

    setUp(() {
      testDocument = NormalizedDocument(
        id: 'test',
        metadata: const DocumentMetadata(
          mimeType: 'text/plain',
          sha256: 'abc123',
          fileSize: 100,
        ),
        parts: [
          const TextBlock(
            id: 'p1',
            text: 'First sentence. Second sentence. Third sentence.',
            type: TextBlockType.paragraph,
          ),
          const TextBlock(
            id: 'p2',
            text: 'Another paragraph with more content here.',
            type: TextBlockType.paragraph,
          ),
        ],
        structure: DocumentStructure.empty,
        provenance: ExtractionProvenance(
          extractorId: 'test',
          extractorVersion: '1.0.0',
          extractedAt: DateTime.now(),
          extractionDuration: Duration.zero,
        ),
      );
    });

    test('SentenceChunker splits by sentences', () async {
      final chunker = SentenceChunker();
      final chunks = await chunker.chunk(testDocument, ChunkOptions.defaults);

      expect(chunks.length, greaterThan(0));
      expect(chunks.every((c) => c.text.isNotEmpty), true);
    });

    test('ParagraphChunker preserves paragraphs', () async {
      final chunker = ParagraphChunker();
      final chunks = await chunker.chunk(testDocument, ChunkOptions.defaults);

      expect(chunks.length, greaterThan(0));
    });

    test('NoChunker returns single chunk', () async {
      final chunker = NoChunker();
      final chunks = await chunker.chunk(testDocument, ChunkOptions.defaults);

      expect(chunks.length, 1);
    });
  });

  group('IngestPipeline', () {
    test('creates with defaults', () {
      final pipeline = IngestPipeline.defaults();
      expect(pipeline, isNotNull);
    });

    test('processes text input', () async {
      final pipeline = IngestPipeline.defaults();
      final input = IngestInput.fromString(
        'This is a test document with some content.',
        mimeType: 'text/plain',
      );

      final result = await pipeline.ingest(input, IngestOptions.defaults);

      expect(result.success, isTrue);
      expect(result.chunks.length, greaterThan(0));
      expect(result.evidence, isNotNull);
    });
  });
}
