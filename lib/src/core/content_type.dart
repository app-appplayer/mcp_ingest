/// Content type detection and MIME handling.
library;

/// Detected content type with MIME and metadata.
class ContentType {
  /// MIME type (e.g., "application/pdf").
  final String mimeType;

  /// File extension (e.g., ".pdf").
  final String? extension;

  /// Original filename.
  final String? filename;

  /// Encoding (for text types).
  final String? encoding;

  const ContentType(
    this.mimeType, {
    this.extension,
    this.filename,
    this.encoding,
  });

  /// Check if this is a text-based format.
  bool get isText => mimeType.startsWith('text/') || _textBasedMimes.contains(mimeType);

  /// Check if this is an image format.
  bool get isImage => mimeType.startsWith('image/');

  /// Check if this is an audio format.
  bool get isAudio => mimeType.startsWith('audio/');

  /// Check if this is a video format.
  bool get isVideo => mimeType.startsWith('video/');

  /// Check if this is a document format (PDF, Office, etc.).
  bool get isDocument => _documentMimes.contains(mimeType);

  /// Primary type (e.g., "application" from "application/pdf").
  String get primaryType => mimeType.split('/').first;

  /// Subtype (e.g., "pdf" from "application/pdf").
  String get subType {
    final parts = mimeType.split('/');
    return parts.length > 1 ? parts[1] : '';
  }

  @override
  String toString() => mimeType;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContentType && mimeType == other.mimeType;

  @override
  int get hashCode => mimeType.hashCode;

  static const _textBasedMimes = {
    'application/json',
    'application/xml',
    'application/javascript',
    'application/x-yaml',
  };

  static const _documentMimes = {
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'application/msword',
    'application/vnd.ms-excel',
    'application/vnd.ms-powerpoint',
  };
}

/// Detects content type from bytes and filename.
class ContentTypeDetector {
  /// Detect content type from bytes and optional filename.
  static ContentType? detect(List<int> bytes, String? filename) {
    // Check magic bytes first
    final mimeFromMagic = _detectFromMagicBytes(bytes);
    if (mimeFromMagic != null) {
      return ContentType(
        mimeFromMagic,
        extension: _mimeToExtension[mimeFromMagic],
        filename: filename,
      );
    }

    // Fall back to extension
    if (filename != null) {
      final ext = _getExtension(filename);
      final mimeFromExt = _extensionToMime[ext];
      if (mimeFromExt != null) {
        return ContentType(
          mimeFromExt,
          extension: ext,
          filename: filename,
        );
      }
    }

    return null;
  }

  /// Detect from filename only.
  static ContentType detectFromFilename(String filename) {
    final ext = _getExtension(filename);
    final mime = _extensionToMime[ext] ?? 'application/octet-stream';
    return ContentType(mime, extension: ext, filename: filename);
  }

  static String _getExtension(String filename) {
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == filename.length - 1) return '';
    return filename.substring(dotIndex).toLowerCase();
  }

  static String? _detectFromMagicBytes(List<int> bytes) {
    if (bytes.length < 4) return null;

    // PDF: %PDF
    if (_matches(bytes, [0x25, 0x50, 0x44, 0x46])) {
      return 'application/pdf';
    }

    // ZIP (Office docs, etc): PK
    if (_matches(bytes, [0x50, 0x4B, 0x03, 0x04])) {
      // Could be Office document or plain ZIP
      // Check for Office signatures within
      return _detectOfficeType(bytes) ?? 'application/zip';
    }

    // PNG: 89 50 4E 47
    if (_matches(bytes, [0x89, 0x50, 0x4E, 0x47])) {
      return 'image/png';
    }

    // JPEG: FF D8 FF
    if (_matches(bytes, [0xFF, 0xD8, 0xFF])) {
      return 'image/jpeg';
    }

    // GIF: GIF87a or GIF89a
    if (_matches(bytes, [0x47, 0x49, 0x46, 0x38])) {
      return 'image/gif';
    }

    // WebP: RIFF....WEBP
    if (_matches(bytes, [0x52, 0x49, 0x46, 0x46]) &&
        bytes.length >= 12 &&
        _matches(bytes.sublist(8, 12), [0x57, 0x45, 0x42, 0x50])) {
      return 'image/webp';
    }

    // MP3: ID3 or FF FB
    if (_matches(bytes, [0x49, 0x44, 0x33]) ||
        _matches(bytes, [0xFF, 0xFB])) {
      return 'audio/mpeg';
    }

    // WAV: RIFF....WAVE
    if (_matches(bytes, [0x52, 0x49, 0x46, 0x46]) &&
        bytes.length >= 12 &&
        _matches(bytes.sublist(8, 12), [0x57, 0x41, 0x56, 0x45])) {
      return 'audio/wav';
    }

    // OGG: OggS
    if (_matches(bytes, [0x4F, 0x67, 0x67, 0x53])) {
      return 'audio/ogg';
    }

    // FLAC: fLaC
    if (_matches(bytes, [0x66, 0x4C, 0x61, 0x43])) {
      return 'audio/flac';
    }

    return null;
  }

  static String? _detectOfficeType(List<int> bytes) {
    // For ZIP-based Office formats, we'd need to inspect internal structure
    // For simplicity, return null and let extension detection handle it
    return null;
  }

  static bool _matches(List<int> bytes, List<int> pattern) {
    if (bytes.length < pattern.length) return false;
    for (var i = 0; i < pattern.length; i++) {
      if (bytes[i] != pattern[i]) return false;
    }
    return true;
  }

  static const _extensionToMime = {
    '.txt': 'text/plain',
    '.md': 'text/markdown',
    '.markdown': 'text/markdown',
    '.html': 'text/html',
    '.htm': 'text/html',
    '.xml': 'application/xml',
    '.json': 'application/json',
    '.yaml': 'application/x-yaml',
    '.yml': 'application/x-yaml',
    '.pdf': 'application/pdf',
    '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    '.pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    '.doc': 'application/msword',
    '.xls': 'application/vnd.ms-excel',
    '.ppt': 'application/vnd.ms-powerpoint',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.tiff': 'image/tiff',
    '.tif': 'image/tiff',
    '.bmp': 'image/bmp',
    '.mp3': 'audio/mpeg',
    '.wav': 'audio/wav',
    '.ogg': 'audio/ogg',
    '.flac': 'audio/flac',
    '.m4a': 'audio/m4a',
    '.aac': 'audio/aac',
  };

  static const _mimeToExtension = {
    'text/plain': '.txt',
    'text/markdown': '.md',
    'text/html': '.html',
    'application/xml': '.xml',
    'application/json': '.json',
    'application/x-yaml': '.yaml',
    'application/pdf': '.pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document': '.docx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': '.xlsx',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation': '.pptx',
    'image/png': '.png',
    'image/jpeg': '.jpg',
    'image/gif': '.gif',
    'image/webp': '.webp',
    'audio/mpeg': '.mp3',
    'audio/wav': '.wav',
    'audio/ogg': '.ogg',
    'audio/flac': '.flac',
  };
}
