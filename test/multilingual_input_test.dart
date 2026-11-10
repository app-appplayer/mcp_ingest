// Korean/Japanese/Chinese input, non-UTF-8 text, Flate-compressed PDFs and the
// target workspace of the emitted Evidence.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show ZLibEncoder;
import 'package:mcp_ingest/mcp_ingest.dart';
import 'package:mcp_ingest/src/extractors/text_decoding.dart';
import 'package:test/test.dart';

NormalizedDocument _doc(String text) => NormalizedDocument(
      id: 'd',
      metadata: const DocumentMetadata(
        mimeType: 'text/plain',
        sha256: 'h',
        fileSize: 1,
      ),
      parts: [
        TextBlock(id: 'p0', text: text, type: TextBlockType.paragraph),
      ],
      structure: DocumentStructure.empty,
      provenance: ExtractionProvenance(
        extractorId: 'test',
        extractorVersion: '1',
        extractedAt: DateTime(2026),
        extractionDuration: Duration.zero,
      ),
    );

void main() {
  group('decodeText', () {
    Future<String> decode(List<int> bytes, {String? encoding}) => decodeText(
          Stream.value(bytes),
          extractorId: 'test',
          encoding: encoding,
        );

    test('UTF-8 Korean/Japanese/Chinese round-trips', () async {
      const text = '배송비는 포함입니다。配送料込み。运费包含。';
      expect(await decode(utf8.encode(text)), text);
    });

    test('a UTF-8 BOM is removed', () async {
      expect(await decode([0xEF, 0xBB, 0xBF, ...utf8.encode('안녕')]), '안녕');
    });

    test('UTF-16 is read from its BOM or the stated encoding', () async {
      final le = [0xFF, 0xFE, 0x48, 0x00, 0x49, 0x00];
      final be = [0xFE, 0xFF, 0x00, 0x48, 0x00, 0x49];
      expect(await decode(le), 'HI');
      expect(await decode(be), 'HI');
      expect(
          await decode([0x48, 0x00, 0x49, 0x00], encoding: 'utf-16le'), 'HI');
      expect(
          await decode([0x00, 0x48, 0x00, 0x49], encoding: 'UTF-16BE'), 'HI');
    });

    test('latin1 is read when stated', () async {
      expect(
          await decode([0x63, 0x61, 0x66, 0xE9], encoding: 'latin1'), 'café');
    });

    test('invalid UTF-8 throws instead of substituting characters', () async {
      // The same two Hangul syllables encoded in EUC-KR.
      await expectLater(
        decode([0xBE, 0xC8, 0xB3, 0xE7]),
        throwsA(isA<ExtractionException>()),
      );
    });

    test('an unsupported encoding is named in the error', () async {
      await expectLater(
        decode([0x41], encoding: 'euc-kr'),
        throwsA(isA<ExtractionException>()
            .having((e) => e.toString(), 'message', contains('euc-kr'))),
      );
    });
  });

  group('extractors', () {
    test('TextExtractor reads Korean text and honours a stated encoding',
        () async {
      final extractor = TextExtractor();
      final doc = await extractor.extract(
        Stream.value(utf8.encode('첫 문장입니다.\n\n둘째 문단입니다.')),
        ExtractOptions.defaults,
      );
      expect(doc.fullText, contains('첫 문장입니다.'));
      expect(doc.fullText, contains('둘째 문단입니다.'));

      final latin = await extractor.extract(
        Stream.value([0x63, 0x61, 0x66, 0xE9]),
        const ExtractOptions(custom: {'encoding': 'latin1'}),
      );
      expect(latin.fullText, contains('café'));
    });

    test('TextExtractor rejects bytes that are not UTF-8', () async {
      await expectLater(
        TextExtractor().extract(
          Stream.value([0xBE, 0xC8, 0xB3, 0xE7]),
          ExtractOptions.defaults,
        ),
        throwsA(isA<ExtractionException>()),
      );
    });

    test('HtmlExtractor reads Korean markup', () async {
      final doc = await HtmlExtractor().extract(
        Stream.value(utf8.encode('<html><body><p>안녕하세요</p></body></html>')),
        ExtractOptions.defaults,
      );
      expect(doc.fullText, contains('안녕하세요'));
    });
  });

  group('SentenceChunker with CJK terminators', () {
    test('splits Japanese and Chinese sentences that have no spaces', () async {
      const options = ChunkOptions(targetSize: 12, maxSize: 14, overlap: 0);
      final chunks = await SentenceChunker().chunk(
        _doc('配送料は込みです。返品は三十日以内です。运费已包含！可以退货吗？'),
        options,
      );
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.text.length, lessThanOrEqualTo(14), reason: c.text);
      }
      expect(chunks.map((c) => c.text).join(), contains('返品は三十日以内です。'));
    });

    test('Latin sentences still need trailing whitespace', () async {
      final chunks = await SentenceChunker().chunk(
        _doc('Version 1.2 is out. It works.'),
        const ChunkOptions(targetSize: 40, maxSize: 60, overlap: 0),
      );
      expect(chunks.single.text, 'Version 1.2 is out. It works.');
    });
  });

  group('PdfExtractor', () {
    Uint8List pdf(List<int> streamBytes, {required bool flate}) {
      final head = latin1.encode(
          '%PDF-1.4\n1 0 obj\n<< /Length ${streamBytes.length}${flate ? ' /Filter /FlateDecode' : ''} >>\nstream\n');
      final tail = latin1.encode('\nendstream\nendobj\n%%EOF\n');
      return Uint8List.fromList([...head, ...streamBytes, ...tail]);
    }

    const content = 'BT /F1 12 Tf (Compressed invoice total) Tj ET';

    test('reads text from a Flate-compressed content stream', () async {
      final compressed = ZLibEncoder().encode(latin1.encode(content));
      final doc = await PdfExtractor().extract(
        Stream.value(pdf(compressed, flate: true)),
        ExtractOptions.defaults,
      );
      expect(doc.fullText, contains('Compressed invoice total'));
    });

    test('still reads an uncompressed stream', () async {
      final doc = await PdfExtractor().extract(
        Stream.value(pdf(latin1.encode(content), flate: false)),
        ExtractOptions.defaults,
      );
      expect(doc.fullText, contains('Compressed invoice total'));
    });

    test('a stream that cannot be inflated is skipped, not fatal', () async {
      final doc = await PdfExtractor().extract(
        Stream.value(pdf([1, 2, 3, 4, 5], flate: true)),
        ExtractOptions.defaults,
      );
      expect(doc.fullText, isNot(contains('Compressed')));
    });
  });

  group('workspace', () {
    test('the Evidence belongs to the workspace in the options', () async {
      final pipeline = IngestPipeline.defaults();
      final result = await pipeline.ingest(
        IngestInput.fromString('배송비는 포함입니다.', mimeType: 'text/plain'),
        const IngestOptions(workspaceId: 'ws-ko'),
      );
      expect(result.error?.message, isNull);
      expect(result.evidence!.workspaceId, "ws-ko");
      final fallback = await pipeline.ingest(
        IngestInput.fromString('hello', mimeType: 'text/plain'),
        IngestOptions.defaults,
      );
      expect(fallback.evidence!.workspaceId, 'default');
    });

    test('copyWith and the builder carry the workspace', () {
      expect(
          IngestOptions.defaults.copyWith(workspaceId: 'w').workspaceId, 'w');
      expect(IngestOptionsBuilder().workspaceId('b').build().workspaceId, 'b');
    });
  });
}
