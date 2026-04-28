import 'package:test/test.dart';
import 'package:mcp_ingest/mcp_ingest.dart';
import 'package:mcp_fact_graph/mcp_fact_graph.dart' show ExtractorType;

void main() {
  // Helper to create a minimal NormalizedDocument with given parts.
  NormalizedDocument makeDocument(
    String id,
    List<DocumentPart> parts,
  ) {
    return NormalizedDocument(
      id: id,
      metadata: const DocumentMetadata(
        mimeType: 'text/plain',
        sha256: 'abc123',
      ),
      parts: parts,
      structure: DocumentStructure.empty,
      provenance: ExtractionProvenance(
        extractorId: 'test',
        extractorVersion: '1.0.0',
        extractedAt: DateTime(2025, 1, 1),
        extractionDuration: Duration.zero,
      ),
    );
  }

  group('FragmentExtractor', () {
    late FragmentExtractor extractor;

    setUp(() {
      extractor = FragmentExtractor();
    });

    test('extract with keyword rule matching', () {
      final doc = makeDocument('ev1', [
        const KeyValueBlock(
          id: 'kv1',
          key: 'Total Amount',
          value: '100.00',
        ),
      ]);

      final rules = [
        const FragmentRule(
          id: 'r1',
          field: 'amount',
          pattern: 'total',
          patternType: FragmentPatternType.keyword,
          valueType: FragmentValueType.currency,
        ),
      ];

      final result = extractor.extract(doc, rules);

      expect(result.length, equals(1));
      expect(result.first.fields['field'], equals('amount'));
      expect(result.first.fields['value'], equals('100.00'));
    });

    test('extract with keyValue rule - exact case-insensitive match', () {
      final doc = makeDocument('ev2', [
        const KeyValueBlock(
          id: 'kv1',
          key: 'Invoice Date',
          value: '2025-01-15',
        ),
      ]);

      final rules = [
        const FragmentRule(
          id: 'r1',
          field: 'date',
          pattern: 'invoice date',
          patternType: FragmentPatternType.keyValue,
          valueType: FragmentValueType.date,
        ),
      ];

      final result = extractor.extract(doc, rules);

      expect(result.length, equals(1));
      expect(result.first.fields['field'], equals('date'));
      expect(result.first.fields['value'], equals('2025-01-15'));
    });

    test('extract with regex rule', () {
      final doc = makeDocument('ev3', [
        const KeyValueBlock(
          id: 'kv1',
          key: 'INV-2025-001',
          value: 'Paid',
        ),
      ]);

      final rules = [
        const FragmentRule(
          id: 'r1',
          field: 'invoiceNumber',
          pattern: r'INV-\d{4}-\d+',
          patternType: FragmentPatternType.regex,
        ),
      ];

      final result = extractor.extract(doc, rules);

      expect(result.length, equals(1));
      expect(result.first.fields['field'], equals('invoiceNumber'));
    });

    test('extract with no matching rules returns empty list', () {
      final doc = makeDocument('ev4', [
        const KeyValueBlock(
          id: 'kv1',
          key: 'Memo',
          value: 'Some note',
        ),
      ]);

      final rules = [
        const FragmentRule(
          id: 'r1',
          field: 'amount',
          pattern: 'total',
          patternType: FragmentPatternType.keyword,
        ),
      ];

      final result = extractor.extract(doc, rules);

      expect(result, isEmpty);
    });

    test('extract with empty document (no KeyValueBlocks) returns empty', () {
      final doc = makeDocument('ev5', [
        const TextBlock(id: 'txt1', text: 'Just a paragraph'),
      ]);

      final rules = [
        const FragmentRule(
          id: 'r1',
          field: 'amount',
          pattern: 'total',
          patternType: FragmentPatternType.keyword,
        ),
      ];

      final result = extractor.extract(doc, rules);

      expect(result, isEmpty);
    });

    test('multiple rules - first match wins', () {
      final doc = makeDocument('ev6', [
        const KeyValueBlock(
          id: 'kv1',
          key: 'Total Price',
          value: '50.00',
        ),
      ]);

      // Both rules match 'Total Price' via keyword, but first should win.
      final rules = [
        const FragmentRule(
          id: 'r1',
          field: 'total_amount',
          pattern: 'total',
          patternType: FragmentPatternType.keyword,
        ),
        const FragmentRule(
          id: 'r2',
          field: 'price',
          pattern: 'price',
          patternType: FragmentPatternType.keyword,
        ),
      ];

      final result = extractor.extract(doc, rules);

      expect(result.length, equals(1));
      expect(result.first.fields['field'], equals('total_amount'));
    });

    test('fragment fields verification', () {
      final doc = makeDocument('evidence_42', [
        const KeyValueBlock(
          id: 'part_7',
          key: 'amount',
          value: '250.00',
          confidence: 0.95,
        ),
      ]);

      final rules = [
        const FragmentRule(
          id: 'r1',
          field: 'amount',
          pattern: 'amount',
          patternType: FragmentPatternType.keyValue,
        ),
      ];

      final result = extractor.extract(doc, rules);

      expect(result.length, equals(1));
      final fragment = result.first;
      expect(fragment.fragmentId, equals('evidence_42_part_7'));
      expect(fragment.evidenceId, equals('evidence_42'));
      expect(fragment.workspaceId, equals('default'));
      expect(fragment.fields['field'], equals('amount'));
      expect(fragment.fields['value'], equals('250.00'));
      expect(fragment.fields['key'], equals('amount'));
      expect(fragment.confidence, equals(0.95));
      expect(fragment.extractor, equals(ExtractorType.rule));
    });

    test('position from part location', () {
      final doc = makeDocument('ev7', [
        const KeyValueBlock(
          id: 'kv1',
          key: 'Date',
          value: '2025-06-01',
          location: SourceLocation(
            charOffset: 100,
            charLength: 20,
            lineNumber: 5,
          ),
        ),
      ]);

      final rules = [
        const FragmentRule(
          id: 'r1',
          field: 'date',
          pattern: 'date',
          patternType: FragmentPatternType.keyValue,
        ),
      ];

      final result = extractor.extract(doc, rules);

      expect(result.length, equals(1));
      final position = result.first.fields['position'] as Map<String, dynamic>;
      expect(position['start'], equals(100));
      expect(position['end'], equals(120));
      expect(position['line'], equals(5));
    });

    test('part without location has no position in fields', () {
      final doc = makeDocument('ev8', [
        const KeyValueBlock(
          id: 'kv1',
          key: 'Merchant',
          value: 'Acme Corp',
        ),
      ]);

      final rules = [
        const FragmentRule(
          id: 'r1',
          field: 'merchant',
          pattern: 'merchant',
          patternType: FragmentPatternType.keyValue,
        ),
      ];

      final result = extractor.extract(doc, rules);

      expect(result.length, equals(1));
      expect(result.first.fields.containsKey('position'), isFalse);
    });

    test('normalizedValue included when present', () {
      final doc = makeDocument('ev9', [
        const KeyValueBlock(
          id: 'kv1',
          key: 'Total',
          value: '\$1,234.56',
          normalizedValue: 1234.56,
        ),
      ]);

      final rules = [
        const FragmentRule(
          id: 'r1',
          field: 'amount',
          pattern: 'total',
          patternType: FragmentPatternType.keyword,
        ),
      ];

      final result = extractor.extract(doc, rules);

      expect(result.length, equals(1));
      expect(result.first.fields['normalizedValue'], equals(1234.56));
    });
  });
}
