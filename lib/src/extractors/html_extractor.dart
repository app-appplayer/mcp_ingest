/// HTML/XML extractor.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:uuid/uuid.dart';

import '../document/document_metadata.dart';
import '../document/document_part.dart';
import '../document/document_structure.dart';
import '../document/normalized_document.dart';
import 'extractor.dart';

/// Extracts HTML/XML documents.
class HtmlExtractor extends Extractor {
  @override
  String get id => 'html_dom_v1';

  @override
  Set<String> get supportedTypes => {
        'text/html',
        'application/xhtml+xml',
        'text/xml',
        'application/xml',
      };

  @override
  int get priority => 0;

  @override
  Duration estimateDuration(int fileSize) =>
      Duration(milliseconds: fileSize ~/ 5000); // ~200ms per MB

  @override
  Future<NormalizedDocument> extract(
    Stream<List<int>> input,
    ExtractOptions options,
  ) async {
    final stopwatch = Stopwatch()..start();
    final content = await utf8.decodeStream(input);
    final document = html_parser.parse(content);
    final parts = <DocumentPart>[];
    var partIndex = 0;

    final title = document.querySelector('title')?.text;

    _extractNode(document.body, parts, options, partIndex);

    stopwatch.stop();
    final hash = sha256.convert(utf8.encode(content)).toString();

    return NormalizedDocument(
      id: const Uuid().v4(),
      metadata: DocumentMetadata(
        title: title,
        mimeType: 'text/html',
        sha256: hash,
        fileSize: content.length,
      ),
      parts: parts,
      structure: _buildStructure(document),
      provenance: ExtractionProvenance(
        extractorId: id,
        extractorVersion: '1.0.0',
        extractedAt: DateTime.now(),
        extractionDuration: stopwatch.elapsed,
      ),
    );
  }

  int _extractNode(
    Element? node,
    List<DocumentPart> parts,
    ExtractOptions options,
    int partIndex,
  ) {
    if (node == null) return partIndex;

    for (final child in node.nodes) {
      if (child is Element) {
        switch (child.localName) {
          case 'p':
            final text = child.text.trim();
            if (text.isNotEmpty) {
              parts.add(TextBlock(
                id: 'p$partIndex',
                text: text,
                type: TextBlockType.paragraph,
              ));
              partIndex++;
            }
          case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
            final level = int.parse(child.localName!.substring(1));
            final text = child.text.trim();
            if (text.isNotEmpty) {
              parts.add(TextBlock(
                id: 'h$partIndex',
                text: text,
                type: TextBlockType.heading,
                headingLevel: level,
              ));
              partIndex++;
            }
          case 'table':
            if (options.extractTables) {
              final table = _extractTable(child, partIndex);
              if (table != null) {
                parts.add(table);
                partIndex++;
              }
            }
          case 'img':
            if (options.extractImages) {
              final src = child.attributes['src'];
              if (src != null) {
                parts.add(ImageBlock(
                  id: 'img$partIndex',
                  assetRef: src,
                  altText: child.attributes['alt'],
                  width: int.tryParse(child.attributes['width'] ?? ''),
                  height: int.tryParse(child.attributes['height'] ?? ''),
                ));
                partIndex++;
              }
            }
          case 'pre' || 'code':
            final text = child.text.trim();
            if (text.isNotEmpty) {
              parts.add(TextBlock(
                id: 'c$partIndex',
                text: text,
                type: TextBlockType.code,
                language:
                    child.attributes['class']?.replaceFirst('language-', ''),
              ));
              partIndex++;
            }
          case 'blockquote':
            final text = child.text.trim();
            if (text.isNotEmpty) {
              parts.add(TextBlock(
                id: 'q$partIndex',
                text: text,
                type: TextBlockType.quote,
              ));
              partIndex++;
            }
          case 'ul' || 'ol':
            final list = _extractList(child, partIndex);
            if (list != null) {
              parts.add(list);
              partIndex++;
            }
          case 'script' || 'style' || 'noscript':
            // Skip script, style, and noscript elements
            break;
          default:
            partIndex = _extractNode(child, parts, options, partIndex);
        }
      }
    }
    return partIndex;
  }

  TableBlock? _extractTable(Element table, int partIndex) {
    final rows = <TableRow>[];
    var maxCols = 0;

    for (final tr in table.querySelectorAll('tr')) {
      final cells = <TableCell>[];
      final isHeaderRow = tr.querySelectorAll('th').isNotEmpty;

      for (final cell in tr.querySelectorAll('td, th')) {
        cells.add(TableCell(
          text: cell.text.trim(),
          type: cell.localName == 'th' ? CellType.header : CellType.data,
          rowSpan: int.tryParse(cell.attributes['rowspan'] ?? '') ?? 1,
          colSpan: int.tryParse(cell.attributes['colspan'] ?? '') ?? 1,
        ));
      }

      if (cells.isNotEmpty) {
        rows.add(TableRow(cells: cells, isHeader: isHeaderRow));
        if (cells.length > maxCols) maxCols = cells.length;
      }
    }

    if (rows.isEmpty) return null;

    final caption = table.querySelector('caption')?.text;

    return TableBlock(
      id: 'table$partIndex',
      rows: rows,
      rowCount: rows.length,
      columnCount: maxCols,
      caption: caption,
    );
  }

  ListBlock? _extractList(Element list, int partIndex) {
    final items = <ListItem>[];
    final listType =
        list.localName == 'ol' ? ListType.ordered : ListType.unordered;

    for (final li in list.children.where((e) => e.localName == 'li')) {
      final content = li.nodes
          .whereType<Text>()
          .map((t) => t.text)
          .join()
          .trim();

      final nestedList = li.querySelector('ul, ol');
      List<ListItem>? children;

      if (nestedList != null) {
        final nested = _extractList(nestedList, 0);
        children = nested?.items;
      }

      if (content.isNotEmpty || children != null) {
        items.add(ListItem(
          text: content,
          children: children,
        ));
      }
    }

    if (items.isEmpty) return null;

    return ListBlock(
      id: 'list$partIndex',
      type: listType,
      items: items,
    );
  }

  DocumentStructure _buildStructure(Document document) {
    final nodes = <StructureNode>[];
    final headings = document.querySelectorAll('h1, h2, h3, h4, h5, h6');

    for (var i = 0; i < headings.length; i++) {
      final heading = headings[i];
      final level = int.parse(heading.localName!.substring(1));

      nodes.add(StructureNode(
        id: 'section_$i',
        type: StructureType.section,
        title: heading.text.trim(),
        level: level - 1,
        partIds: ['h$i'],
      ));
    }

    return DocumentStructure(nodes: nodes);
  }
}
