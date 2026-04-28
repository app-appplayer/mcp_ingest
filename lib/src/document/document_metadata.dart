/// Document metadata.
library;

/// Metadata for normalized document.
class DocumentMetadata {
  /// Document title.
  final String? title;

  /// Document author.
  final String? author;

  /// MIME type of original file.
  final String mimeType;

  /// Original filename.
  final String? originalFilename;

  /// File size in bytes.
  final int? fileSize;

  /// SHA256 hash of original file.
  final String sha256;

  /// Document creation date.
  final DateTime? createdAt;

  /// Document modification date.
  final DateTime? modifiedAt;

  /// Detected language (ISO 639-1 code).
  final String? language;

  /// Page count (for paginated documents).
  final int? pageCount;

  /// Word count.
  final int? wordCount;

  /// Source URI.
  final String? sourceUri;

  /// Custom metadata fields.
  final Map<String, dynamic>? custom;

  const DocumentMetadata({
    this.title,
    this.author,
    required this.mimeType,
    this.originalFilename,
    this.fileSize,
    required this.sha256,
    this.createdAt,
    this.modifiedAt,
    this.language,
    this.pageCount,
    this.wordCount,
    this.sourceUri,
    this.custom,
  });

  factory DocumentMetadata.fromJson(Map<String, dynamic> json) {
    return DocumentMetadata(
      title: json['title'] as String?,
      author: json['author'] as String?,
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      originalFilename: json['originalFilename'] as String?,
      fileSize: json['fileSize'] as int?,
      sha256: json['sha256'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      modifiedAt: json['modifiedAt'] != null
          ? DateTime.parse(json['modifiedAt'] as String)
          : null,
      language: json['language'] as String?,
      pageCount: json['pageCount'] as int?,
      wordCount: json['wordCount'] as int?,
      sourceUri: json['sourceUri'] as String?,
      custom: json['custom'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (author != null) 'author': author,
        'mimeType': mimeType,
        if (originalFilename != null) 'originalFilename': originalFilename,
        if (fileSize != null) 'fileSize': fileSize,
        'sha256': sha256,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (modifiedAt != null) 'modifiedAt': modifiedAt!.toIso8601String(),
        if (language != null) 'language': language,
        if (pageCount != null) 'pageCount': pageCount,
        if (wordCount != null) 'wordCount': wordCount,
        if (sourceUri != null) 'sourceUri': sourceUri,
        if (custom != null) 'custom': custom,
      };

  DocumentMetadata copyWith({
    String? title,
    String? author,
    String? mimeType,
    String? originalFilename,
    int? fileSize,
    String? sha256,
    DateTime? createdAt,
    DateTime? modifiedAt,
    String? language,
    int? pageCount,
    int? wordCount,
    String? sourceUri,
    Map<String, dynamic>? custom,
  }) {
    return DocumentMetadata(
      title: title ?? this.title,
      author: author ?? this.author,
      mimeType: mimeType ?? this.mimeType,
      originalFilename: originalFilename ?? this.originalFilename,
      fileSize: fileSize ?? this.fileSize,
      sha256: sha256 ?? this.sha256,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      language: language ?? this.language,
      pageCount: pageCount ?? this.pageCount,
      wordCount: wordCount ?? this.wordCount,
      sourceUri: sourceUri ?? this.sourceUri,
      custom: custom ?? this.custom,
    );
  }
}

/// Extraction provenance - records how the document was extracted.
class ExtractionProvenance {
  /// Extractor identifier (e.g., 'pdf_text_v1', 'ocr_tesseract_v5').
  final String extractorId;

  /// Extractor version.
  final String extractorVersion;

  /// Extraction timestamp.
  final DateTime extractedAt;

  /// How long extraction took.
  final Duration extractionDuration;

  /// Settings used for extraction.
  final Map<String, dynamic>? settings;

  /// Warnings generated during extraction.
  final List<String>? warnings;

  const ExtractionProvenance({
    required this.extractorId,
    required this.extractorVersion,
    required this.extractedAt,
    required this.extractionDuration,
    this.settings,
    this.warnings,
  });

  factory ExtractionProvenance.fromJson(Map<String, dynamic> json) {
    return ExtractionProvenance(
      extractorId: json['extractorId'] as String,
      extractorVersion: json['extractorVersion'] as String,
      extractedAt: DateTime.parse(json['extractedAt'] as String),
      extractionDuration: Duration(
        milliseconds: json['extractionDurationMs'] as int? ?? 0,
      ),
      settings: json['settings'] as Map<String, dynamic>?,
      warnings: (json['warnings'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'extractorId': extractorId,
        'extractorVersion': extractorVersion,
        'extractedAt': extractedAt.toIso8601String(),
        'extractionDurationMs': extractionDuration.inMilliseconds,
        if (settings != null) 'settings': settings,
        if (warnings != null && warnings!.isNotEmpty) 'warnings': warnings,
      };
}
