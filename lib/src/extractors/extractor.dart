/// Base extractor interface.
library;

import '../core/content_type.dart';
import '../document/normalized_document.dart';
import 'text_extractor.dart';
import 'html_extractor.dart';
import 'json_extractor.dart';
import 'pdf_extractor.dart';
import 'office_extractor.dart';
import 'image_extractor.dart';
import 'audio_extractor.dart';

/// Options for extraction.
class ExtractOptions {
  /// Maximum pages to extract.
  final int? maxPages;

  /// Extract images as separate assets.
  final bool extractImages;

  /// Perform OCR on embedded images.
  final bool performOcr;

  /// Extract table structure.
  final bool extractTables;

  /// Target language for OCR.
  final String? ocrLanguage;

  /// Custom extractor-specific settings.
  final Map<String, dynamic>? custom;

  const ExtractOptions({
    this.maxPages,
    this.extractImages = true,
    this.performOcr = false,
    this.extractTables = true,
    this.ocrLanguage,
    this.custom,
  });

  static const ExtractOptions defaults = ExtractOptions();

  static const ExtractOptions minimal = ExtractOptions(
    extractImages: false,
    extractTables: false,
  );

  ExtractOptions copyWith({
    int? maxPages,
    bool? extractImages,
    bool? performOcr,
    bool? extractTables,
    String? ocrLanguage,
    Map<String, dynamic>? custom,
  }) {
    return ExtractOptions(
      maxPages: maxPages ?? this.maxPages,
      extractImages: extractImages ?? this.extractImages,
      performOcr: performOcr ?? this.performOcr,
      extractTables: extractTables ?? this.extractTables,
      ocrLanguage: ocrLanguage ?? this.ocrLanguage,
      custom: custom ?? this.custom,
    );
  }
}

/// Base interface for all extractors.
abstract class Extractor {
  /// Unique identifier for this extractor.
  String get id;

  /// MIME types this extractor can handle.
  Set<String> get supportedTypes;

  /// Priority when multiple extractors match (higher = preferred).
  int get priority => 0;

  /// Check if this extractor can handle the content type.
  bool canHandle(ContentType contentType) {
    return supportedTypes.contains(contentType.mimeType);
  }

  /// Extract content from input stream.
  Future<NormalizedDocument> extract(
    Stream<List<int>> input,
    ExtractOptions options,
  );

  /// Estimate extraction time for given file size.
  Duration estimateDuration(int fileSize) {
    // Default: ~1MB/second
    return Duration(milliseconds: fileSize ~/ 1000);
  }
}

/// Registry for extractor lookup.
class ExtractorRegistry {
  final List<Extractor> _extractors = [];

  /// Default constructor.
  ExtractorRegistry();

  /// Register an extractor.
  void register(Extractor extractor) {
    _extractors.add(extractor);
    _extractors.sort((a, b) => b.priority.compareTo(a.priority));
  }

  /// Find extractor for content type.
  Extractor? find(ContentType contentType) {
    for (final extractor in _extractors) {
      if (extractor.canHandle(contentType)) {
        return extractor;
      }
    }
    return null;
  }

  /// Get all registered extractors.
  List<Extractor> get all => List.unmodifiable(_extractors);

  /// Create with default extractors (no port params).
  factory ExtractorRegistry.defaults() {
    final registry = ExtractorRegistry();
    registry.register(TextExtractor());
    registry.register(HtmlExtractor());
    registry.register(JsonExtractor());
    registry.register(PdfExtractor());
    registry.register(OfficeExtractor());
    registry.register(ImageExtractor());
    registry.register(AudioExtractor());
    return registry;
  }
}
