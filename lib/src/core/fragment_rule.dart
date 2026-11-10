/// Fragment extraction rules.
library;

import 'fragment_value_type.dart';

/// Rule for extracting fragments from document content.
class FragmentRule {
  /// Rule identifier.
  final String id;

  /// Target field name (e.g., 'amount', 'date', 'merchant').
  final String field;

  /// Expected value type.
  final FragmentValueType valueType;

  /// Extraction pattern type.
  final FragmentPatternType patternType;

  /// Pattern for extraction (regex, keyword, etc.).
  final String pattern;

  /// Optional transformation function name.
  final String? transform;

  /// Minimum confidence threshold.
  final double minConfidence;

  /// Rule priority (higher = preferred).
  final int priority;

  const FragmentRule({
    required this.id,
    required this.field,
    this.valueType = FragmentValueType.string,
    this.patternType = FragmentPatternType.regex,
    required this.pattern,
    this.transform,
    this.minConfidence = 0.5,
    this.priority = 0,
  });

  factory FragmentRule.fromJson(Map<String, dynamic> json) {
    return FragmentRule(
      id: json['id'] as String,
      field: json['field'] as String,
      valueType: FragmentValueType.fromString(
          json['valueType'] as String? ?? 'string'),
      patternType: FragmentPatternType.fromString(
          json['patternType'] as String? ?? 'regex'),
      pattern: json['pattern'] as String,
      transform: json['transform'] as String?,
      minConfidence: (json['minConfidence'] as num?)?.toDouble() ?? 0.5,
      priority: json['priority'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'field': field,
        'valueType': valueType.name,
        'patternType': patternType.name,
        'pattern': pattern,
        if (transform != null) 'transform': transform,
        'minConfidence': minConfidence,
        'priority': priority,
      };
}

/// Fragment pattern type.
enum FragmentPatternType {
  /// Regular expression pattern.
  regex,

  /// Keyword matching.
  keyword,

  /// Key-value pattern (key: value).
  keyValue,

  /// JSON path extraction.
  jsonPath,

  /// XPath extraction.
  xpath,

  /// Custom extractor.
  custom;

  static FragmentPatternType fromString(String value) {
    return FragmentPatternType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => FragmentPatternType.regex,
    );
  }
}

/// Common fragment rules for receipts/invoices.
class CommonFragmentRules {
  /// Amount extraction rules.
  static final amount = FragmentRule(
    id: 'common_amount',
    field: 'amount',
    valueType: FragmentValueType.currency,
    patternType: FragmentPatternType.regex,
    pattern: r'(?:total|amount|sum)[:\s]*[\$€£¥₩]?\s*([\d,]+\.?\d*)',
    priority: 10,
  );

  /// Date extraction rules.
  static final date = FragmentRule(
    id: 'common_date',
    field: 'date',
    valueType: FragmentValueType.date,
    patternType: FragmentPatternType.regex,
    pattern: r'(\d{4}[-/]\d{2}[-/]\d{2}|\d{2}[-/]\d{2}[-/]\d{4})',
    priority: 10,
  );

  /// Merchant/vendor name.
  static final merchant = FragmentRule(
    id: 'common_merchant',
    field: 'merchant',
    valueType: FragmentValueType.string,
    patternType: FragmentPatternType.regex,
    pattern: r'^([A-Z][A-Za-z\s&]+)(?:\n|$)',
    priority: 5,
  );

  /// All common rules.
  static final all = [amount, date, merchant];
}
