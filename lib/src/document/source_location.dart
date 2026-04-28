/// Source location tracking.
library;

/// Bounding box for visual elements.
/// Matches mcp_bundle's BoundingBox (x, y, width, height).
class BoundingBox {
  /// X coordinate.
  final double x;

  /// Y coordinate.
  final double y;

  /// Width.
  final double width;

  /// Height.
  final double height;

  const BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory BoundingBox.fromJson(Map<String, dynamic> json) => BoundingBox(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };
}

/// Source location in original document.
class SourceLocation {
  /// Page number (1-indexed).
  final int? pageNumber;

  /// Line number (1-indexed).
  final int? lineNumber;

  /// Character offset from start.
  final int? charOffset;

  /// Character length.
  final int? charLength;

  /// Bounding box (for visual elements).
  /// Uses mcp_bundle's BoundingBox (x, y, width, height).
  final BoundingBox? bbox;

  /// Coordinate unit for bounding box ('px', 'pt', 'mm').
  /// Separate from BoundingBox to match mcp_bundle contract.
  final String? bboxUnit;

  const SourceLocation({
    this.pageNumber,
    this.lineNumber,
    this.charOffset,
    this.charLength,
    this.bbox,
    this.bboxUnit,
  });

  /// Empty location.
  static const empty = SourceLocation();

  factory SourceLocation.fromJson(Map<String, dynamic> json) {
    return SourceLocation(
      pageNumber: json['pageNumber'] as int?,
      lineNumber: json['lineNumber'] as int?,
      charOffset: json['charOffset'] as int?,
      charLength: json['charLength'] as int?,
      bbox: json['bbox'] != null
          ? BoundingBox.fromJson(json['bbox'] as Map<String, dynamic>)
          : null,
      bboxUnit: json['bboxUnit'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (pageNumber != null) 'pageNumber': pageNumber,
        if (lineNumber != null) 'lineNumber': lineNumber,
        if (charOffset != null) 'charOffset': charOffset,
        if (charLength != null) 'charLength': charLength,
        if (bbox != null) 'bbox': bbox!.toJson(),
        if (bboxUnit != null) 'bboxUnit': bboxUnit,
      };

  @override
  String toString() {
    final parts = <String>[];
    if (pageNumber != null) parts.add('page: $pageNumber');
    if (lineNumber != null) parts.add('line: $lineNumber');
    if (charOffset != null) parts.add('offset: $charOffset');
    return 'SourceLocation(${parts.join(', ')})';
  }
}
