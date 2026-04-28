/// Native plugin interfaces and registry.
library;

/// Base interface for all native plugins.
///
/// Native plugins provide local processing capabilities
/// without requiring cloud API calls.
abstract class NativePlugin {
  /// Unique identifier for this plugin.
  String get id;

  /// Human-readable name.
  String get name;

  /// Plugin version.
  String get version;

  /// Check if plugin is available on current platform.
  Future<bool> isAvailable();

  /// Initialize the plugin.
  Future<void> initialize();

  /// Cleanup resources.
  Future<void> dispose();
}

/// OCR plugin interface.
abstract class OcrPlugin extends NativePlugin {
  /// Perform OCR on image bytes.
  Future<OcrPluginResult> recognize(
    List<int> imageBytes,
    OcrPluginOptions options,
  );

  /// Supported languages.
  List<String> get supportedLanguages;
}

/// OCR plugin options.
class OcrPluginOptions {
  /// Target language code.
  final String language;

  /// Page segmentation mode.
  final int? pageSegMode;

  /// Preserve layout.
  final bool preserveLayout;

  const OcrPluginOptions({
    this.language = 'eng',
    this.pageSegMode,
    this.preserveLayout = false,
  });
}

/// OCR plugin result.
class OcrPluginResult {
  /// Extracted text.
  final String text;

  /// Overall confidence (0.0-1.0).
  final double confidence;

  /// Detected language.
  final String? language;

  /// Processing time.
  final Duration processingTime;

  /// Word-level details (optional).
  final List<OcrWord>? words;

  const OcrPluginResult({
    required this.text,
    required this.confidence,
    this.language,
    this.processingTime = Duration.zero,
    this.words,
  });
}

/// OCR word with position.
class OcrWord {
  final String text;
  final double confidence;
  final int x;
  final int y;
  final int width;
  final int height;

  const OcrWord({
    required this.text,
    required this.confidence,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

/// ASR plugin interface.
abstract class AsrPlugin extends NativePlugin {
  /// Transcribe audio bytes.
  Future<AsrPluginResult> transcribe(
    List<int> audioBytes,
    AsrPluginOptions options,
  );

  /// Supported audio formats.
  List<String> get supportedFormats;

  /// Supported languages.
  List<String> get supportedLanguages;
}

/// ASR plugin options.
class AsrPluginOptions {
  /// Target language code.
  final String language;

  /// Model size (tiny, small, medium, large).
  final String modelSize;

  /// Enable word timestamps.
  final bool wordTimestamps;

  const AsrPluginOptions({
    this.language = 'en',
    this.modelSize = 'small',
    this.wordTimestamps = true,
  });
}

/// ASR plugin result.
class AsrPluginResult {
  /// Full transcript text.
  final String text;

  /// Overall confidence (0.0-1.0).
  final double confidence;

  /// Detected language.
  final String? language;

  /// Audio duration.
  final Duration audioDuration;

  /// Processing time.
  final Duration processingTime;

  /// Transcript segments with timestamps.
  final List<AsrSegmentResult>? segments;

  const AsrPluginResult({
    required this.text,
    required this.confidence,
    this.language,
    required this.audioDuration,
    this.processingTime = Duration.zero,
    this.segments,
  });
}

/// ASR segment with timing.
class AsrSegmentResult {
  final String text;
  final Duration startTime;
  final Duration endTime;
  final double? confidence;

  const AsrSegmentResult({
    required this.text,
    required this.startTime,
    required this.endTime,
    this.confidence,
  });
}

/// PDF plugin interface.
abstract class PdfPlugin extends NativePlugin {
  /// Extract text from PDF bytes.
  Future<PdfPluginResult> extractText(
    List<int> pdfBytes,
    PdfPluginOptions options,
  );

  /// Render PDF page to image.
  Future<List<int>> renderPage(
    List<int> pdfBytes,
    int pageIndex,
    RenderOptions options,
  );

  /// Get PDF page count.
  Future<int> getPageCount(List<int> pdfBytes);

  /// Get PDF metadata.
  Future<PdfMetadata> getMetadata(List<int> pdfBytes);
}

/// PDF plugin options.
class PdfPluginOptions {
  /// Maximum pages to extract.
  final int? maxPages;

  /// Extract images.
  final bool extractImages;

  /// Extract tables.
  final bool extractTables;

  const PdfPluginOptions({
    this.maxPages,
    this.extractImages = true,
    this.extractTables = true,
  });
}

/// PDF extraction result.
class PdfPluginResult {
  /// Extracted pages.
  final List<PdfPageResult> pages;

  /// Document metadata.
  final PdfMetadata metadata;

  /// Processing time.
  final Duration processingTime;

  const PdfPluginResult({
    required this.pages,
    required this.metadata,
    this.processingTime = Duration.zero,
  });
}

/// PDF page extraction result.
class PdfPageResult {
  /// Page index (0-based).
  final int index;

  /// Extracted text.
  final String text;

  /// Page width in points.
  final double width;

  /// Page height in points.
  final double height;

  /// Extracted images (as references).
  final List<PdfImageRef>? images;

  /// Whether page has text layer.
  final bool hasTextLayer;

  const PdfPageResult({
    required this.index,
    required this.text,
    required this.width,
    required this.height,
    this.images,
    this.hasTextLayer = true,
  });
}

/// PDF image reference.
class PdfImageRef {
  final int index;
  final int x;
  final int y;
  final int width;
  final int height;

  const PdfImageRef({
    required this.index,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

/// PDF metadata.
class PdfMetadata {
  final String? title;
  final String? author;
  final String? subject;
  final String? creator;
  final DateTime? creationDate;
  final DateTime? modificationDate;
  final int pageCount;

  const PdfMetadata({
    this.title,
    this.author,
    this.subject,
    this.creator,
    this.creationDate,
    this.modificationDate,
    required this.pageCount,
  });
}

/// Render options for PDF pages.
class RenderOptions {
  /// DPI for rendering.
  final int dpi;

  /// Output format (png, jpeg).
  final String format;

  const RenderOptions({
    this.dpi = 150,
    this.format = 'png',
  });
}
