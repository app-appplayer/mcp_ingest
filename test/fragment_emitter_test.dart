import 'package:test/test.dart';
import 'package:mcp_ingest/mcp_ingest.dart';
import 'package:mcp_fact_graph/mcp_fact_graph.dart' show ExtractorType;

/// Helper to create a NormalizedDocument from parts.
NormalizedDocument _createDoc(List<DocumentPart> parts) {
  return NormalizedDocument(
    id: 'doc1',
    metadata: const DocumentMetadata(mimeType: 'text/plain', sha256: 'abc123'),
    parts: parts,
    structure: DocumentStructure.empty,
    provenance: ExtractionProvenance(
      extractorId: 'test',
      extractorVersion: '1.0',
      extractedAt: DateTime(2024, 1, 1),
      extractionDuration: Duration.zero,
    ),
  );
}

/// Helper to create a Chunk with minimal boilerplate.
Chunk _createChunk({
  required String id,
  required String text,
  required int index,
  required int totalChunks,
  List<ChunkSpan>? sourceSpans,
  String? contextPrefix,
}) {
  return Chunk(
    id: id,
    text: text,
    sourceSpans: sourceSpans ?? const [],
    location: const SourceLocation(),
    index: index,
    totalChunks: totalChunks,
    contextPrefix: contextPrefix,
  );
}

