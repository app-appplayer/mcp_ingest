import 'dart:io';

import 'package:test/test.dart';
import 'package:mcp_ingest/mcp_ingest.dart';

/// Helper to create and chmod a mock shell script.
Future<String> _createMockScript(
    Directory dir, String name, String content) async {
  final file = File('${dir.path}/$name');
  await file.writeAsString(content);
  await Process.run('chmod', ['+x', file.path]);
  return file.path;
}

void main() {
  // ===========================================================================
  // PdfiumPdfPlugin
  // ===========================================================================
  group('PdfiumPdfPlugin', () {
    test('id returns pdfium', () {
      final plugin = PdfiumPdfPlugin();
      expect(plugin.id, 'pdfium');
    });

    test('name returns Pdfium PDF', () {
      final plugin = PdfiumPdfPlugin();
      expect(plugin.name, 'Pdfium PDF');
    });

    test('version returns 1.0.0', () {
      final plugin = PdfiumPdfPlugin();
      expect(plugin.version, '1.0.0');
    });

    test('default constructor creates instance with default paths', () {
      final plugin = PdfiumPdfPlugin();
      expect(plugin.pdftotextPath, 'pdftotext');
      expect(plugin.pdftoppmPath, 'pdftoppm');
      expect(plugin.pdfinfoPath, 'pdfinfo');
      expect(plugin.pdfiumPath, isNull);
    });

    test('custom paths constructor sets all paths', () {
      final plugin = PdfiumPdfPlugin(
        pdfiumPath: '/usr/local/bin/pdfium',
        pdftotextPath: '/usr/local/bin/pdftotext',
        pdftoppmPath: '/usr/local/bin/pdftoppm',
        pdfinfoPath: '/usr/local/bin/pdfinfo',
      );
      expect(plugin.pdfiumPath, '/usr/local/bin/pdfium');
      expect(plugin.pdftotextPath, '/usr/local/bin/pdftotext');
      expect(plugin.pdftoppmPath, '/usr/local/bin/pdftoppm');
      expect(plugin.pdfinfoPath, '/usr/local/bin/pdfinfo');
    });

    test('isAvailable returns a bool', () async {
      final plugin = PdfiumPdfPlugin();
      final result = await plugin.isAvailable();
      expect(result, isA<bool>());
    });

    test('initialize completes without error', () async {
      final plugin = PdfiumPdfPlugin();
      await expectLater(plugin.initialize(), completes);
    });

    test('dispose completes without error', () async {
      final plugin = PdfiumPdfPlugin();
      await expectLater(plugin.dispose(), completes);
    });

    test('isAvailable returns false for non-existent binary', () async {
      final plugin = PdfiumPdfPlugin(
        pdftotextPath: '/nonexistent/path/pdftotext',
      );
      final result = await plugin.isAvailable();
      expect(result, isFalse);
    });

    test('PdfException stores message', () {
      final exception = PdfException('test error');
      expect(exception.message, 'test error');
    });

    test('PdfException toString includes prefix and message', () {
      final exception = PdfException('file not found');
      expect(exception.toString(), 'PdfException: file not found');
    });

    test('PdfException implements Exception', () {
      final exception = PdfException('test');
      expect(exception, isA<Exception>());
    });

    // =========================================================================
    // Mock CLI tools tests for PdfiumPdfPlugin
    // =========================================================================
    group('with mock CLI tools', () {
      late Directory tempDir;
      late String mockPdftotext;
      late String mockPdfinfo;
      late String mockPdftoppm;
      late String mockPdfinfoFail;
      late String mockPdftoppmFail;
      late String mockPdftoppmNoOutput;
      late String mockPdfinfoNoPages;
      late String mockPdfinfoIsoDate;
      late String mockPdfinfoInvalidDate;
      late String mockPdfinfoNoPageSize;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('pdfium_test_');

        // mock_pdftotext: writes sample text to the output file
        mockPdftotext = await _createMockScript(
          tempDir,
          'mock_pdftotext',
          '#!/bin/bash\n'
              'output="\${@: -1}"\n'
              'echo "Sample extracted text from page." > "\$output"\n'
              'exit 0\n',
        );

        // mock_pdfinfo: outputs standard pdfinfo fields
        mockPdfinfo = await _createMockScript(
          tempDir,
          'mock_pdfinfo',
          '#!/bin/bash\n'
              'if echo "\$@" | grep -q "\\-f"; then\n'
              '  echo "Page size:      612.0 x 792.0 pts (letter)"\n'
              'else\n'
              '  echo "Title:          Test Document"\n'
              '  echo "Author:         Test Author"\n'
              '  echo "Subject:        Test Subject"\n'
              '  echo "Creator:        Test Creator"\n'
              '  echo "CreationDate:   D:20240115120000"\n'
              '  echo "ModDate:        D:20240115120000"\n'
              '  echo "Pages:          2"\n'
              'fi\n'
              'exit 0\n',
        );

        // mock_pdftoppm: creates a minimal PNG file
        mockPdftoppm = await _createMockScript(
          tempDir,
          'mock_pdftoppm',
          '#!/bin/bash\n'
              'output_base="\${@: -1}"\n'
              "printf '\\x89PNG\\r\\n\\x1a\\n' > \"\${output_base}-001.png\"\n"
              'exit 0\n',
        );

        // mock_pdfinfo_fail: exits with code 1
        mockPdfinfoFail = await _createMockScript(
          tempDir,
          'mock_pdfinfo_fail',
          '#!/bin/bash\n'
              'echo "Error: pdfinfo failed" >&2\n'
              'exit 1\n',
        );

        // mock_pdftoppm_fail: exits with code 1
        mockPdftoppmFail = await _createMockScript(
          tempDir,
          'mock_pdftoppm_fail',
          '#!/bin/bash\n'
              'echo "Error: render failed" >&2\n'
              'exit 1\n',
        );

        // mock_pdftoppm_no_output: succeeds but creates no output file
        mockPdftoppmNoOutput = await _createMockScript(
          tempDir,
          'mock_pdftoppm_no_output',
          '#!/bin/bash\n'
              'exit 0\n',
        );

        // mock_pdfinfo_no_pages: outputs no Pages line
        mockPdfinfoNoPages = await _createMockScript(
          tempDir,
          'mock_pdfinfo_no_pages',
          '#!/bin/bash\n'
              'echo "Title:          No Pages Doc"\n'
              'exit 0\n',
        );

        // mock_pdfinfo_iso_date: outputs ISO date format
        mockPdfinfoIsoDate = await _createMockScript(
          tempDir,
          'mock_pdfinfo_iso_date',
          '#!/bin/bash\n'
              'if echo "\$@" | grep -q "\\-f"; then\n'
              '  echo "Page size:      612.0 x 792.0 pts (letter)"\n'
              'else\n'
              '  echo "Title:          ISO Date Doc"\n'
              '  echo "Author:         ISO Author"\n'
              '  echo "CreationDate:   2024-03-15T10:30:00"\n'
              '  echo "ModDate:        2024-03-15T10:30:00"\n'
              '  echo "Pages:          1"\n'
              'fi\n'
              'exit 0\n',
        );

        // mock_pdfinfo_invalid_date: outputs garbage date
        mockPdfinfoInvalidDate = await _createMockScript(
          tempDir,
          'mock_pdfinfo_invalid_date',
          '#!/bin/bash\n'
              'if echo "\$@" | grep -q "\\-f"; then\n'
              '  echo "Page size:      612.0 x 792.0 pts (letter)"\n'
              'else\n'
              '  echo "Title:          Invalid Date Doc"\n'
              '  echo "CreationDate:   not-a-date-at-all"\n'
              '  echo "ModDate:        garbage"\n'
              '  echo "Pages:          1"\n'
              'fi\n'
              'exit 0\n',
        );

        // mock_pdfinfo_no_page_size: no Page size in -f mode
        mockPdfinfoNoPageSize = await _createMockScript(
          tempDir,
          'mock_pdfinfo_no_page_size',
          '#!/bin/bash\n'
              'if echo "\$@" | grep -q "\\-f"; then\n'
              '  echo "Some other info"\n'
              'else\n'
              '  echo "Pages:          1"\n'
              'fi\n'
              'exit 0\n',
        );
      });

      tearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      // -- getPageCount tests --

      test('getPageCount parses Pages from pdfinfo output', () async {
        final plugin = PdfiumPdfPlugin(pdfinfoPath: mockPdfinfo);
        final count = await plugin.getPageCount([0x25, 0x50, 0x44, 0x46]);
        expect(count, 2);
      });

      test('getPageCount returns 0 when pdfinfo has no Pages line', () async {
        final plugin = PdfiumPdfPlugin(pdfinfoPath: mockPdfinfoNoPages);
        final count = await plugin.getPageCount([0x25, 0x50, 0x44, 0x46]);
        expect(count, 0);
      });

      test('getPageCount throws when pdfinfo fails', () async {
        final plugin = PdfiumPdfPlugin(pdfinfoPath: mockPdfinfoFail);
        expect(
          () => plugin.getPageCount([0x25, 0x50, 0x44, 0x46]),
          throwsA(isA<PdfException>()),
        );
      });

      // -- getMetadata tests --

      test('getMetadata parses all fields from pdfinfo output', () async {
        final plugin = PdfiumPdfPlugin(pdfinfoPath: mockPdfinfo);
        final metadata = await plugin.getMetadata([0x25, 0x50, 0x44, 0x46]);

        expect(metadata.title, 'Test Document');
        expect(metadata.author, 'Test Author');
        expect(metadata.subject, 'Test Subject');
        expect(metadata.creator, 'Test Creator');
        expect(metadata.pageCount, 2);
        expect(metadata.creationDate, isNotNull);
        expect(metadata.creationDate!.year, 2024);
        expect(metadata.creationDate!.month, 1);
        expect(metadata.creationDate!.day, 15);
        expect(metadata.modificationDate, isNotNull);
        expect(metadata.modificationDate!.year, 2024);
        expect(metadata.modificationDate!.month, 1);
        expect(metadata.modificationDate!.day, 15);
      });

      test('getMetadata returns empty metadata when pdfinfo fails', () async {
        final plugin = PdfiumPdfPlugin(pdfinfoPath: mockPdfinfoFail);
        final metadata = await plugin.getMetadata([0x25, 0x50, 0x44, 0x46]);

        expect(metadata.pageCount, 0);
        expect(metadata.title, isNull);
        expect(metadata.author, isNull);
      });

      test('getMetadata parses ISO date format via DateTime.tryParse',
          () async {
        final plugin = PdfiumPdfPlugin(pdfinfoPath: mockPdfinfoIsoDate);
        final metadata = await plugin.getMetadata([0x25, 0x50, 0x44, 0x46]);

        expect(metadata.title, 'ISO Date Doc');
        expect(metadata.author, 'ISO Author');
        expect(metadata.creationDate, isNotNull);
        expect(metadata.creationDate!.year, 2024);
        expect(metadata.creationDate!.month, 3);
        expect(metadata.creationDate!.day, 15);
        expect(metadata.modificationDate, isNotNull);
      });

      test('getMetadata returns null dates for invalid date strings', () async {
        final plugin = PdfiumPdfPlugin(pdfinfoPath: mockPdfinfoInvalidDate);
        final metadata = await plugin.getMetadata([0x25, 0x50, 0x44, 0x46]);

        expect(metadata.title, 'Invalid Date Doc');
        expect(metadata.creationDate, isNull);
        expect(metadata.modificationDate, isNull);
      });

      // -- extractText tests --

      test('extractText extracts text from all pages', () async {
        final plugin = PdfiumPdfPlugin(
          pdftotextPath: mockPdftotext,
          pdfinfoPath: mockPdfinfo,
        );
        const options = PdfPluginOptions();
        final result = await plugin.extractText(
          [0x25, 0x50, 0x44, 0x46],
          options,
        );

        expect(result, isA<PdfPluginResult>());
        expect(result.pages.length, 2);
        expect(result.pages[0].index, 0);
        expect(result.pages[1].index, 1);
        expect(result.pages[0].text, contains('Sample extracted text'));
        expect(result.pages[0].hasTextLayer, isTrue);
        expect(result.pages[0].width, 612.0);
        expect(result.pages[0].height, 792.0);
        expect(result.metadata.title, 'Test Document');
        expect(result.metadata.pageCount, 2);
        expect(result.processingTime, isA<Duration>());
      });

      test('extractText respects maxPages option', () async {
        final plugin = PdfiumPdfPlugin(
          pdftotextPath: mockPdftotext,
          pdfinfoPath: mockPdfinfo,
        );
        const options = PdfPluginOptions(maxPages: 1);
        final result = await plugin.extractText(
          [0x25, 0x50, 0x44, 0x46],
          options,
        );

        expect(result.pages.length, 1);
        expect(result.pages[0].index, 0);
      });

      test('extractText when maxPages exceeds page count', () async {
        final plugin = PdfiumPdfPlugin(
          pdftotextPath: mockPdftotext,
          pdfinfoPath: mockPdfinfo,
        );
        const options = PdfPluginOptions(maxPages: 10);
        final result = await plugin.extractText(
          [0x25, 0x50, 0x44, 0x46],
          options,
        );

        // Page count is 2, maxPages is 10 -> extracts only 2 pages
        expect(result.pages.length, 2);
      });

      test('extractText handles pdftotext failure gracefully', () async {
        final mockPdftotextFail = await _createMockScript(
          tempDir,
          'mock_pdftotext_fail',
          '#!/bin/bash\n'
              'exit 1\n',
        );

        final plugin = PdfiumPdfPlugin(
          pdftotextPath: mockPdftotextFail,
          pdfinfoPath: mockPdfinfo,
        );
        const options = PdfPluginOptions();
        final result = await plugin.extractText(
          [0x25, 0x50, 0x44, 0x46],
          options,
        );

        // Pages are still created but with empty text
        expect(result.pages.length, 2);
        expect(result.pages[0].text, isEmpty);
        expect(result.pages[0].hasTextLayer, isFalse);
      });

      test('extractText falls back to US Letter when no page size', () async {
        final plugin = PdfiumPdfPlugin(
          pdftotextPath: mockPdftotext,
          pdfinfoPath: mockPdfinfoNoPageSize,
        );
        const options = PdfPluginOptions();
        final result = await plugin.extractText(
          [0x25, 0x50, 0x44, 0x46],
          options,
        );

        // No page size returned -> _getPageDimensions falls back to 612x792
        expect(result.pages.length, 1);
        expect(result.pages[0].width, 612.0);
        expect(result.pages[0].height, 792.0);
      });

      test('_getPageDimensions falls back to US Letter when pdfinfo -f fails',
          () async {
        final mockPdfinfoPartial = await _createMockScript(
          tempDir,
          'mock_pdfinfo_partial',
          '#!/bin/bash\n'
              'if echo "\$@" | grep -q "\\-f"; then\n'
              '  exit 1\n'
              'else\n'
              '  echo "Pages:          1"\n'
              'fi\n'
              'exit 0\n',
        );

        final plugin = PdfiumPdfPlugin(
          pdftotextPath: mockPdftotext,
          pdfinfoPath: mockPdfinfoPartial,
        );
        const options = PdfPluginOptions();
        final result = await plugin.extractText(
          [0x25, 0x50, 0x44, 0x46],
          options,
        );

        // When pdfinfo -f fails, dimensions fall back to 612.0 x 792.0
        expect(result.pages[0].width, 612.0);
        expect(result.pages[0].height, 792.0);
      });

      // -- renderPage tests --

      test('renderPage returns rendered PNG bytes', () async {
        final plugin = PdfiumPdfPlugin(pdftoppmPath: mockPdftoppm);
        const options = RenderOptions(dpi: 150, format: 'png');
        final bytes = await plugin.renderPage(
          [0x25, 0x50, 0x44, 0x46],
          0,
          options,
        );

        expect(bytes, isNotEmpty);
        // PNG header starts with 0x89 P N G
        expect(bytes[0], 0x89);
        expect(bytes[1], 0x50); // 'P'
        expect(bytes[2], 0x4E); // 'N'
        expect(bytes[3], 0x47); // 'G'
      });

      test('renderPage throws PdfException when pdftoppm fails', () async {
        final plugin = PdfiumPdfPlugin(pdftoppmPath: mockPdftoppmFail);
        const options = RenderOptions(dpi: 150, format: 'png');
        expect(
          () => plugin.renderPage([0x25, 0x50, 0x44, 0x46], 0, options),
          throwsA(
            isA<PdfException>().having(
              (e) => e.message,
              'message',
              contains('Page render failed'),
            ),
          ),
        );
      });

      test('renderPage throws when output file not found', () async {
        final plugin = PdfiumPdfPlugin(pdftoppmPath: mockPdftoppmNoOutput);
        const options = RenderOptions(dpi: 150, format: 'png');
        expect(
          () => plugin.renderPage([0x25, 0x50, 0x44, 0x46], 0, options),
          throwsA(
            isA<PdfException>().having(
              (e) => e.message,
              'message',
              contains('Output file not found'),
            ),
          ),
        );
      });

      test('renderPage uses ppm format when not png', () async {
        final mockPdftoppmPpm = await _createMockScript(
          tempDir,
          'mock_pdftoppm_ppm',
          '#!/bin/bash\n'
              'output_base="\${@: -1}"\n'
              'echo "P6 1 1 255" > "\${output_base}-001.ppm"\n'
              'exit 0\n',
        );

        final plugin = PdfiumPdfPlugin(pdftoppmPath: mockPdftoppmPpm);
        const options = RenderOptions(dpi: 72, format: 'ppm');
        final bytes = await plugin.renderPage(
          [0x25, 0x50, 0x44, 0x46],
          0,
          options,
        );

        expect(bytes, isNotEmpty);
      });

      // -- _parseDate edge cases via getMetadata --

      test('getMetadata handles D: prefix date with exactly 8 chars', () async {
        final mockPdfinfoShortDate = await _createMockScript(
          tempDir,
          'mock_pdfinfo_short_date',
          '#!/bin/bash\n'
              'echo "Title:          Short Date"\n'
              'echo "CreationDate:   D:20240301"\n'
              'echo "Pages:          1"\n'
              'exit 0\n',
        );

        final plugin = PdfiumPdfPlugin(pdfinfoPath: mockPdfinfoShortDate);
        final metadata = await plugin.getMetadata([0x25, 0x50, 0x44, 0x46]);

        expect(metadata.creationDate, isNotNull);
        expect(metadata.creationDate!.year, 2024);
        expect(metadata.creationDate!.month, 3);
        expect(metadata.creationDate!.day, 1);
      });

      test('getMetadata returns null date for D: prefix with < 8 chars',
          () async {
        final mockPdfinfoTinyDate = await _createMockScript(
          tempDir,
          'mock_pdfinfo_tiny_date',
          '#!/bin/bash\n'
              'echo "Title:          Tiny Date"\n'
              'echo "CreationDate:   D:2024"\n'
              'echo "Pages:          1"\n'
              'exit 0\n',
        );

        final plugin = PdfiumPdfPlugin(pdfinfoPath: mockPdfinfoTinyDate);
        final metadata = await plugin.getMetadata([0x25, 0x50, 0x44, 0x46]);

        // D:2024 has only 4 chars after D:, which is < 8, falls through
        // to DateTime.tryParse("D:2024") which returns null
        expect(metadata.creationDate, isNull);
      });

      // -- _extractField returns null for missing fields --

      test('_extractField returns null for missing fields', () async {
        final mockPdfinfoMinimal = await _createMockScript(
          tempDir,
          'mock_pdfinfo_minimal',
          '#!/bin/bash\n'
              'echo "Pages:          1"\n'
              'exit 0\n',
        );

        final plugin = PdfiumPdfPlugin(pdfinfoPath: mockPdfinfoMinimal);
        final metadata = await plugin.getMetadata([0x25, 0x50, 0x44, 0x46]);

        expect(metadata.title, isNull);
        expect(metadata.author, isNull);
        expect(metadata.subject, isNull);
        expect(metadata.creator, isNull);
        expect(metadata.creationDate, isNull);
        expect(metadata.modificationDate, isNull);
        expect(metadata.pageCount, 1);
      });

      // -- isAvailable with absolute mock path --

      test('isAvailable returns a bool with mock pdftotext path', () async {
        final plugin = PdfiumPdfPlugin(pdftotextPath: mockPdftotext);
        final result = await plugin.isAvailable();
        // `which` looks up in PATH; an absolute path may or may not be found
        expect(result, isA<bool>());
      });
    });
  });

  // ===========================================================================
  // TesseractOcrPlugin
  // ===========================================================================
  group('TesseractOcrPlugin', () {
    test('default constructor creates instance with default path', () {
      final plugin = TesseractOcrPlugin();
      expect(plugin.tesseractPath, 'tesseract');
      expect(plugin.dataDir, isNull);
    });

    test('custom path constructor sets tesseractPath', () {
      final plugin = TesseractOcrPlugin(
        tesseractPath: '/usr/local/bin/tesseract',
      );
      expect(plugin.tesseractPath, '/usr/local/bin/tesseract');
    });

    test('custom dataDir is set', () {
      final plugin = TesseractOcrPlugin(
        dataDir: '/usr/share/tessdata',
      );
      expect(plugin.dataDir, '/usr/share/tessdata');
    });

    test('implements OcrPort', () {
      final plugin = TesseractOcrPlugin();
      expect(plugin, isA<OcrPort>());
    });

    test('isAvailable returns a bool', () async {
      final plugin = TesseractOcrPlugin();
      final result = await plugin.isAvailable();
      expect(result, isA<bool>());
    });

    test('isAvailable returns false for non-existent binary', () async {
      final plugin = TesseractOcrPlugin(
        tesseractPath: '/nonexistent/path/tesseract',
      );
      final result = await plugin.isAvailable();
      expect(result, isFalse);
    });

    test('supportedLanguages returns a list', () async {
      final plugin = TesseractOcrPlugin();
      final langs = await plugin.supportedLanguages();
      expect(langs, isA<List<String>>());
    });

    test('OcrException stores message', () {
      final exception = OcrException('ocr failed');
      expect(exception.message, 'ocr failed');
    });

    test('OcrException toString includes prefix and message', () {
      final exception = OcrException('image corrupt');
      expect(exception.toString(), 'OcrException: image corrupt');
    });

    test('OcrException implements Exception', () {
      final exception = OcrException('test');
      expect(exception, isA<Exception>());
    });

    // =========================================================================
    // Mock CLI tests for TesseractOcrPlugin
    // =========================================================================
    group('with mock CLI', () {
      late Directory tempDir;
      late String mockTesseract;
      late String mockTesseractFail;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('tesseract_test_');

        // Mock tesseract that handles --version, --list-langs, and OCR
        mockTesseract = await _createMockScript(tempDir, 'mock_tesseract', '''
#!/bin/bash
# Handle --version
if [ "\$1" = "--version" ]; then
  echo "tesseract 5.3.0"
  exit 0
fi
# Handle --list-langs
if [ "\$1" = "--list-langs" ]; then
  echo "List of available languages (3):"
  echo "eng"
  echo "fra"
  echo "deu"
  exit 0
fi
# Normal OCR mode: tesseract input.png outputBase -l lang [...] txt
# \$1 = input file, \$2 = output base
echo "Recognized text from OCR." > "\$2.txt"
exit 0
''');

        // Mock tesseract that always fails
        mockTesseractFail =
            await _createMockScript(tempDir, 'mock_tesseract_fail', '''
#!/bin/bash
echo "Error: recognition failed" >&2
exit 1
''');
      });

      tearDown(() async {
        await tempDir.delete(recursive: true);
      });

      test('isAvailable returns true with mock tesseract', () async {
        final plugin = TesseractOcrPlugin(tesseractPath: mockTesseract);
        final result = await plugin.isAvailable();
        expect(result, isTrue);
      });

      test('supportedLanguages returns parsed languages', () async {
        final plugin = TesseractOcrPlugin(tesseractPath: mockTesseract);
        final langs = await plugin.supportedLanguages();
        expect(langs, equals(['eng', 'fra', 'deu']));
      });

      test('supportedLanguages with dataDir adds --tessdata-dir arg', () async {
        final plugin = TesseractOcrPlugin(
          tesseractPath: mockTesseract,
          dataDir: '/usr/share/tessdata',
        );
        final langs = await plugin.supportedLanguages();
        // Mock script ignores --tessdata-dir but still returns languages
        expect(langs, equals(['eng', 'fra', 'deu']));
      });

      test('supportedLanguages returns empty on failure', () async {
        final plugin = TesseractOcrPlugin(tesseractPath: mockTesseractFail);
        final langs = await plugin.supportedLanguages();
        expect(langs, isEmpty);
      });

      test('supportedLanguages returns empty when binary not found', () async {
        final plugin = TesseractOcrPlugin(
          tesseractPath: '/nonexistent/path/tesseract_xyz',
        );
        final langs = await plugin.supportedLanguages();
        expect(langs, isEmpty);
      });

      test('recognize extracts text from image data', () async {
        final plugin = TesseractOcrPlugin(tesseractPath: mockTesseract);
        final imageBytes = [0x89, 0x50, 0x4E, 0x47]; // PNG header bytes
        final imageStream = Stream<List<int>>.value(imageBytes);
        const options = OcrOptions(language: 'eng');

        final result = await plugin.recognize(imageStream, options);

        expect(result.text, 'Recognized text from OCR.');
        expect(result.confidence, 0.9);
        expect(result.processingTime, Duration.zero);
      });

      test('recognize with pageSegMode adds --psm arg', () async {
        final plugin = TesseractOcrPlugin(tesseractPath: mockTesseract);
        final imageStream = Stream<List<int>>.value([0x89, 0x50]);
        const options = OcrOptions(language: 'eng', pageSegMode: 3);

        final result = await plugin.recognize(imageStream, options);
        expect(result.text, 'Recognized text from OCR.');
      });

      test('recognize with preserveLayout adds --psm 6', () async {
        final plugin = TesseractOcrPlugin(tesseractPath: mockTesseract);
        final imageStream = Stream<List<int>>.value([0x89, 0x50]);
        const options = OcrOptions(language: 'eng', preserveLayout: true);

        final result = await plugin.recognize(imageStream, options);
        expect(result.text, 'Recognized text from OCR.');
      });

      test('recognize with dataDir adds --tessdata-dir arg', () async {
        final plugin = TesseractOcrPlugin(
          tesseractPath: mockTesseract,
          dataDir: '/usr/share/tessdata',
        );
        final imageStream = Stream<List<int>>.value([0x89, 0x50]);
        const options = OcrOptions(language: 'eng');

        final result = await plugin.recognize(imageStream, options);
        expect(result.text, 'Recognized text from OCR.');
      });

      test('recognize throws OcrException on failure', () async {
        final plugin = TesseractOcrPlugin(tesseractPath: mockTesseractFail);
        final imageStream = Stream<List<int>>.value([0x89, 0x50]);
        const options = OcrOptions(language: 'eng');

        expect(
          () => plugin.recognize(imageStream, options),
          throwsA(isA<OcrException>()),
        );
      });
    });
  });

  // ===========================================================================
  // WhisperAsrPlugin
  // ===========================================================================
  group('WhisperAsrPlugin', () {
    test('default constructor creates instance with default values', () {
      final plugin = WhisperAsrPlugin();
      expect(plugin.whisperPath, 'whisper');
      expect(plugin.defaultModel, 'base');
      expect(plugin.modelsDir, isNull);
    });

    test('custom whisperPath is set', () {
      final plugin = WhisperAsrPlugin(
        whisperPath: '/usr/local/bin/whisper',
      );
      expect(plugin.whisperPath, '/usr/local/bin/whisper');
    });

    test('custom defaultModel is set', () {
      final plugin = WhisperAsrPlugin(defaultModel: 'large');
      expect(plugin.defaultModel, 'large');
    });

    test('custom modelsDir is set', () {
      final plugin = WhisperAsrPlugin(modelsDir: '/models');
      expect(plugin.modelsDir, '/models');
    });

    test('implements AsrPort', () {
      final plugin = WhisperAsrPlugin();
      expect(plugin, isA<AsrPort>());
    });

    test('isAvailable returns a bool', () async {
      final plugin = WhisperAsrPlugin();
      final result = await plugin.isAvailable();
      expect(result, isA<bool>());
    });

    test('isAvailable returns false for non-existent binary', () async {
      final plugin = WhisperAsrPlugin(
        whisperPath: '/nonexistent/path/whisper',
      );
      final result = await plugin.isAvailable();
      expect(result, isFalse);
    });

    test('supportedLanguages returns expected language codes', () async {
      final plugin = WhisperAsrPlugin();
      final langs = await plugin.supportedLanguages();

      expect(langs, isA<List<String>>());
      expect(langs.length, greaterThanOrEqualTo(30));

      // Verify key language codes are present
      expect(langs, contains('en'));
      expect(langs, contains('zh'));
      expect(langs, contains('de'));
      expect(langs, contains('es'));
      expect(langs, contains('fr'));
      expect(langs, contains('ja'));
      expect(langs, contains('ko'));
      expect(langs, contains('ru'));
      expect(langs, contains('pt'));
      expect(langs, contains('ar'));
    });

    test('supportedLanguages includes less common languages', () async {
      final plugin = WhisperAsrPlugin();
      final langs = await plugin.supportedLanguages();

      expect(langs, contains('mi')); // Maori
      expect(langs, contains('cy')); // Welsh
      expect(langs, contains('la')); // Latin
    });

    test('AsrException stores message', () {
      final exception = AsrException('transcription failed');
      expect(exception.message, 'transcription failed');
    });

    test('AsrException toString includes prefix and message', () {
      final exception = AsrException('no audio data');
      expect(exception.toString(), 'AsrException: no audio data');
    });

    test('AsrException implements Exception', () {
      final exception = AsrException('test');
      expect(exception, isA<Exception>());
    });

    // =========================================================================
    // Mock CLI tests for WhisperAsrPlugin
    // =========================================================================
    group('with mock CLI', () {
      late Directory tempDir;
      late String mockWhisper;
      late String mockWhisperTextOnly;
      late String mockWhisperNoOutput;
      late String mockWhisperFail;
      late String mockWhisperEmptySegments;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('whisper_test_');

        // Mock whisper that produces JSON output with segments
        mockWhisper = await _createMockScript(tempDir, 'mock_whisper', '''
#!/bin/bash
# Handle --help
if [ "\$1" = "--help" ]; then
  echo "whisper help text"
  exit 0
fi
# Normal transcription mode - parse --output_dir from args
output_dir=""
prev=""
for i in "\$@"; do
  if [ "\$prev" = "--output_dir" ]; then
    output_dir="\$i"
  fi
  prev="\$i"
done
# Create JSON output
cat > "\${output_dir}/input.json" << 'JSONEOF'
{"text": "Hello world.", "duration": 5.0, "segments": [{"text": "Hello", "start": 0.0, "end": 2.0, "confidence": 0.95}, {"text": "world.", "start": 2.0, "end": 5.0, "confidence": 0.85}]}
JSONEOF
exit 0
''');

        // Mock whisper that produces only text output (no JSON)
        mockWhisperTextOnly =
            await _createMockScript(tempDir, 'mock_whisper_text', '''
#!/bin/bash
if [ "\$1" = "--help" ]; then
  echo "help"
  exit 0
fi
output_dir=""
prev=""
for i in "\$@"; do
  if [ "\$prev" = "--output_dir" ]; then
    output_dir="\$i"
  fi
  prev="\$i"
done
echo "Fallback text output." > "\${output_dir}/input.txt"
exit 0
''');

        // Mock whisper that creates no output files
        mockWhisperNoOutput =
            await _createMockScript(tempDir, 'mock_whisper_noout', '''
#!/bin/bash
if [ "\$1" = "--help" ]; then
  echo "help"
  exit 0
fi
exit 0
''');

        // Mock whisper that always fails
        mockWhisperFail =
            await _createMockScript(tempDir, 'mock_whisper_fail', '''
#!/bin/bash
echo "Error" >&2
exit 1
''');

        // Mock whisper that produces JSON with empty segments
        mockWhisperEmptySegments =
            await _createMockScript(tempDir, 'mock_whisper_empty_seg', '''
#!/bin/bash
if [ "\$1" = "--help" ]; then
  echo "help"
  exit 0
fi
output_dir=""
prev=""
for i in "\$@"; do
  if [ "\$prev" = "--output_dir" ]; then
    output_dir="\$i"
  fi
  prev="\$i"
done
cat > "\${output_dir}/input.json" << 'JSONEOF'
{"text": "", "duration": 0.0, "segments": []}
JSONEOF
exit 0
''');
      });

      tearDown(() async {
        await tempDir.delete(recursive: true);
      });

      test('isAvailable returns true with mock whisper', () async {
        final plugin = WhisperAsrPlugin(whisperPath: mockWhisper);
        final result = await plugin.isAvailable();
        expect(result, isTrue);
      });

      test('transcribe parses JSON output with segments', () async {
        final plugin = WhisperAsrPlugin(whisperPath: mockWhisper);
        final audioBytes = [0x52, 0x49, 0x46, 0x46]; // RIFF header bytes
        final audioStream = Stream<List<int>>.value(audioBytes);
        const options = AsrOptions(language: 'en');

        final result = await plugin.transcribe(audioStream, options);

        expect(result.text, 'Hello world.');
        expect(result.language, 'en');
        expect(result.segments, isNotNull);
        expect(result.segments!.length, 2);

        // Verify first segment
        expect(result.segments![0].text, 'Hello');
        expect(result.segments![0].startTime, Duration.zero);
        expect(result.segments![0].endTime, const Duration(milliseconds: 2000));
        expect(result.segments![0].confidence, 0.95);

        // Verify second segment
        expect(result.segments![1].text, 'world.');
        expect(
            result.segments![1].startTime, const Duration(milliseconds: 2000));
        expect(result.segments![1].endTime, const Duration(milliseconds: 5000));
        expect(result.segments![1].confidence, 0.85);

        // Verify audio duration
        expect(result.audioDuration, const Duration(milliseconds: 5000));

        // Verify overall confidence is average of segment confidences
        expect(result.confidence, closeTo(0.9, 0.001));
      });

      test('transcribe falls back to text output when JSON missing', () async {
        final plugin = WhisperAsrPlugin(whisperPath: mockWhisperTextOnly);
        final audioStream = Stream<List<int>>.value([0x52, 0x49]);
        const options = AsrOptions(language: 'en');

        final result = await plugin.transcribe(audioStream, options);

        expect(result.text, 'Fallback text output.');
        expect(result.language, 'en');
        expect(result.confidence, 0.0);
        expect(result.audioDuration, Duration.zero);
      });

      test('transcribe throws when no output files exist', () async {
        final plugin = WhisperAsrPlugin(whisperPath: mockWhisperNoOutput);
        final audioStream = Stream<List<int>>.value([0x52, 0x49]);
        const options = AsrOptions(language: 'en');

        expect(
          () => plugin.transcribe(audioStream, options),
          throwsA(isA<AsrException>()),
        );
      });

      test('transcribe throws when whisper fails', () async {
        final plugin = WhisperAsrPlugin(whisperPath: mockWhisperFail);
        final audioStream = Stream<List<int>>.value([0x52, 0x49]);
        const options = AsrOptions(language: 'en');

        expect(
          () => plugin.transcribe(audioStream, options),
          throwsA(isA<AsrException>()),
        );
      });

      test('transcribe uses custom model and modelsDir', () async {
        final plugin = WhisperAsrPlugin(
          whisperPath: mockWhisper,
          defaultModel: 'tiny',
          modelsDir: '/custom/models',
        );
        final audioStream = Stream<List<int>>.value([0x52, 0x49]);
        const options = AsrOptions(language: 'fr', modelSize: 'large');

        final result = await plugin.transcribe(audioStream, options);
        // The mock script produces the same output regardless of args,
        // but this exercises the code paths that build the args list
        // with --model, --model_dir options
        expect(result.text, 'Hello world.');
      });

      test('transcribe with wordTimestamps passes flag', () async {
        final plugin = WhisperAsrPlugin(whisperPath: mockWhisper);
        final audioStream = Stream<List<int>>.value([0x52, 0x49]);
        const options = AsrOptions(language: 'en', wordTimestamps: true);

        final result = await plugin.transcribe(audioStream, options);
        // Exercises the code path that adds --word_timestamps
        expect(result.text, 'Hello world.');
      });

      test('overall confidence returns 0 for empty segments', () async {
        final plugin = WhisperAsrPlugin(whisperPath: mockWhisperEmptySegments);
        final audioStream = Stream<List<int>>.value([0x52, 0x49]);
        const options = AsrOptions(language: 'en');

        final result = await plugin.transcribe(audioStream, options);

        expect(result.confidence, 0.0);
        expect(result.segments, isEmpty);
        expect(result.audioDuration, Duration.zero);
      });
    });
  });
}
