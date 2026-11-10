/// Paragraph-based chunker.
library;

import '../document/chunk.dart';
import '../document/document_part.dart';
import '../document/document_structure.dart';
import '../document/normalized_document.dart';
import '../document/source_location.dart';
import 'chunker.dart';

/// Chunks documents by paragraph boundaries.
class ParagraphChunker implements Chunker {
  @override
  String get id => 'paragraph_v1';

  @override
  String get name => 'Paragraph Chunker';

  @override
  Future<List<Chunk>> chunk(
      NormalizedDocument document, ChunkOptions options) async {
    final chunks = <Chunk>[];
    final buffer = StringBuffer();
    final spans = <ChunkSpan>[];
    SourceLocation? startLocation;
    String? currentSection;

    for (final part in document.parts) {
      // Check section boundary
      if (options.respectBoundaries) {
        final partSection = _getSectionForPart(document.structure, part.id);
        if (partSection != currentSection && buffer.isNotEmpty) {
          // Emit chunk at section boundary
          chunks.add(_createChunk(
            chunks.length,
            buffer.toString().trim(),
            spans.toList(),
            startLocation,
            sectionTitle: currentSection,
          ));
          buffer.clear();
          spans.clear();
          startLocation = null;
        }
        currentSection = partSection;
      }

      final partText = _getPartText(part);
      if (partText.isEmpty) continue;

      // Check size limit
      if (buffer.length + partText.length > options.maxSize &&
          buffer.isNotEmpty) {
        // Emit current chunk
        chunks.add(_createChunk(
          chunks.length,
          buffer.toString().trim(),
          spans.toList(),
          startLocation,
          sectionTitle: currentSection,
        ));
        buffer.clear();
        spans.clear();
        startLocation = null;
      }

      if (startLocation == null) {
        startLocation = part.location;
      }
      spans.add(ChunkSpan(
        partId: part.id,
        startOffset: 0,
        endOffset: partText.length,
      ));
      buffer.writeln(partText);
      buffer.writeln();
    }

    // Emit final chunk
    if (buffer.isNotEmpty) {
      chunks.add(_createChunk(
        chunks.length,
        buffer.toString().trim(),
        spans.toList(),
        startLocation,
        sectionTitle: currentSection,
      ));
    }

    return _updateTotalChunks(chunks);
  }

  String _getPartText(DocumentPart part) {
    return switch (part) {
      TextBlock(:final text) => text,
      TableBlock() => part.toMarkdown(),
      ListBlock(:final items) => items.map((i) => '- ${i.text}').join('\n'),
      KeyValueBlock(:final key, :final value) => '$key: $value',
      ImageBlock(:final caption, :final ocrText, :final visionDescription) =>
        [caption, ocrText, visionDescription].whereType<String>().join('\n'),
      AudioBlock(:final transcript) => transcript ?? '',
    };
  }

  String? _getSectionForPart(DocumentStructure structure, String partId) {
    for (final node in structure.nodes) {
      final result = _findSection(node, partId);
      if (result != null) return result;
    }
    return null;
  }

  String? _findSection(StructureNode node, String partId) {
    if (node.partIds.contains(partId)) {
      return node.title ?? node.id;
    }
    for (final child in node.children) {
      final result = _findSection(child, partId);
      if (result != null) return result;
    }
    return null;
  }

  Chunk _createChunk(
    int index,
    String text,
    List<ChunkSpan> spans,
    SourceLocation? location, {
    String? sectionTitle,
  }) {
    return Chunk(
      id: 'chunk_$index',
      text: text,
      index: index,
      totalChunks: 0,
      sourceSpans: spans,
      location: location ?? const SourceLocation(),
      metadata: {
        'chunker': id,
        'paragraphCount': text.split(RegExp(r'\n\s*\n')).length,
        if (sectionTitle != null) 'sectionTitle': sectionTitle,
      },
    );
  }

  List<Chunk> _updateTotalChunks(List<Chunk> chunks) {
    final total = chunks.length;
    return chunks.map((c) => c.copyWith(totalChunks: total)).toList();
  }
}
