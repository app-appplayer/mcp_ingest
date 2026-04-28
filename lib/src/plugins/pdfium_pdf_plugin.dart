/// Pdfium PDF plugin implementation.
library;

import 'dart:io';

import 'plugin.dart';

/// Pdfium PDF implementation using native CLI or FFI.
///
/// Requires pdfium tools to be installed on the system.
/// - macOS: brew install pdfium (or use bundled binary)
/// - Linux: apt install libpdfium-dev
/// - Windows: Download from pdfium releases
class PdfiumPdfPlugin extends PdfPlugin {
  /// Path to pdfium binary or library.
  final String? pdfiumPath;

  /// Path to pdftoppm (poppler-utils fallback).
  final String pdftoppmPath;

  /// Path to pdftotext (poppler-utils fallback).
  final String pdftotextPath;

  /// Path to pdfinfo (poppler-utils fallback).
  final String pdfinfoPath;

  PdfiumPdfPlugin({
    this.pdfiumPath,
    this.pdftoppmPath = 'pdftoppm',
    this.pdftotextPath = 'pdftotext',
    this.pdfinfoPath = 'pdfinfo',
  });

  @override
  String get id => 'pdfium';

  @override
  String get name => 'Pdfium PDF';

  @override
  String get version => '1.0.0';

