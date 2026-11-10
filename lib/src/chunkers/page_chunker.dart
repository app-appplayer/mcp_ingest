/// Page-based chunker.
library;

import '../document/chunk.dart';
import '../document/document_part.dart';
import '../document/document_structure.dart';
import '../document/normalized_document.dart';
import '../document/source_location.dart';
import 'chunker.dart';

/// Chunks documents by page boundaries.
class PageChunker implements Chunker {
  @override
  String get id => 'page_v1';

  @override
  String get name => 'Page Chunker';

  @override
  Future<List<Chunk>> chunk(
      NormalizedDocument document, ChunkOptions options) async {
    final chunks = <Chunk>[];

    // Group parts by page using structure
    final pageNodes = document.structure.nodes
        .where((n) =>
            n.type == StructureType.page || n.type == StructureType.slide)
        .toList();

    if (pageNodes.isNotEmpty) {
      // Use structure-based page grouping
      var chunkIndex = 0;
      for (final pageNode in pageNodes) {
        final pageParts = pageNode.partIds
            .map((id) => document.findPart(id))
            .whereType<DocumentPart>()
            .toList();

        final pageText = _extractText(pageParts);
        if (pageText.trim().isEmpty) continue;

        final pageNum = pageNode.level + 1;

        // Split page if too large
        if (pageText.length > options.maxSize) {
          chunks.addAll(_splitPage(pageText, pageNode, chunkIndex, options));
          chunkIndex += (pageText.length / options.maxSize).ceil();
        } else {
          chunks.add(Chunk(
            id: 'chunk_$chunkIndex',
            text: pageText.trim(),
            index: chunkIndex,
            totalChunks: 0,
            sourceSpans: pageNode.partIds
                .map(
                    (id) => ChunkSpan(partId: id, startOffset: 0, endOffset: 0))
                .toList(),
            location: SourceLocation(pageNumber: pageNum),
            metadata: {
              'chunker': id,
              'pageNumber': pageNum,
              'pageTitle': pageNode.title,
            },
          ));
          chunkIndex++;
        }
      }
    } else {
      // Fallback: group parts by page number in location
      final pageGroups = <int, List<DocumentPart>>{};

      for (final part in document.parts) {
        final pageNum = _getPageNumber(part);
        pageGroups.putIfAbsent(pageNum, () => []).add(part);
      }

      var chunkIndex = 0;
      for (final entry in pageGroups.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key))) {
        final pageText = _extractText(entry.value);
        if (pageText.trim().isEmpty) continue;

        chunks.add(Chunk(
          id: 'chunk_$chunkIndex',
          text: pageText.trim(),
          index: chunkIndex,
          totalChunks: 0,
          sourceSpans: entry.value
              .map((p) => ChunkSpan(partId: p.id, startOffset: 0, endOffset: 0))
              .toList(),
          location: SourceLocation(pageNumber: entry.key),
          metadata: {
            'chunker': id,
            'pageNumber': entry.key,
          },
        ));
        chunkIndex++;
      }
    }

    return _updateTotalChunks(chunks);
  }

  int _getPageNumber(DocumentPart part) {
    return switch (part) {
      TextBlock(:final location) => location?.pageNumber ?? 1,
      TableBlock(:final location) => location?.pageNumber ?? 1,
      ImageBlock(:final location) => location?.pageNumber ?? 1,
      _ => 1,
    };
  }

  String _extractText(List<DocumentPart> parts) {
    final buffer = StringBuffer();
    for (final part in parts) {
      final text = switch (part) {
        TextBlock(:final text) => text,
        TableBlock() => part.toMarkdown(),
        ListBlock(:final items) => items.map((i) => '- ${i.text}').join('\n'),
        KeyValueBlock(:final key, :final value) => '$key: $value',
        ImageBlock(:final caption, :final ocrText, :final visionDescription) =>
          [caption, ocrText, visionDescription].whereType<String>().join('\n'),
        AudioBlock(:final transcript) => transcript ?? '',
      };
      if (text.isNotEmpty) {
        buffer.writeln(text);
        buffer.writeln();
      }
    }
    return buffer.toString();
  }

  List<Chunk> _splitPage(
    String pageText,
    StructureNode pageNode,
    int startIndex,
    ChunkOptions options,
  ) {
    final chunks = <Chunk>[];
    var remaining = pageText;
    var index = startIndex;
    var subIndex = 0;
    final pageNum = pageNode.level + 1;

    while (remaining.isNotEmpty) {
      var end = options.maxSize;
      if (end >= remaining.length) {
        end = remaining.length;
      } else {
        // Try to break at paragraph
        final paraBreak = remaining.lastIndexOf('\n\n', end);
        if (paraBreak > options.minSize) {
          end = paraBreak;
        } else {
          // Try sentence boundary
          final sentenceEnd = remaining.lastIndexOf('. ', end);
          if (sentenceEnd > options.minSize) {
            end = sentenceEnd + 1;
          }
        }
      }

      final chunkText = remaining.substring(0, end).trim();
      if (chunkText.isNotEmpty) {
        chunks.add(Chunk(
          id: 'chunk_$index',
          text: chunkText,
          index: index,
          totalChunks: 0,
          sourceSpans: pageNode.partIds
              .map((id) => ChunkSpan(partId: id, startOffset: 0, endOffset: 0))
              .toList(),
          location: SourceLocation(pageNumber: pageNum),
          metadata: {
            'chunker': id,
            'pageNumber': pageNum,
            'pageTitle': pageNode.title,
            'subChunk': subIndex,
          },
        ));
        index++;
        subIndex++;
      }

      remaining = remaining.substring(end).trim();
    }

    return chunks;
  }

  List<Chunk> _updateTotalChunks(List<Chunk> chunks) {
    final total = chunks.length;
    return chunks.map((c) => c.copyWith(totalChunks: total)).toList();
  }
}
