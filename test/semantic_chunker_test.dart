import 'package:test/test.dart';
import 'package:mcp_bundle/ports.dart';
import 'package:mcp_ingest/mcp_ingest.dart';

// Mock LlmPort for testing SemanticChunker without a real LLM.
class MockLlmPort extends LlmPort {
  String responseContent = '{"splits": [50, 120]}';
  int callCount = 0;

  @override
  LlmCapabilities get capabilities => const LlmCapabilities.minimal();

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    callCount++;
    return LlmResponse(content: responseContent);
  }

  @override
  Future<bool> isAvailable() async => true;
}

/// Helper to create a NormalizedDocument with a single text part.
NormalizedDocument _createDoc(String text) {
  return NormalizedDocument(
    id: 'doc1',
    metadata:
        const DocumentMetadata(mimeType: 'text/plain', sha256: 'abc123'),
    parts: [TextBlock(id: 'p1', text: text)],
    structure: DocumentStructure.empty,
    provenance: ExtractionProvenance(
      extractorId: 'test',
      extractorVersion: '1.0',
      extractedAt: DateTime(2024, 1, 1),
      extractionDuration: Duration.zero,
    ),
  );
}

/// Helper to create a NormalizedDocument with multiple text parts.
NormalizedDocument _createMultiPartDoc(List<MapEntry<String, String>> parts) {
  return NormalizedDocument(
    id: 'doc1',
    metadata:
        const DocumentMetadata(mimeType: 'text/plain', sha256: 'abc123'),
    parts: parts
        .map((e) => TextBlock(id: e.key, text: e.value))
        .toList(),
    structure: DocumentStructure.empty,
    provenance: ExtractionProvenance(
      extractorId: 'test',
      extractorVersion: '1.0',
      extractedAt: DateTime(2024, 1, 1),
      extractionDuration: Duration.zero,
    ),
  );
}

