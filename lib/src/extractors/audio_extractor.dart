/// Audio metadata extractor.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../core/ingest_input.dart';
import '../document/document_metadata.dart';
import '../document/document_part.dart';
import '../document/document_structure.dart';
import '../document/normalized_document.dart';
import 'extractor.dart';

/// Extracts audio metadata only.
/// ASR transcription is handled by IngestPipeline's Enhance stage
/// (see pipeline.md Stage 5), not by the extractor.
class AudioExtractor extends Extractor {
  AudioExtractor();

  @override
  String get id => 'audio_meta_v1';

  @override
  Set<String> get supportedTypes => {
        'audio/mpeg',
        'audio/mp3',
        'audio/wav',
        'audio/ogg',
        'audio/flac',
        'audio/aac',
        'audio/m4a',
        'audio/x-wav',
      };

  @override
  int get priority => 0;

  @override
  Duration estimateDuration(int fileSize) =>
      Duration(milliseconds: fileSize ~/ 50000); // ~20ms per MB (metadata only)

  @override
  Future<NormalizedDocument> extract(
    Stream<List<int>> input,
    ExtractOptions options,
  ) async {
    final stopwatch = Stopwatch()..start();
    final bytes = await collectBytes(input);
    final parts = <DocumentPart>[];

    // Store audio as inline base64 (pipeline will handle permanent storage)
    final assetRef = 'inline:${base64Encode(bytes)}';

    // Extract audio metadata
    final audioInfo = _extractAudioMetadata(bytes);

    parts.add(AudioBlock(
      id: 'audio0',
      assetRef: assetRef,
      format: audioInfo.format,
      sampleRate: audioInfo.sampleRate,
    ));

    stopwatch.stop();
    final hash = sha256.convert(bytes).toString();

    return NormalizedDocument(
      id: const Uuid().v4(),
      metadata: DocumentMetadata(
        mimeType: audioInfo.mimeType,
        sha256: hash,
        fileSize: bytes.length,
      ),
      parts: parts,
      structure: DocumentStructure.empty,
      provenance: ExtractionProvenance(
        extractorId: id,
        extractorVersion: '1.0.0',
        extractedAt: DateTime.now(),
        extractionDuration: stopwatch.elapsed,
      ),
    );
  }

  _AudioInfo _extractAudioMetadata(Uint8List bytes) {
    // MP3 (ID3 or sync word)
    if (bytes.length >= 3 &&
        ((bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) ||
            (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0))) {
      return _AudioInfo(
        format: 'mp3',
        mimeType: 'audio/mpeg',
      );
    }

    // WAV (RIFF....WAVE)
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x41 &&
        bytes[10] == 0x56 &&
        bytes[11] == 0x45) {
      // Try to extract sample rate from fmt chunk
      int? sampleRate;
      if (bytes.length >= 28) {
        sampleRate = bytes[24] |
            (bytes[25] << 8) |
            (bytes[26] << 16) |
            (bytes[27] << 24);
      }
      return _AudioInfo(
        format: 'wav',
        mimeType: 'audio/wav',
        sampleRate: sampleRate,
      );
    }

    // OGG
    if (bytes.length >= 4 &&
        bytes[0] == 0x4F &&
        bytes[1] == 0x67 &&
        bytes[2] == 0x67 &&
        bytes[3] == 0x53) {
      return _AudioInfo(
        format: 'ogg',
        mimeType: 'audio/ogg',
      );
    }

    // FLAC
    if (bytes.length >= 4 &&
        bytes[0] == 0x66 &&
        bytes[1] == 0x4C &&
        bytes[2] == 0x61 &&
        bytes[3] == 0x43) {
      return _AudioInfo(
        format: 'flac',
        mimeType: 'audio/flac',
      );
    }

    return _AudioInfo(
      format: 'unknown',
      mimeType: 'audio/mpeg',
    );
  }
}

class _AudioInfo {
  final String format;
  final String mimeType;
  final int? sampleRate;

  _AudioInfo({
    required this.format,
    required this.mimeType,
    this.sampleRate,
  });
}
