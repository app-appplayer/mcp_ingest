/// Tesseract OCR plugin implementation.
library;

import 'dart:io';

import '../core/ingest_input.dart';
import '../ports/ocr_port.dart';
import 'plugin.dart';

/// Tesseract OCR implementation using native CLI.
///
/// Requires tesseract to be installed on the system.
/// Install via: brew install tesseract (macOS), apt install tesseract-ocr (Linux)
///
/// Implements both [OcrPort] (for pipeline injection) and [NativePlugin]
/// (for `PluginRegistry` lifecycle management).
class TesseractOcrPlugin implements OcrPort, NativePlugin {
  /// Path to tesseract binary.
  final String tesseractPath;

  /// Data directory for language files.
  final String? dataDir;

  TesseractOcrPlugin({
    this.tesseractPath = 'tesseract',
    this.dataDir,
  });

  // === NativePlugin ===

  @override
  String get id => 'tesseract';

  @override
  String get name => 'Tesseract OCR';

  @override
  String get version => '1.0';

  @override
  Future<void> initialize() async {
    // Tesseract CLI is stateless; nothing to initialize.
  }

  @override
  Future<void> dispose() async {
    // Nothing to dispose.
  }

  @override
  Future<OcrResult> recognize(
    Stream<List<int>> imageData,
    OcrOptions options,
  ) async {
    // Collect bytes
    final bytes = await collectBytes(imageData);

    // Write to temp file
    final tempDir = await Directory.systemTemp.createTemp('tesseract_');
    final inputFile = File('${tempDir.path}/input.png');
    final outputBase = '${tempDir.path}/output';

    try {
      await inputFile.writeAsBytes(bytes);

      // Build tesseract command
      final args = <String>[
        inputFile.path,
        outputBase,
        '-l', options.language,
        if (options.pageSegMode != null) ...[
          '--psm', options.pageSegMode.toString(),
        ],
        if (dataDir != null) ...[
          '--tessdata-dir', dataDir!,
        ],
        if (options.preserveLayout) ...[
          '--psm', '6', // Assume uniform block of text
        ],
        'txt', // Output format
      ];

      // Run tesseract
      final result = await Process.run(tesseractPath, args);

      if (result.exitCode != 0) {
        throw OcrException('Tesseract failed: ${result.stderr}');
      }

      // Read output
      final outputFile = File('$outputBase.txt');
      final text = await outputFile.readAsString();

      return OcrResult(
        text: text.trim(),
        confidence: 0.9, // Tesseract doesn't provide overall confidence
        processingTime: Duration.zero, // TODO: measure actual time
      );
    } finally {
      // Cleanup
      await tempDir.delete(recursive: true);
    }
  }

  @override
  Future<bool> isAvailable() async {
    try {
      final result = await Process.run(tesseractPath, ['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<String>> supportedLanguages() async {
    try {
      final args = ['--list-langs'];
      if (dataDir != null) {
        args.addAll(['--tessdata-dir', dataDir!]);
      }

      final result = await Process.run(tesseractPath, args);
      if (result.exitCode != 0) return [];

      final output = result.stdout as String;
      return output
          .split('\n')
          .skip(1) // Skip header line
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }
}

/// OCR-specific exception.
class OcrException implements Exception {
  final String message;
  OcrException(this.message);

  @override
  String toString() => 'OcrException: $message';
}
