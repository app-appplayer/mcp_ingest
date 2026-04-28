import 'dart:convert';

import 'package:test/test.dart';
import 'package:mcp_bundle/ports.dart';
import 'package:mcp_ingest/mcp_ingest.dart';
import 'package:mcp_fact_graph/mcp_fact_graph.dart' show ExtractorType;

/// Mock LlmPort for testing LlmFragmentExtractor.
class MockLlmPort extends LlmPort {
  String responseContent = '';
  int callCount = 0;

  @override
  LlmCapabilities get capabilities => const LlmCapabilities.minimal();

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    callCount++;
    return LlmResponse(content: responseContent);
  }

  @override
  Future<bool> isAvailable() async => true;
}

void main() {
  // Helper to create a minimal NormalizedDocument with text content.
  NormalizedDocument makeDocument(String id, String text) {
    return NormalizedDocument(
      id: id,
      metadata: const DocumentMetadata(
        mimeType: 'text/plain',
        sha256: 'abc123',
      ),
      parts: [
        TextBlock(id: 'txt1', text: text),
      ],
      structure: DocumentStructure.empty,
      provenance: ExtractionProvenance(
        extractorId: 'test',
        extractorVersion: '1.0.0',
        extractedAt: DateTime(2025, 1, 1),
        extractionDuration: Duration.zero,
      ),
    );
  }

  // Helper to create an empty NormalizedDocument.
  NormalizedDocument makeEmptyDocument(String id) {
    return NormalizedDocument(
      id: id,
      metadata: const DocumentMetadata(
        mimeType: 'text/plain',
        sha256: 'abc123',
      ),
      parts: [],
      structure: DocumentStructure.empty,
      provenance: ExtractionProvenance(
        extractorId: 'test',
        extractorVersion: '1.0.0',
        extractedAt: DateTime(2025, 1, 1),
        extractionDuration: Duration.zero,
      ),
    );
  }

  group('LlmFragmentExtractor', () {
    late MockLlmPort mockLlm;
    late LlmFragmentExtractor extractor;

    setUp(() {
      mockLlm = MockLlmPort();
      extractor = LlmFragmentExtractor(mockLlm);
    });

    test('extract with fields returns fragments from LLM response', () async {
      mockLlm.responseContent = jsonEncode({
        'extractions': [
          {
            'field': 'amount',
            'value': '150.00',
            'normalizedValue': '150.00',
            'valueType': 'currency',
            'confidence': 0.95,
            'position': {'start': 10, 'end': 16},
          },
          {
            'field': 'date',
            'value': '2025-01-15',
            'valueType': 'date',
            'confidence': 0.90,
          },
        ],
      });

      final doc = makeDocument('ev1', 'Invoice total: \$150.00 on 2025-01-15');
      final result = await extractor.extract(
        doc,
        'ev1',
        fields: ['amount', 'date'],
      );

      expect(result.length, equals(2));
      expect(result[0].fields['field'], equals('amount'));
      expect(result[0].fields['value'], equals('150.00'));
      expect(result[0].fields['normalizedValue'], equals('150.00'));
      expect(result[0].confidence, equals(0.95));
      expect(result[0].extractor, equals(ExtractorType.llm));
      expect(result[0].evidenceId, equals('ev1'));
      expect(result[0].workspaceId, equals('default'));

      expect(result[1].fields['field'], equals('date'));
      expect(result[1].fields['value'], equals('2025-01-15'));
      expect(mockLlm.callCount, equals(1));
    });

    test('extract with rules builds field descriptions from rules', () async {
      mockLlm.responseContent = jsonEncode({
        'extractions': [
          {
            'field': 'merchant',
            'value': 'Acme Corp',
            'valueType': 'string',
            'confidence': 0.85,
          },
        ],
      });

      final doc = makeDocument('ev2', 'Acme Corp Invoice #123');
      final rules = [
        const FragmentRule(
          id: 'r1',
          field: 'merchant',
          pattern: r'^[A-Z]',
          patternType: FragmentPatternType.regex,
        ),
      ];

      final result = await extractor.extract(
        doc,
        'ev2',
        rules: rules,
      );

      expect(result.length, equals(1));
      expect(result.first.fields['field'], equals('merchant'));
    });

    test('extract with default fields when no fields or rules', () async {
      mockLlm.responseContent = jsonEncode({
        'extractions': [
          {
            'field': 'amount',
            'value': '99.99',
            'valueType': 'currency',
            'confidence': 0.80,
          },
        ],
      });

      final doc = makeDocument('ev3', 'Total: \$99.99');
      final result = await extractor.extract(doc, 'ev3');

      // Should use default fields (amount, date, merchant)
      expect(result.length, equals(1));
      expect(mockLlm.callCount, equals(1));
    });

    test('extractFields with FieldDefinitions', () async {
      mockLlm.responseContent = jsonEncode({
        'extractions': [
          {
            'field': 'invoiceNumber',
            'value': 'INV-2025-001',
            'valueType': 'string',
            'confidence': 0.99,
          },
        ],
      });

      final doc = makeDocument('ev4', 'Invoice INV-2025-001');
      final fieldDefs = [
        const FieldDefinition(
          name: 'invoiceNumber',
          description: 'Invoice or receipt number',
          valueType: FragmentValueType.string,
        ),
      ];

      final result = await extractor.extractFields(doc, 'ev4', fieldDefs);

      expect(result.length, equals(1));
      expect(result.first.fields['field'], equals('invoiceNumber'));
      expect(result.first.fields['value'], equals('INV-2025-001'));
      expect(mockLlm.callCount, equals(1));
    });

    test('extractWithSchema passes schema to LLM', () async {
      mockLlm.responseContent = jsonEncode({
        'extractions': [
          {
            'field': 'total',
            'value': '500.00',
            'valueType': 'currency',
            'confidence': 0.92,
          },
        ],
      });

      final doc = makeDocument('ev5', 'Order total: \$500.00');
      final schema = {
        'type': 'object',
        'properties': {
          'total': {'type': 'number', 'description': 'Order total amount'},
        },
      };

      final result = await extractor.extractWithSchema(doc, 'ev5', schema);

      expect(result.length, equals(1));
      expect(result.first.fields['field'], equals('total'));
      expect(mockLlm.callCount, equals(1));
    });

    test('empty document returns empty list', () async {
      final doc = makeEmptyDocument('ev6');

      final result = await extractor.extract(doc, 'ev6');
      expect(result, isEmpty);
      expect(mockLlm.callCount, equals(0));
    });

    test('LLM returns invalid JSON returns empty list', () async {
      mockLlm.responseContent = 'This is not valid JSON at all';

      final doc = makeDocument('ev7', 'Some content');
      final result = await extractor.extract(doc, 'ev7');

      expect(result, isEmpty);
    });

    test('LLM returns missing extractions key returns empty list', () async {
      mockLlm.responseContent = jsonEncode({
        'results': [
          {'field': 'amount', 'value': '100'},
        ],
      });

      final doc = makeDocument('ev8', 'Some content');
      final result = await extractor.extract(doc, 'ev8');

      expect(result, isEmpty);
    });

    test('missing field in extraction entry - entry skipped', () async {
      mockLlm.responseContent = jsonEncode({
        'extractions': [
          {
            // Missing 'field' key
            'value': '100.00',
            'confidence': 0.9,
          },
          {
            'field': 'date',
            'value': '2025-01-01',
            'confidence': 0.85,
          },
        ],
      });

      final doc = makeDocument('ev9', 'Amount: 100 Date: 2025-01-01');
      final result = await extractor.extract(doc, 'ev9');

      expect(result.length, equals(1));
      expect(result.first.fields['field'], equals('date'));
    });

    test('missing value in extraction entry - entry skipped', () async {
      mockLlm.responseContent = jsonEncode({
        'extractions': [
          {
            'field': 'amount',
            // Missing 'value' key
            'confidence': 0.9,
          },
          {
            'field': 'merchant',
            'value': 'Shop Inc',
            'confidence': 0.80,
          },
        ],
      });

      final doc = makeDocument('ev10', 'Shop Inc: some amount');
      final result = await extractor.extract(doc, 'ev10');

      expect(result.length, equals(1));
      expect(result.first.fields['field'], equals('merchant'));
    });

    test('value type parsing', () async {
      // Test all value type mappings by providing extractions with each type.
      mockLlm.responseContent = jsonEncode({
        'extractions': [
          {'field': 'f1', 'value': '42', 'valueType': 'number', 'confidence': 0.9},
          {'field': 'f2', 'value': '42', 'valueType': 'int', 'confidence': 0.9},
          {'field': 'f3', 'value': '42', 'valueType': 'integer', 'confidence': 0.9},
          {'field': 'f4', 'value': '3.14', 'valueType': 'float', 'confidence': 0.9},
          {'field': 'f5', 'value': '3.14', 'valueType': 'double', 'confidence': 0.9},
          {'field': 'f6', 'value': '2025-01-01', 'valueType': 'date', 'confidence': 0.9},
          {'field': 'f7', 'value': '2025-01-01T10:00', 'valueType': 'datetime', 'confidence': 0.9},
          {'field': 'f8', 'value': '10:00', 'valueType': 'time', 'confidence': 0.9},
          {'field': 'f9', 'value': '100.00', 'valueType': 'currency', 'confidence': 0.9},
          {'field': 'f10', 'value': '100.00', 'valueType': 'money', 'confidence': 0.9},
          {'field': 'f11', 'value': '100.00', 'valueType': 'amount', 'confidence': 0.9},
          {'field': 'f12', 'value': '50%', 'valueType': 'percentage', 'confidence': 0.9},
          {'field': 'f13', 'value': '50%', 'valueType': 'percent', 'confidence': 0.9},
          {'field': 'f14', 'value': '50%', 'valueType': '%', 'confidence': 0.9},
          {'field': 'f15', 'value': 'true', 'valueType': 'boolean', 'confidence': 0.9},
          {'field': 'f16', 'value': 'true', 'valueType': 'bool', 'confidence': 0.9},
          {'field': 'f17', 'value': 'hello', 'valueType': 'string', 'confidence': 0.9},
          {'field': 'f18', 'value': 'hello', 'valueType': 'unknown_type', 'confidence': 0.9},
        ],
      });

      final doc = makeDocument('ev11', 'Content for value type testing');
      final result = await extractor.extract(doc, 'ev11');

      expect(result.length, equals(18));

      // number types -> 'number'
      expect(result[0].fields['valueType'], equals('number'));
      expect(result[1].fields['valueType'], equals('number'));
      expect(result[2].fields['valueType'], equals('number'));
      expect(result[3].fields['valueType'], equals('number'));
      expect(result[4].fields['valueType'], equals('number'));

      // date types -> 'date'
      expect(result[5].fields['valueType'], equals('date'));
      expect(result[6].fields['valueType'], equals('date'));
      expect(result[7].fields['valueType'], equals('date'));

      // currency types -> 'currency'
      expect(result[8].fields['valueType'], equals('currency'));
      expect(result[9].fields['valueType'], equals('currency'));
      expect(result[10].fields['valueType'], equals('currency'));

      // percentage types -> 'percentage'
      expect(result[11].fields['valueType'], equals('percentage'));
      expect(result[12].fields['valueType'], equals('percentage'));
      expect(result[13].fields['valueType'], equals('percentage'));

      // boolean types -> 'boolean'
      expect(result[14].fields['valueType'], equals('boolean'));
      expect(result[15].fields['valueType'], equals('boolean'));

      // string / unknown -> 'string'
      expect(result[16].fields['valueType'], equals('string'));
      expect(result[17].fields['valueType'], equals('string'));
    });

    test('FieldDefinition.fromRule creates from FragmentRule', () {
      const rule = FragmentRule(
        id: 'r1',
        field: 'amount',
        pattern: r'\d+\.\d{2}',
        patternType: FragmentPatternType.regex,
        valueType: FragmentValueType.currency,
      );

      final fieldDef = FieldDefinition.fromRule(rule);

      expect(fieldDef.name, equals('amount'));
      expect(fieldDef.description, equals(r'Pattern: \d+\.\d{2}'));
      expect(fieldDef.valueType, equals(FragmentValueType.currency));
      expect(fieldDef.required, isFalse);
    });

    test('FieldDefinition.toJson serialization', () {
      const fieldDef = FieldDefinition(
        name: 'date',
        description: 'Transaction date',
        valueType: FragmentValueType.date,
        required: true,
      );

      final json = fieldDef.toJson();

      expect(json['name'], equals('date'));
      expect(json['description'], equals('Transaction date'));
      expect(json['valueType'], equals('date'));
      expect(json['required'], isTrue);
    });

    test('CommonFieldDefinitions constants', () {
      expect(CommonFieldDefinitions.amount.name, equals('amount'));
      expect(
          CommonFieldDefinitions.amount.valueType, equals(FragmentValueType.currency));

      expect(CommonFieldDefinitions.date.name, equals('date'));
      expect(CommonFieldDefinitions.date.valueType, equals(FragmentValueType.date));

      expect(CommonFieldDefinitions.merchant.name, equals('merchant'));
      expect(
          CommonFieldDefinitions.merchant.valueType, equals(FragmentValueType.string));

      expect(CommonFieldDefinitions.invoiceNumber.name, equals('invoiceNumber'));
      expect(CommonFieldDefinitions.taxAmount.name, equals('taxAmount'));
      expect(CommonFieldDefinitions.subtotal.name, equals('subtotal'));

      // invoiceFields contains all 6 definitions
      expect(CommonFieldDefinitions.invoiceFields.length, equals(6));
      expect(
        CommonFieldDefinitions.invoiceFields.map((f) => f.name).toList(),
        equals(['amount', 'date', 'merchant', 'invoiceNumber', 'taxAmount', 'subtotal']),
      );
    });

    test('extractFields with empty document returns empty list', () async {
      final doc = makeEmptyDocument('ev12');
      final result = await extractor.extractFields(
        doc,
        'ev12',
        [CommonFieldDefinitions.amount],
      );

      expect(result, isEmpty);
      expect(mockLlm.callCount, equals(0));
    });

    test('extractWithSchema with empty document returns empty list', () async {
      final doc = makeEmptyDocument('ev13');
      final result = await extractor.extractWithSchema(
        doc,
        'ev13',
        {'type': 'object'},
      );

      expect(result, isEmpty);
      expect(mockLlm.callCount, equals(0));
    });

    test('LLM response with JSON embedded in text is extracted', () async {
      // LLM might return text around the JSON
      mockLlm.responseContent =
          'Here is the result: {"extractions": [{"field": "amount", "value": "75.50", "confidence": 0.88}]} Done.';

      final doc = makeDocument('ev14', 'Total: 75.50');
      final result = await extractor.extract(doc, 'ev14');

      expect(result.length, equals(1));
      expect(result.first.fields['field'], equals('amount'));
      expect(result.first.fields['value'], equals('75.50'));
    });

    test('extraction with position includes start and end', () async {
      mockLlm.responseContent = jsonEncode({
        'extractions': [
          {
            'field': 'merchant',
            'value': 'Coffee Shop',
            'confidence': 0.92,
            'position': {'start': 0, 'end': 11},
          },
        ],
      });

      final doc = makeDocument('ev15', 'Coffee Shop - Receipt');
      final result = await extractor.extract(doc, 'ev15');

      expect(result.length, equals(1));
      final position = result.first.fields['position'] as Map<String, dynamic>;
      expect(position['start'], equals(0));
      expect(position['end'], equals(11));
    });

    test('default confidence is 0.5 when not provided', () async {
      mockLlm.responseContent = jsonEncode({
        'extractions': [
          {
            'field': 'note',
            'value': 'Something',
            // No confidence provided
          },
        ],
      });

      final doc = makeDocument('ev16', 'Something here');
      final result = await extractor.extract(doc, 'ev16');

      expect(result.length, equals(1));
      expect(result.first.confidence, equals(0.5));
    });

    test('default valueType is string when not provided', () async {
      mockLlm.responseContent = jsonEncode({
        'extractions': [
          {
            'field': 'note',
            'value': 'Some text',
            'confidence': 0.7,
            // No valueType provided
          },
        ],
      });

      final doc = makeDocument('ev17', 'Some text');
      final result = await extractor.extract(doc, 'ev17');

      expect(result.length, equals(1));
      expect(result.first.fields['valueType'], equals('string'));
    });

    test('extract with both fields and matching rules builds descriptions from rules', () async {
      // This test covers _buildFieldDescriptions lines 191-195:
      // when fields AND rules are both provided and a field matches a rule.
      mockLlm.responseContent = jsonEncode({
        'extractions': [
          {
            'field': 'amount',
            'value': '250.00',
            'valueType': 'currency',
            'confidence': 0.95,
          },
          {
            'field': 'date',
            'value': '2025-03-01',
            'valueType': 'date',
            'confidence': 0.90,
          },
        ],
      });

      final doc = makeDocument('ev18', 'Invoice: \$250.00 on 2025-03-01');

      // Provide both fields AND rules where some fields match rules
      final rules = [
        const FragmentRule(
          id: 'r1',
          field: 'amount',
          pattern: r'\$[\d,]+\.?\d*',
          patternType: FragmentPatternType.regex,
          valueType: FragmentValueType.currency,
        ),
        const FragmentRule(
          id: 'r2',
          field: 'date',
          // Empty pattern to test the pattern.isNotEmpty branch (line 194)
          pattern: '',
          patternType: FragmentPatternType.regex,
          valueType: FragmentValueType.date,
        ),
      ];

      final result = await extractor.extract(
        doc,
        'ev18',
        fields: ['amount', 'date', 'unknown_field'],
        rules: rules,
      );

      expect(result.length, equals(2));
      expect(result[0].fields['field'], equals('amount'));
      expect(result[1].fields['field'], equals('date'));
      expect(mockLlm.callCount, equals(1));
    });

    test('extract with fields and rules where rule has non-empty pattern', () async {
      // Specifically exercises line 195: buffer.writeln('  Pattern hint: ...')
      mockLlm.responseContent = jsonEncode({
        'extractions': [
          {
            'field': 'amount',
            'value': '99.99',
            'valueType': 'currency',
            'confidence': 0.88,
          },
        ],
      });

      final doc = makeDocument('ev19', 'Total: \$99.99');

      final rules = [
        const FragmentRule(
          id: 'r1',
          field: 'amount',
          pattern: r'\$[\d.]+',
          patternType: FragmentPatternType.regex,
          valueType: FragmentValueType.currency,
        ),
      ];

      final result = await extractor.extract(
        doc,
        'ev19',
        fields: ['amount'],
        rules: rules,
      );

      expect(result.length, equals(1));
      expect(result.first.fields['field'], equals('amount'));
    });
  });
}