void main() {
  late MockLlmPort mockLlm;
  late SemanticChunker chunker;

  setUp(() {
    mockLlm = MockLlmPort();
    chunker = SemanticChunker(mockLlm);
  });

  group('SemanticChunker', () {
    // Test 1: id and name getters
    test('id returns semantic_v1', () {
      expect(chunker.id, equals('semantic_v1'));
    });

    test('name returns Semantic Chunker', () {
      expect(chunker.name, equals('Semantic Chunker'));
    });

    // Test 2: Short document returns single chunk
    test('short document returns single chunk with all parts as sourceSpans',
        () async {
      final doc = _createDoc('Short text.');
      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 10000,
        minSize: 10,
      );

      final chunks = await chunker.chunk(doc, options);

      expect(chunks.length, equals(1));
      expect(chunks[0].text, equals('Short text.'));
      expect(chunks[0].sourceSpans.length, equals(1));
      expect(chunks[0].sourceSpans[0].partId, equals('p1'));
      expect(chunks[0].sourceSpans[0].startOffset, equals(0));
      expect(chunks[0].sourceSpans[0].endOffset, equals(11));
      expect(chunks[0].metadata?['chunker'], equals('semantic_v1'));
      expect(chunks[0].metadata?['method'], equals('llm'));
      expect(chunks[0].totalChunks, equals(1));
      expect(chunks[0].index, equals(0));
    });

    // Test 2b: Short doc does NOT call the LLM
    test('short document does not call LLM', () async {
      final doc = _createDoc('Short text.');
      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 10000,
        minSize: 10,
      );

      await chunker.chunk(doc, options);
      expect(mockLlm.callCount, equals(0));
    });

    // Test 3: Normal document with LLM splits
    test('normal document with LLM splits creates multiple chunks', () async {
      // Create a document long enough to exceed maxSize (200)
      final text = 'A' * 50 + 'B' * 70 + 'C' * 100;
      // fullText for single part = text itself (trim removes trailing \n\n)
      // text.length = 220 > maxSize 200
      final doc = _createDoc(text);
      mockLlm.responseContent = '{"splits": [50, 120]}';

      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 200,
        minSize: 10,
      );

      final chunks = await chunker.chunk(doc, options);

      // Should have 3 chunks: [0, 50), [50, 120), [120, 220)
      expect(chunks.length, equals(3));
      expect(chunks[0].text, equals(text.substring(0, 50).trim()));
      expect(chunks[1].text, equals(text.substring(50, 120).trim()));
      expect(chunks[2].text, equals(text.substring(120).trim()));
    });

    // Test 4: LLM returns invalid JSON -> fallback to regex number parsing
    test('LLM returns invalid JSON falls back to regex number parsing',
        () async {
      final text = 'A' * 250;
      final doc = _createDoc(text);
      // Invalid JSON but contains numbers that can be parsed
      mockLlm.responseContent = 'Split at positions: 80, 160';

      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 200,
        minSize: 10,
      );

      final chunks = await chunker.chunk(doc, options);

      // Regex parses 80 and 160 as split points
      expect(chunks.length, equals(3));
      expect(chunks[0].text, equals(text.substring(0, 80)));
      expect(chunks[1].text, equals(text.substring(80, 160)));
      expect(chunks[2].text, equals(text.substring(160)));
    });

    // Test 5: LLM returns empty splits -> single chunk
    test('LLM returns empty splits creates single chunk', () async {
      final text = 'A' * 250;
      final doc = _createDoc(text);
      mockLlm.responseContent = '{"splits": []}';

      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 200,
        minSize: 10,
      );

      final chunks = await chunker.chunk(doc, options);

      // No valid splits -> entire document as one chunk
      expect(chunks.length, equals(1));
      expect(chunks[0].text, equals(text));
    });

    // Test 6: LLM returns no splits key -> single chunk
    test('LLM returns no splits key creates single chunk', () async {
      final text = 'A' * 250;
      final doc = _createDoc(text);
      mockLlm.responseContent = '{"foo": "bar"}';

      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 200,
        minSize: 10,
      );

      final chunks = await chunker.chunk(doc, options);

      // No 'splits' key -> _parseSplits returns [] -> one chunk
      expect(chunks.length, equals(1));
      expect(chunks[0].text, equals(text));
    });

    // Test 7: Split points out of range are ignored
    test('split points out of range are ignored', () async {
      final text = 'A' * 250;
      final doc = _createDoc(text);
      // 500 is beyond text length (250), 0 is not > start, -10 is negative
      mockLlm.responseContent = '{"splits": [100, 500, 0]}';

      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 200,
        minSize: 10,
      );

      final chunks = await chunker.chunk(doc, options);

      // Only split at 100 is valid (500 >= text.length, 0 is not > start=0)
      expect(chunks.length, equals(2));
      expect(chunks[0].text, equals(text.substring(0, 100)));
      expect(chunks[1].text, equals(text.substring(100)));
    });

    // Test 8: Chunks below minSize are filtered
    test('chunks below minSize are filtered out', () async {
      final text = 'A' * 250;
      final doc = _createDoc(text);
      // Split at 5 creates a chunk of length 5 which is below minSize=10
      // Split at 100 creates chunk [5,100) = 95 chars, [100,250) = 150 chars
      mockLlm.responseContent = '{"splits": [5, 100]}';

      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 200,
        minSize: 10,
      );

      final chunks = await chunker.chunk(doc, options);

      // First chunk [0,5) has length 5 < minSize 10, so it is filtered
      // Remaining chunks: [5,100) and [100,250)
      expect(chunks.length, equals(2));
      expect(chunks[0].text.length, greaterThanOrEqualTo(10));
      expect(chunks[1].text.length, greaterThanOrEqualTo(10));
    });

    // Test 9: sourceSpans populated correctly
    test('sourceSpans map to correct source parts', () async {
      // Create multi-part document where text spans multiple parts
      final doc = _createMultiPartDoc([
        MapEntry('p1', 'A' * 100),
        MapEntry('p2', 'B' * 100),
        MapEntry('p3', 'C' * 100),
      ]);
      final fullText = doc.fullText;
      // fullText should be around 300+ chars (parts joined with \n\n separators)

      // Put split in the middle area
      final splitPoint = 110;
      mockLlm.responseContent = '{"splits": [$splitPoint]}';

      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 200,
        minSize: 10,
      );

      final chunks = await chunker.chunk(doc, options);

      // Verify all chunks have non-empty sourceSpans
      for (final chunk in chunks) {
        expect(chunk.sourceSpans, isNotEmpty,
            reason: 'Chunk "${chunk.id}" should have sourceSpans');
        for (final span in chunk.sourceSpans) {
          expect(span.partId, isNotEmpty);
          expect(span.startOffset, greaterThanOrEqualTo(0));
          expect(span.endOffset, greaterThanOrEqualTo(span.startOffset));
        }
      }

      // First chunk should reference part p1 at minimum
      expect(chunks[0].sourceSpans.any((s) => s.partId == 'p1'), isTrue);

      // Verify chunks cover the full text
      expect(chunks.isNotEmpty, isTrue);
      expect(
        chunks.last.text,
        equals(fullText.substring(splitPoint).trim()),
      );
    });

    // Test 10: totalChunks updated on all chunks
    test('totalChunks updated on all returned chunks', () async {
      final text = 'A' * 250;
      final doc = _createDoc(text);
      mockLlm.responseContent = '{"splits": [80, 160]}';

      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 200,
        minSize: 10,
      );

      final chunks = await chunker.chunk(doc, options);

      expect(chunks.length, equals(3));
      for (final chunk in chunks) {
        expect(chunk.totalChunks, equals(3));
      }
    });

    // Test 11: Empty document
    test('empty document returns single chunk', () async {
      final doc = _createDoc('');
      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 10000,
        minSize: 10,
      );

      final chunks = await chunker.chunk(doc, options);

      // Empty fullText.length <= maxSize, returns single chunk path
      expect(chunks.length, equals(1));
      expect(chunks[0].text, equals(''));
    });

    // Test 12: LLM called exactly once for a normal document
    test('LLM called exactly once for normal document', () async {
      final text = 'A' * 250;
      final doc = _createDoc(text);
      mockLlm.responseContent = '{"splits": [100]}';

      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 200,
        minSize: 10,
      );

      await chunker.chunk(doc, options);

      expect(mockLlm.callCount, equals(1));
    });

    // Additional edge case: splits are sorted regardless of order from LLM
    test('splits are sorted before processing', () async {
      final text = 'A' * 250;
      final doc = _createDoc(text);
      // Provide splits in reverse order
      mockLlm.responseContent = '{"splits": [150, 80]}';

      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 200,
        minSize: 10,
      );

      final chunks = await chunker.chunk(doc, options);

      // Sorted splits: [80, 150] -> chunks: [0,80), [80,150), [150,250)
      expect(chunks.length, equals(3));
      expect(chunks[0].text, equals(text.substring(0, 80)));
      expect(chunks[1].text, equals(text.substring(80, 150)));
      expect(chunks[2].text, equals(text.substring(150)));
    });

    // Chunk indices are sequential
    test('chunk indices are sequential starting from 0', () async {
      final text = 'A' * 250;
      final doc = _createDoc(text);
      mockLlm.responseContent = '{"splits": [80, 160]}';

      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 200,
        minSize: 10,
      );

      final chunks = await chunker.chunk(doc, options);

      for (var i = 0; i < chunks.length; i++) {
        expect(chunks[i].index, equals(i));
      }
    });

    // Chunk IDs follow pattern chunk_0, chunk_1, ...
    test('chunk IDs follow chunk_N pattern', () async {
      final text = 'A' * 250;
      final doc = _createDoc(text);
      mockLlm.responseContent = '{"splits": [80, 160]}';

      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 200,
        minSize: 10,
      );

      final chunks = await chunker.chunk(doc, options);

      for (var i = 0; i < chunks.length; i++) {
        expect(chunks[i].id, equals('chunk_$i'));
      }
    });

    // Metadata includes chunker info
    test('chunk metadata includes chunker id and method', () async {
      final text = 'A' * 250;
      final doc = _createDoc(text);
      mockLlm.responseContent = '{"splits": [100]}';

      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 200,
        minSize: 10,
      );

      final chunks = await chunker.chunk(doc, options);

      for (final chunk in chunks) {
        expect(chunk.metadata?['chunker'], equals('semantic_v1'));
        expect(chunk.metadata?['method'], equals('llm'));
      }
    });

    // JSON embedded in surrounding text (e.g., "Here is the result: {...}")
    test('extracts JSON from surrounding text', () async {
      final text = 'A' * 250;
      final doc = _createDoc(text);
      mockLlm.responseContent =
          'Here is the result: {"splits": [100]} end of response';

      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 200,
        minSize: 10,
      );

      final chunks = await chunker.chunk(doc, options);

      // Should parse splits from embedded JSON
      expect(chunks.length, equals(2));
    });
  });

  group('SemanticChunker _extractPartText branch coverage', () {
    late MockLlmPort mockLlm;
    late SemanticChunker chunker;

    setUp(() {
      mockLlm = MockLlmPort();
      chunker = SemanticChunker(mockLlm);
    });

    test('handles TableBlock part via toMarkdown()', () async {
      // Create a document with a TableBlock to exercise line 227
      final doc = NormalizedDocument(
        id: 'doc_table',
        metadata: const DocumentMetadata(mimeType: 'text/html', sha256: 'abc'),
        parts: [
          const TableBlock(
            id: 'tbl1',
            rows: [
              TableRow(
                cells: [TableCell(text: 'Name'), TableCell(text: 'Age')],
                isHeader: true,
              ),
              TableRow(
                cells: [TableCell(text: 'Alice'), TableCell(text: '30')],
              ),
            ],
            rowCount: 2,
            columnCount: 2,
          ),
        ],
        structure: DocumentStructure.empty,
        provenance: ExtractionProvenance(
          extractorId: 'test',
          extractorVersion: '1.0',
          extractedAt: DateTime(2024, 1, 1),
          extractionDuration: Duration.zero,
        ),
      );

      // Short doc path (maxSize large) to exercise _extractPartText without LLM
      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 10000,
        minSize: 1,
      );

      final chunks = await chunker.chunk(doc, options);

      expect(chunks.length, equals(1));
      // The text should contain the markdown table output
      expect(chunks[0].text, contains('Name'));
      expect(chunks[0].text, contains('Alice'));
    });

    test('handles ListBlock part via items mapping', () async {
      // Create a document with a ListBlock to exercise line 228
      final doc = NormalizedDocument(
        id: 'doc_list',
        metadata: const DocumentMetadata(mimeType: 'text/plain', sha256: 'abc'),
        parts: [
          const ListBlock(
            id: 'lst1',
            type: ListType.unordered,
            items: [
              ListItem(text: 'Item one'),
              ListItem(text: 'Item two'),
              ListItem(text: 'Item three'),
            ],
          ),
        ],
        structure: DocumentStructure.empty,
        provenance: ExtractionProvenance(
          extractorId: 'test',
          extractorVersion: '1.0',
          extractedAt: DateTime(2024, 1, 1),
          extractionDuration: Duration.zero,
        ),
      );

      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 10000,
        minSize: 1,
      );

      final chunks = await chunker.chunk(doc, options);

      expect(chunks.length, equals(1));
      expect(chunks[0].text, contains('- Item one'));
      expect(chunks[0].text, contains('- Item two'));
      expect(chunks[0].text, contains('- Item three'));
    });

    test('handles KeyValueBlock part via key:value format', () async {
      // Create a document with a KeyValueBlock to exercise line 229
      final doc = NormalizedDocument(
        id: 'doc_kv',
        metadata: const DocumentMetadata(mimeType: 'text/plain', sha256: 'abc'),
        parts: [
          const KeyValueBlock(
            id: 'kv1',
            key: 'total',
            value: '250.00',
          ),
        ],
        structure: DocumentStructure.empty,
        provenance: ExtractionProvenance(
          extractorId: 'test',
          extractorVersion: '1.0',
          extractedAt: DateTime(2024, 1, 1),
          extractionDuration: Duration.zero,
        ),
      );

      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 10000,
        minSize: 1,
      );

      final chunks = await chunker.chunk(doc, options);

      expect(chunks.length, equals(1));
      expect(chunks[0].text, contains('total: 250.00'));
    });

    test('handles ImageBlock part via caption/ocrText/visionDescription', () async {
      // Create a document with an ImageBlock to exercise lines 230-231
      // _extractPartText is called internally for sourceSpan calculation
      // and part offset mapping, even though the chunk text comes from fullText
      final doc = NormalizedDocument(
        id: 'doc_img',
        metadata: const DocumentMetadata(mimeType: 'image/png', sha256: 'abc'),
        parts: [
          const ImageBlock(
            id: 'img1',
            assetRef: 'inline:abc123',
            caption: 'A sunset photo',
            ocrText: 'OCR text from image',
            visionDescription: 'A beautiful sunset over the ocean',
          ),
        ],
        structure: DocumentStructure.empty,
        provenance: ExtractionProvenance(
          extractorId: 'test',
          extractorVersion: '1.0',
          extractedAt: DateTime(2024, 1, 1),
          extractionDuration: Duration.zero,
        ),
      );

      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 10000,
        minSize: 1,
      );

      final chunks = await chunker.chunk(doc, options);

      expect(chunks.length, equals(1));
      // chunk text comes from NormalizedDocument.fullText which includes caption and ocrText
      expect(chunks[0].text, contains('A sunset photo'));
      expect(chunks[0].text, contains('OCR text from image'));
      // sourceSpans should be populated (proves _extractPartText was called)
      expect(chunks[0].sourceSpans.length, equals(1));
      expect(chunks[0].sourceSpans[0].partId, equals('img1'));
    });

    test('handles AudioBlock part via transcript', () async {
      // Create a document with an AudioBlock to exercise line 232
      final doc = NormalizedDocument(
        id: 'doc_audio',
        metadata: const DocumentMetadata(mimeType: 'audio/mpeg', sha256: 'abc'),
        parts: [
          const AudioBlock(
            id: 'aud1',
            assetRef: 'inline:audio123',
            transcript: 'This is the audio transcript content',
          ),
        ],
        structure: DocumentStructure.empty,
        provenance: ExtractionProvenance(
          extractorId: 'test',
          extractorVersion: '1.0',
          extractedAt: DateTime(2024, 1, 1),
          extractionDuration: Duration.zero,
        ),
      );

      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 10000,
        minSize: 1,
      );

      final chunks = await chunker.chunk(doc, options);

      expect(chunks.length, equals(1));
      expect(chunks[0].text, contains('This is the audio transcript content'));
    });

    test('handles AudioBlock part with null transcript', () async {
      // AudioBlock without transcript returns empty string (line 232)
      final doc = NormalizedDocument(
        id: 'doc_audio_null',
        metadata: const DocumentMetadata(mimeType: 'audio/mpeg', sha256: 'abc'),
        parts: [
          const AudioBlock(
            id: 'aud2',
            assetRef: 'inline:audio456',
            // transcript is null
          ),
        ],
        structure: DocumentStructure.empty,
        provenance: ExtractionProvenance(
          extractorId: 'test',
          extractorVersion: '1.0',
          extractedAt: DateTime(2024, 1, 1),
          extractionDuration: Duration.zero,
        ),
      );

      final options = const ChunkOptions(
        targetSize: 100,
        maxSize: 10000,
        minSize: 1,
      );

      final chunks = await chunker.chunk(doc, options);

      // AudioBlock with null transcript produces empty text, but the chunk
      // still exists since the short-doc path always returns one chunk
      expect(chunks.length, equals(1));
    });
  });
}
