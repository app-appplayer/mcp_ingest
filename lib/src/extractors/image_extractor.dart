/// Image metadata extractor.
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

/// Extracts image metadata only.
/// OCR and Vision analysis are handled by IngestPipeline's Enhance stage
/// (see pipeline.md Stage 5), not by the extractor.
class ImageExtractor extends Extractor {
  ImageExtractor();

  @override
  String get id => 'image_meta_v1';

  @override
  Set<String> get supportedTypes => {
        'image/jpeg',
        'image/png',
        'image/gif',
        'image/webp',
        'image/tiff',
        'image/bmp',
      };

  @override
  int get priority => 0;

  @override
  Duration estimateDuration(int fileSize) =>
      Duration(milliseconds: fileSize ~/ 50000); // ~20ms per MB

  @override
  Future<NormalizedDocument> extract(
    Stream<List<int>> input,
    ExtractOptions options,
  ) async {
    final stopwatch = Stopwatch()..start();
    final bytes = await collectBytes(input);
    final parts = <DocumentPart>[];

    // Store image as inline base64 (pipeline will handle permanent storage)
    final assetRef = 'inline:${base64Encode(bytes)}';

    // Extract image metadata
    final imageInfo = _extractImageMetadata(bytes);

    parts.add(ImageBlock(
      id: 'img0',
      assetRef: assetRef,
      width: imageInfo.width,
      height: imageInfo.height,
      format: imageInfo.format,
    ));

    stopwatch.stop();
    final hash = sha256.convert(bytes).toString();

    return NormalizedDocument(
      id: const Uuid().v4(),
      metadata: DocumentMetadata(
        mimeType: imageInfo.mimeType,
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

  _ImageInfo _extractImageMetadata(Uint8List bytes) {
    // PNG
    if (bytes.length >= 24 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      final width =
          (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      final height =
          (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
      return _ImageInfo(
        width: width,
        height: height,
        format: 'png',
        mimeType: 'image/png',
      );
    }

    // JPEG
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      // Find SOF0 marker for dimensions
      var offset = 2;
      while (offset < bytes.length - 8) {
        if (bytes[offset] == 0xFF) {
          final marker = bytes[offset + 1];
          if (marker >= 0xC0 && marker <= 0xC3) {
            final height = (bytes[offset + 5] << 8) | bytes[offset + 6];
            final width = (bytes[offset + 7] << 8) | bytes[offset + 8];
            return _ImageInfo(
              width: width,
              height: height,
              format: 'jpeg',
              mimeType: 'image/jpeg',
            );
          }
          final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
          offset += length + 2;
        } else {
          offset++;
        }
      }
      return _ImageInfo(format: 'jpeg', mimeType: 'image/jpeg');
    }

    // GIF
    if (bytes.length >= 10 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      final width = bytes[6] | (bytes[7] << 8);
      final height = bytes[8] | (bytes[9] << 8);
      return _ImageInfo(
        width: width,
        height: height,
        format: 'gif',
        mimeType: 'image/gif',
      );
    }

    // WebP
    if (bytes.length >= 30 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return _ImageInfo(format: 'webp', mimeType: 'image/webp');
    }

    return _ImageInfo(format: 'unknown', mimeType: 'application/octet-stream');
  }
}

class _ImageInfo {
  final int? width;
  final int? height;
  final String format;
  final String mimeType;

  _ImageInfo({
    this.width,
    this.height,
    required this.format,
    required this.mimeType,
  });
}
