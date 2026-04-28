/// Ingest exceptions.
library;

import 'content_type.dart';

/// Base exception for ingest errors.
sealed class IngestException implements Exception {
  final String message;
  final Object? cause;

  const IngestException(this.message, [this.cause]);

  @override
  String toString() => 'IngestException: $message';
}

/// Unsupported file format.
class UnsupportedFormatException extends IngestException {
  final ContentType contentType;

  UnsupportedFormatException(this.contentType)
      : super('Unsupported format: ${contentType.mimeType}');
}

/// Extraction failed.
class ExtractionException extends IngestException {
  final String extractorId;

  ExtractionException(this.extractorId, String message, [Object? cause])
      : super('Extraction failed [$extractorId]: $message', cause);
}

/// File size limit exceeded.
class FileSizeLimitException extends IngestException {
  final int actualSize;
  final int maxSize;

  FileSizeLimitException(this.actualSize, this.maxSize)
      : super('File size $actualSize exceeds limit $maxSize');
}

/// Page limit exceeded.
class PageLimitException extends IngestException {
  final int actualPages;
  final int maxPages;

  PageLimitException(this.actualPages, this.maxPages)
      : super('Page count $actualPages exceeds limit $maxPages');
}

/// Port not configured.
class PortNotConfiguredException extends IngestException {
  final String portName;

  PortNotConfiguredException(this.portName)
      : super('Port not configured: $portName');
}

/// Plugin not available.
class PluginNotAvailableException extends IngestException {
  final String pluginName;
  final String? reason;

  PluginNotAvailableException(this.pluginName, [this.reason])
      : super(_buildMessage(pluginName, reason));

  static String _buildMessage(String pluginName, String? reason) {
    final base = 'Plugin not available: $pluginName';
    return reason != null ? '$base ($reason)' : base;
  }
}

/// Chunking failed.
class ChunkingException extends IngestException {
  final String chunkerId;

  ChunkingException(this.chunkerId, String message, [Object? cause])
      : super('Chunking failed [$chunkerId]: $message', cause);
}

/// Pipeline stage failed.
class PipelineStageException extends IngestException {
  final String stageName;

  PipelineStageException(this.stageName, String message, [Object? cause])
      : super('Pipeline stage failed [$stageName]: $message', cause);
}
