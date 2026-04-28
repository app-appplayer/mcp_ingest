/// Ingest input types.
library;

import 'dart:io';
import 'dart:typed_data';

/// Input for ingestion.
class IngestInput {
  /// Input byte stream.
  final Stream<List<int>> stream;

  /// Original filename (for MIME detection).
  final String? filename;

  /// Known MIME type (skips detection if provided).
  final String? mimeType;

  /// Source URI or path.
  final String? sourceUri;

  /// Reference to stored content (used when building Evidence entity).
  final String? contentRef;

  /// File size in bytes (optional, for limits checking).
  final int? size;

  /// Additional metadata.
  final Map<String, dynamic> metadata;

  const IngestInput({
    required this.stream,
    this.filename,
    this.mimeType,
    this.sourceUri,
    this.contentRef,
    this.size,
    this.metadata = const {},
  });

  /// Create from file path.
  factory IngestInput.fromFile(String path) {
    final file = File(path);
    return IngestInput(
      stream: file.openRead(),
      filename: file.uri.pathSegments.last,
      sourceUri: path,
      contentRef: 'file://$path',
      size: file.lengthSync(),
    );
  }

  /// Create from file object.
  factory IngestInput.fromFileSync(File file) {
    return IngestInput(
      stream: file.openRead(),
      filename: file.uri.pathSegments.last,
      sourceUri: file.uri.toString(),
      contentRef: 'file://${file.path}',
      size: file.lengthSync(),
    );
  }

  /// Create from bytes.
  factory IngestInput.fromBytes(
    Uint8List data, {
    String? filename,
    String? mimeType,
  }) {
    return IngestInput(
      stream: Stream.value(data),
      filename: filename,
      mimeType: mimeType,
      size: data.length,
    );
  }

  /// Create from string.
  factory IngestInput.fromString(
    String content, {
    String? filename,
    String mimeType = 'text/plain',
  }) {
    final bytes = Uint8List.fromList(content.codeUnits);
    return IngestInput(
      stream: Stream.value(bytes),
      filename: filename,
      mimeType: mimeType,
      size: bytes.length,
    );
  }

  /// Create from URI (supports file:// and data: URIs).
  factory IngestInput.fromUri(Uri uri) {
    if (uri.scheme == 'file') {
      return IngestInput.fromFile(uri.toFilePath());
    }
    throw ArgumentError('Unsupported URI scheme: ${uri.scheme}');
  }

  /// Collect all bytes into memory.
  Future<Uint8List> collectBytes() async {
    final chunks = <List<int>>[];
    await for (final chunk in stream) {
      chunks.add(chunk);
    }
    final length = chunks.fold<int>(0, (sum, c) => sum + c.length);
    final result = Uint8List(length);
    var offset = 0;
    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return result;
  }
}

/// Helper to collect bytes from stream.
Future<Uint8List> collectBytes(Stream<List<int>> stream) async {
  final chunks = <List<int>>[];
  await for (final chunk in stream) {
    chunks.add(chunk);
  }
  final length = chunks.fold<int>(0, (sum, c) => sum + c.length);
  final result = Uint8List(length);
  var offset = 0;
  for (final chunk in chunks) {
    result.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  return result;
}
