/// Microsoft Office document extractor (DOCX, XLSX, PPTX).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import '../core/content_type.dart';
import '../core/exceptions.dart';
import '../core/ingest_input.dart';
import '../document/document_metadata.dart';
import '../document/document_part.dart';
import '../document/document_structure.dart';
import '../document/normalized_document.dart';
import '../document/source_location.dart';
import 'extractor.dart';

/// Extracts Microsoft Office documents (DOCX, XLSX, PPTX).
class OfficeExtractor extends Extractor {
  @override
  String get id => 'office_xml_v1';

  @override
  Set<String> get supportedTypes => {
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      };

  @override
  int get priority => 0;

  @override
  Duration estimateDuration(int fileSize) =>
      Duration(milliseconds: fileSize ~/ 500); // ~2s per MB

  @override
  Future<NormalizedDocument> extract(
    Stream<List<int>> input,
    ExtractOptions options,
  ) async {
    final stopwatch = Stopwatch()..start();
    final bytes = await collectBytes(input);
    final archive = ZipDecoder().decodeBytes(bytes);
    final mimeType = _detectOfficeType(archive);

    final document = switch (mimeType) {
      _ when mimeType.contains('wordprocessing') =>
        _extractDocx(archive, options, bytes),
      _ when mimeType.contains('spreadsheet') =>
        _extractXlsx(archive, options, bytes),
      _ when mimeType.contains('presentation') =>
        _extractPptx(archive, options, bytes),
      _ => throw UnsupportedFormatException(ContentType(mimeType)),
    };

    stopwatch.stop();
    return document._copyWithDuration(stopwatch.elapsed);
  }

