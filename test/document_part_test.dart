import 'package:test/test.dart';
import 'package:mcp_ingest/mcp_ingest.dart';
import 'package:mcp_fact_graph/mcp_fact_graph.dart' show ExtractorType;

void main() {
  // =========================================================================
  // TextSpan
  // =========================================================================
  group('TextSpan', () {
    test('constructor sets all fields', () {
      const span = TextSpan(
        start: 3,
        end: 12,
        type: TextSpanType.bold,
      );
      expect(span.start, equals(3));
      expect(span.end, equals(12));
      expect(span.type, equals(TextSpanType.bold));
      expect(span.value, isNull);
    });

    test('length getter returns end - start', () {
      const span = TextSpan(start: 5, end: 20, type: TextSpanType.italic);
      expect(span.length, equals(15));
    });

    test('toJson serializes all fields', () {
      const span = TextSpan(
        start: 0,
        end: 10,
        type: TextSpanType.link,
        value: 'https://example.com',
      );
      final json = span.toJson();
      expect(json['start'], equals(0));
      expect(json['end'], equals(10));
      expect(json['type'], equals('link'));
      expect(json['value'], equals('https://example.com'));
    });

    test('toJson omits null value', () {
      const span = TextSpan(start: 0, end: 5, type: TextSpanType.bold);
      final json = span.toJson();
      expect(json.containsKey('value'), isFalse);
    });

    test('fromJson constructs from JSON map', () {
      final json = {
        'start': 2,
        'end': 8,
        'type': 'highlight',
        'value': 'note',
      };
      final span = TextSpan.fromJson(json);
      expect(span.start, equals(2));
      expect(span.end, equals(8));
      expect(span.type, equals(TextSpanType.highlight));
      expect(span.value, equals('note'));
    });

    test('fromJson without value sets null', () {
      final json = {'start': 0, 'end': 3, 'type': 'code'};
      final span = TextSpan.fromJson(json);
      expect(span.value, isNull);
    });

    test('round-trip fromJson(toJson()) preserves all fields', () {
      const original = TextSpan(
        start: 10,
        end: 25,
        type: TextSpanType.link,
        value: 'https://dart.dev',
      );
      final restored = TextSpan.fromJson(original.toJson());
      expect(restored.start, equals(original.start));
      expect(restored.end, equals(original.end));
      expect(restored.type, equals(original.type));
      expect(restored.value, equals(original.value));
      expect(restored.length, equals(original.length));
    });

    test('with value for link type', () {
      const span = TextSpan(
        start: 0,
        end: 5,
        type: TextSpanType.link,
        value: 'https://example.com/page',
      );
      expect(span.type, equals(TextSpanType.link));
      expect(span.value, equals('https://example.com/page'));
    });
  });

  // =========================================================================
  // TextBlock
  // =========================================================================
  group('TextBlock', () {
    test('fromJson constructs paragraph type by default', () {
      final json = {
        'type': 'text',
        'id': 'p1',
        'text': 'Hello paragraph',
      };
      final block = TextBlock.fromJson(json);
      expect(block.id, equals('p1'));
      expect(block.text, equals('Hello paragraph'));
      expect(block.type, equals(TextBlockType.paragraph));
      expect(block.headingLevel, isNull);
      expect(block.language, isNull);
      expect(block.spans, isNull);
      expect(block.location, isNull);
      expect(block.metadata, isNull);
    });

    test('fromJson constructs heading with headingLevel', () {
      final json = {
        'type': 'text',
        'id': 'h1',
        'text': 'Chapter Title',
        'blockType': 'heading',
        'headingLevel': 2,
      };
      final block = TextBlock.fromJson(json);
      expect(block.type, equals(TextBlockType.heading));
      expect(block.headingLevel, equals(2));
    });

    test('fromJson constructs code block with language', () {
      final json = {
        'type': 'text',
        'id': 'c1',
        'text': 'void main() {}',
        'blockType': 'code',
        'language': 'dart',
      };
      final block = TextBlock.fromJson(json);
      expect(block.type, equals(TextBlockType.code));
      expect(block.language, equals('dart'));
    });

    test('fromJson with spans list', () {
      final json = {
        'type': 'text',
        'id': 'p2',
        'text': 'bold and italic',
        'spans': [
          {'start': 0, 'end': 4, 'type': 'bold'},
          {'start': 9, 'end': 15, 'type': 'italic'},
        ],
      };
      final block = TextBlock.fromJson(json);
      expect(block.spans, isNotNull);
      expect(block.spans!.length, equals(2));
      expect(block.spans![0].type, equals(TextSpanType.bold));
      expect(block.spans![1].type, equals(TextSpanType.italic));
    });

    test('fromJson with location and metadata', () {
      final json = {
        'type': 'text',
        'id': 'p3',
        'text': 'Located text',
        'location': {
          'pageNumber': 3,
          'lineNumber': 42,
          'charOffset': 100,
          'charLength': 12,
        },
        'metadata': {'source': 'pdf', 'confidence': 0.95},
      };
      final block = TextBlock.fromJson(json);
      expect(block.location, isNotNull);
      expect(block.location!.pageNumber, equals(3));
      expect(block.location!.lineNumber, equals(42));
      expect(block.location!.charOffset, equals(100));
      expect(block.location!.charLength, equals(12));
      expect(block.metadata, isNotNull);
      expect(block.metadata!['source'], equals('pdf'));
    });

    test('toJson serializes all fields', () {
      const block = TextBlock(
        id: 'h2',
        text: 'Section Header',
        type: TextBlockType.heading,
        headingLevel: 3,
        language: null,
        location: SourceLocation(pageNumber: 1, charOffset: 50),
        metadata: {'tag': 'important'},
        spans: [TextSpan(start: 0, end: 7, type: TextSpanType.bold)],
      );
      final json = block.toJson();
      expect(json['type'], equals('text'));
      expect(json['id'], equals('h2'));
      expect(json['text'], equals('Section Header'));
      expect(json['blockType'], equals('heading'));
      expect(json['headingLevel'], equals(3));
      expect(json['location'], isNotNull);
      expect(json['metadata'], isNotNull);
      expect(json['spans'], isNotNull);
      expect((json['spans'] as List).length, equals(1));
    });

    test('toJson omits null optional fields', () {
      const block = TextBlock(id: 'p1', text: 'Simple');
      final json = block.toJson();
      expect(json.containsKey('headingLevel'), isFalse);
      expect(json.containsKey('language'), isFalse);
      expect(json.containsKey('spans'), isFalse);
      expect(json.containsKey('location'), isFalse);
      expect(json.containsKey('metadata'), isFalse);
    });

    test('round-trip fromJson(toJson()) preserves all fields', () {
      const original = TextBlock(
        id: 'rt1',
        text: 'Round trip text',
        type: TextBlockType.code,
        language: 'python',
        headingLevel: null,
        location: SourceLocation(pageNumber: 2, lineNumber: 10),
        metadata: {'key': 'val'},
        spans: [
          TextSpan(
            start: 0,
            end: 5,
            type: TextSpanType.link,
            value: 'https://x.com',
          ),
        ],
      );
      final restored = TextBlock.fromJson(original.toJson());
      expect(restored.id, equals(original.id));
      expect(restored.text, equals(original.text));
      expect(restored.type, equals(original.type));
      expect(restored.language, equals(original.language));
      expect(restored.location!.pageNumber,
          equals(original.location!.pageNumber));
      expect(restored.metadata!['key'], equals('val'));
      expect(restored.spans!.length, equals(1));
      expect(restored.spans!.first.value, equals('https://x.com'));
    });

    test('copyWith changes one field, preserves others', () {
      const original = TextBlock(
        id: 'p1',
        text: 'Original text',
        type: TextBlockType.heading,
        headingLevel: 2,
        language: null,
        location: SourceLocation(pageNumber: 1),
        metadata: {'a': 1},
      );
      final modified = original.copyWith(text: 'Changed text');
      expect(modified.text, equals('Changed text'));
      expect(modified.id, equals('p1'));
      expect(modified.type, equals(TextBlockType.heading));
      expect(modified.headingLevel, equals(2));
      expect(modified.location!.pageNumber, equals(1));
      expect(modified.metadata!['a'], equals(1));
    });

    test('copyWith preserves text when not specified', () {
      const original = TextBlock(
        id: 'p1',
        text: 'Original text',
        type: TextBlockType.paragraph,
      );
      final modified = original.copyWith(type: TextBlockType.heading);
      expect(modified.text, equals('Original text'));
      expect(modified.type, equals(TextBlockType.heading));
    });

    test('partType returns DocumentPartType.text', () {
      const block = TextBlock(id: 'x', text: 'y');
      expect(block.partType, equals(DocumentPartType.text));
    });
  });

  // =========================================================================
  // TableCell
  // =========================================================================
  group('TableCell', () {
    test('fromJson with text field', () {
      final json = {'text': 'Cell value', 'type': 'data'};
      final cell = TableCell.fromJson(json);
      expect(cell.text, equals('Cell value'));
      expect(cell.type, equals(CellType.data));
    });

    test('fromJson with content field fallback', () {
      final json = {'content': 'Fallback content'};
      final cell = TableCell.fromJson(json);
      expect(cell.text, equals('Fallback content'));
    });

    test('fromJson with empty text when neither text nor content', () {
      final json = <String, dynamic>{};
      final cell = TableCell.fromJson(json);
      expect(cell.text, equals(''));
    });

    test('fromJson with isHeader bool fallback', () {
      final json = {'text': 'H', 'isHeader': true};
      final cell = TableCell.fromJson(json);
      expect(cell.type, equals(CellType.header));
      expect(cell.isHeader, isTrue);
    });

    test('fromJson with isHeader false', () {
      final json = {'text': 'D', 'isHeader': false};
      final cell = TableCell.fromJson(json);
      expect(cell.type, equals(CellType.data));
      expect(cell.isHeader, isFalse);
    });

    test('fromJson with explicit type overrides isHeader', () {
      final json = {'text': 'X', 'type': 'header', 'isHeader': false};
      final cell = TableCell.fromJson(json);
      expect(cell.type, equals(CellType.header));
    });

    test('isHeader getter returns true for header type', () {
      const cell = TableCell(text: 'H', type: CellType.header);
      expect(cell.isHeader, isTrue);
    });

    test('isHeader getter returns false for data type', () {
      const cell = TableCell(text: 'D');
      expect(cell.isHeader, isFalse);
    });

    test('toJson includes non-default rowSpan and colSpan', () {
      const cell = TableCell(text: 'Merged', rowSpan: 2, colSpan: 3);
      final json = cell.toJson();
      expect(json['rowSpan'], equals(2));
      expect(json['colSpan'], equals(3));
    });

    test('toJson omits default rowSpan and colSpan', () {
      const cell = TableCell(text: 'Normal');
      final json = cell.toJson();
      expect(json.containsKey('rowSpan'), isFalse);
      expect(json.containsKey('colSpan'), isFalse);
    });

    test('toJson includes dataType when set', () {
      const cell = TableCell(text: '42', dataType: 'number');
      final json = cell.toJson();
      expect(json['dataType'], equals('number'));
    });

    test('toJson omits null dataType', () {
      const cell = TableCell(text: 'plain');
      final json = cell.toJson();
      expect(json.containsKey('dataType'), isFalse);
    });

    test('round-trip fromJson(toJson()) preserves all fields', () {
      const original = TableCell(
        text: 'Data',
        rowSpan: 3,
        colSpan: 2,
        type: CellType.header,
        dataType: 'currency',
      );
      final restored = TableCell.fromJson(original.toJson());
      expect(restored.text, equals(original.text));
      expect(restored.rowSpan, equals(original.rowSpan));
      expect(restored.colSpan, equals(original.colSpan));
      expect(restored.type, equals(original.type));
      expect(restored.dataType, equals(original.dataType));
    });
  });

  // =========================================================================
  // TableRow
  // =========================================================================
  group('TableRow', () {
    test('fromJson constructs with cells', () {
      final json = {
        'cells': [
          {'text': 'A', 'type': 'data'},
          {'text': 'B', 'type': 'header'},
        ],
        'isHeader': true,
      };
      final row = TableRow.fromJson(json);
      expect(row.cells.length, equals(2));
      expect(row.cells[0].text, equals('A'));
      expect(row.cells[1].text, equals('B'));
      expect(row.isHeader, isTrue);
    });

    test('fromJson defaults to empty cells and isHeader false', () {
      final json = <String, dynamic>{};
      final row = TableRow.fromJson(json);
      expect(row.cells, isEmpty);
      expect(row.isHeader, isFalse);
    });

    test('toJson serializes cells and isHeader', () {
      const row = TableRow(
        cells: [TableCell(text: 'X'), TableCell(text: 'Y')],
        isHeader: true,
      );
      final json = row.toJson();
      expect((json['cells'] as List).length, equals(2));
      expect(json['isHeader'], isTrue);
    });

    test('toJson omits isHeader when false', () {
      const row = TableRow(cells: [TableCell(text: 'Z')]);
      final json = row.toJson();
      expect(json.containsKey('isHeader'), isFalse);
    });

    test('round-trip fromJson(toJson()) preserves all fields', () {
      const original = TableRow(
        cells: [
          TableCell(text: 'C1', type: CellType.header),
          TableCell(text: 'C2', rowSpan: 2),
        ],
        isHeader: true,
      );
      final restored = TableRow.fromJson(original.toJson());
      expect(restored.cells.length, equals(2));
      expect(restored.cells[0].text, equals('C1'));
      expect(restored.cells[0].type, equals(CellType.header));
      expect(restored.cells[1].rowSpan, equals(2));
      expect(restored.isHeader, isTrue);
    });
  });

  // =========================================================================
  // TableBlock
  // =========================================================================
  group('TableBlock', () {
    test('fromJson constructs with header and data rows', () {
      final json = {
        'type': 'table',
        'id': 't1',
        'rows': [
          {
            'cells': [
              {'text': 'Name', 'type': 'header'},
              {'text': 'Age', 'type': 'header'},
            ],
            'isHeader': true,
          },
          {
            'cells': [
              {'text': 'Alice'},
              {'text': '30'},
            ],
          },
        ],
        'rowCount': 2,
        'columnCount': 2,
        'caption': 'People',
      };
      final block = TableBlock.fromJson(json);
      expect(block.id, equals('t1'));
      expect(block.rows.length, equals(2));
      expect(block.rowCount, equals(2));
      expect(block.columnCount, equals(2));
      expect(block.caption, equals('People'));
      expect(block.rows[0].isHeader, isTrue);
      expect(block.rows[0].cells[0].text, equals('Name'));
      expect(block.rows[1].cells[0].text, equals('Alice'));
    });

    test('toJson serializes all fields', () {
      const block = TableBlock(
        id: 't2',
        rows: [
          TableRow(
            cells: [TableCell(text: 'H1'), TableCell(text: 'H2')],
            isHeader: true,
          ),
          TableRow(cells: [TableCell(text: 'D1'), TableCell(text: 'D2')]),
        ],
        rowCount: 2,
        columnCount: 2,
        caption: 'Test table',
        location: SourceLocation(pageNumber: 5),
        metadata: {'source': 'html'},
      );
      final json = block.toJson();
      expect(json['type'], equals('table'));
      expect(json['id'], equals('t2'));
      expect((json['rows'] as List).length, equals(2));
      expect(json['rowCount'], equals(2));
      expect(json['columnCount'], equals(2));
      expect(json['caption'], equals('Test table'));
      expect(json['location'], isNotNull);
      expect(json['metadata'], isNotNull);
    });

    test('toJson omits null optional fields', () {
      const block = TableBlock(
        id: 't3',
        rows: [],
        rowCount: 0,
        columnCount: 0,
      );
      final json = block.toJson();
      expect(json.containsKey('caption'), isFalse);
      expect(json.containsKey('location'), isFalse);
      expect(json.containsKey('metadata'), isFalse);
    });

    test('round-trip fromJson(toJson()) preserves all fields', () {
      const original = TableBlock(
        id: 'trt',
        rows: [
          TableRow(
            cells: [
              TableCell(text: 'H', type: CellType.header, rowSpan: 1),
            ],
            isHeader: true,
          ),
          TableRow(
            cells: [
              TableCell(text: 'V', dataType: 'number'),
            ],
          ),
        ],
        rowCount: 2,
        columnCount: 1,
        caption: 'Round-trip table',
        location: SourceLocation(pageNumber: 7, charOffset: 200),
      );
      final restored = TableBlock.fromJson(original.toJson());
      expect(restored.id, equals(original.id));
      expect(restored.rows.length, equals(original.rows.length));
      expect(restored.rowCount, equals(original.rowCount));
      expect(restored.columnCount, equals(original.columnCount));
      expect(restored.caption, equals(original.caption));
      expect(restored.location!.pageNumber, equals(7));
      expect(restored.rows[0].isHeader, isTrue);
      expect(restored.rows[1].cells[0].dataType, equals('number'));
    });

    test('toMarkdown output format', () {
      const block = TableBlock(
        id: 'md1',
        rows: [
          TableRow(cells: [TableCell(text: 'Name'), TableCell(text: 'Value')]),
          TableRow(cells: [TableCell(text: 'foo'), TableCell(text: 'bar')]),
          TableRow(cells: [TableCell(text: 'baz'), TableCell(text: 'qux')]),
        ],
        rowCount: 3,
        columnCount: 2,
      );
      final md = block.toMarkdown();
      expect(md, contains('| Name | Value |'));
      expect(md, contains('| --- | --- |'));
      expect(md, contains('| foo | bar |'));
      expect(md, contains('| baz | qux |'));
    });

    test('toMarkdown returns empty for empty table', () {
      const block = TableBlock(
        id: 'empty',
        rows: [],
        rowCount: 0,
        columnCount: 0,
      );
      expect(block.toMarkdown(), isEmpty);
    });

    test('toCsv output format', () {
      const block = TableBlock(
        id: 'csv1',
        rows: [
          TableRow(cells: [TableCell(text: 'A'), TableCell(text: 'B')]),
          TableRow(cells: [TableCell(text: '1'), TableCell(text: '2')]),
        ],
        rowCount: 2,
        columnCount: 2,
      );
      final csv = block.toCsv();
      expect(csv, contains('A,B'));
      expect(csv, contains('1,2'));
    });

    test('toCsv escapes commas', () {
      const block = TableBlock(
        id: 'csv2',
        rows: [
          TableRow(cells: [TableCell(text: 'hello, world')]),
        ],
        rowCount: 1,
        columnCount: 1,
      );
      final csv = block.toCsv();
      expect(csv, contains('"hello, world"'));
    });

    test('toCsv escapes quotes', () {
      const block = TableBlock(
        id: 'csv3',
        rows: [
          TableRow(cells: [TableCell(text: 'say "hi"')]),
        ],
        rowCount: 1,
        columnCount: 1,
      );
      final csv = block.toCsv();
      expect(csv, contains('"say ""hi"""'));
    });

    test('toCsv escapes newlines', () {
      const block = TableBlock(
        id: 'csv4',
        rows: [
          TableRow(cells: [TableCell(text: 'line1\nline2')]),
        ],
        rowCount: 1,
        columnCount: 1,
      );
      final csv = block.toCsv();
      expect(csv, contains('"line1\nline2"'));
    });

    test('toCsv returns empty for empty table', () {
      const block = TableBlock(
        id: 'csvE',
        rows: [],
        rowCount: 0,
        columnCount: 0,
      );
      expect(block.toCsv(), isEmpty);
    });

    test('copyWith changes one field, preserves others', () {
      const original = TableBlock(
        id: 't_copy',
        rows: [
          TableRow(cells: [TableCell(text: 'A')]),
        ],
        rowCount: 1,
        columnCount: 1,
        caption: 'Original caption',
      );
      final modified = original.copyWith(caption: 'New caption');
      expect(modified.id, equals('t_copy'));
      expect(modified.rows.length, equals(1));
      expect(modified.rowCount, equals(1));
      expect(modified.columnCount, equals(1));
      expect(modified.caption, equals('New caption'));
    });

    test('copyWith preserves caption when not specified', () {
      const original = TableBlock(
        id: 't_cap',
        rows: [TableRow(cells: [TableCell(text: 'A')])],
        rowCount: 1,
        columnCount: 1,
        caption: 'Original caption',
      );
      final modified = original.copyWith(rowCount: 5);
      expect(modified.caption, equals('Original caption'));
      expect(modified.rowCount, equals(5));
    });

    test('partType returns DocumentPartType.table', () {
      const block = TableBlock(
        id: 'x',
        rows: [],
        rowCount: 0,
        columnCount: 0,
      );
      expect(block.partType, equals(DocumentPartType.table));
    });
  });

  // =========================================================================
  // ListItem
  // =========================================================================
  group('ListItem', () {
    test('fromJson with text field', () {
      final json = {'text': 'Item text'};
      final item = ListItem.fromJson(json);
      expect(item.text, equals('Item text'));
      expect(item.checked, isNull);
      expect(item.children, isNull);
    });

    test('fromJson with content fallback', () {
      final json = {'content': 'Fallback content'};
      final item = ListItem.fromJson(json);
      expect(item.text, equals('Fallback content'));
    });

    test('fromJson with empty text when neither text nor content', () {
      final json = <String, dynamic>{};
      final item = ListItem.fromJson(json);
      expect(item.text, equals(''));
    });

    test('fromJson with checked flag', () {
      final json = {'text': 'Task', 'checked': true};
      final item = ListItem.fromJson(json);
      expect(item.checked, isTrue);
    });

    test('fromJson with children (nested)', () {
      final json = {
        'text': 'Parent',
        'children': [
          {'text': 'Child 1'},
          {'text': 'Child 2', 'checked': false},
        ],
      };
      final item = ListItem.fromJson(json);
      expect(item.children, isNotNull);
      expect(item.children!.length, equals(2));
      expect(item.children![0].text, equals('Child 1'));
      expect(item.children![1].checked, isFalse);
    });

    test('toJson serializes all fields', () {
      const item = ListItem(
        text: 'Task item',
        checked: false,
        children: [ListItem(text: 'Sub')],
      );
      final json = item.toJson();
      expect(json['text'], equals('Task item'));
      expect(json['checked'], isFalse);
      expect(json['children'], isNotNull);
      expect((json['children'] as List).length, equals(1));
    });

    test('toJson omits null fields', () {
      const item = ListItem(text: 'Simple');
      final json = item.toJson();
      expect(json.containsKey('checked'), isFalse);
      expect(json.containsKey('children'), isFalse);
    });

    test('round-trip fromJson(toJson()) preserves all fields', () {
      const original = ListItem(
        text: 'Task',
        checked: true,
        children: [
          ListItem(text: 'Sub A'),
          ListItem(text: 'Sub B', checked: false),
        ],
      );
      final restored = ListItem.fromJson(original.toJson());
      expect(restored.text, equals(original.text));
      expect(restored.checked, equals(original.checked));
      expect(restored.children!.length, equals(2));
      expect(restored.children![0].text, equals('Sub A'));
      expect(restored.children![1].checked, isFalse);
    });
  });

  // =========================================================================
  // ListBlock
  // =========================================================================
  group('ListBlock', () {
    test('fromJson constructs ordered list with startNumber', () {
      final json = {
        'type': 'list',
        'id': 'ol1',
        'listType': 'ordered',
        'items': [
          {'text': 'First'},
          {'text': 'Second'},
        ],
        'startNumber': 3,
      };
      final block = ListBlock.fromJson(json);
      expect(block.id, equals('ol1'));
      expect(block.type, equals(ListType.ordered));
      expect(block.items.length, equals(2));
      expect(block.startNumber, equals(3));
    });

    test('fromJson constructs unordered list', () {
      final json = {
        'type': 'list',
        'id': 'ul1',
        'listType': 'unordered',
        'items': [
          {'text': 'Bullet A'},
          {'text': 'Bullet B'},
        ],
      };
      final block = ListBlock.fromJson(json);
      expect(block.type, equals(ListType.unordered));
      expect(block.startNumber, isNull);
    });

    test('fromJson constructs checklist type', () {
      final json = {
        'type': 'list',
        'id': 'cl1',
        'listType': 'checklist',
        'items': [
          {'text': 'Done', 'checked': true},
          {'text': 'Pending', 'checked': false},
        ],
      };
      final block = ListBlock.fromJson(json);
      expect(block.type, equals(ListType.checklist));
      expect(block.items[0].checked, isTrue);
      expect(block.items[1].checked, isFalse);
    });

    test('toJson serializes all fields', () {
      const block = ListBlock(
        id: 'list_s',
        type: ListType.ordered,
        items: [
          ListItem(text: 'A'),
          ListItem(text: 'B'),
        ],
        startNumber: 10,
        location: SourceLocation(pageNumber: 2),
        metadata: {'style': 'roman'},
      );
      final json = block.toJson();
      expect(json['type'], equals('list'));
      expect(json['id'], equals('list_s'));
      expect(json['listType'], equals('ordered'));
      expect((json['items'] as List).length, equals(2));
      expect(json['startNumber'], equals(10));
      expect(json['location'], isNotNull);
      expect(json['metadata'], isNotNull);
    });

    test('toJson omits null optional fields', () {
      const block = ListBlock(
        id: 'lst',
        type: ListType.unordered,
        items: [ListItem(text: 'X')],
      );
      final json = block.toJson();
      expect(json.containsKey('startNumber'), isFalse);
      expect(json.containsKey('location'), isFalse);
      expect(json.containsKey('metadata'), isFalse);
    });

    test('round-trip fromJson(toJson()) preserves all fields', () {
      const original = ListBlock(
        id: 'lrt',
        type: ListType.checklist,
        items: [
          ListItem(text: 'Task 1', checked: true),
          ListItem(
            text: 'Task 2',
            checked: false,
            children: [ListItem(text: 'Sub')],
          ),
        ],
        startNumber: null,
        location: SourceLocation(lineNumber: 20),
        metadata: {'tag': 'todo'},
      );
      final restored = ListBlock.fromJson(original.toJson());
      expect(restored.id, equals(original.id));
      expect(restored.type, equals(original.type));
      expect(restored.items.length, equals(2));
      expect(restored.items[0].checked, isTrue);
      expect(restored.items[1].children!.length, equals(1));
      expect(restored.startNumber, isNull);
      expect(restored.location!.lineNumber, equals(20));
      expect(restored.metadata!['tag'], equals('todo'));
    });

    test('copyWith changes one field, preserves others', () {
      const original = ListBlock(
        id: 'lc',
        type: ListType.unordered,
        items: [ListItem(text: 'Item')],
        startNumber: null,
      );
      final modified = original.copyWith(type: ListType.ordered, startNumber: 5);
      expect(modified.id, equals('lc'));
      expect(modified.type, equals(ListType.ordered));
      expect(modified.startNumber, equals(5));
      expect(modified.items.length, equals(1));
    });

    test('copyWith preserves type when not specified', () {
      const original = ListBlock(
        id: 'lc2',
        type: ListType.checklist,
        items: [ListItem(text: 'Task')],
      );
      final modified = original.copyWith(startNumber: 10);
      expect(modified.type, equals(ListType.checklist));
      expect(modified.startNumber, equals(10));
    });

    test('partType returns DocumentPartType.list', () {
      const block = ListBlock(
        id: 'x',
        type: ListType.unordered,
        items: [],
      );
      expect(block.partType, equals(DocumentPartType.list));
    });
  });

  // =========================================================================
  // KeyValueBlock
  // =========================================================================
  group('KeyValueBlock', () {
    test('fromJson constructs with all fields', () {
      final json = {
        'type': 'keyValue',
        'id': 'kv1',
        'key': 'email',
        'value': 'test@example.com',
        'normalizedValue': 'test@example.com',
        'valueType': 'string',
        'extractor': 'rule',
        'confidence': 0.95,
        'location': {'lineNumber': 5},
        'metadata': {'source': 'form'},
      };
      final block = KeyValueBlock.fromJson(json);
      expect(block.id, equals('kv1'));
      expect(block.key, equals('email'));
      expect(block.value, equals('test@example.com'));
      expect(block.normalizedValue, equals('test@example.com'));
      expect(block.valueType, equals(FragmentValueType.string));
      expect(block.extractor, equals(ExtractorType.rule));
      expect(block.confidence, equals(0.95));
      expect(block.location!.lineNumber, equals(5));
      expect(block.metadata!['source'], equals('form'));
    });

    test('fromJson uses default values', () {
      final json = {
        'type': 'keyValue',
        'id': 'kv2',
        'key': 'amount',
        'value': '100',
      };
      final block = KeyValueBlock.fromJson(json);
      expect(block.confidence, equals(0.8));
      expect(block.extractor, equals(ExtractorType.rule));
      expect(block.valueType, equals(FragmentValueType.string));
      expect(block.normalizedValue, isNull);
    });

    test('toJson serializes all fields', () {
      const block = KeyValueBlock(
        id: 'kv3',
        key: 'price',
        value: '\$49.99',
        normalizedValue: 49.99,
        valueType: FragmentValueType.currency,
        extractor: ExtractorType.llm,
        confidence: 0.92,
      );
      final json = block.toJson();
      expect(json['type'], equals('keyValue'));
      expect(json['id'], equals('kv3'));
      expect(json['key'], equals('price'));
      expect(json['value'], equals('\$49.99'));
      expect(json['normalizedValue'], equals(49.99));
      expect(json['valueType'], equals('currency'));
      expect(json['extractor'], equals('llm'));
      expect(json['confidence'], equals(0.92));
    });

    test('toJson omits null normalizedValue', () {
      const block = KeyValueBlock(id: 'kv4', key: 'k', value: 'v');
      final json = block.toJson();
      expect(json.containsKey('normalizedValue'), isFalse);
    });

    test('round-trip fromJson(toJson()) preserves all fields', () {
      const original = KeyValueBlock(
        id: 'kvrt',
        key: 'date',
        value: '2024-01-15',
        normalizedValue: '2024-01-15T00:00:00Z',
        valueType: FragmentValueType.date,
        extractor: ExtractorType.ocr,
        confidence: 0.75,
        location: SourceLocation(charOffset: 50, charLength: 10),
        metadata: {'field_id': 'f1'},
      );
      final restored = KeyValueBlock.fromJson(original.toJson());
      expect(restored.id, equals(original.id));
      expect(restored.key, equals(original.key));
      expect(restored.value, equals(original.value));
      expect(restored.normalizedValue, equals(original.normalizedValue));
      expect(restored.valueType, equals(original.valueType));
      expect(restored.extractor, equals(original.extractor));
      expect(restored.confidence, equals(original.confidence));
      expect(restored.location!.charOffset, equals(50));
      expect(restored.location!.charLength, equals(10));
      expect(restored.metadata!['field_id'], equals('f1'));
    });

    test('copyWith changes one field, preserves others', () {
      const original = KeyValueBlock(
        id: 'kvc',
        key: 'Name',
        value: 'Alice',
        confidence: 0.9,
        extractor: ExtractorType.rule,
        valueType: FragmentValueType.string,
      );
      final modified = original.copyWith(confidence: 0.5);
      expect(modified.id, equals('kvc'));
      expect(modified.key, equals('Name'));
      expect(modified.value, equals('Alice'));
      expect(modified.confidence, equals(0.5));
      expect(modified.extractor, equals(ExtractorType.rule));
      expect(modified.valueType, equals(FragmentValueType.string));
    });

    test('toFragment() creates Fragment with correct fields', () {
      const block = KeyValueBlock(
        id: 'kv_frag',
        key: 'total',
        value: '250.00',
        normalizedValue: 250.0,
        valueType: FragmentValueType.currency,
        extractor: ExtractorType.llm,
        confidence: 0.88,
        location: SourceLocation(charOffset: 100, charLength: 6, lineNumber: 3),
      );
      final fragment = block.toFragment('ev123', workspaceId: 'ws1');
      expect(fragment.fragmentId, equals('ev123_kv_frag'));
      expect(fragment.workspaceId, equals('ws1'));
      expect(fragment.evidenceId, equals('ev123'));
      expect(fragment.confidence, equals(0.88));
      expect(fragment.extractor, equals(ExtractorType.llm));
      expect(fragment.fields['field'], equals('total'));
      expect(fragment.fields['value'], equals('250.00'));
      expect(fragment.fields['normalizedValue'], equals(250.0));
      expect(fragment.fields['valueType'], equals('currency'));
      expect(fragment.fields['position'], isNotNull);
      final position = fragment.fields['position'] as Map<String, dynamic>;
      expect(position['start'], equals(100));
      expect(position['end'], equals(106));
      expect(position['line'], equals(3));
    });

    test('toFragment() uses default workspaceId', () {
      const block = KeyValueBlock(id: 'kv_def', key: 'k', value: 'v');
      final fragment = block.toFragment('ev1');
      expect(fragment.workspaceId, equals('default'));
    });

    test('toFragment() omits position when location is null', () {
      const block = KeyValueBlock(id: 'kv_noloc', key: 'k', value: 'v');
      final fragment = block.toFragment('ev1');
      expect(fragment.fields.containsKey('position'), isFalse);
    });

    test('toFragment() omits normalizedValue when null', () {
      const block = KeyValueBlock(id: 'kv_nonorm', key: 'k', value: 'v');
      final fragment = block.toFragment('ev1');
      expect(fragment.fields.containsKey('normalizedValue'), isFalse);
    });

    test('default confidence is 0.8', () {
      const block = KeyValueBlock(id: 'kv', key: 'k', value: 'v');
      expect(block.confidence, equals(0.8));
    });

    test('default extractor is rule', () {
      const block = KeyValueBlock(id: 'kv', key: 'k', value: 'v');
      expect(block.extractor, equals(ExtractorType.rule));
    });

    test('partType returns DocumentPartType.keyValue', () {
      const block = KeyValueBlock(id: 'x', key: 'k', value: 'v');
      expect(block.partType, equals(DocumentPartType.keyValue));
    });
  });

  // =========================================================================
  // ImageBlock
  // =========================================================================
  group('ImageBlock', () {
    test('fromJson constructs with all optional fields', () {
      final json = {
        'type': 'image',
        'id': 'img1',
        'assetRef': 'file:///photo.jpg',
        'width': 1920,
        'height': 1080,
        'format': 'jpeg',
        'altText': 'A scenic view',
        'caption': 'Mountain landscape',
        'ocrText': 'Sign reads: Welcome',
        'visionDescription': 'A mountain with snow on top',
        'location': {'pageNumber': 4},
        'metadata': {'dpi': 300},
      };
      final block = ImageBlock.fromJson(json);
      expect(block.id, equals('img1'));
      expect(block.assetRef, equals('file:///photo.jpg'));
      expect(block.width, equals(1920));
      expect(block.height, equals(1080));
      expect(block.format, equals('jpeg'));
      expect(block.altText, equals('A scenic view'));
      expect(block.caption, equals('Mountain landscape'));
      expect(block.ocrText, equals('Sign reads: Welcome'));
      expect(block.visionDescription, equals('A mountain with snow on top'));
      expect(block.location!.pageNumber, equals(4));
      expect(block.metadata!['dpi'], equals(300));
    });

    test('fromJson constructs with minimal fields', () {
      final json = {
        'type': 'image',
        'id': 'img2',
        'assetRef': 'mem://abc',
      };
      final block = ImageBlock.fromJson(json);
      expect(block.id, equals('img2'));
      expect(block.assetRef, equals('mem://abc'));
      expect(block.width, isNull);
      expect(block.height, isNull);
      expect(block.format, isNull);
      expect(block.altText, isNull);
      expect(block.caption, isNull);
      expect(block.ocrText, isNull);
      expect(block.visionDescription, isNull);
    });

    test('toJson serializes all fields', () {
      const block = ImageBlock(
        id: 'img3',
        assetRef: 'ref',
        width: 640,
        height: 480,
        format: 'png',
        altText: 'alt',
        caption: 'cap',
        ocrText: 'ocr',
        visionDescription: 'vision',
        location: SourceLocation(pageNumber: 1),
        metadata: {'k': 'v'},
      );
      final json = block.toJson();
      expect(json['type'], equals('image'));
      expect(json['id'], equals('img3'));
      expect(json['assetRef'], equals('ref'));
      expect(json['width'], equals(640));
      expect(json['height'], equals(480));
      expect(json['format'], equals('png'));
      expect(json['altText'], equals('alt'));
      expect(json['caption'], equals('cap'));
      expect(json['ocrText'], equals('ocr'));
      expect(json['visionDescription'], equals('vision'));
      expect(json['location'], isNotNull);
      expect(json['metadata'], isNotNull);
    });

    test('toJson omits null optional fields', () {
      const block = ImageBlock(id: 'img4', assetRef: 'ref');
      final json = block.toJson();
      expect(json.containsKey('width'), isFalse);
      expect(json.containsKey('height'), isFalse);
      expect(json.containsKey('format'), isFalse);
      expect(json.containsKey('altText'), isFalse);
      expect(json.containsKey('caption'), isFalse);
      expect(json.containsKey('ocrText'), isFalse);
      expect(json.containsKey('visionDescription'), isFalse);
      expect(json.containsKey('location'), isFalse);
      expect(json.containsKey('metadata'), isFalse);
    });

    test('round-trip fromJson(toJson()) preserves all fields', () {
      const original = ImageBlock(
        id: 'imgrt',
        assetRef: 'file:///rt.png',
        width: 300,
        height: 200,
        format: 'png',
        altText: 'Alt text',
        caption: 'Caption text',
        ocrText: 'OCR extracted',
        visionDescription: 'Vision desc',
        location: SourceLocation(pageNumber: 3, charOffset: 500),
        metadata: {'quality': 'high'},
      );
      final restored = ImageBlock.fromJson(original.toJson());
      expect(restored.id, equals(original.id));
      expect(restored.assetRef, equals(original.assetRef));
      expect(restored.width, equals(original.width));
      expect(restored.height, equals(original.height));
      expect(restored.format, equals(original.format));
      expect(restored.altText, equals(original.altText));
      expect(restored.caption, equals(original.caption));
      expect(restored.ocrText, equals(original.ocrText));
      expect(restored.visionDescription, equals(original.visionDescription));
      expect(restored.location!.pageNumber, equals(3));
      expect(restored.metadata!['quality'], equals('high'));
    });

    test('hasOcr returns true when ocrText is set', () {
      const block = ImageBlock(
        id: 'img',
        assetRef: 'ref',
        ocrText: 'Some text',
      );
      expect(block.hasOcr, isTrue);
    });

    test('hasOcr returns false when ocrText is null', () {
      const block = ImageBlock(id: 'img', assetRef: 'ref');
      expect(block.hasOcr, isFalse);
    });

    test('hasVision returns true when visionDescription is set', () {
      const block = ImageBlock(
        id: 'img',
        assetRef: 'ref',
        visionDescription: 'A cat',
      );
      expect(block.hasVision, isTrue);
    });

    test('hasVision returns false when visionDescription is null', () {
      const block = ImageBlock(id: 'img', assetRef: 'ref');
      expect(block.hasVision, isFalse);
    });

    test('copyWith changes one field, preserves others', () {
      const original = ImageBlock(
        id: 'imgc',
        assetRef: 'original_ref',
        width: 800,
        height: 600,
        format: 'png',
      );
      final modified = original.copyWith(ocrText: 'New OCR text');
      expect(modified.id, equals('imgc'));
      expect(modified.assetRef, equals('original_ref'));
      expect(modified.width, equals(800));
      expect(modified.height, equals(600));
      expect(modified.format, equals('png'));
      expect(modified.ocrText, equals('New OCR text'));
      expect(modified.hasOcr, isTrue);
    });

    test('with dimensions and format', () {
      const block = ImageBlock(
        id: 'dim',
        assetRef: 'ref',
        width: 1024,
        height: 768,
        format: 'webp',
      );
      expect(block.width, equals(1024));
      expect(block.height, equals(768));
      expect(block.format, equals('webp'));
    });

    test('partType returns DocumentPartType.image', () {
      const block = ImageBlock(id: 'x', assetRef: 'r');
      expect(block.partType, equals(DocumentPartType.image));
    });
  });

  // =========================================================================
  // TranscriptSegment
  // =========================================================================
  group('TranscriptSegment', () {
    test('fromJson constructs from JSON map', () {
      final json = {
        'startTimeMs': 1500,
        'endTimeMs': 3000,
        'text': 'Hello world',
        'confidence': 0.95,
        'speaker': 'SPEAKER_01',
      };
      final segment = TranscriptSegment.fromJson(json);
      expect(segment.startTime, equals(const Duration(milliseconds: 1500)));
      expect(segment.endTime, equals(const Duration(milliseconds: 3000)));
      expect(segment.text, equals('Hello world'));
      expect(segment.confidence, equals(0.95));
      expect(segment.speaker, equals('SPEAKER_01'));
    });

    test('fromJson with minimal fields', () {
      final json = {
        'startTimeMs': 0,
        'endTimeMs': 500,
        'text': 'Hi',
      };
      final segment = TranscriptSegment.fromJson(json);
      expect(segment.confidence, isNull);
      expect(segment.speaker, isNull);
    });

    test('toJson serializes duration as milliseconds', () {
      const segment = TranscriptSegment(
        startTime: Duration(seconds: 2, milliseconds: 500),
        endTime: Duration(seconds: 5),
        text: 'Segment text',
        confidence: 0.88,
        speaker: 'SP_00',
      );
      final json = segment.toJson();
      expect(json['startTimeMs'], equals(2500));
      expect(json['endTimeMs'], equals(5000));
      expect(json['text'], equals('Segment text'));
      expect(json['confidence'], equals(0.88));
      expect(json['speaker'], equals('SP_00'));
    });

    test('toJson omits null optional fields', () {
      const segment = TranscriptSegment(
        startTime: Duration.zero,
        endTime: Duration(seconds: 1),
        text: 'X',
      );
      final json = segment.toJson();
      expect(json.containsKey('confidence'), isFalse);
      expect(json.containsKey('speaker'), isFalse);
    });

    test('full round-trip fromJson(toJson()) with confidence and speaker', () {
      const original = TranscriptSegment(
        startTime: Duration(minutes: 1, seconds: 30),
        endTime: Duration(minutes: 1, seconds: 45),
        text: 'Testing round trip',
        confidence: 0.91,
        speaker: 'SPEAKER_02',
      );
      final restored = TranscriptSegment.fromJson(original.toJson());
      expect(restored.startTime, equals(original.startTime));
      expect(restored.endTime, equals(original.endTime));
      expect(restored.text, equals(original.text));
      expect(restored.confidence, equals(original.confidence));
      expect(restored.speaker, equals(original.speaker));
    });

    test('round-trip preserves Duration precision in milliseconds', () {
      const original = TranscriptSegment(
        startTime: Duration(milliseconds: 123),
        endTime: Duration(milliseconds: 456),
        text: 'precise',
      );
      final restored = TranscriptSegment.fromJson(original.toJson());
      expect(
        restored.startTime.inMilliseconds,
        equals(original.startTime.inMilliseconds),
      );
      expect(
        restored.endTime.inMilliseconds,
        equals(original.endTime.inMilliseconds),
      );
    });
  });

  // =========================================================================
  // AudioBlock
  // =========================================================================
  group('AudioBlock', () {
    test('fromJson constructs with all fields', () {
      final json = {
        'type': 'audio',
        'id': 'a1',
        'assetRef': 'file:///clip.wav',
        'durationMs': 300000,
        'format': 'wav',
        'sampleRate': 48000,
        'transcript': 'Full transcript here.',
        'segments': [
          {
            'startTimeMs': 0,
            'endTimeMs': 1000,
            'text': 'Full',
            'confidence': 0.9,
          },
          {
            'startTimeMs': 1000,
            'endTimeMs': 2000,
            'text': 'transcript',
            'speaker': 'SP1',
          },
        ],
        'location': {'pageNumber': 1},
        'metadata': {'channels': 2},
      };
      final block = AudioBlock.fromJson(json);
      expect(block.id, equals('a1'));
      expect(block.assetRef, equals('file:///clip.wav'));
      expect(block.duration, equals(const Duration(milliseconds: 300000)));
      expect(block.format, equals('wav'));
      expect(block.sampleRate, equals(48000));
      expect(block.transcript, equals('Full transcript here.'));
      expect(block.segments, isNotNull);
      expect(block.segments!.length, equals(2));
      expect(block.segments![0].confidence, equals(0.9));
      expect(block.segments![1].speaker, equals('SP1'));
      expect(block.location!.pageNumber, equals(1));
      expect(block.metadata!['channels'], equals(2));
    });

    test('fromJson constructs with minimal fields', () {
      final json = {
        'type': 'audio',
        'id': 'a2',
        'assetRef': 'mem://audio',
      };
      final block = AudioBlock.fromJson(json);
      expect(block.id, equals('a2'));
      expect(block.assetRef, equals('mem://audio'));
      expect(block.duration, isNull);
      expect(block.format, isNull);
      expect(block.sampleRate, isNull);
      expect(block.transcript, isNull);
      expect(block.segments, isNull);
    });

    test('toJson serializes duration as milliseconds', () {
      const block = AudioBlock(
        id: 'a3',
        assetRef: 'ref',
        duration: Duration(minutes: 2, seconds: 30),
        format: 'mp3',
        sampleRate: 44100,
        transcript: 'hello',
        segments: [
          TranscriptSegment(
            startTime: Duration.zero,
            endTime: Duration(seconds: 1),
            text: 'hello',
          ),
        ],
      );
      final json = block.toJson();
      expect(json['type'], equals('audio'));
      expect(json['id'], equals('a3'));
      expect(json['assetRef'], equals('ref'));
      expect(json['durationMs'], equals(150000));
      expect(json['format'], equals('mp3'));
      expect(json['sampleRate'], equals(44100));
      expect(json['transcript'], equals('hello'));
      expect((json['segments'] as List).length, equals(1));
    });

    test('toJson omits null optional fields', () {
      const block = AudioBlock(id: 'a4', assetRef: 'ref');
      final json = block.toJson();
      expect(json.containsKey('durationMs'), isFalse);
      expect(json.containsKey('format'), isFalse);
      expect(json.containsKey('sampleRate'), isFalse);
      expect(json.containsKey('transcript'), isFalse);
      expect(json.containsKey('segments'), isFalse);
      expect(json.containsKey('location'), isFalse);
      expect(json.containsKey('metadata'), isFalse);
    });

    test('round-trip fromJson(toJson()) preserves all fields', () {
      const original = AudioBlock(
        id: 'art',
        assetRef: 'file:///rt.mp3',
        duration: Duration(seconds: 90),
        format: 'mp3',
        sampleRate: 22050,
        transcript: 'Round trip transcript',
        segments: [
          TranscriptSegment(
            startTime: Duration.zero,
            endTime: Duration(seconds: 5),
            text: 'Round trip',
            confidence: 0.87,
            speaker: 'SPEAKER_00',
          ),
          TranscriptSegment(
            startTime: Duration(seconds: 5),
            endTime: Duration(seconds: 10),
            text: 'transcript',
            confidence: 0.93,
          ),
        ],
        location: SourceLocation(pageNumber: 1, charOffset: 0),
        metadata: {'bitrate': 128},
      );
      final restored = AudioBlock.fromJson(original.toJson());
      expect(restored.id, equals(original.id));
      expect(restored.assetRef, equals(original.assetRef));
      expect(restored.duration, equals(original.duration));
      expect(restored.format, equals(original.format));
      expect(restored.sampleRate, equals(original.sampleRate));
      expect(restored.transcript, equals(original.transcript));
      expect(restored.segments!.length, equals(2));
      expect(restored.segments![0].speaker, equals('SPEAKER_00'));
      expect(restored.segments![1].confidence, equals(0.93));
      expect(restored.location!.pageNumber, equals(1));
      expect(restored.metadata!['bitrate'], equals(128));
    });

    test('copyWith changes one field, preserves others', () {
      const original = AudioBlock(
        id: 'ac',
        assetRef: 'original_ref',
        duration: Duration(minutes: 3),
        format: 'ogg',
        sampleRate: 16000,
      );
      final modified = original.copyWith(transcript: 'New transcript');
      expect(modified.id, equals('ac'));
      expect(modified.assetRef, equals('original_ref'));
      expect(modified.duration, equals(const Duration(minutes: 3)));
      expect(modified.format, equals('ogg'));
      expect(modified.sampleRate, equals(16000));
      expect(modified.transcript, equals('New transcript'));
    });

    test('partType returns DocumentPartType.audio', () {
      const block = AudioBlock(id: 'x', assetRef: 'r');
      expect(block.partType, equals(DocumentPartType.audio));
    });
  });

  // =========================================================================
  // DocumentPart.fromJson static dispatch
  // =========================================================================
  group('DocumentPart.fromJson dispatch', () {
    test('text type routes to TextBlock', () {
      final json = {
        'type': 'text',
        'id': 'p1',
        'text': 'Hello',
      };
      final part = DocumentPart.fromJson(json);
      expect(part, isA<TextBlock>());
      expect((part as TextBlock).text, equals('Hello'));
    });

    test('table type routes to TableBlock', () {
      final json = {
        'type': 'table',
        'id': 't1',
        'rows': <dynamic>[],
        'rowCount': 0,
        'columnCount': 0,
      };
      final part = DocumentPart.fromJson(json);
      expect(part, isA<TableBlock>());
      expect((part as TableBlock).id, equals('t1'));
    });

    test('list type routes to ListBlock', () {
      final json = {
        'type': 'list',
        'id': 'l1',
        'listType': 'unordered',
        'items': <dynamic>[],
      };
      final part = DocumentPart.fromJson(json);
      expect(part, isA<ListBlock>());
      expect((part as ListBlock).type, equals(ListType.unordered));
    });

    test('keyValue type routes to KeyValueBlock', () {
      final json = {
        'type': 'keyValue',
        'id': 'kv1',
        'key': 'name',
        'value': 'test',
      };
      final part = DocumentPart.fromJson(json);
      expect(part, isA<KeyValueBlock>());
      expect((part as KeyValueBlock).key, equals('name'));
    });

    test('image type routes to ImageBlock', () {
      final json = {
        'type': 'image',
        'id': 'img1',
        'assetRef': 'ref',
      };
      final part = DocumentPart.fromJson(json);
      expect(part, isA<ImageBlock>());
      expect((part as ImageBlock).assetRef, equals('ref'));
    });

    test('audio type routes to AudioBlock', () {
      final json = {
        'type': 'audio',
        'id': 'a1',
        'assetRef': 'ref',
      };
      final part = DocumentPart.fromJson(json);
      expect(part, isA<AudioBlock>());
      expect((part as AudioBlock).assetRef, equals('ref'));
    });

    test('missing type field throws ArgumentError', () {
      final json = {'id': 'x', 'text': 'no type'};
      expect(
        () => DocumentPart.fromJson(json),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('invalid type field throws', () {
      final json = {'type': 'unknown_type_xyz', 'id': 'x'};
      expect(
        () => DocumentPart.fromJson(json),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
