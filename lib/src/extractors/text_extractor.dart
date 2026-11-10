/// Plain text and markdown extractor.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../core/content_type.dart';
import '../document/document_metadata.dart';
import '../document/document_part.dart';
import '../document/document_structure.dart';
import '../document/normalized_document.dart';
import '../document/source_location.dart';
import 'extractor.dart';
import 'text_decoding.dart';

/// Extracts plain text and markdown files.
class TextExtractor extends Extractor {
  @override
  String get id => 'text_plain_v1';

  @override
  Set<String> get supportedTypes => {
        'text/plain',
        'text/markdown',
        'text/x-markdown',
      };

  @override
  int get priority => 0;

  @override
  Duration estimateDuration(int fileSize) =>
      Duration(milliseconds: fileSize ~/ 10000); // ~100ms per MB

  @override
  bool canHandle(ContentType contentType) {
    return supportedTypes.contains(contentType.mimeType);
  }

  @override
  Future<NormalizedDocument> extract(
    Stream<List<int>> input,
    ExtractOptions options,
  ) async {
    final stopwatch = Stopwatch()..start();
    final content = await decodeText(
      input,
      extractorId: id,
      encoding: options.custom?['encoding'] as String?,
    );
    final isMarkdown = options.custom?['isMarkdown'] == true;

    final document = isMarkdown
        ? _parseMarkdown(content, options)
        : _parsePlainText(content, options);

    stopwatch.stop();
    return document.copyWithProvenance(stopwatch.elapsed);
  }

  NormalizedDocument _parsePlainText(String content, ExtractOptions options) {
    final paragraphs = content.split(RegExp(r'\n\s*\n'));
    final parts = <DocumentPart>[];
    var lineNumber = 1;

    for (var i = 0; i < paragraphs.length; i++) {
      final text = paragraphs[i].trim();
      if (text.isNotEmpty) {
        parts.add(TextBlock(
          id: 'p$i',
          text: text,
          type: TextBlockType.paragraph,
          location: SourceLocation(lineNumber: lineNumber),
        ));
      }
      lineNumber += paragraphs[i].split('\n').length + 1;
    }

    return _createDocument(content, parts, 'text/plain');
  }

  NormalizedDocument _parseMarkdown(String content, ExtractOptions options) {
    final lines = content.split('\n');
    final parts = <DocumentPart>[];
    final structure = <StructureNode>[];
    var currentSection = <String>[];
    var lineNumber = 0;
    var partIndex = 0;

    for (final line in lines) {
      lineNumber++;

      // Check for headings
      final headingMatch = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line);
      if (headingMatch != null) {
        // Flush current section
        if (currentSection.isNotEmpty) {
          final text = currentSection.join('\n').trim();
          if (text.isNotEmpty) {
            parts.add(TextBlock(
              id: 'p$partIndex',
              text: text,
              type: TextBlockType.paragraph,
              location: SourceLocation(
                  lineNumber: lineNumber - currentSection.length),
            ));
            partIndex++;
          }
          currentSection = [];
        }

        final level = headingMatch.group(1)!.length;
        final title = headingMatch.group(2)!;
        parts.add(TextBlock(
          id: 'h$partIndex',
          text: title,
          type: TextBlockType.heading,
          headingLevel: level,
          location: SourceLocation(lineNumber: lineNumber),
        ));

        structure.add(StructureNode(
          id: 'section_$partIndex',
          type: StructureType.section,
          title: title,
          level: level - 1,
          partIds: ['h$partIndex'],
        ));
        partIndex++;
        continue;
      }

      // Check for code blocks
      if (line.startsWith('```')) {
        // Flush current section
        if (currentSection.isNotEmpty) {
          final text = currentSection.join('\n').trim();
          if (text.isNotEmpty) {
            parts.add(TextBlock(
              id: 'p$partIndex',
              text: text,
              type: TextBlockType.paragraph,
              location: SourceLocation(
                  lineNumber: lineNumber - currentSection.length),
            ));
            partIndex++;
          }
          currentSection = [];
        }

        final language = line.substring(3).trim();
        final codeLines = <String>[];
        lineNumber++;

        while (lineNumber <= lines.length) {
          final codeLine = lines[lineNumber - 1];
          if (codeLine.startsWith('```')) {
            break;
          }
          codeLines.add(codeLine);
          lineNumber++;
        }

        if (codeLines.isNotEmpty) {
          parts.add(TextBlock(
            id: 'c$partIndex',
            text: codeLines.join('\n'),
            type: TextBlockType.code,
            language: language.isNotEmpty ? language : null,
            location:
                SourceLocation(lineNumber: lineNumber - codeLines.length - 1),
          ));
          partIndex++;
        }
        continue;
      }

      currentSection.add(line);
    }

    // Flush remaining content
    if (currentSection.isNotEmpty) {
      final text = currentSection.join('\n').trim();
      if (text.isNotEmpty) {
        parts.add(TextBlock(
          id: 'p$partIndex',
          text: text,
          type: TextBlockType.paragraph,
          location:
              SourceLocation(lineNumber: lineNumber - currentSection.length),
        ));
      }
    }

    return _createDocument(
      content,
      parts,
      'text/markdown',
      structure: DocumentStructure(nodes: structure),
    );
  }

  NormalizedDocument _createDocument(
    String content,
    List<DocumentPart> parts,
    String mimeType, {
    DocumentStructure? structure,
  }) {
    final hash = sha256.convert(utf8.encode(content)).toString();

    return NormalizedDocument(
      id: const Uuid().v4(),
      metadata: DocumentMetadata(
        mimeType: mimeType,
        sha256: hash,
        fileSize: content.length,
        wordCount: content.split(RegExp(r'\s+')).length,
      ),
      parts: parts,
      structure: structure ?? DocumentStructure.empty,
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
  NormalizedDocument copyWithProvenance(Duration duration) {
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