void main() {
  // =========================================================================
  // FragmentEmitterConfig
  // =========================================================================
  group('FragmentEmitterConfig', () {
    test('has correct default values', () {
      const config = FragmentEmitterConfig();
      expect(config.extractKeyValues, isTrue);
      expect(config.extractTableCells, isFalse);
      expect(config.defaultConfidence, 0.8);
      expect(config.defaultExtractor, ExtractorType.rule);
      expect(config.defaultWorkspaceId, 'default');
    });

    test('static defaults matches default constructor', () {
      const config = FragmentEmitterConfig.defaults;
      expect(config.extractKeyValues, isTrue);
      expect(config.extractTableCells, isFalse);
      expect(config.defaultConfidence, 0.8);
      expect(config.defaultExtractor, ExtractorType.rule);
      expect(config.defaultWorkspaceId, 'default');
    });

    test('accepts custom values', () {
      const config = FragmentEmitterConfig(
        extractKeyValues: false,
        extractTableCells: true,
        defaultConfidence: 0.95,
        defaultExtractor: ExtractorType.llm,
        defaultWorkspaceId: 'custom-ws',
      );
      expect(config.extractKeyValues, isFalse);
      expect(config.extractTableCells, isTrue);
      expect(config.defaultConfidence, 0.95);
      expect(config.defaultExtractor, ExtractorType.llm);
      expect(config.defaultWorkspaceId, 'custom-ws');
    });
  });

  // =========================================================================
  // emitFromDocument - KeyValueBlocks
  // =========================================================================
  group('FragmentEmitter.emitFromDocument with KeyValueBlocks', () {
    test('creates fragments from key-value blocks', () {
      final emitter = FragmentEmitter();
      final doc = _createDoc([
        const KeyValueBlock(
          id: 'kv1',
          key: 'name',
          value: 'John Doe',
          confidence: 0.9,
        ),
        const KeyValueBlock(
          id: 'kv2',
          key: 'email',
          value: 'john@example.com',
          confidence: 0.85,
        ),
      ]);

      final fragments = emitter.emitFromDocument(
        document: doc,
        evidenceId: 'ev_test1',
      );

      expect(fragments, hasLength(2));
      expect(fragments[0].fields['field'], 'name');
      expect(fragments[0].fields['value'], 'John Doe');
      expect(fragments[0].confidence, 0.9);
      expect(fragments[0].evidenceId, 'ev_test1');
      expect(fragments[0].workspaceId, 'default');

      expect(fragments[1].fields['field'], 'email');
      expect(fragments[1].fields['value'], 'john@example.com');
      expect(fragments[1].confidence, 0.85);
    });

    test('uses custom workspaceId when provided', () {
      final emitter = FragmentEmitter();
      final doc = _createDoc([
        const KeyValueBlock(id: 'kv1', key: 'field1', value: 'val1'),
      ]);

      final fragments = emitter.emitFromDocument(
        document: doc,
        evidenceId: 'ev_test1',
        workspaceId: 'custom-ws',
      );

      expect(fragments.first.workspaceId, 'custom-ws');
    });

    test('skips key-value extraction when extractKeyValues is false', () {
      final emitter = FragmentEmitter(
        config: const FragmentEmitterConfig(extractKeyValues: false),
      );
      final doc = _createDoc([
        const KeyValueBlock(id: 'kv1', key: 'name', value: 'John'),
      ]);

      final fragments = emitter.emitFromDocument(
        document: doc,
        evidenceId: 'ev_test1',
      );

      expect(fragments, isEmpty);
    });

    test('generates unique fragment IDs', () {
      final emitter = FragmentEmitter();
      final doc = _createDoc([
        const KeyValueBlock(id: 'kv1', key: 'a', value: '1'),
        const KeyValueBlock(id: 'kv2', key: 'b', value: '2'),
        const KeyValueBlock(id: 'kv3', key: 'c', value: '3'),
      ]);

      final fragments = emitter.emitFromDocument(
        document: doc,
        evidenceId: 'ev_test1',
      );

      final ids = fragments.map((f) => f.fragmentId).toSet();
      expect(ids, hasLength(3));
    });
  });

  // =========================================================================
  // emitFromDocument - TableBlocks
  // =========================================================================
  group('FragmentEmitter.emitFromDocument with extractTableCells', () {
    test('extracts table cells as fragments when enabled', () {
      final emitter = FragmentEmitter(
        config: const FragmentEmitterConfig(extractTableCells: true),
      );

      final doc = _createDoc([
        TableBlock(
          id: 'tbl1',
          rows: [
            const TableRow(
              isHeader: true,
              cells: [
                TableCell(text: 'Name'),
                TableCell(text: 'Age'),
              ],
            ),
            const TableRow(cells: [
              TableCell(text: 'Alice'),
              TableCell(text: '30'),
            ]),
            const TableRow(cells: [
              TableCell(text: 'Bob'),
              TableCell(text: '25'),
            ]),
          ],
          rowCount: 3,
          columnCount: 2,
        ),
      ]);

      final fragments = emitter.emitFromDocument(
        document: doc,
        evidenceId: 'ev_tbl',
      );

      // 2 data rows * 2 columns = 4 fragments
      expect(fragments, hasLength(4));

      // Verify header-based field naming: Name_row0, Age_row0, Name_row1, Age_row1
      expect(fragments[0].fields['field'], 'Name_row0');
      expect(fragments[0].fields['value'], 'Alice');
      expect(fragments[0].metadata['header'], 'Name');
      expect(fragments[0].metadata['row'], 0);
      expect(fragments[0].metadata['column'], 0);
      expect(fragments[0].metadata['tableId'], 'tbl1');

      expect(fragments[1].fields['field'], 'Age_row0');
      expect(fragments[1].fields['value'], '30');

      expect(fragments[2].fields['field'], 'Name_row1');
      expect(fragments[2].fields['value'], 'Bob');

      expect(fragments[3].fields['field'], 'Age_row1');
      expect(fragments[3].fields['value'], '25');
    });

    test('does not extract table cells when extractTableCells is false', () {
      final emitter = FragmentEmitter(); // default: extractTableCells=false

      final doc = _createDoc([
        TableBlock(
          id: 'tbl1',
          rows: [
            const TableRow(cells: [TableCell(text: 'A')]),
          ],
          rowCount: 1,
          columnCount: 1,
        ),
      ]);

      final fragments = emitter.emitFromDocument(
        document: doc,
        evidenceId: 'ev_tbl',
      );

      expect(fragments, isEmpty);
    });
  });

  // =========================================================================
  // emitFromDocument - empty document
  // =========================================================================
  group('FragmentEmitter.emitFromDocument with empty document', () {
    test('returns empty list when document has no parts', () {
      final emitter = FragmentEmitter();
      final doc = _createDoc([]);

      final fragments = emitter.emitFromDocument(
        document: doc,
        evidenceId: 'ev_empty',
      );

      expect(fragments, isEmpty);
    });

    test('returns empty when only text blocks present', () {
      final emitter = FragmentEmitter();
      final doc = _createDoc([
        const TextBlock(id: 'txt1', text: 'Hello world'),
      ]);

      // TextBlocks are not extracted by key-value or table extraction
      final fragments = emitter.emitFromDocument(
        document: doc,
        evidenceId: 'ev_text',
      );

      expect(fragments, isEmpty);
    });
  });

  // =========================================================================
  // emitFromChunks
  // =========================================================================
  group('FragmentEmitter.emitFromChunks', () {
    test('creates one fragment per chunk with metadata', () {
      final emitter = FragmentEmitter();

      final chunks = [
        _createChunk(
          id: 'c1',
          text: 'First chunk text',
          index: 0,
          totalChunks: 3,
        ),
        _createChunk(
          id: 'c2',
          text: 'Second chunk text',
          index: 1,
          totalChunks: 3,
        ),
        _createChunk(
          id: 'c3',
          text: 'Third chunk text',
          index: 2,
          totalChunks: 3,
        ),
      ];

      final fragments = emitter.emitFromChunks(
        chunks: chunks,
        evidenceId: 'ev_chunks',
      );

      expect(fragments, hasLength(3));

      // First chunk
      expect(fragments[0].fields['field'], 'chunk_0');
      expect(fragments[0].fields['value'], 'First chunk text');
      expect(fragments[0].metadata['chunkId'], 'c1');
      expect(fragments[0].metadata['chunkIndex'], 0);
      expect(fragments[0].metadata['totalChunks'], 3);
      expect(fragments[0].evidenceId, 'ev_chunks');
      expect(fragments[0].confidence, 0.8);

      // Second chunk
      expect(fragments[1].fields['field'], 'chunk_1');
      expect(fragments[1].metadata['chunkId'], 'c2');
      expect(fragments[1].metadata['chunkIndex'], 1);

      // Third chunk
      expect(fragments[2].fields['field'], 'chunk_2');
      expect(fragments[2].metadata['chunkId'], 'c3');
    });

    test('includes contextPrefix in metadata when present', () {
      final emitter = FragmentEmitter();

      final chunks = [
        _createChunk(
          id: 'c1',
          text: 'Some text',
          index: 0,
          totalChunks: 1,
          contextPrefix: 'Section > Heading',
        ),
      ];

      final fragments = emitter.emitFromChunks(
        chunks: chunks,
        evidenceId: 'ev_ctx',
      );

      expect(fragments.first.metadata['contextPrefix'], 'Section > Heading');
    });

    test('omits contextPrefix from metadata when null', () {
      final emitter = FragmentEmitter();

      final chunks = [
        _createChunk(
          id: 'c1',
          text: 'Some text',
          index: 0,
          totalChunks: 1,
        ),
      ];

      final fragments = emitter.emitFromChunks(
        chunks: chunks,
        evidenceId: 'ev_noctx',
      );

      expect(fragments.first.metadata.containsKey('contextPrefix'), isFalse);
    });

    test('uses custom fieldPrefix', () {
      final emitter = FragmentEmitter();

      final chunks = [
        _createChunk(id: 'c1', text: 'Text', index: 0, totalChunks: 1),
      ];

      final fragments = emitter.emitFromChunks(
        chunks: chunks,
        evidenceId: 'ev_prefix',
        fieldPrefix: 'paragraph',
      );

      expect(fragments.first.fields['field'], 'paragraph_0');
    });

    test('uses config workspaceId when not specified', () {
      final emitter = FragmentEmitter(
        config: const FragmentEmitterConfig(defaultWorkspaceId: 'ws-custom'),
      );

      final chunks = [
        _createChunk(id: 'c1', text: 'Text', index: 0, totalChunks: 1),
      ];

      final fragments = emitter.emitFromChunks(
        chunks: chunks,
        evidenceId: 'ev_ws',
      );

      expect(fragments.first.workspaceId, 'ws-custom');
    });
  });

  // =========================================================================
  // emitSingle
  // =========================================================================
  group('FragmentEmitter.emitSingle', () {
    test('creates a single fragment with custom properties', () {
      final emitter = FragmentEmitter();
      final position = const SourcePosition(start: 10, end: 50, line: 3);

      final fragment = emitter.emitSingle(
        evidenceId: 'ev_single',
        field: 'invoice_number',
        value: 'INV-2024-001',
        confidence: 0.95,
        extractor: ExtractorType.llm,
        position: position,
        metadata: {'source': 'header'},
      );

      expect(fragment.evidenceId, 'ev_single');
      expect(fragment.fields['field'], 'invoice_number');
      expect(fragment.fields['value'], 'INV-2024-001');
      expect(fragment.confidence, 0.95);
      expect(fragment.extractor, ExtractorType.llm);
      expect(fragment.metadata['source'], 'header');
      expect(fragment.fields['position'], isNotNull);
    });

    test('uses default confidence and extractor when not specified', () {
      final emitter = FragmentEmitter(
        config: const FragmentEmitterConfig(
          defaultConfidence: 0.7,
          defaultExtractor: ExtractorType.ocr,
        ),
      );

      final fragment = emitter.emitSingle(
        evidenceId: 'ev_def',
        field: 'amount',
        value: '100.00',
      );

      expect(fragment.confidence, 0.7);
      expect(fragment.extractor, ExtractorType.ocr);
    });

    test('uses default workspaceId when not specified', () {
      final emitter = FragmentEmitter();

      final fragment = emitter.emitSingle(
        evidenceId: 'ev_ws',
        field: 'test_field',
        value: 'test_value',
      );

      expect(fragment.workspaceId, 'default');
    });

    test('uses custom workspaceId when provided', () {
      final emitter = FragmentEmitter();

      final fragment = emitter.emitSingle(
        evidenceId: 'ev_ws',
        field: 'test_field',
        value: 'test_value',
        workspaceId: 'my-workspace',
      );

      expect(fragment.workspaceId, 'my-workspace');
    });
  });

  // =========================================================================
  // Value type detection (_detectValueType via emitSingle fields)
  // =========================================================================
  group('Value type detection', () {
    late FragmentEmitter emitter;

    setUp(() {
      emitter = FragmentEmitter();
    });

    // Access the detected valueType through the fragment fields
    String _emitAndGetValueType(dynamic value) {
      final fragment = emitter.emitSingle(
        evidenceId: 'ev_vt',
        field: 'test',
        value: value,
      );
      return fragment.fields['valueType'] as String;
    }

    test('null value -> unknown', () {
      expect(_emitAndGetValueType(null), 'unknown');
    });

    test('bool value -> boolean', () {
      expect(_emitAndGetValueType(true), 'boolean');
      expect(_emitAndGetValueType(false), 'boolean');
    });

    test('int value -> number', () {
      expect(_emitAndGetValueType(42), 'number');
      expect(_emitAndGetValueType(0), 'number');
      expect(_emitAndGetValueType(-10), 'number');
    });

    test('double value -> number', () {
      expect(_emitAndGetValueType(3.14), 'number');
      expect(_emitAndGetValueType(0.0), 'number');
    });

    test('DateTime value -> datetime', () {
      expect(_emitAndGetValueType(DateTime(2024, 1, 15)), 'datetime');
    });

    test('List value -> array', () {
      expect(_emitAndGetValueType([1, 2, 3]), 'array');
      expect(_emitAndGetValueType(<String>[]), 'array');
    });

    test('Map value -> object', () {
      expect(_emitAndGetValueType({'key': 'val'}), 'object');
      expect(_emitAndGetValueType(<String, dynamic>{}), 'object');
    });

    test('date string "2024-01-15" -> date', () {
      expect(_emitAndGetValueType('2024-01-15'), 'date');
    });

    test('date string with slashes "2024/06/30" -> date', () {
      expect(_emitAndGetValueType('2024/06/30'), 'date');
    });

    test('currency string "\$100.50" -> currency', () {
      expect(_emitAndGetValueType('\$100.50'), 'currency');
    });

    test('currency string with euro sign -> currency', () {
      expect(_emitAndGetValueType('\u20AC250.00'), 'currency');
    });

    test('percentage string "95.5%" -> percentage', () {
      expect(_emitAndGetValueType('95.5%'), 'percentage');
    });

    test('percentage string "100%" -> percentage', () {
      expect(_emitAndGetValueType('100%'), 'percentage');
    });

    test('numeric string "1234.56" -> number', () {
      // Numeric strings without commas parse as double
      expect(_emitAndGetValueType('1234.56'), 'number');
    });

    test('numeric string with commas "1,234.56" -> number', () {
      expect(_emitAndGetValueType('1,234.56'), 'number');
    });

    test('plain string -> string', () {
      expect(_emitAndGetValueType('hello world'), 'string');
      expect(_emitAndGetValueType('abc'), 'string');
    });
  });

  // =========================================================================
  // Value normalization (_normalizeValue via emitSingle fields)
  // =========================================================================
  group('Value normalization', () {
    late FragmentEmitter emitter;

    setUp(() {
      emitter = FragmentEmitter();
    });

    dynamic _emitAndGetNormalizedValue(dynamic value) {
      final fragment = emitter.emitSingle(
        evidenceId: 'ev_norm',
        field: 'test',
        value: value,
      );
      return fragment.fields['normalizedValue'];
    }

    test('null value -> null', () {
      expect(_emitAndGetNormalizedValue(null), isNull);
    });

    test('numeric string -> double', () {
      final result = _emitAndGetNormalizedValue('42');
      expect(result, isA<double>());
      expect(result, 42.0);
    });

    test('numeric string with commas -> double', () {
      final result = _emitAndGetNormalizedValue('1,234.56');
      expect(result, isA<double>());
      expect(result, 1234.56);
    });

    test('currency string with dollar sign -> double (strips \$)', () {
      final result = _emitAndGetNormalizedValue('\$100.50');
      expect(result, isA<double>());
      expect(result, 100.50);
    });

    test('date string -> ISO8601 string', () {
      // "2024-01-15" parses as a valid DateTime
      final result = _emitAndGetNormalizedValue('2024-01-15');
      expect(result, isA<String>());
      expect(result, contains('2024-01-15'));
    });

    test('plain text -> passthrough', () {
      final result = _emitAndGetNormalizedValue('hello world');
      expect(result, 'hello world');
    });

    test('integer value -> double (toString then parse)', () {
      // int 42 -> "42" -> 42.0
      final result = _emitAndGetNormalizedValue(42);
      expect(result, isA<double>());
      expect(result, 42.0);
    });
  });

  // =========================================================================
  // Table extraction details
  // =========================================================================
  group('Table extraction details', () {
    test('header row + data rows: uses header names in field', () {
      final emitter = FragmentEmitter(
        config: const FragmentEmitterConfig(extractTableCells: true),
      );

      final doc = _createDoc([
        TableBlock(
          id: 'tbl1',
          rows: [
            const TableRow(
              isHeader: true,
              cells: [
                TableCell(text: 'Product'),
                TableCell(text: 'Price'),
              ],
            ),
            const TableRow(cells: [
              TableCell(text: 'Widget'),
              TableCell(text: '\$9.99'),
            ]),
          ],
          rowCount: 2,
          columnCount: 2,
        ),
      ]);

      final fragments = emitter.emitFromDocument(
        document: doc,
        evidenceId: 'ev_tbl_hdr',
      );

      expect(fragments, hasLength(2));
      expect(fragments[0].fields['field'], 'Product_row0');
      expect(fragments[1].fields['field'], 'Price_row0');
    });

    test('no headers: uses cell_row_col naming', () {
      final emitter = FragmentEmitter(
        config: const FragmentEmitterConfig(extractTableCells: true),
      );

      final doc = _createDoc([
        TableBlock(
          id: 'tbl_noheader',
          rows: [
            const TableRow(cells: [
              TableCell(text: 'A1'),
              TableCell(text: 'B1'),
            ]),
            const TableRow(cells: [
              TableCell(text: 'A2'),
              TableCell(text: 'B2'),
            ]),
          ],
          rowCount: 2,
          columnCount: 2,
        ),
      ]);

      final fragments = emitter.emitFromDocument(
        document: doc,
        evidenceId: 'ev_tbl_nh',
      );

      // No header row -> all rows are data rows, startRow=0
      expect(fragments, hasLength(4));
      expect(fragments[0].fields['field'], 'cell_0_0');
      expect(fragments[0].fields['value'], 'A1');
      expect(fragments[1].fields['field'], 'cell_0_1');
      expect(fragments[2].fields['field'], 'cell_1_0');
      expect(fragments[3].fields['field'], 'cell_1_1');
    });

    test('empty cells are skipped', () {
      final emitter = FragmentEmitter(
        config: const FragmentEmitterConfig(extractTableCells: true),
      );

      final doc = _createDoc([
        TableBlock(
          id: 'tbl_empty',
          rows: [
            const TableRow(
              isHeader: true,
              cells: [
                TableCell(text: 'Name'),
                TableCell(text: 'Value'),
              ],
            ),
            const TableRow(cells: [
              TableCell(text: 'Filled'),
              TableCell(text: ''), // empty cell - should be skipped
            ]),
          ],
          rowCount: 2,
          columnCount: 2,
        ),
      ]);

      final fragments = emitter.emitFromDocument(
        document: doc,
        evidenceId: 'ev_tbl_skip',
      );

      // Only 1 fragment (the non-empty cell)
      expect(fragments, hasLength(1));
      expect(fragments[0].fields['value'], 'Filled');
    });

    test('empty table returns no fragments', () {
      final emitter = FragmentEmitter(
        config: const FragmentEmitterConfig(extractTableCells: true),
      );

      final doc = _createDoc([
        const TableBlock(
          id: 'tbl_empty',
          rows: [],
          rowCount: 0,
          columnCount: 0,
        ),
      ]);

      final fragments = emitter.emitFromDocument(
        document: doc,
        evidenceId: 'ev_tbl_mt',
      );

      expect(fragments, isEmpty);
    });

    test('includes dataType in metadata when cell has dataType', () {
      final emitter = FragmentEmitter(
        config: const FragmentEmitterConfig(extractTableCells: true),
      );

      final doc = _createDoc([
        TableBlock(
          id: 'tbl_dt',
          rows: [
            const TableRow(
              isHeader: true,
              cells: [TableCell(text: 'Amount')],
            ),
            const TableRow(cells: [
              TableCell(text: '100', dataType: 'number'),
            ]),
          ],
          rowCount: 2,
          columnCount: 1,
        ),
      ]);

      final fragments = emitter.emitFromDocument(
        document: doc,
        evidenceId: 'ev_tbl_dtype',
      );

      expect(fragments, hasLength(1));
      expect(fragments[0].metadata['dataType'], 'number');
    });
  });

  // =========================================================================
  // Position from part (_partPosition)
  // =========================================================================
  group('Position from part', () {
    test('part with location produces SourcePosition', () {
      final emitter = FragmentEmitter();
      final doc = _createDoc([
        const KeyValueBlock(
          id: 'kv_pos',
          key: 'field',
          value: 'val',
          location: SourceLocation(
            charOffset: 100,
            charLength: 20,
            lineNumber: 5,
          ),
        ),
      ]);

      final fragments = emitter.emitFromDocument(
        document: doc,
        evidenceId: 'ev_pos',
      );

      expect(fragments, hasLength(1));
      final posJson = fragments[0].fields['position'] as Map<String, dynamic>;
      expect(posJson['start'], 100);
      expect(posJson['end'], 120); // 100 + 20
      expect(posJson['line'], 5);
    });

    test('part without location produces no position', () {
      final emitter = FragmentEmitter();
      final doc = _createDoc([
        const KeyValueBlock(
          id: 'kv_nopos',
          key: 'field',
          value: 'val',
          // no location
        ),
      ]);

      final fragments = emitter.emitFromDocument(
        document: doc,
        evidenceId: 'ev_nopos',
      );

      expect(fragments, hasLength(1));
      expect(fragments[0].fields.containsKey('position'), isFalse);
    });

    test('part with location but null charOffset produces no position', () {
      final emitter = FragmentEmitter();
      final doc = _createDoc([
        const KeyValueBlock(
          id: 'kv_noco',
          key: 'field',
          value: 'val',
          location: SourceLocation(lineNumber: 5),
        ),
      ]);

      final fragments = emitter.emitFromDocument(
        document: doc,
        evidenceId: 'ev_noco',
      );

      expect(fragments, hasLength(1));
      expect(fragments[0].fields.containsKey('position'), isFalse);
    });

    test('part with charOffset but no charLength uses offset as end', () {
      final emitter = FragmentEmitter();
      final doc = _createDoc([
        const KeyValueBlock(
          id: 'kv_nolen',
          key: 'field',
          value: 'val',
          location: SourceLocation(charOffset: 50),
        ),
      ]);

      final fragments = emitter.emitFromDocument(
        document: doc,
        evidenceId: 'ev_nolen',
      );

      expect(fragments, hasLength(1));
      final posJson = fragments[0].fields['position'] as Map<String, dynamic>;
      expect(posJson['start'], 50);
      expect(posJson['end'], 50); // no charLength -> end = start
    });
  });

  // =========================================================================
  // Position from chunk (_chunkPosition)
  // =========================================================================
  group('Position from chunk', () {
    test('chunk with sourceSpans produces SourcePosition', () {
      final emitter = FragmentEmitter();
      final chunks = [
        _createChunk(
          id: 'c_pos',
          text: 'Some text',
          index: 0,
          totalChunks: 1,
          sourceSpans: [
            const ChunkSpan(partId: 'p1', startOffset: 10, endOffset: 30),
            const ChunkSpan(partId: 'p2', startOffset: 50, endOffset: 80),
          ],
        ),
      ];

      final fragments = emitter.emitFromChunks(
        chunks: chunks,
        evidenceId: 'ev_cpos',
      );

      expect(fragments, hasLength(1));
      final posJson = fragments[0].fields['position'] as Map<String, dynamic>;
      // start from first span, end from last span
      expect(posJson['start'], 10);
      expect(posJson['end'], 80);
    });

    test('chunk with empty sourceSpans produces no position', () {
      final emitter = FragmentEmitter();
      final chunks = [
        _createChunk(
          id: 'c_nopos',
          text: 'Text',
          index: 0,
          totalChunks: 1,
          sourceSpans: [],
        ),
      ];

      final fragments = emitter.emitFromChunks(
        chunks: chunks,
        evidenceId: 'ev_cnopos',
      );

      expect(fragments, hasLength(1));
      expect(fragments[0].fields.containsKey('position'), isFalse);
    });

    test('chunk with single sourceSpan uses same start and end', () {
      final emitter = FragmentEmitter();
      final chunks = [
        _createChunk(
          id: 'c_single',
          text: 'Text',
          index: 0,
          totalChunks: 1,
          sourceSpans: [
            const ChunkSpan(partId: 'p1', startOffset: 5, endOffset: 25),
          ],
        ),
      ];

      final fragments = emitter.emitFromChunks(
        chunks: chunks,
        evidenceId: 'ev_csingle',
      );

      final posJson = fragments[0].fields['position'] as Map<String, dynamic>;
      expect(posJson['start'], 5);
      expect(posJson['end'], 25);
    });
  });

  // =========================================================================
  // BatchFragmentEmitter.emitBatch
  // =========================================================================
  group('BatchFragmentEmitter.emitBatch', () {
    test('processes multiple documents and returns map by evidenceId', () {
      final batchEmitter = BatchFragmentEmitter();

      final doc1 = _createDoc([
        const KeyValueBlock(id: 'kv1', key: 'name', value: 'Doc1'),
      ]);
      final doc2 = _createDoc([
        const KeyValueBlock(id: 'kv2', key: 'title', value: 'Doc2'),
        const KeyValueBlock(id: 'kv3', key: 'author', value: 'Alice'),
      ]);

      final result = batchEmitter.emitBatch(
        items: [(doc1, 'ev_doc1'), (doc2, 'ev_doc2')],
      );

      expect(result, hasLength(2));
      expect(result.containsKey('ev_doc1'), isTrue);
      expect(result.containsKey('ev_doc2'), isTrue);
      expect(result['ev_doc1'], hasLength(1));
      expect(result['ev_doc2'], hasLength(2));
    });

    test('uses custom workspaceId for all documents', () {
      final batchEmitter = BatchFragmentEmitter();

      final doc = _createDoc([
        const KeyValueBlock(id: 'kv1', key: 'name', value: 'Test'),
      ]);

      final result = batchEmitter.emitBatch(
        items: [(doc, 'ev_batch')],
        workspaceId: 'batch-ws',
      );

      expect(result['ev_batch']!.first.workspaceId, 'batch-ws');
    });

    test('empty items returns empty map', () {
      final batchEmitter = BatchFragmentEmitter();

      final result = batchEmitter.emitBatch(items: []);

      expect(result, isEmpty);
    });

    test('accepts custom config', () {
      final batchEmitter = BatchFragmentEmitter(
        config: const FragmentEmitterConfig(
          extractKeyValues: false,
          extractTableCells: true,
        ),
      );

      final doc = _createDoc([
        const KeyValueBlock(id: 'kv1', key: 'name', value: 'Test'),
      ]);

      // extractKeyValues is false, so no fragments from KeyValueBlocks
      final result = batchEmitter.emitBatch(
        items: [(doc, 'ev_nokeys')],
      );

      expect(result['ev_nokeys'], isEmpty);
    });
  });

  // =========================================================================
  // BatchFragmentEmitter.emitChunksBatch
  // =========================================================================
  group('BatchFragmentEmitter.emitChunksBatch', () {
    test('processes chunks grouped by evidence', () {
      final batchEmitter = BatchFragmentEmitter();

      final chunksByEvidence = {
        'ev_a': [
          _createChunk(id: 'a1', text: 'Chunk A1', index: 0, totalChunks: 2),
          _createChunk(id: 'a2', text: 'Chunk A2', index: 1, totalChunks: 2),
        ],
        'ev_b': [
          _createChunk(id: 'b1', text: 'Chunk B1', index: 0, totalChunks: 1),
        ],
      };

      final result = batchEmitter.emitChunksBatch(
        chunksByEvidence: chunksByEvidence,
      );

      expect(result, hasLength(2));
      expect(result.containsKey('ev_a'), isTrue);
      expect(result.containsKey('ev_b'), isTrue);
      expect(result['ev_a'], hasLength(2));
      expect(result['ev_b'], hasLength(1));

      // Verify evidence IDs are set correctly
      expect(result['ev_a']!.first.evidenceId, 'ev_a');
      expect(result['ev_b']!.first.evidenceId, 'ev_b');
    });

    test('uses custom workspaceId for all chunks', () {
      final batchEmitter = BatchFragmentEmitter();

      final chunksByEvidence = {
        'ev_c': [
          _createChunk(id: 'c1', text: 'Text', index: 0, totalChunks: 1),
        ],
      };

      final result = batchEmitter.emitChunksBatch(
        chunksByEvidence: chunksByEvidence,
        workspaceId: 'chunks-ws',
      );

      expect(result['ev_c']!.first.workspaceId, 'chunks-ws');
    });

    test('empty map returns empty result', () {
      final batchEmitter = BatchFragmentEmitter();

      final result = batchEmitter.emitChunksBatch(
        chunksByEvidence: {},
      );

      expect(result, isEmpty);
    });

    test('evidence with empty chunk list returns empty fragment list', () {
      final batchEmitter = BatchFragmentEmitter();

      final result = batchEmitter.emitChunksBatch(
        chunksByEvidence: {'ev_empty': []},
      );

      expect(result, hasLength(1));
      expect(result['ev_empty'], isEmpty);
    });
  });
}
