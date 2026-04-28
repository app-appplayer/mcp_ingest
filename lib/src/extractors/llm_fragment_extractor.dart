/// LLM-based fragment extraction.
library;

import 'dart:convert';

import 'package:mcp_bundle/ports.dart' show LlmPort, LlmRequest;
import 'package:mcp_fact_graph/mcp_fact_graph.dart'
    show Fragment, ExtractorType;
import 'package:uuid/uuid.dart';

import '../core/fragment_value_type.dart';

import '../core/fragment_rule.dart';
import '../document/normalized_document.dart';

/// LLM-based fragment extractor.
///
/// Uses LLM to extract structured data from document content.
/// CAUTION: This incurs LLM costs.
class LlmFragmentExtractor {
  /// LLM port for extraction.
  final LlmPort llmPort;

  LlmFragmentExtractor(this.llmPort);

  /// Extract fragments from document using LLM.
  ///
  /// [document] - The normalized document to extract from.
  /// [evidenceId] - The evidence ID for the fragments.
  /// [fields] - List of fields to extract (e.g., ['amount', 'date', 'merchant']).
  /// [rules] - Optional fragment rules for guidance.
  Future<List<Fragment>> extract(
    NormalizedDocument document,
    String evidenceId, {
    List<String>? fields,
    List<FragmentRule>? rules,
  }) async {
    final fullText = document.fullText;
    if (fullText.trim().isEmpty) return [];

    // Build field descriptions from rules if available
    final fieldDescriptions = _buildFieldDescriptions(fields, rules);

    // Create extraction prompt
    final response = await llmPort.complete(LlmRequest(
      systemPrompt: '''You are a document data extraction assistant.
Extract structured data from the document and return as JSON.

For each field, provide:
- value: The extracted value
- confidence: Confidence score (0.0-1.0)
- position: Optional character offset where found

Return JSON format:
{
  "extractions": [
    {
      "field": "field_name",
      "value": "extracted_value",
      "normalizedValue": "normalized_value",
      "valueType": "string|number|date|currency|percentage",
      "confidence": 0.95,
      "position": {"start": 0, "end": 10}
    }
  ]
}

If a field cannot be found, omit it from the results.
Only return valid JSON, no explanation.''',
      prompt: '''Extract the following fields from this document:

$fieldDescriptions

Document:
$fullText

Return JSON with the extractions.''',
      temperature: 0.0,
      responseFormat: 'json',
    ));

    // Parse LLM response
    return _parseExtractions(response.content, evidenceId);
  }

  /// Extract specific field types from document.
  Future<List<Fragment>> extractFields(
    NormalizedDocument document,
    String evidenceId,
    List<FieldDefinition> fieldDefs,
  ) async {
    final fullText = document.fullText;
    if (fullText.trim().isEmpty) return [];

    final fieldList = fieldDefs.map((f) {
      return '- ${f.name}: ${f.description} (type: ${f.valueType.name})';
    }).join('\n');

    final response = await llmPort.complete(LlmRequest(
      systemPrompt: '''You are a document data extraction assistant.
Extract structured data from the document and return as JSON.

For each field, provide:
- value: The extracted raw value
- normalizedValue: The normalized/standardized value
- confidence: Confidence score (0.0-1.0)
- position: Character offset where the value was found

Return JSON format:
{
  "extractions": [
    {
      "field": "field_name",
      "value": "extracted_value",
      "normalizedValue": "normalized_value",
      "valueType": "string|number|date|currency|percentage",
      "confidence": 0.95,
      "position": {"start": 0, "end": 10}
    }
  ]
}

Only extract fields that are clearly present in the document.
Be conservative with confidence scores.
Only return valid JSON.''',
      prompt: '''Extract these fields from the document:

$fieldList

Document:
$fullText

Return JSON with the extractions.''',
      temperature: 0.0,
      responseFormat: 'json',
    ));

    return _parseExtractions(response.content, evidenceId);
  }

  /// Extract fragments matching a specific schema.
  Future<List<Fragment>> extractWithSchema(
    NormalizedDocument document,
    String evidenceId,
    Map<String, dynamic> schema,
  ) async {
    final fullText = document.fullText;
    if (fullText.trim().isEmpty) return [];

    final schemaJson = const JsonEncoder.withIndent('  ').convert(schema);

    final response = await llmPort.complete(LlmRequest(
      systemPrompt: '''You are a document data extraction assistant.
Extract data matching the provided JSON schema.

Return extracted data as JSON with confidence scores:
{
  "extractions": [
    {
      "field": "json_path",
      "value": "extracted_value",
      "normalizedValue": "normalized_value",
      "valueType": "string|number|date|currency|percentage",
      "confidence": 0.95,
      "position": {"start": 0, "end": 10}
    }
  ]
}

Only return valid JSON.''',
      prompt: '''Extract data matching this schema:

$schemaJson

Document:
$fullText

Return JSON with the extractions.''',
      temperature: 0.0,
      responseFormat: 'json',
    ));

    return _parseExtractions(response.content, evidenceId);
  }

