/// PDF document extractor.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../core/exceptions.dart';
import '../core/ingest_input.dart';
import '../document/document_metadata.dart';
import '../document/document_part.dart';
import '../document/document_structure.dart';
import '../document/normalized_document.dart';
import '../document/source_location.dart';
import 'extractor.dart';

/// Extracts PDF documents.
///
/// Pure text layer extraction only.
/// OCR for scanned pages is handled by IngestPipeline's Enhance stage
/// (see pipeline.md Stage 5), not by the extractor.
class PdfExtractor extends Extractor {
  PdfExtractor();

  @override
  String get id => 'pdf_text_v1';

  @override
  Set<String> get supportedTypes => {'application/pdf'};

  @override
  int get priority => 0;

  @override
  Duration estimateDuration(int fileSize) =>
      Duration(milliseconds: fileSize ~/ 200); // ~5s per MB

  @override
  Future<NormalizedDocument> extract(
    Stream<List<int>> input,
    ExtractOptions options,
  ) async {
    final stopwatch = Stopwatch()..start();
    final bytes = await collectBytes(input);

    // Validate PDF header
    if (!_isPdf(bytes)) {
      throw ExtractionException(id, 'Invalid PDF header');
    }

    final parts = <DocumentPart>[];
    final structure = <StructureNode>[];

    // Extract basic text content
    final textContent = _extractTextContent(bytes);
    final pageTexts = _splitByPages(textContent);

    var partIndex = 0;
    for (var pageNum = 0; pageNum < pageTexts.length; pageNum++) {
      final pageText = pageTexts[pageNum].trim();
      if (pageText.isNotEmpty) {
        parts.add(TextBlock(
          id: 'page${pageNum}_p$partIndex',
          text: pageText,
          type: TextBlockType.paragraph,
          location: SourceLocation(pageNumber: pageNum + 1),
        ));

        structure.add(StructureNode(
          id: 'page_${pageNum + 1}',
          type: StructureType.page,
          title: 'Page ${pageNum + 1}',
          level: 0,
          partIds: ['page${pageNum}_p$partIndex'],
        ));

        partIndex++;
      }
    }

    stopwatch.stop();
    final hash = sha256.convert(bytes).toString();
    final pageCount = _estimatePageCount(bytes);

    return NormalizedDocument(
      id: const Uuid().v4(),
      metadata: DocumentMetadata(
        mimeType: 'application/pdf',
        sha256: hash,
        fileSize: bytes.length,
        pageCount: pageCount,
      ),
      parts: parts,
      structure: DocumentStructure(nodes: structure),
      provenance: ExtractionProvenance(
        extractorId: id,
        extractorVersion: '1.0.0',
        extractedAt: DateTime.now(),
        extractionDuration: stopwatch.elapsed,
      ),
    );
  }

  bool _isPdf(Uint8List bytes) {
    if (bytes.length < 5) return false;
    // Check for %PDF- header
    return bytes[0] == 0x25 && // %
        bytes[1] == 0x50 && // P
        bytes[2] == 0x44 && // D
        bytes[3] == 0x46 && // F
        bytes[4] == 0x2D; // -
  }

  String _extractTextContent(Uint8List bytes) {
    // Basic text extraction from PDF streams
    final content = StringBuffer();
    final text = latin1.decode(bytes, allowInvalid: true);

    // Find and extract text from stream objects
    final streamPattern = RegExp(r'stream\s*([\s\S]*?)\s*endstream');
    for (final match in streamPattern.allMatches(text)) {
      final streamContent = match.group(1) ?? '';
      final textContent = _extractReadableText(streamContent);
      if (textContent.isNotEmpty) {
        content.writeln(textContent);
      }
    }

    // Also look for text between BT (Begin Text) and ET (End Text)
    final btPattern = RegExp(r'BT\s*([\s\S]*?)\s*ET');
    for (final match in btPattern.allMatches(text)) {
      final textBlock = match.group(1) ?? '';
      final extracted = _extractTextOperators(textBlock);
      if (extracted.isNotEmpty) {
        content.writeln(extracted);
      }
    }

    return content.toString();
  }

  String _extractReadableText(String content) {
    final buffer = StringBuffer();
    final stringPattern = RegExp(r'\(([^)]*)\)');

    for (final match in stringPattern.allMatches(content)) {
      var str = match.group(1) ?? '';
      str = str
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\r', '\r')
          .replaceAll(r'\t', '\t')
          .replaceAll(r'\\', '\\')
          .replaceAll(r'\(', '(')
          .replaceAll(r'\)', ')');

      if (_isReadable(str)) {
        buffer.write(str);
        buffer.write(' ');
      }
    }

    return buffer.toString().trim();
  }

  String _extractTextOperators(String content) {
    final buffer = StringBuffer();

    // Handle Tj operator: (text) Tj
    final tjPattern = RegExp(r'\(([^)]*)\)\s*Tj');
    for (final match in tjPattern.allMatches(content)) {
      buffer.write(match.group(1) ?? '');
      buffer.write(' ');
    }

    // Handle TJ operator: [(text) -kern (text)] TJ
    final tjArrayPattern = RegExp(r'\[(.*?)\]\s*TJ');
    for (final match in tjArrayPattern.allMatches(content)) {
      final arrayContent = match.group(1) ?? '';
      final strings = RegExp(r'\(([^)]*)\)').allMatches(arrayContent);
      for (final strMatch in strings) {
        buffer.write(strMatch.group(1) ?? '');
      }
      buffer.write(' ');
    }

    return buffer.toString().trim();
  }

  bool _isReadable(String str) {
    if (str.isEmpty) return false;
    var readable = 0;
    for (final char in str.codeUnits) {
      if ((char >= 0x20 && char <= 0x7E) ||
          (char >= 0xA0 && char <= 0xFF) ||
          char == 0x0A ||
          char == 0x0D) {
        readable++;
      }
    }
    return readable > str.length * 0.5;
  }

  List<String> _splitByPages(String content) {
    final pages = content.split(RegExp(r'\f|\x0C'));
    if (pages.length > 1) return pages;
    return [content];
  }

  int _estimatePageCount(Uint8List bytes) {
    final text = latin1.decode(bytes, allowInvalid: true);
    final pattern = RegExp(r'/Type\s*/Page\b');
    return pattern.allMatches(text).length;
  }
}
