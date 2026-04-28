/// Rule-based fragment extraction from document parts.
library;

import 'package:mcp_fact_graph/mcp_fact_graph.dart';

import '../core/fragment_rule.dart';
import '../document/document_part.dart';
import '../document/normalized_document.dart';

/// Extracts Fragment entities from document parts.
class FragmentExtractor {
  /// Extract fragments using rules.
  List<Fragment> extract(
    NormalizedDocument document,
    List<FragmentRule> rules,
  ) {
    final fragments = <Fragment>[];
    final evidenceId = document.id;

    // Extract from KeyValueBlock parts
    for (final part in document.partsOfType<KeyValueBlock>()) {
      for (final rule in rules) {
        if (_ruleMatches(rule, part.key)) {
          fragments.add(_keyValueToFragment(part, evidenceId, rule));
          break;
        }
      }
    }

    return fragments;
  }

  /// Convert KeyValueBlock to Fragment using the actual mcp_fact_graph Fragment API.
  Fragment _keyValueToFragment(
    KeyValueBlock part,
    String evidenceId,
    FragmentRule rule,
  ) {
    return Fragment(
      fragmentId: '${evidenceId}_${part.id}',
      evidenceId: evidenceId,
      workspaceId: 'default',
      fields: {
        'field': rule.field,
        'value': part.value,
        'key': part.key,
        if (part.normalizedValue != null) 'normalizedValue': part.normalizedValue,
        if (part.location != null) 'position': {
          'start': part.location!.charOffset ?? 0,
          'end': (part.location!.charOffset ?? 0) + (part.location!.charLength ?? 0),
          if (part.location!.lineNumber != null) 'line': part.location!.lineNumber,
        },
      },
      confidence: part.confidence,
      extractor: ExtractorType.rule,
      createdAt: DateTime.now(),
    );
  }

  /// Check if a rule matches a key.
  bool _ruleMatches(FragmentRule rule, String key) {
    final pattern = rule.pattern;

    return switch (rule.patternType) {
      FragmentPatternType.keyword =>
        key.toLowerCase().contains(pattern.toLowerCase()),
      FragmentPatternType.keyValue =>
        key.toLowerCase() == pattern.toLowerCase(),
      _ => RegExp(pattern, caseSensitive: false).hasMatch(key),
    };
  }
}