  @override
  Future<bool> isAvailable() async {
    // Check for pdftotext (poppler-utils) as fallback
    try {
      final result = await Process.run('which', [pdftotextPath]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> initialize() async {
    // No initialization needed for CLI-based implementation
  }

  @override
  Future<void> dispose() async {
    // No cleanup needed for CLI-based implementation
  }

  @override
  Future<PdfPluginResult> extractText(
    List<int> pdfBytes,
    PdfPluginOptions options,
  ) async {
    final stopwatch = Stopwatch()..start();
    final tempDir = await Directory.systemTemp.createTemp('pdfium_');
    final inputFile = File('${tempDir.path}/input.pdf');

    try {
      await inputFile.writeAsBytes(pdfBytes);

      // Get page count first
      final pageCount = await getPageCount(pdfBytes);
      final maxPages = options.maxPages ?? pageCount;
      final pagesToExtract = maxPages < pageCount ? maxPages : pageCount;

      // Extract text using pdftotext
      final pages = <PdfPageResult>[];

      for (var i = 0; i < pagesToExtract; i++) {
        final outputFile = File('${tempDir.path}/page_$i.txt');

        // Extract single page
        final args = [
          '-f', '${i + 1}',  // First page (1-indexed)
          '-l', '${i + 1}',  // Last page
          '-layout',         // Maintain layout
          inputFile.path,
          outputFile.path,
        ];

        final result = await Process.run(pdftotextPath, args);

        String pageText = '';
        if (result.exitCode == 0 && await outputFile.exists()) {
          pageText = await outputFile.readAsString();
        }

        // Get page dimensions from pdfinfo
        final dimensions = await _getPageDimensions(inputFile.path, i);

        pages.add(PdfPageResult(
          index: i,
          text: pageText.trim(),
          width: dimensions.$1,
          height: dimensions.$2,
          hasTextLayer: pageText.trim().isNotEmpty,
        ));
      }

      // Get metadata
      final metadata = await getMetadata(pdfBytes);

      stopwatch.stop();

      return PdfPluginResult(
        pages: pages,
        metadata: metadata,
        processingTime: stopwatch.elapsed,
      );
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  @override
  Future<List<int>> renderPage(
    List<int> pdfBytes,
    int pageIndex,
    RenderOptions options,
  ) async {
    final tempDir = await Directory.systemTemp.createTemp('pdfium_render_');
    final inputFile = File('${tempDir.path}/input.pdf');

    try {
      await inputFile.writeAsBytes(pdfBytes);

      final outputBase = '${tempDir.path}/output';

      // Use pdftoppm to render page
      final args = [
        '-f', '${pageIndex + 1}',  // First page (1-indexed)
        '-l', '${pageIndex + 1}',  // Last page
        '-r', options.dpi.toString(),
        if (options.format == 'png') '-png',
        inputFile.path,
        outputBase,
      ];

      final result = await Process.run(pdftoppmPath, args);

      if (result.exitCode != 0) {
        throw PdfException('Page render failed: ${result.stderr}');
      }

      // Find output file
      final outputFile = _findOutputFile(tempDir, pageIndex, options.format);
      if (outputFile == null) {
        throw PdfException('Output file not found after rendering');
      }

      return await outputFile.readAsBytes();
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  File? _findOutputFile(Directory dir, int pageIndex, String format) {
    final extension = format == 'png' ? '.png' : '.ppm';

    // pdftoppm outputs with page numbers
    for (final file in dir.listSync()) {
      if (file is File && file.path.endsWith(extension)) {
        return file;
      }
    }
    return null;
  }

  @override
  Future<int> getPageCount(List<int> pdfBytes) async {
    final tempDir = await Directory.systemTemp.createTemp('pdfium_info_');
    final inputFile = File('${tempDir.path}/input.pdf');

    try {
      await inputFile.writeAsBytes(pdfBytes);

      final result = await Process.run(pdfinfoPath, [inputFile.path]);

      if (result.exitCode != 0) {
        throw PdfException('pdfinfo failed: ${result.stderr}');
      }

      final output = result.stdout as String;
      final pageMatch = RegExp(r'Pages:\s+(\d+)').firstMatch(output);

      if (pageMatch != null) {
        return int.parse(pageMatch.group(1)!);
      }

      return 0;
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  @override
  Future<PdfMetadata> getMetadata(List<int> pdfBytes) async {
    final tempDir = await Directory.systemTemp.createTemp('pdfium_meta_');
    final inputFile = File('${tempDir.path}/input.pdf');

    try {
      await inputFile.writeAsBytes(pdfBytes);

      final result = await Process.run(pdfinfoPath, [inputFile.path]);

      if (result.exitCode != 0) {
        return const PdfMetadata(pageCount: 0);
      }

      final output = result.stdout as String;

      return PdfMetadata(
        title: _extractField(output, 'Title'),
        author: _extractField(output, 'Author'),
        subject: _extractField(output, 'Subject'),
        creator: _extractField(output, 'Creator'),
        creationDate: _parseDate(_extractField(output, 'CreationDate')),
        modificationDate: _parseDate(_extractField(output, 'ModDate')),
        pageCount: int.tryParse(_extractField(output, 'Pages') ?? '0') ?? 0,
      );
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  Future<(double, double)> _getPageDimensions(String pdfPath, int pageIndex) async {
    try {
      final result = await Process.run(pdfinfoPath, [
        '-f', '${pageIndex + 1}',
        '-l', '${pageIndex + 1}',
        pdfPath,
      ]);

      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final sizeMatch = RegExp(r'Page size:\s+([\d.]+)\s+x\s+([\d.]+)').firstMatch(output);

        if (sizeMatch != null) {
          final width = double.tryParse(sizeMatch.group(1)!) ?? 612.0;
          final height = double.tryParse(sizeMatch.group(2)!) ?? 792.0;
          return (width, height);
        }
      }
    } catch (_) {
      // Ignore errors
    }

    // Default to US Letter size in points
    return (612.0, 792.0);
  }

  String? _extractField(String output, String field) {
    final match = RegExp('$field:\\s*(.+)').firstMatch(output);
    final value = match?.group(1)?.trim();
    return (value?.isNotEmpty ?? false) ? value : null;
  }

  DateTime? _parseDate(String? dateStr) {
    if (dateStr == null) return null;

    try {
      // PDF date format: D:YYYYMMDDHHmmSS
      if (dateStr.startsWith('D:')) {
        final cleaned = dateStr.substring(2);
        if (cleaned.length >= 8) {
          final year = int.parse(cleaned.substring(0, 4));
          final month = int.parse(cleaned.substring(4, 6));
          final day = int.parse(cleaned.substring(6, 8));
          return DateTime(year, month, day);
        }
      }
      return DateTime.tryParse(dateStr);
    } catch (_) {
      return null;
    }
  }
}

/// PDF-specific exception.
class PdfException implements Exception {
  final String message;
  PdfException(this.message);

  @override
  String toString() => 'PdfException: $message';
}