  String _buildFieldDescriptions(List<String>? fields, List<FragmentRule>? rules) {
    final buffer = StringBuffer();

    if (fields != null) {
      for (final field in fields) {
        // Find matching rule for description
        final rule = rules?.where((r) => r.field == field).firstOrNull;
        if (rule != null) {
          buffer.writeln('- ${rule.field}: ${rule.valueType.name}');
          if (rule.pattern.isNotEmpty) {
            buffer.writeln('  Pattern hint: ${rule.pattern}');
          }
        } else {
          buffer.writeln('- $field');
        }
      }
    } else if (rules != null) {
      for (final rule in rules) {
        buffer.writeln('- ${rule.field}: ${rule.valueType.name}');
        if (rule.pattern.isNotEmpty) {
          buffer.writeln('  Pattern hint: ${rule.pattern}');
        }
      }
    } else {
      // Default common fields
      buffer.writeln('- amount: currency amount (total, sum, price)');
      buffer.writeln('- date: date of transaction/document');
      buffer.writeln('- merchant: business/vendor name');
    }

    return buffer.toString();
  }

  List<Fragment> _parseExtractions(String response, String evidenceId) {
    try {
      final jsonStr = _extractJson(response);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final extractions = json['extractions'] as List<dynamic>?;

      if (extractions == null) return [];

      final fragments = <Fragment>[];
      final uuid = const Uuid();

      for (final extraction in extractions) {
        if (extraction is! Map<String, dynamic>) continue;

        final field = extraction['field'] as String?;
        final value = extraction['value']?.toString();
        if (field == null || value == null) continue;

        final normalizedValue = extraction['normalizedValue']?.toString();
        final valueTypeStr = extraction['valueType'] as String? ?? 'string';
        final confidence = (extraction['confidence'] as num?)?.toDouble() ?? 0.5;
        final position = extraction['position'] as Map<String, dynamic>?;

        fragments.add(Fragment(
          fragmentId: uuid.v4(),
          evidenceId: evidenceId,
          workspaceId: 'default',
          fields: {
            'field': field,
            'value': value,
            if (normalizedValue != null) 'normalizedValue': normalizedValue,
            'valueType': _parseValueType(valueTypeStr).name,
            if (position != null)
              'position': {
                'start': (position['start'] as num?)?.toInt() ?? 0,
                'end': (position['end'] as num?)?.toInt() ?? value.length,
              },
          },
          confidence: confidence,
          extractor: ExtractorType.llm,
          createdAt: DateTime.now(),
        ));
      }

      return fragments;
    } catch (e) {
      // Return empty list on parse failure
      return [];
    }
  }

  String _extractJson(String response) {
    // Find JSON object in response
    final start = response.indexOf('{');
    final end = response.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return response.substring(start, end + 1);
    }
    return response;
  }

  FragmentValueType _parseValueType(String typeStr) {
    return switch (typeStr.toLowerCase()) {
      'number' || 'int' || 'integer' || 'float' || 'double' => FragmentValueType.number,
      'date' || 'datetime' || 'time' => FragmentValueType.date,
      'currency' || 'money' || 'amount' => FragmentValueType.currency,
      'percentage' || 'percent' || '%' => FragmentValueType.percentage,
      'boolean' || 'bool' => FragmentValueType.boolean,
      _ => FragmentValueType.string,
    };
  }
}

/// Field definition for LLM extraction.
class FieldDefinition {
  /// Field name.
  final String name;

  /// Description of what to extract.
  final String description;

  /// Expected value type.
  final FragmentValueType valueType;

  /// Whether this field is required.
  final bool required;

  const FieldDefinition({
    required this.name,
    required this.description,
    this.valueType = FragmentValueType.string,
    this.required = false,
  });

  /// Create field definition from rule.
  factory FieldDefinition.fromRule(FragmentRule rule) {
    return FieldDefinition(
      name: rule.field,
      description: 'Pattern: ${rule.pattern}',
      valueType: rule.valueType,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'valueType': valueType.name,
        'required': required,
      };
}

/// Common field definitions.
class CommonFieldDefinitions {
  static const amount = FieldDefinition(
    name: 'amount',
    description: 'Total amount, price, or sum',
    valueType: FragmentValueType.currency,
  );

  static const date = FieldDefinition(
    name: 'date',
    description: 'Date of transaction, invoice, or document',
    valueType: FragmentValueType.date,
  );

  static const merchant = FieldDefinition(
    name: 'merchant',
    description: 'Business name, vendor, or merchant',
    valueType: FragmentValueType.string,
  );

  static const invoiceNumber = FieldDefinition(
    name: 'invoiceNumber',
    description: 'Invoice number, receipt number, or reference ID',
    valueType: FragmentValueType.string,
  );

  static const taxAmount = FieldDefinition(
    name: 'taxAmount',
    description: 'Tax amount or VAT',
    valueType: FragmentValueType.currency,
  );

  static const subtotal = FieldDefinition(
    name: 'subtotal',
    description: 'Subtotal before tax',
    valueType: FragmentValueType.currency,
  );

  /// Common invoice/receipt fields.
  static const invoiceFields = [
    amount,
    date,
    merchant,
    invoiceNumber,
    taxAmount,
    subtotal,
  ];
}