  String _detectOfficeType(Archive archive) {
    final contentTypes = archive.findFile('[Content_Types].xml');
    if (contentTypes == null) {
      return 'application/zip';
    }

    final content = utf8.decode(contentTypes.content as List<int>);
    if (content.contains('wordprocessingml')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (content.contains('spreadsheetml')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (content.contains('presentationml')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    return 'application/zip';
  }

  NormalizedDocument _extractDocx(
    Archive archive,
    ExtractOptions options,
    Uint8List originalBytes,
  ) {
    final documentXml = archive.findFile('word/document.xml');
    if (documentXml == null) {
      throw ExtractionException(id, 'Missing document.xml');
    }

    final doc =
        XmlDocument.parse(utf8.decode(documentXml.content as List<int>));
    final parts = <DocumentPart>[];
    final structure = <StructureNode>[];
    var partIndex = 0;

    // Extract paragraphs
    for (final paragraph in doc.findAllElements('w:p')) {
      final textElements = paragraph.findAllElements('w:t');
      final text = textElements.map((e) => e.innerText).join();

      if (text.trim().isNotEmpty) {
        final type = _detectDocxParagraphType(paragraph);
        final headingLevel = _getDocxHeadingLevel(paragraph);

        parts.add(TextBlock(
          id: 'p$partIndex',
          text: text.trim(),
          type: type,
          headingLevel: headingLevel,
        ));

        if (type == TextBlockType.heading && headingLevel != null) {
          structure.add(StructureNode(
            id: 'section_$partIndex',
            type: StructureType.section,
            title: text.trim(),
            level: headingLevel - 1,
            partIds: ['p$partIndex'],
          ));
        }

        partIndex++;
      }
    }

    // Extract tables
    if (options.extractTables) {
      for (final table in doc.findAllElements('w:tbl')) {
        final tableBlock = _extractDocxTable(table, partIndex);
        if (tableBlock != null) {
          parts.add(tableBlock);
          partIndex++;
        }
      }
    }

    final hash = sha256.convert(originalBytes).toString();

    return NormalizedDocument(
      id: const Uuid().v4(),
      metadata: DocumentMetadata(
        mimeType:
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        sha256: hash,
        fileSize: originalBytes.length,
      ),
      parts: parts,
      structure: DocumentStructure(nodes: structure),
      provenance: ExtractionProvenance(
        extractorId: id,
        extractorVersion: '1.0.0',
        extractedAt: DateTime.now(),
        extractionDuration: Duration.zero,
      ),
    );
  }

  TextBlockType _detectDocxParagraphType(XmlElement paragraph) {
    final pStyle = paragraph.findAllElements('w:pStyle').firstOrNull;
    final styleVal = pStyle?.getAttribute('w:val') ?? '';

    if (styleVal.toLowerCase().contains('heading') ||
        styleVal.toLowerCase().startsWith('h')) {
      return TextBlockType.heading;
    }
    return TextBlockType.paragraph;
  }

  int? _getDocxHeadingLevel(XmlElement paragraph) {
    final pStyle = paragraph.findAllElements('w:pStyle').firstOrNull;
    final styleVal = pStyle?.getAttribute('w:val') ?? '';

    final match = RegExp(r'[Hh]eading\s*(\d)').firstMatch(styleVal);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }

    final numMatch = RegExp(r'(\d)$').firstMatch(styleVal);
    if (numMatch != null && styleVal.toLowerCase().contains('head')) {
      return int.tryParse(numMatch.group(1)!);
    }

    return null;
  }

  TableBlock? _extractDocxTable(XmlElement table, int partIndex) {
    final rows = <TableRow>[];
    var maxCols = 0;

    for (final tr in table.findAllElements('w:tr')) {
      final cells = <TableCell>[];

      for (final tc in tr.findAllElements('w:tc')) {
        final text =
            tc.findAllElements('w:t').map((e) => e.innerText).join(' ').trim();
        cells.add(TableCell(text: text));
      }

      if (cells.isNotEmpty) {
        rows.add(TableRow(cells: cells));
        if (cells.length > maxCols) maxCols = cells.length;
      }
    }

    if (rows.isEmpty) return null;

    return TableBlock(
      id: 'table$partIndex',
      rows: rows,
      rowCount: rows.length,
      columnCount: maxCols,
    );
  }

  NormalizedDocument _extractXlsx(
    Archive archive,
    ExtractOptions options,
    Uint8List originalBytes,
  ) {
    final parts = <DocumentPart>[];
    final structure = <StructureNode>[];

    // Read shared strings
    final sharedStrings = _readSharedStrings(archive);

    // Find all sheet files
    var sheetIndex = 1;
    var partIndex = 0;

    while (true) {
      final sheetFile = archive.findFile('xl/worksheets/sheet$sheetIndex.xml');
      if (sheetFile == null) break;

      final sheetName =
          _getSheetName(archive, sheetIndex) ?? 'Sheet $sheetIndex';
      final table = _parseSheet(sheetFile, sharedStrings);

      if (table.isNotEmpty) {
        final partId = 'sheet_$partIndex';
        parts.add(TableBlock(
          id: partId,
          rows: table,
          rowCount: table.length,
          columnCount: table.isEmpty ? 0 : table.first.cells.length,
          caption: sheetName,
        ));

        structure.add(StructureNode(
          id: 'sheet_$sheetIndex',
          type: StructureType.sheet,
          title: sheetName,
          partIds: [partId],
        ));

        partIndex++;
      }

      sheetIndex++;
    }

    final hash = sha256.convert(originalBytes).toString();

    return NormalizedDocument(
      id: const Uuid().v4(),
      metadata: DocumentMetadata(
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        sha256: hash,
        fileSize: originalBytes.length,
      ),
      parts: parts,
      structure: DocumentStructure(nodes: structure),
      provenance: ExtractionProvenance(
        extractorId: id,
        extractorVersion: '1.0.0',
        extractedAt: DateTime.now(),
        extractionDuration: Duration.zero,
      ),
    );
  }

  List<String> _readSharedStrings(Archive archive) {
    final sharedStringsFile = archive.findFile('xl/sharedStrings.xml');
    if (sharedStringsFile == null) return [];

    final doc =
        XmlDocument.parse(utf8.decode(sharedStringsFile.content as List<int>));
    return doc
        .findAllElements('si')
        .map((si) => si.findAllElements('t').map((t) => t.innerText).join())
        .toList();
  }

  String? _getSheetName(Archive archive, int sheetIndex) {
    final workbookFile = archive.findFile('xl/workbook.xml');
    if (workbookFile == null) return null;

    final doc =
        XmlDocument.parse(utf8.decode(workbookFile.content as List<int>));
    final sheets = doc.findAllElements('sheet').toList();

    if (sheetIndex > 0 && sheetIndex <= sheets.length) {
      return sheets[sheetIndex - 1].getAttribute('name');
    }
    return null;
  }

  List<TableRow> _parseSheet(
      ArchiveFile sheetFile, List<String> sharedStrings) {
    final doc = XmlDocument.parse(utf8.decode(sheetFile.content as List<int>));
    final rows = <TableRow>[];

    for (final row in doc.findAllElements('row')) {
      final cells = <TableCell>[];

      for (final cell in row.findAllElements('c')) {
        final type = cell.getAttribute('t');
        final valueElement = cell.findElements('v').firstOrNull;
        var value = valueElement?.innerText ?? '';

        // Handle shared string reference
        if (type == 's' && value.isNotEmpty) {
          final index = int.tryParse(value);
          if (index != null && index < sharedStrings.length) {
            value = sharedStrings[index];
          }
        }

        cells.add(TableCell(text: value));
      }

      if (cells.isNotEmpty) {
        rows.add(TableRow(cells: cells));
      }
    }

    return rows;
  }

  NormalizedDocument _extractPptx(
    Archive archive,
    ExtractOptions options,
    Uint8List originalBytes,
  ) {
    final parts = <DocumentPart>[];
    final structure = <StructureNode>[];

    var slideNum = 1;

    while (true) {
      final slideFile = archive.findFile('ppt/slides/slide$slideNum.xml');
      if (slideFile == null) break;

      final slidePartIds = <String>[];
      final doc =
          XmlDocument.parse(utf8.decode(slideFile.content as List<int>));

      // Extract text from shapes
      for (final text in doc.findAllElements('a:t')) {
        final content = text.innerText.trim();
        if (content.isNotEmpty) {
          final partId = 'slide${slideNum}_p${slidePartIds.length}';
          parts.add(TextBlock(
            id: partId,
            text: content,
            type: TextBlockType.paragraph,
            location: SourceLocation(pageNumber: slideNum),
          ));
          slidePartIds.add(partId);
        }
      }

      structure.add(StructureNode(
        id: 'slide$slideNum',
        type: StructureType.slide,
        title: 'Slide $slideNum',
        level: 0,
        partIds: slidePartIds,
      ));

      slideNum++;
    }

    final hash = sha256.convert(originalBytes).toString();

    return NormalizedDocument(
      id: const Uuid().v4(),
      metadata: DocumentMetadata(
        mimeType:
            'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        sha256: hash,
        fileSize: originalBytes.length,
        pageCount: slideNum - 1,
      ),
      parts: parts,
      structure: DocumentStructure(nodes: structure),
      provenance: ExtractionProvenance(
        extractorId: id,
        extractorVersion: '1.0.0',
        extractedAt: DateTime.now(),
        extractionDuration: Duration.zero,
      ),
    );
  }
}

extension on NormalizedDocument {
  NormalizedDocument _copyWithDuration(Duration duration) {
    return NormalizedDocument(
      id: id,
      metadata: metadata,
      parts: parts,
      structure: structure,
      provenance: ExtractionProvenance(
        extractorId: provenance.extractorId,
        extractorVersion: provenance.extractorVersion,
        extractedAt: provenance.extractedAt,
        extractionDuration: duration,
        warnings: provenance.warnings,
      ),
    );
  }
}
