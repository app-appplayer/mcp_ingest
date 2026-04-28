/// Fragment value type for document model.
///
/// Describes the type of value extracted from a document.
/// Used by KeyValueBlock, FragmentRule, and extractors.
///
/// Defined locally in mcp_ingest since mcp_fact_graph uses
/// fields: Map<String, dynamic> for Fragment values.
library;

/// Value type classification for extracted fragments.
enum FragmentValueType {
  /// Plain text string.
  string,

  /// Numeric value.
  number,

  /// Boolean value.
  boolean,

  /// Date value (without time).
  date,

  /// DateTime value (with time).
  datetime,

  /// Currency/monetary amount.
  currency,

  /// Percentage value.
  percentage,

  /// Array/list value.
  array,

  /// Object/map value.
  object,

  /// Unknown or undetected type.
  unknown;

  /// Parse from string name.
  static FragmentValueType fromString(String value) {
    return FragmentValueType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => FragmentValueType.string,
    );
  }
}
