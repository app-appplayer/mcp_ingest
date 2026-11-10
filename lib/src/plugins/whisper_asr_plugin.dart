/// Whisper ASR plugin implementation.
library;

import 'dart:convert';
import 'dart:io';

import '../core/ingest_input.dart';
import '../ports/asr_port.dart';
import 'plugin.dart';

/// Whisper ASR implementation using native CLI.
///
/// Requires whisper.cpp or OpenAI whisper to be installed.
/// Install via: pip install openai-whisper (Python)
/// Or build whisper.cpp for native binary.
///
/// Implements both [AsrPort] (for pipeline injection) and [NativePlugin]
/// (for `PluginRegistry` lifecycle management).
class WhisperAsrPlugin implements AsrPort, NativePlugin {
  /// Path to whisper binary.
  final String whisperPath;

  /// Model to use (tiny, base, small, medium, large).
  final String defaultModel;

  /// Models directory.
  final String? modelsDir;

  WhisperAsrPlugin({
    this.whisperPath = 'whisper',
    this.defaultModel = 'base',
    this.modelsDir,
  });

  // === NativePlugin ===

  @override
  String get id => 'whisper';

  @override
  String get name => 'Whisper ASR';

  @override
  String get version => '1.0';

  @override
  Future<void> initialize() async {
    // Whisper CLI is stateless; nothing to initialize.
  }

  @override
  Future<void> dispose() async {
    // Nothing to dispose.
  }

  @override
  Future<AsrResult> transcribe(
    Stream<List<int>> audioData,
    AsrOptions options,
  ) async {
    // Collect bytes
    final bytes = await collectBytes(audioData);

    // Write to temp file
    final tempDir = await Directory.systemTemp.createTemp('whisper_');
    final inputFile = File('${tempDir.path}/input.wav');

    try {
      await inputFile.writeAsBytes(bytes);

      final model = options.modelSize ?? defaultModel;

      // Build whisper command
      final args = <String>[
        inputFile.path,
        '--model',
        model,
        '--language',
        options.language,
        '--output_format',
        'json',
        '--output_dir',
        tempDir.path,
        if (options.wordTimestamps) '--word_timestamps',
        'True',
        if (modelsDir != null) ...[
          '--model_dir',
          modelsDir!,
        ],
      ];

      // Run whisper
      final result = await Process.run(whisperPath, args);

      if (result.exitCode != 0) {
        throw AsrException('Whisper failed: ${result.stderr}');
      }

      // Read JSON output
      final outputFile = File('${tempDir.path}/input.json');
      if (!await outputFile.exists()) {
        // Fallback to text output
        final textFile = File('${tempDir.path}/input.txt');
        if (await textFile.exists()) {
          final text = await textFile.readAsString();
          return AsrResult(
            text: text.trim(),
            language: options.language,
            confidence: 0.0,
            audioDuration: Duration.zero,
            processingTime: Duration.zero,
          );
        }
        throw AsrException('No output file generated');
      }

      final jsonContent = await outputFile.readAsString();
      final json = jsonDecode(jsonContent) as Map<String, dynamic>;

      return _parseWhisperJson(json, options.language);
    } finally {
      // Cleanup
      await tempDir.delete(recursive: true);
    }
  }

  AsrResult _parseWhisperJson(Map<String, dynamic> json, String language) {
    final text = json['text'] as String? ?? '';
    final segmentsJson = json['segments'] as List<dynamic>? ?? [];

    final segments = segmentsJson.map((s) {
      final segment = s as Map<String, dynamic>;
      final startSec = (segment['start'] as num?)?.toDouble() ?? 0.0;
      final endSec = (segment['end'] as num?)?.toDouble() ?? 0.0;
      return AsrSegment(
        text: segment['text'] as String? ?? '',
        startTime: Duration(milliseconds: (startSec * 1000).round()),
        endTime: Duration(milliseconds: (endSec * 1000).round()),
        confidence: (segment['confidence'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();

    final audioDurationSec = (json['duration'] as num?)?.toDouble() ?? 0.0;

    return AsrResult(
      text: text.trim(),
      language: language,
      confidence: _calculateOverallConfidence(segments),
      segments: segments,
      audioDuration: Duration(milliseconds: (audioDurationSec * 1000).round()),
      processingTime: Duration.zero, // TODO: measure actual time
    );
  }

  double _calculateOverallConfidence(List<AsrSegment> segments) {
    if (segments.isEmpty) return 0.0;

    final sum = segments.fold(0.0, (sum, s) => sum + s.confidence);
    return sum / segments.length;
  }

  @override
  Future<bool> isAvailable() async {
    try {
      final result = await Process.run(whisperPath, ['--help']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<String>> supportedLanguages() async {
    // Whisper supports many languages
    return [
      'en',
      'zh',
      'de',
      'es',
      'ru',
      'ko',
      'fr',
      'ja',
      'pt',
      'tr',
      'pl',
      'ca',
      'nl',
      'ar',
      'sv',
      'it',
      'id',
      'hi',
      'fi',
      'vi',
      'he',
      'uk',
      'el',
      'ms',
      'cs',
      'ro',
      'da',
      'hu',
      'ta',
      'no',
      'th',
      'ur',
      'hr',
      'bg',
      'lt',
      'la',
      'mi',
      'ml',
      'cy',
      'sk',
    ];
  }
}

/// ASR-specific exception.
class AsrException implements Exception {
  final String message;
  AsrException(this.message);

  @override
  String toString() => 'AsrException: $message';
}
