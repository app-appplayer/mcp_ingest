/// Source position for fragment provenance.
///
/// Tracks the character-level position of an extracted value
/// within the source document.
///
/// Defined locally in mcp_ingest since mcp_fact_graph does not
/// export SourcePosition.
library;

/// Character-level position within source document.
class SourcePosition {
  /// Start character offset.
  final int start;

  /// End character offset.
  final int end;

  /// Optional line number.
  final int? line;

  const SourcePosition({
    required this.start,
    required this.end,
    this.line,
  });

  /// Convert to JSON map.
  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        if (line != null) 'line': line,
      };

  /// Create from JSON map.
  factory SourcePosition.fromJson(Map<String, dynamic> json) {
    return SourcePosition(
      start: json['start'] as int,
      end: json['end'] as int,
      line: json['line'] as int?,
    );
  }
}
