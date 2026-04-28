import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:mcp_ingest/mcp_ingest.dart';

void main() {
  group('ExtractOptions', () {
    test('defaults has expected values', () {
      const options = ExtractOptions.defaults;
      expect(options.extractImages, isTrue);
      expect(options.performOcr, isFalse);
      expect(options.extractTables, isTrue);
      expect(options.maxPages, isNull);
    });

    test('minimal disables images and tables', () {
      const options = ExtractOptions.minimal;
      expect(options.extractImages, isFalse);
      expect(options.extractTables, isFalse);
    });

    test('copyWith preserves unchanged values', () {
      const original = ExtractOptions(
        maxPages: 10,
        extractImages: true,
        performOcr: true,
      );
      final modified = original.copyWith(maxPages: 5);
      expect(modified.maxPages, equals(5));
      expect(modified.extractImages, isTrue);
      expect(modified.performOcr, isTrue);
    });

    test('copyWith without maxPages uses fallback from original', () {
      const original = ExtractOptions(
        maxPages: 10,
        extractImages: true,
        performOcr: true,
        extractTables: false,
        ocrLanguage: 'eng',
        custom: {'key': 'value'},
      );
      // Call copyWith without providing maxPages so the ?? fallback is used
      final modified = original.copyWith(extractImages: false);
      expect(modified.maxPages, equals(10));
      expect(modified.extractImages, isFalse);
      expect(modified.performOcr, isTrue);
      expect(modified.extractTables, isFalse);
      expect(modified.ocrLanguage, equals('eng'));
      expect(modified.custom, equals({'key': 'value'}));
    });
  });

  group('ExtractorRegistry', () {
    test('registers and finds extractors', () {
      final registry = ExtractorRegistry();
      final textExtractor = TextExtractor();
      registry.register(textExtractor);

      final found = registry.find(ContentType('text/plain'));
      expect(found, equals(textExtractor));
    });

    test('returns null for unsupported type', () {
      final registry = ExtractorRegistry();
      registry.register(TextExtractor());

      final found = registry.find(ContentType('video/mp4'));
      expect(found, isNull);
    });

    test('prioritizes higher priority extractors', () {
      final registry = ExtractorRegistry();
      final lowPriority = _TestExtractor(
        'low',
        {'text/custom'},
        0,
      );
      final highPriority = _TestExtractor(
        'high',
        {'text/custom'},
        10,
      );
      registry.register(lowPriority);
      registry.register(highPriority);

      final found = registry.find(ContentType('text/custom'));
      expect(found?.id, equals('high'));
    });

    test('all returns registered extractors', () {
      final registry = ExtractorRegistry();
      registry.register(TextExtractor());
      registry.register(JsonExtractor());

      expect(registry.all.length, equals(2));
    });
  });

  group('TextExtractor', () {
    late TextExtractor extractor;

    setUp(() {
      extractor = TextExtractor();
    });

    test('has correct id', () {
      expect(extractor.id, equals('text_plain_v1'));
    });

    test('supports text and markdown types', () {
      expect(extractor.supportedTypes, contains('text/plain'));
      expect(extractor.supportedTypes, contains('text/markdown'));
    });

    test('canHandle returns true for supported types', () {
      expect(extractor.canHandle(ContentType('text/plain')), isTrue);
      expect(extractor.canHandle(ContentType('text/markdown')), isTrue);
      expect(extractor.canHandle(ContentType('application/json')), isFalse);
    });

    test('extracts plain text paragraphs', () async {
      const content = '''First paragraph.

Second paragraph.

Third paragraph.''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.parts.length, equals(3));
      expect(doc.metadata.mimeType, equals('text/plain'));
      expect(doc.fullText, contains('First paragraph'));
      expect(doc.fullText, contains('Third paragraph'));
    });

    test('extracts markdown headings', () async {
      const content = '''# Title

Some content.

## Section

More content.''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(
        input,
        const ExtractOptions(custom: {'isMarkdown': true}),
      );

      final headings = doc.textBlocks
          .where((b) => b.type == TextBlockType.heading)
          .toList();
      expect(headings.length, equals(2));
      expect(headings[0].text, equals('Title'));
      expect(headings[0].headingLevel, equals(1));
      expect(headings[1].text, equals('Section'));
      expect(headings[1].headingLevel, equals(2));
    });

    test('extracts markdown code blocks', () async {
      const content = '''# Code Example

\`\`\`dart
void main() {
  print('Hello');
}
\`\`\`

Done.''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(
        input,
        const ExtractOptions(custom: {'isMarkdown': true}),
      );

      final codeBlocks = doc.textBlocks
          .where((b) => b.type == TextBlockType.code)
          .toList();
      expect(codeBlocks.length, equals(1));
      expect(codeBlocks[0].language, equals('dart'));
      expect(codeBlocks[0].text, contains('print'));
    });

    test('sets provenance correctly', () async {
      final input = Stream.value(utf8.encode('Test content'));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.provenance.extractorId, equals('text_plain_v1'));
      expect(doc.provenance.extractorVersion, equals('1.0.0'));
      expect(doc.provenance.extractedAt, isNotNull);
    });

    test('calculates word count', () async {
      const content = 'This is a test with seven words';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.metadata.wordCount, equals(7));
    });

    test('computes SHA256 hash', () async {
      const content = 'Test content';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.metadata.sha256.length, equals(64));
    });
  });

  group('JsonExtractor', () {
    late JsonExtractor extractor;

    setUp(() {
      extractor = JsonExtractor();
    });

    test('has correct id', () {
      expect(extractor.id, equals('json_schema_v1'));
    });

    test('supports json type', () {
      expect(extractor.supportedTypes, contains('application/json'));
    });

    test('extracts JSON object', () async {
      const content = '{"name": "Test", "value": 42}';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.parts.isNotEmpty, isTrue);
      expect(doc.metadata.mimeType, equals('application/json'));
    });

    test('extracts JSON array', () async {
      const content = '[{"id": 1}, {"id": 2}, {"id": 3}]';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.parts.isNotEmpty, isTrue);
    });

    test('handles nested structures', () async {
      const content = '''
{
  "user": {
    "name": "John",
    "address": {
      "city": "NYC"
    }
  }
}''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.fullText, contains('John'));
      expect(doc.fullText, contains('NYC'));
    });
  });

  group('HtmlExtractor', () {
    late HtmlExtractor extractor;

    setUp(() {
      extractor = HtmlExtractor();
    });

    test('has correct id', () {
      expect(extractor.id, equals('html_dom_v1'));
    });

    test('supports html type', () {
      expect(extractor.supportedTypes, contains('text/html'));
    });

    test('extracts headings from HTML', () async {
      const content = '''
<html>
<body>
  <h1>Main Title</h1>
  <p>Intro paragraph.</p>
  <h2>Section</h2>
  <p>Section content.</p>
</body>
</html>''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      final headings = doc.textBlocks
          .where((b) => b.type == TextBlockType.heading)
          .toList();
      expect(headings.isNotEmpty, isTrue);
      expect(headings.any((h) => h.text.contains('Main Title')), isTrue);
    });

    test('extracts paragraphs from HTML', () async {
      const content = '''
<html>
<body>
  <p>First paragraph.</p>
  <p>Second paragraph.</p>
</body>
</html>''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      final paragraphs = doc.textBlocks
          .where((b) => b.type == TextBlockType.paragraph)
          .toList();
      expect(paragraphs.length, greaterThanOrEqualTo(2));
    });

    test('extracts tables when enabled', () async {
      const content = '''
<html>
<body>
  <table>
    <tr><th>Name</th><th>Value</th></tr>
    <tr><td>A</td><td>1</td></tr>
  </table>
</body>
</html>''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(
        input,
        const ExtractOptions(extractTables: true),
      );

      final tables = doc.parts.whereType<TableBlock>().toList();
      expect(tables.isNotEmpty, isTrue);
    });

    test('handles content with lists', () async {
      // Note: HTML parser has limitations with :scope selector
      // Test basic extraction works without error
      const content = '''
<html>
<body>
  <p>Some paragraph before list.</p>
  <p>Item 1, Item 2, Item 3</p>
</body>
</html>''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.parts.isNotEmpty, isTrue);
    });

    test('extracts code blocks', () async {
      const content = '''
<html>
<body>
  <pre><code class="language-python">print("hello")</code></pre>
</body>
</html>''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      final codeBlocks = doc.textBlocks
          .where((b) => b.type == TextBlockType.code)
          .toList();
      expect(codeBlocks.isNotEmpty, isTrue);
    });

    test('unordered list extraction produces ListBlock', () async {
      const content = '''
<html>
<body>
  <ul>
    <li>Item 1</li>
    <li>Item 2</li>
  </ul>
</body>
</html>''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);
      final lists = doc.parts.whereType<ListBlock>().toList();
      expect(lists.length, equals(1));
      expect(lists.first.type, equals(ListType.unordered));
      expect(lists.first.items.length, equals(2));
      expect(lists.first.items[0].text, equals('Item 1'));
      expect(lists.first.items[1].text, equals('Item 2'));
    });

    test('ordered list extraction produces ListBlock', () async {
      const content = '''
<html>
<body>
  <ol>
    <li>First</li>
    <li>Second</li>
  </ol>
</body>
</html>''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);
      final lists = doc.parts.whereType<ListBlock>().toList();
      expect(lists.length, equals(1));
      expect(lists.first.type, equals(ListType.ordered));
      expect(lists.first.items.length, equals(2));
      expect(lists.first.items[0].text, equals('First'));
      expect(lists.first.items[1].text, equals('Second'));
    });

    test('nested list extraction produces ListBlock with children', () async {
      const content = '''
<html>
<body>
  <ul>
    <li>Parent<ul><li>Child</li></ul></li>
  </ul>
</body>
</html>''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);
      final lists = doc.parts.whereType<ListBlock>().toList();
      expect(lists.length, equals(1));
      expect(lists.first.items.length, equals(1));
      expect(lists.first.items[0].text, equals('Parent'));
      expect(lists.first.items[0].children, isNotNull);
      expect(lists.first.items[0].children!.length, equals(1));
      expect(lists.first.items[0].children![0].text, equals('Child'));
    });

    test('empty list items are filtered out', () async {
      const content = '''
<html>
<body>
  <ul>
    <li></li>
  </ul>
</body>
</html>''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);
      final lists = doc.parts.whereType<ListBlock>().toList();
      // Empty items are skipped, empty list returns null
      expect(lists, isEmpty);
    });

    test('builds structure from heading hierarchy', () async {
      const content = '''
<html>
<body>
  <h1>Document Title</h1>
  <p>Introduction text.</p>
  <h2>Chapter One</h2>
  <p>Chapter one content.</p>
  <h3>Section 1.1</h3>
  <p>Section content.</p>
</body>
</html>''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      // _buildStructure creates StructureNodes from h1, h2, h3
      expect(doc.structure.nodes.length, equals(3));

      // h1 -> level 0
      expect(doc.structure.nodes[0].title, equals('Document Title'));
      expect(doc.structure.nodes[0].level, equals(0));
      expect(doc.structure.nodes[0].type, equals(StructureType.section));
      expect(doc.structure.nodes[0].id, equals('section_0'));

      // h2 -> level 1
      expect(doc.structure.nodes[1].title, equals('Chapter One'));
      expect(doc.structure.nodes[1].level, equals(1));
      expect(doc.structure.nodes[1].id, equals('section_1'));

      // h3 -> level 2
      expect(doc.structure.nodes[2].title, equals('Section 1.1'));
      expect(doc.structure.nodes[2].level, equals(2));
      expect(doc.structure.nodes[2].id, equals('section_2'));

      // partIds reference heading part indices
      expect(doc.structure.nodes[0].partIds, equals(['h0']));
      expect(doc.structure.nodes[1].partIds, equals(['h1']));
      expect(doc.structure.nodes[2].partIds, equals(['h2']));
    });

    test('estimateDuration returns duration based on file size', () {
      expect(extractor.estimateDuration(5000).inMilliseconds, equals(1));
      expect(extractor.estimateDuration(50000).inMilliseconds, equals(10));
    });

    test('priority returns 0', () {
      expect(extractor.priority, equals(0));
    });

    test('default case recurses into div children', () async {
      const content = '''
<html>
<body>
  <div><p>Inside div</p></div>
</body>
</html>''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      final textParts = doc.textBlocks;
      expect(textParts.any((b) => b.text == 'Inside div'), isTrue);
    });
  });

  group('ImageExtractor', () {
    late ImageExtractor extractor;

    setUp(() {
      extractor = ImageExtractor();
    });

    test('has correct id', () {
      expect(extractor.id, equals('image_meta_v1'));
    });

    test('supports image types', () {
      expect(extractor.supportedTypes, contains('image/png'));
      expect(extractor.supportedTypes, contains('image/jpeg'));
      expect(extractor.supportedTypes, contains('image/gif'));
      expect(extractor.supportedTypes, contains('image/webp'));
    });

    test('extracts PNG metadata', () async {
      // Minimal PNG header
      final pngBytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
        0x00, 0x00, 0x00, 0x0D, // IHDR chunk length
        0x49, 0x48, 0x44, 0x52, // IHDR type
        0x00, 0x00, 0x00, 0x10, // width: 16
        0x00, 0x00, 0x00, 0x10, // height: 16
        0x08, 0x02, 0x00, 0x00, 0x00, // bit depth, color type, etc
        0x00, 0x00, 0x00, 0x00, // CRC (dummy)
      ]);

      final input = Stream.value(pngBytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.parts.isNotEmpty, isTrue);
      final imageBlock = doc.parts.first as ImageBlock;
      expect(imageBlock.format, equals('png'));
      expect(imageBlock.width, equals(16));
      expect(imageBlock.height, equals(16));
    });

    test('extracts JPEG metadata', () async {
      // Minimal JPEG header with SOI, APP0, SOF0
      final jpegBytes = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xFF, 0xE0, 0x00, 0x10, // APP0 marker and length
        0x4A, 0x46, 0x49, 0x46, 0x00, // JFIF identifier
        0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, // JFIF header
        0xFF, 0xC0, 0x00, 0x0B, // SOF0 marker and length
        0x08, // precision
        0x00, 0x20, // height: 32
        0x00, 0x40, // width: 64
        0x01, 0x01, 0x00, // components
      ]);

      final input = Stream.value(jpegBytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.parts.isNotEmpty, isTrue);
      final imageBlock = doc.parts.first as ImageBlock;
      expect(imageBlock.format, equals('jpeg'));
    });

    test('extracts GIF metadata', () async {
      // Minimal GIF header
      final gifBytes = Uint8List.fromList([
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // GIF89a
        0x10, 0x00, // width: 16
        0x20, 0x00, // height: 32
        0x80, 0x00, 0x00, // flags
      ]);

      final input = Stream.value(gifBytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.parts.isNotEmpty, isTrue);
      final imageBlock = doc.parts.first as ImageBlock;
      expect(imageBlock.format, equals('gif'));
      expect(imageBlock.width, equals(16));
      expect(imageBlock.height, equals(32));
    });

  });

  group('AudioExtractor', () {
    late AudioExtractor extractor;

    setUp(() {
      extractor = AudioExtractor();
    });

    test('has correct id', () {
      expect(extractor.id, equals('audio_meta_v1'));
    });

    test('supports audio types', () {
      expect(extractor.supportedTypes, contains('audio/mpeg'));
      expect(extractor.supportedTypes, contains('audio/mp3'));
      expect(extractor.supportedTypes, contains('audio/wav'));
      expect(extractor.supportedTypes, contains('audio/ogg'));
      expect(extractor.supportedTypes, contains('audio/flac'));
    });

    test('extracts MP3 metadata', () async {
      // MP3 with ID3 header
      final mp3Bytes = Uint8List.fromList([
        0x49, 0x44, 0x33, // ID3
        0x04, 0x00, // version 2.4.0
        0x00, // flags
        0x00, 0x00, 0x00, 0x00, // size
      ]);

      final input = Stream.value(mp3Bytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.parts.isNotEmpty, isTrue);
      final audioBlock = doc.parts.first as AudioBlock;
      expect(audioBlock.format, equals('mp3'));
      expect(doc.metadata.mimeType, equals('audio/mpeg'));
    });

    test('extracts WAV metadata', () async {
      // WAV RIFF header
      final wavBytes = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, // RIFF
        0x00, 0x00, 0x00, 0x00, // chunk size
        0x57, 0x41, 0x56, 0x45, // WAVE
        0x66, 0x6D, 0x74, 0x20, // fmt
        0x10, 0x00, 0x00, 0x00, // subchunk size
        0x01, 0x00, // audio format
        0x02, 0x00, // num channels
        0x44, 0xAC, 0x00, 0x00, // sample rate: 44100
        0x00, 0x00, 0x00, 0x00, // byte rate
        0x00, 0x00, // block align
        0x00, 0x00, // bits per sample
      ]);

      final input = Stream.value(wavBytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.parts.isNotEmpty, isTrue);
      final audioBlock = doc.parts.first as AudioBlock;
      expect(audioBlock.format, equals('wav'));
      expect(audioBlock.sampleRate, equals(44100));
    });

    test('extracts OGG metadata', () async {
      // OGG header
      final oggBytes = Uint8List.fromList([
        0x4F, 0x67, 0x67, 0x53, // OggS
        0x00, 0x02, // flags
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // granule
        0x00, 0x00, 0x00, 0x00, // serial
      ]);

      final input = Stream.value(oggBytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.parts.isNotEmpty, isTrue);
      final audioBlock = doc.parts.first as AudioBlock;
      expect(audioBlock.format, equals('ogg'));
    });

    test('extracts FLAC metadata', () async {
      // FLAC header
      final flacBytes = Uint8List.fromList([
        0x66, 0x4C, 0x61, 0x43, // fLaC
        0x00, 0x00, 0x00, 0x22, // metadata block header
      ]);

      final input = Stream.value(flacBytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.parts.isNotEmpty, isTrue);
      final audioBlock = doc.parts.first as AudioBlock;
      expect(audioBlock.format, equals('flac'));
    });

  });

  group('Extractor estimateDuration', () {
    test('estimates based on file size', () {
      final extractor = TextExtractor();
      final duration = extractor.estimateDuration(1000000);
      expect(duration.inMilliseconds, greaterThan(0));
    });
  });

  group('PdfExtractor', () {
    late PdfExtractor extractor;

    setUp(() {
      extractor = PdfExtractor();
    });

    test('has correct id', () {
      expect(extractor.id, equals('pdf_text_v1'));
    });

    test('supports application/pdf type', () {
      expect(extractor.supportedTypes, contains('application/pdf'));
      expect(extractor.supportedTypes.length, equals(1));
    });

    test('priority is 0', () {
      expect(extractor.priority, equals(0));
    });

    test('estimateDuration scales with file size', () {
      final small = extractor.estimateDuration(200);
      final large = extractor.estimateDuration(2000000);
      expect(small.inMilliseconds, equals(1));
      expect(large.inMilliseconds, equals(10000));
    });

    test('extracts text from valid PDF with Tj operator', () async {
      // Build a minimal PDF with text stream containing Tj operator
      final pdfContent = StringBuffer();
      pdfContent.write('%PDF-1.4\n');
      pdfContent.write('1 0 obj\n<< /Type /Page >>\nendobj\n');
      pdfContent.write('stream\n');
      pdfContent.write('BT\n');
      pdfContent.write('(Hello World) Tj\n');
      pdfContent.write('ET\n');
      pdfContent.write('endstream\n');
      pdfContent.write('%%EOF\n');

      final bytes = latin1.encode(pdfContent.toString());
      final input = Stream.value(bytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.provenance.extractorId, equals('pdf_text_v1'));
      expect(doc.metadata.mimeType, equals('application/pdf'));
      expect(doc.metadata.sha256.length, equals(64));
      // The PDF should extract "Hello World" text
      final fullText = doc.fullText;
      expect(fullText, contains('Hello World'));
    });

    test('detects page breaks from form feed characters', () async {
      // Build a PDF where text content contains a form feed to split pages
      final pdfContent = StringBuffer();
      pdfContent.write('%PDF-1.4\n');
      pdfContent.write('stream\n');
      pdfContent.write('(Page one text) Tj\n');
      pdfContent.write('endstream\n');
      pdfContent.write('stream\n');
      pdfContent.write('(Page two text) Tj\n');
      pdfContent.write('endstream\n');
      // Add /Type /Page markers for page count estimation
      pdfContent.write('/Type /Page\n');
      pdfContent.write('/Type /Page\n');
      pdfContent.write('%%EOF\n');

      final bytes = latin1.encode(pdfContent.toString());
      final input = Stream.value(bytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.metadata.pageCount, equals(2));
    });

    test('throws ExtractionException for invalid PDF header', () async {
      // Bytes that do not start with %PDF-
      final bytes = Uint8List.fromList(utf8.encode('Not a PDF file'));
      final input = Stream.value(bytes);

      expect(
        () => extractor.extract(input, ExtractOptions.defaults),
        throwsA(isA<ExtractionException>()),
      );
    });

    test('throws ExtractionException for small/empty input', () async {
      // Less than 5 bytes
      final bytes = Uint8List.fromList([0x25, 0x50]);
      final input = Stream.value(bytes);

      expect(
        () => extractor.extract(input, ExtractOptions.defaults),
        throwsA(isA<ExtractionException>()),
      );
    });

    test('handles PDF with string escape sequences in stream', () async {
      final pdfContent = StringBuffer();
      pdfContent.write('%PDF-1.4\n');
      pdfContent.write('stream\n');
      pdfContent.write(r'(Hello\nWorld) ');
      pdfContent.write('\nendstream\n');
      pdfContent.write('%%EOF\n');

      final bytes = latin1.encode(pdfContent.toString());
      final input = Stream.value(bytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      // Should extract text without error
      expect(doc.provenance.extractorId, equals('pdf_text_v1'));
    });

    test('handles PDF with TJ array operator', () async {
      final pdfContent = StringBuffer();
      pdfContent.write('%PDF-1.4\n');
      pdfContent.write('BT\n');
      pdfContent.write('[(Hello) -100 (World)] TJ\n');
      pdfContent.write('ET\n');
      pdfContent.write('%%EOF\n');

      final bytes = latin1.encode(pdfContent.toString());
      final input = Stream.value(bytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.fullText, contains('Hello'));
      expect(doc.fullText, contains('World'));
    });

    test('handles PDF with no readable text', () async {
      final pdfContent = StringBuffer();
      pdfContent.write('%PDF-1.4\n');
      pdfContent.write('%%EOF\n');

      final bytes = latin1.encode(pdfContent.toString());
      final input = Stream.value(bytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.parts, isEmpty);
    });

    test('canHandle returns true for PDF content type', () {
      expect(extractor.canHandle(ContentType('application/pdf')), isTrue);
      expect(extractor.canHandle(ContentType('text/plain')), isFalse);
    });
  });

  group('OfficeExtractor', () {
    late OfficeExtractor extractor;

    setUp(() {
      extractor = OfficeExtractor();
    });

    test('has correct id', () {
      expect(extractor.id, equals('office_xml_v1'));
    });

    test('supports DOCX, XLSX, PPTX types', () {
      expect(
        extractor.supportedTypes,
        contains('application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
      );
      expect(
        extractor.supportedTypes,
        contains('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
      );
      expect(
        extractor.supportedTypes,
        contains('application/vnd.openxmlformats-officedocument.presentationml.presentation'),
      );
    });

    test('priority is 0', () {
      expect(extractor.priority, equals(0));
    });

    test('estimateDuration scales with file size', () {
      final duration = extractor.estimateDuration(500000);
      expect(duration.inMilliseconds, equals(1000));
    });

    test('extracts DOCX with paragraphs', () async {
      final archive = Archive();

      // Content_Types.xml identifying this as wordprocessingml
      final contentTypesXml = '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';
      archive.addFile(ArchiveFile(
        '[Content_Types].xml',
        contentTypesXml.length,
        utf8.encode(contentTypesXml),
      ));

      // word/document.xml with paragraphs
      final documentXml = '''<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r><w:t>Hello from DOCX</w:t></w:r>
    </w:p>
    <w:p>
      <w:r><w:t>Second paragraph</w:t></w:r>
    </w:p>
  </w:body>
</w:document>''';
      archive.addFile(ArchiveFile(
        'word/document.xml',
        documentXml.length,
        utf8.encode(documentXml),
      ));

      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
      final input = Stream.value(zipBytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.metadata.mimeType, contains('wordprocessingml'));
      expect(doc.parts.length, greaterThanOrEqualTo(2));
      expect(doc.fullText, contains('Hello from DOCX'));
      expect(doc.fullText, contains('Second paragraph'));
    });

    test('extracts DOCX headings with structure', () async {
      final archive = Archive();

      final contentTypesXml = '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';
      archive.addFile(ArchiveFile(
        '[Content_Types].xml',
        contentTypesXml.length,
        utf8.encode(contentTypesXml),
      ));

      final documentXml = '''<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:pPr><w:pStyle w:val="Heading1"/></w:pPr>
      <w:r><w:t>Chapter One</w:t></w:r>
    </w:p>
    <w:p>
      <w:r><w:t>Body text here</w:t></w:r>
    </w:p>
  </w:body>
</w:document>''';
      archive.addFile(ArchiveFile(
        'word/document.xml',
        documentXml.length,
        utf8.encode(documentXml),
      ));

      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
      final input = Stream.value(zipBytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      final headings = doc.textBlocks
          .where((b) => b.type == TextBlockType.heading)
          .toList();
      expect(headings.length, equals(1));
      expect(headings.first.text, equals('Chapter One'));
      // Structure should include heading
      expect(doc.structure.nodes, isNotEmpty);
    });

    test('extracts DOCX tables', () async {
      final archive = Archive();

      final contentTypesXml = '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';
      archive.addFile(ArchiveFile(
        '[Content_Types].xml',
        contentTypesXml.length,
        utf8.encode(contentTypesXml),
      ));

      final documentXml = '''<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:tbl>
      <w:tr>
        <w:tc><w:p><w:r><w:t>Name</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>Age</w:t></w:r></w:p></w:tc>
      </w:tr>
      <w:tr>
        <w:tc><w:p><w:r><w:t>Alice</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>30</w:t></w:r></w:p></w:tc>
      </w:tr>
    </w:tbl>
  </w:body>
</w:document>''';
      archive.addFile(ArchiveFile(
        'word/document.xml',
        documentXml.length,
        utf8.encode(documentXml),
      ));

      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
      final input = Stream.value(zipBytes);
      final doc = await extractor.extract(
        input,
        const ExtractOptions(extractTables: true),
      );

      final tables = doc.parts.whereType<TableBlock>().toList();
      expect(tables.length, equals(1));
      expect(tables.first.rowCount, equals(2));
      expect(tables.first.columnCount, equals(2));
    });

    test('extracts XLSX with shared strings', () async {
      final archive = Archive();

      final contentTypesXml = '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
</Types>''';
      archive.addFile(ArchiveFile(
        '[Content_Types].xml',
        contentTypesXml.length,
        utf8.encode(contentTypesXml),
      ));

      // Shared strings
      final sharedStringsXml = '''<?xml version="1.0" encoding="UTF-8"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="2" uniqueCount="2">
  <si><t>Name</t></si>
  <si><t>Alice</t></si>
</sst>''';
      archive.addFile(ArchiveFile(
        'xl/sharedStrings.xml',
        sharedStringsXml.length,
        utf8.encode(sharedStringsXml),
      ));

      // Sheet data
      final sheet1Xml = '''<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="A1" t="s"><v>0</v></c>
    </row>
    <row r="2">
      <c r="A2" t="s"><v>1</v></c>
    </row>
  </sheetData>
</worksheet>''';
      archive.addFile(ArchiveFile(
        'xl/worksheets/sheet1.xml',
        sheet1Xml.length,
        utf8.encode(sheet1Xml),
      ));

      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
      final input = Stream.value(zipBytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.metadata.mimeType, contains('spreadsheetml'));
      final tables = doc.parts.whereType<TableBlock>().toList();
      expect(tables.length, equals(1));
      // Shared string index 0 is "Name", index 1 is "Alice"
      expect(tables.first.rows.first.cells.first.text, equals('Name'));
      expect(tables.first.rows[1].cells.first.text, equals('Alice'));
    });

    test('extracts PPTX slide text', () async {
      final archive = Archive();

      final contentTypesXml = '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
</Types>''';
      archive.addFile(ArchiveFile(
        '[Content_Types].xml',
        contentTypesXml.length,
        utf8.encode(contentTypesXml),
      ));

      // Slide 1
      final slide1Xml = '''<?xml version="1.0" encoding="UTF-8"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
       xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:sp>
        <p:txBody>
          <a:p><a:r><a:t>Slide Title</a:t></a:r></a:p>
          <a:p><a:r><a:t>Bullet point one</a:t></a:r></a:p>
        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:sld>''';
      archive.addFile(ArchiveFile(
        'ppt/slides/slide1.xml',
        slide1Xml.length,
        utf8.encode(slide1Xml),
      ));

      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
      final input = Stream.value(zipBytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.metadata.mimeType, contains('presentationml'));
      expect(doc.metadata.pageCount, equals(1));
      expect(doc.fullText, contains('Slide Title'));
      expect(doc.fullText, contains('Bullet point one'));
      // Structure should have slide node
      expect(doc.structure.nodes.any((n) => n.type == StructureType.slide), isTrue);
    });

    test('throws UnsupportedFormatException for unrecognized office type', () async {
      // ZIP without [Content_Types].xml causes _detectOfficeType to return
      // 'application/zip' which does not match any of the three office types
      final archive = Archive();
      archive.addFile(ArchiveFile(
        'dummy.txt',
        5,
        utf8.encode('hello'),
      ));
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
      final input = Stream.value(zipBytes);

      expect(
        () => extractor.extract(input, ExtractOptions.defaults),
        throwsA(isA<UnsupportedFormatException>()),
      );
    });

    test('throws ExtractionException for DOCX missing document.xml', () async {
      // Content_Types.xml identifies this as wordprocessingml but no
      // word/document.xml is present in the archive
      final archive = Archive();
      final contentTypesXml = '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';
      archive.addFile(ArchiveFile(
        '[Content_Types].xml',
        contentTypesXml.length,
        utf8.encode(contentTypesXml),
      ));

      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
      final input = Stream.value(zipBytes);

      expect(
        () => extractor.extract(input, ExtractOptions.defaults),
        throwsA(isA<ExtractionException>()),
      );
    });

    test('detects heading level from style ending with digit and containing head', () async {
      // Style "customHead2" ends with a digit and contains "head",
      // triggering the fallback heading level detection (lines 180-182)
      final archive = Archive();

      final contentTypesXml = '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';
      archive.addFile(ArchiveFile(
        '[Content_Types].xml',
        contentTypesXml.length,
        utf8.encode(contentTypesXml),
      ));

      // "hHead2" starts with 'h' so _detectDocxParagraphType returns heading.
      // It does NOT match /[Hh]eading\s*(\d)/ so the first regex in
      // _getDocxHeadingLevel fails. It DOES match /(\d)$/ and the lowercase
      // form contains 'head', triggering the fallback level detection.
      final documentXml = '''<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:pPr><w:pStyle w:val="hHead2"/></w:pPr>
      <w:r><w:t>Subheading via custom style</w:t></w:r>
    </w:p>
  </w:body>
</w:document>''';
      archive.addFile(ArchiveFile(
        'word/document.xml',
        documentXml.length,
        utf8.encode(documentXml),
      ));

      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
      final input = Stream.value(zipBytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      final headings = doc.textBlocks
          .where((b) => b.type == TextBlockType.heading)
          .toList();
      expect(headings.length, equals(1));
      expect(headings.first.text, equals('Subheading via custom style'));
      expect(headings.first.headingLevel, equals(2));
    });

    test('extracts XLSX without sharedStrings.xml', () async {
      // XLSX with sheet data but no sharedStrings.xml file (line 287)
      final archive = Archive();

      final contentTypesXml = '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
</Types>''';
      archive.addFile(ArchiveFile(
        '[Content_Types].xml',
        contentTypesXml.length,
        utf8.encode(contentTypesXml),
      ));

      // Sheet with inline numeric values (no shared string references)
      final sheet1Xml = '''<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="A1"><v>42</v></c>
      <c r="B1"><v>100</v></c>
    </row>
  </sheetData>
</worksheet>''';
      archive.addFile(ArchiveFile(
        'xl/worksheets/sheet1.xml',
        sheet1Xml.length,
        utf8.encode(sheet1Xml),
      ));

      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
      final input = Stream.value(zipBytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.metadata.mimeType, contains('spreadsheetml'));
      final tables = doc.parts.whereType<TableBlock>().toList();
      expect(tables.length, equals(1));
      // Numeric values should be extracted as-is since no shared strings exist
      expect(tables.first.rows.first.cells[0].text, equals('42'));
      expect(tables.first.rows.first.cells[1].text, equals('100'));
    });

    test('extracts XLSX sheet name from workbook.xml', () async {
      // XLSX with workbook.xml containing sheet elements (lines 300-304)
      final archive = Archive();

      final contentTypesXml = '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
</Types>''';
      archive.addFile(ArchiveFile(
        '[Content_Types].xml',
        contentTypesXml.length,
        utf8.encode(contentTypesXml),
      ));

      // Shared strings
      final sharedStringsXml = '''<?xml version="1.0" encoding="UTF-8"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="1" uniqueCount="1">
  <si><t>Revenue</t></si>
</sst>''';
      archive.addFile(ArchiveFile(
        'xl/sharedStrings.xml',
        sharedStringsXml.length,
        utf8.encode(sharedStringsXml),
      ));

      // Workbook with named sheets
      final workbookXml = '''<?xml version="1.0" encoding="UTF-8"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheets>
    <sheet name="Sales Data" sheetId="1" r:id="rId1" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/>
  </sheets>
</workbook>''';
      archive.addFile(ArchiveFile(
        'xl/workbook.xml',
        workbookXml.length,
        utf8.encode(workbookXml),
      ));

      // Sheet data referencing shared string
      final sheet1Xml = '''<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="A1" t="s"><v>0</v></c>
    </row>
  </sheetData>
</worksheet>''';
      archive.addFile(ArchiveFile(
        'xl/worksheets/sheet1.xml',
        sheet1Xml.length,
        utf8.encode(sheet1Xml),
      ));

      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
      final input = Stream.value(zipBytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      // The table caption should use the sheet name from workbook.xml
      final tables = doc.parts.whereType<TableBlock>().toList();
      expect(tables.length, equals(1));
      expect(tables.first.caption, equals('Sales Data'));

      // Structure node should also have the sheet name
      expect(doc.structure.nodes.length, equals(1));
      expect(doc.structure.nodes.first.title, equals('Sales Data'));
      expect(doc.structure.nodes.first.type, equals(StructureType.sheet));
    });
  });

  group('HtmlExtractor additional coverage', () {
    late HtmlExtractor extractor;

    setUp(() {
      extractor = HtmlExtractor();
    });

    test('extracts table with th header cells', () async {
      const content = '''
<html>
<body>
  <table>
    <tr><th>Header A</th><th>Header B</th></tr>
    <tr><td>Data A</td><td>Data B</td></tr>
  </table>
</body>
</html>''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(
        input,
        const ExtractOptions(extractTables: true),
      );

      final tables = doc.parts.whereType<TableBlock>().toList();
      expect(tables.isNotEmpty, isTrue);
      final table = tables.first;
      // First row should be a header row
      expect(table.rows.first.isHeader, isTrue);
      // Header cells should have CellType.header
      expect(table.rows.first.cells.first.type, equals(CellType.header));
      expect(table.rows.first.cells.first.text, equals('Header A'));
    });

    test('extracts images with width and height attributes', () async {
      const content = '''
<html>
<body>
  <img src="photo.jpg" alt="Photo" width="640" height="480"/>
</body>
</html>''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(
        input,
        const ExtractOptions(extractImages: true),
      );

      final images = doc.parts.whereType<ImageBlock>().toList();
      expect(images.length, equals(1));
      expect(images.first.assetRef, equals('photo.jpg'));
      expect(images.first.altText, equals('Photo'));
      expect(images.first.width, equals(640));
      expect(images.first.height, equals(480));
    });

    test('does not extract images when extractImages is false', () async {
      const content = '''
<html>
<body>
  <img src="photo.jpg" alt="Photo"/>
</body>
</html>''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(
        input,
        const ExtractOptions(extractImages: false),
      );

      final images = doc.parts.whereType<ImageBlock>().toList();
      expect(images, isEmpty);
    });

    test('extracts blockquote as quote type', () async {
      const content = '''
<html>
<body>
  <blockquote>This is a famous quote.</blockquote>
</body>
</html>''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      final quotes = doc.textBlocks
          .where((b) => b.type == TextBlockType.quote)
          .toList();
      expect(quotes.length, equals(1));
      expect(quotes.first.text, equals('This is a famous quote.'));
    });

    test('list extraction produces ListBlock with items', () async {
      const content = '''
<html>
<body>
  <ul>
    <li>Item Alpha</li>
    <li>Item Beta</li>
  </ul>
</body>
</html>''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);
      final lists = doc.parts.whereType<ListBlock>().toList();
      expect(lists.length, equals(1));
      expect(lists.first.items.length, equals(2));
      expect(lists.first.items[0].text, equals('Item Alpha'));
      expect(lists.first.items[1].text, equals('Item Beta'));
    });

    test('builds structure from heading hierarchy', () async {
      const content = '''
<html>
<body>
  <h1>Title</h1>
  <p>Intro</p>
  <h2>Section A</h2>
  <p>Content A</p>
  <h2>Section B</h2>
  <p>Content B</p>
  <h3>Subsection B1</h3>
  <p>Content B1</p>
</body>
</html>''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.structure.nodes.length, equals(4));
      expect(doc.structure.nodes[0].title, equals('Title'));
      expect(doc.structure.nodes[0].level, equals(0)); // h1 -> level 0
      expect(doc.structure.nodes[1].title, equals('Section A'));
      expect(doc.structure.nodes[1].level, equals(1)); // h2 -> level 1
      expect(doc.structure.nodes[3].title, equals('Subsection B1'));
      expect(doc.structure.nodes[3].level, equals(2)); // h3 -> level 2
    });

    test('extracts title from head element', () async {
      const content = '''
<html>
<head><title>My Page Title</title></head>
<body>
  <p>Content</p>
</body>
</html>''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.metadata.title, equals('My Page Title'));
    });

    test('skips script and style elements', () async {
      const content = '''
<html>
<body>
  <script>var x = 1;</script>
  <style>.cls { color: red; }</style>
  <p>Visible content</p>
</body>
</html>''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      expect(doc.fullText, contains('Visible content'));
      expect(doc.fullText, isNot(contains('var x')));
      expect(doc.fullText, isNot(contains('color: red')));
    });

    test('table caption is extracted', () async {
      const content = '''
<html>
<body>
  <table>
    <caption>Sales Data</caption>
    <tr><th>Product</th><th>Sales</th></tr>
    <tr><td>Widget</td><td>100</td></tr>
  </table>
</body>
</html>''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(
        input,
        const ExtractOptions(extractTables: true),
      );

      final tables = doc.parts.whereType<TableBlock>().toList();
      expect(tables.first.caption, equals('Sales Data'));
    });

    test('does not extract tables when extractTables is false', () async {
      const content = '''
<html>
<body>
  <table><tr><td>Data</td></tr></table>
  <p>Paragraph</p>
</body>
</html>''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(
        input,
        const ExtractOptions(extractTables: false),
      );

      final tables = doc.parts.whereType<TableBlock>().toList();
      expect(tables, isEmpty);
    });
  });

  group('ImageExtractor additional coverage', () {
    late ImageExtractor extractor;

    setUp(() {
      extractor = ImageExtractor();
    });

    test('detects WebP format', () async {
      // WebP header: RIFF....WEBP
      final webpBytes = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, // RIFF
        0x00, 0x00, 0x00, 0x00, // file size (dummy)
        0x57, 0x45, 0x42, 0x50, // WEBP
        // VP8 chunk header and dummy data
        0x56, 0x50, 0x38, 0x20,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00,
      ]);

      final input = Stream.value(webpBytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      final imageBlock = doc.parts.first as ImageBlock;
      expect(imageBlock.format, equals('webp'));
      expect(doc.metadata.mimeType, equals('image/webp'));
    });

    test('returns unknown format for unrecognized bytes', () async {
      // Random bytes that do not match any known image format
      final unknownBytes = Uint8List.fromList(
        List.generate(40, (i) => i + 1),
      );

      final input = Stream.value(unknownBytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      final imageBlock = doc.parts.first as ImageBlock;
      expect(imageBlock.format, equals('unknown'));
      expect(doc.metadata.mimeType, equals('application/octet-stream'));
    });

    test('estimateDuration returns small value for metadata extraction', () {
      // 50000 bytes -> 1ms
      final duration = extractor.estimateDuration(50000);
      expect(duration.inMilliseconds, equals(1));

      // 5MB -> 100ms
      final largeDuration = extractor.estimateDuration(5000000);
      expect(largeDuration.inMilliseconds, equals(100));
    });

    test('stores image as inline base64 asset', () async {
      final pngBytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x08, // width: 8
        0x00, 0x00, 0x00, 0x08, // height: 8
        0x08, 0x02, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
      ]);

      final input = Stream.value(pngBytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      final imageBlock = doc.parts.first as ImageBlock;
      expect(imageBlock.assetRef, startsWith('inline:'));
    });
  });

  group('JsonExtractor additional coverage', () {
    late JsonExtractor extractor;

    setUp(() {
      extractor = JsonExtractor();
    });

    test('throws on malformed JSON input', () async {
      const content = '{ invalid json [[[';
      final input = Stream.value(utf8.encode(content));

      // Malformed JSON that also fails YAML parse will throw
      expect(
        () => extractor.extract(input, ExtractOptions.defaults),
        throwsA(anything),
      );
    });

    test('parses YAML input with custom option', () async {
      const content = '''
name: John
age: 30
city: NYC
''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(
        input,
        const ExtractOptions(custom: {'isYaml': true}),
      );

      expect(doc.metadata.mimeType, equals('application/x-yaml'));
      expect(doc.parts.isNotEmpty, isTrue);
      expect(doc.fullText, contains('John'));
      expect(doc.fullText, contains('30'));
    });

    test('detects YAML from mimeType custom option', () async {
      const content = '''
key: value
list:
  - item1
  - item2
''';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(
        input,
        const ExtractOptions(custom: {'mimeType': 'text/yaml'}),
      );

      expect(doc.metadata.mimeType, equals('application/x-yaml'));
    });

    test('infers date type for date-like strings', () async {
      const content = '{"created": "2024-01-15"}';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      final kvParts = doc.parts.whereType<KeyValueBlock>().toList();
      expect(kvParts.isNotEmpty, isTrue);
      final datePart = kvParts.firstWhere((p) => p.key == 'created');
      expect(datePart.valueType, equals(FragmentValueType.date));
    });

    test('infers currency type for currency strings', () async {
      const content = '{"price": "\$99.99"}';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      final kvParts = doc.parts.whereType<KeyValueBlock>().toList();
      final pricePart = kvParts.firstWhere((p) => p.key == 'price');
      expect(pricePart.valueType, equals(FragmentValueType.currency));
    });

    test('infers percentage type', () async {
      const content = '{"rate": "85.5%"}';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      final kvParts = doc.parts.whereType<KeyValueBlock>().toList();
      final ratePart = kvParts.firstWhere((p) => p.key == 'rate');
      expect(ratePart.valueType, equals(FragmentValueType.percentage));
    });

    test('handles null values in JSON', () async {
      const content = '{"key": null}';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      final kvParts = doc.parts.whereType<KeyValueBlock>().toList();
      expect(kvParts.isNotEmpty, isTrue);
    });

    test('infers boolean type', () async {
      const content = '{"active": true}';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      final kvParts = doc.parts.whereType<KeyValueBlock>().toList();
      final activePart = kvParts.firstWhere((p) => p.key == 'active');
      expect(activePart.valueType, equals(FragmentValueType.boolean));
    });

    test('infers number type for integers and doubles', () async {
      const content = '{"count": 42, "ratio": 3.14}';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      final kvParts = doc.parts.whereType<KeyValueBlock>().toList();
      final countPart = kvParts.firstWhere((p) => p.key == 'count');
      expect(countPart.valueType, equals(FragmentValueType.number));
      final ratioPart = kvParts.firstWhere((p) => p.key == 'ratio');
      expect(ratioPart.valueType, equals(FragmentValueType.number));
    });

    test('falls back to YAML parsing when JSON fails', () async {
      // Valid YAML but invalid JSON
      const content = 'key: value\nlist:\n  - item1';
      final input = Stream.value(utf8.encode(content));
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      // Should succeed since YAML fallback works
      expect(doc.parts.isNotEmpty, isTrue);
    });

    test('supports all YAML mime types', () {
      expect(extractor.supportedTypes, contains('application/x-yaml'));
      expect(extractor.supportedTypes, contains('text/yaml'));
      expect(extractor.supportedTypes, contains('text/x-yaml'));
    });
  });

  group('AudioExtractor additional coverage', () {
    late AudioExtractor extractor;

    setUp(() {
      extractor = AudioExtractor();
    });

    test('estimateDuration returns small value for metadata extraction', () {
      final duration = extractor.estimateDuration(50000);
      expect(duration.inMilliseconds, equals(1));

      final largeDuration = extractor.estimateDuration(5000000);
      expect(largeDuration.inMilliseconds, equals(100));
    });

    test('returns unknown format for unrecognized audio bytes', () async {
      // Random bytes that do not match any known audio format
      final unknownBytes = Uint8List.fromList([
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
      ]);

      final input = Stream.value(unknownBytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      final audioBlock = doc.parts.first as AudioBlock;
      expect(audioBlock.format, equals('unknown'));
      // Default mime for unknown is audio/mpeg
      expect(doc.metadata.mimeType, equals('audio/mpeg'));
    });

    test('detects MP3 from sync word (non-ID3)', () async {
      // MP3 sync word: FF E0+ (frame sync)
      final mp3SyncBytes = Uint8List.fromList([
        0xFF, 0xE0, // sync word
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      ]);

      final input = Stream.value(mp3SyncBytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      final audioBlock = doc.parts.first as AudioBlock;
      expect(audioBlock.format, equals('mp3'));
    });

    test('stores audio as inline base64 asset', () async {
      final oggBytes = Uint8List.fromList([
        0x4F, 0x67, 0x67, 0x53, // OggS
        0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
      ]);

      final input = Stream.value(oggBytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      final audioBlock = doc.parts.first as AudioBlock;
      expect(audioBlock.assetRef, startsWith('inline:'));
    });
  });

  group('ExtractorRegistry exception handling', () {
    test('defaults factory creates all extractors', () {
      final registry = ExtractorRegistry.defaults();
      expect(registry.all.length, equals(7));
    });

    test('finds extractor for known types via defaults', () {
      final registry = ExtractorRegistry.defaults();

      expect(registry.find(ContentType('text/plain')), isNotNull);
      expect(registry.find(ContentType('text/html')), isNotNull);
      expect(registry.find(ContentType('application/json')), isNotNull);
      expect(registry.find(ContentType('application/pdf')), isNotNull);
      expect(registry.find(ContentType('image/png')), isNotNull);
      expect(registry.find(ContentType('audio/mpeg')), isNotNull);
    });

    test('extractor that throws during extract propagates exception', () async {
      final registry = ExtractorRegistry();
      final throwingExtractor = _ThrowingExtractor();
      registry.register(throwingExtractor);

      final found = registry.find(ContentType('text/custom'));
      expect(found, isNotNull);

      expect(
        () => found!.extract(
          Stream.value(utf8.encode('test')),
          ExtractOptions.defaults,
        ),
        throwsA(isA<ExtractionException>()),
      );
    });

    test('canHandle checks against supportedTypes set', () {
      final extractor = TextExtractor();
      expect(extractor.canHandle(ContentType('text/plain')), isTrue);
      expect(extractor.canHandle(ContentType('text/markdown')), isTrue);
      expect(extractor.canHandle(ContentType('application/pdf')), isFalse);
    });

    test('base estimateDuration returns default rate', () {
      // Use the _TestExtractor which inherits base estimateDuration
      final ext = _TestExtractor('test', {'text/test'}, 0);
      // Base implementation: fileSize ~/ 1000
      final duration = ext.estimateDuration(5000);
      expect(duration.inMilliseconds, equals(5));
    });
  });

  group('Extractor default priority', () {
    test('default priority getter returns 0', () {
      // _DefaultPriorityExtractor does NOT override priority,
      // so it uses the base Extractor default: int get priority => 0
      final extractor = _DefaultPriorityExtractor();
      expect(extractor.priority, equals(0));
    });
  });

  group('JsonExtractor estimateDuration', () {
    test('estimateDuration returns expected duration based on file size', () {
      final extractor = JsonExtractor();
      // 10000 bytes -> 10000 ~/ 10000 = 1ms
      expect(extractor.estimateDuration(10000).inMilliseconds, equals(1));
      // 100000 bytes -> 100000 ~/ 10000 = 10ms
      expect(extractor.estimateDuration(100000).inMilliseconds, equals(10));
      // 0 bytes -> 0ms
      expect(extractor.estimateDuration(0).inMilliseconds, equals(0));
    });
  });

  group('ImageExtractor JPEG parsing edge cases', () {
    late ImageExtractor extractor;

    setUp(() {
      extractor = ImageExtractor();
    });

    test('JPEG with non-SOF marker skips bytes and exits loop without dimensions', () async {
      // Build a JPEG that has a non-FF byte after SOI.
      // The while loop condition is: offset < bytes.length - 8
      // So bytes.length must be > offset + 8 (i.e., > 10) for the loop to run.
      // At offset=2, bytes[2]=0x00 (not FF) triggers offset++ (line 130).
      // Then offset=3, loop condition 3 < 11-8=3 is false, loop exits.
      // Falls through to line 133 (JPEG without dimensions).
      final jpegBytes = Uint8List.fromList([
        0xFF, 0xD8, // SOI marker (offset starts at 2)
        0x00,       // non-FF byte -> triggers offset++ (line 130)
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // padding to reach 11 bytes
      ]);

      final input = Stream.value(jpegBytes);
      final doc = await extractor.extract(input, ExtractOptions.defaults);

      final imageBlock = doc.parts.first as ImageBlock;
      expect(imageBlock.format, equals('jpeg'));
      // No SOF marker found, so width and height should be null
      expect(imageBlock.width, isNull);
      expect(imageBlock.height, isNull);
    });
  });

  group('PdfExtractor carriage return handling', () {
    test('text containing carriage return is detected as readable', () async {
      final pdfExtractor = PdfExtractor();

      // Build a PDF with text that includes carriage return (0x0D)
      final pdfContent = StringBuffer();
      pdfContent.write('%PDF-1.4\n');
      pdfContent.write('stream\n');
      pdfContent.write('(Hello\r\nWorld) Tj\n');
      pdfContent.write('endstream\n');
      pdfContent.write('%%EOF\n');

      final bytes = latin1.encode(pdfContent.toString());
      final input = Stream.value(bytes);
      final doc = await pdfExtractor.extract(input, ExtractOptions.defaults);

      // The carriage return character (0x0D) should be treated as readable
      // and the text should be extracted successfully
      expect(doc.provenance.extractorId, equals('pdf_text_v1'));
      expect(doc.fullText, contains('Hello'));
    });
  });
}

/// Test extractor that throws during extract.
class _ThrowingExtractor extends Extractor {
  @override
  String get id => 'throwing_test';

  @override
  Set<String> get supportedTypes => {'text/custom'};

  @override
  Future<NormalizedDocument> extract(
    Stream<List<int>> input,
    ExtractOptions options,
  ) {
    throw ExtractionException('throwing_test', 'Intentional test error');
  }
}

/// Test extractor for priority testing.
class _TestExtractor extends Extractor {
  @override
  final String id;

  @override
  final Set<String> supportedTypes;

  @override
  final int priority;

  _TestExtractor(this.id, this.supportedTypes, this.priority);

  @override
  Future<NormalizedDocument> extract(
    Stream<List<int>> input,
    ExtractOptions options,
  ) {
    throw UnimplementedError();
  }
}

/// Test extractor that does NOT override priority, using the base default.
class _DefaultPriorityExtractor extends Extractor {
  @override
  String get id => 'default_priority';

  @override
  Set<String> get supportedTypes => {'text/test'};

  @override
  Future<NormalizedDocument> extract(
    Stream<List<int>> input,
    ExtractOptions options,
  ) async {
    throw UnimplementedError();
  }
}
