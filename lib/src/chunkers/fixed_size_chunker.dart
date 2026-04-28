/// Fixed-size chunker with overlap.
library;

import '../document/chunk.dart';
import '../document/document_part.dart';
import '../document/normalized_document.dart';
import '../document/source_location.dart';
import 'chunker.dart';

/// Chunks by fixed character count with overlap.
class FixedSizeChunker implements Chunker {
  @override
  String get id => 'fixed_size_v1';

  @override
  String get name => 'Fixed Size Chunker';

  @override
  Future<List<Chunk>> chunk(NormalizedDocument document, ChunkOptions options) async {
    final fullText = document.fullText;
    if (fullText.isEmpty) return [];

    final chunks = <Chunk>[];
    var start = 0;

    // Build part offset map for provenance tracking
    final partOffsets = _buildPartOffsetMap(document);

    while (start < fullText.length) {
      var end = start + options.targetSize;

      // Extend to word boundary if possible
      if (end < fullText.length) {
        final nextSpace = fullText.indexOf(' ', end);
        if (nextSpace != -1 && nextSpace < end + 50) {
          end = nextSpace;
        }
      } else {
        end = fullText.length;
      }

      final chunkText = fullText.substring(start, end).trim();

      if (chunkText.isNotEmpty) {
        // Resolve source spans from character offsets
        final spans = _resolveSpans(partOffsets, start, end);

        chunks.add(Chunk(
          id: 'chunk_${chunks.length}',
          text: chunkText,
          sourceSpans: spans,
          location: SourceLocation(charOffset: start, charLength: end - start),
          index: chunks.length,
          totalChunks: 0,
        ));
      }

      // Move start with overlap
      final nextStart = end - options.overlap;
      // Ensure we always advance to prevent infinite loop
      if (nextStart <= start) {
        start = end;
      } else {
        start = nextStart;
      }
    }

    // Update total chunks
    return chunks
        .asMap()
        .entries
        .map((e) => Chunk(
              id: e.value.id,
              text: e.value.text,
              sourceSpans: e.value.sourceSpans,
              location: e.value.location,
              index: e.key,
              totalChunks: chunks.length,
            ))
        .toList();
  }

  /// Build map of part ID to (globalStart, globalEnd) from fullText offsets.
  List<_PartOffset> _buildPartOffsetMap(NormalizedDocument document) {
    final offsets = <_PartOffset>[];
    var pos = 0;
    for (final part in document.parts) {
      final text = _getPartText(part);
      offsets.add(_PartOffset(part.id, pos, pos + text.length));
      pos += text.length + 1; // +1 for separator
    }
    return offsets;
  }

  /// Resolve which parts a character range [start, end] overlaps.
  List<ChunkSpan> _resolveSpans(
    List<_PartOffset> partOffsets,
    int start,
    int end,
  ) {
    final spans = <ChunkSpan>[];
    for (final po in partOffsets) {
      if (po.end > start && po.start < end) {
        spans.add(ChunkSpan(
          partId: po.partId,
          startOffset: (start - po.start).clamp(0, po.end - po.start),
          endOffset: (end - po.start).clamp(0, po.end - po.start),
        ));
      }
    }
    return spans;
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
}

class _PartOffset {
  final String partId;
  final int start;
  final int end;
  _PartOffset(this.partId, this.start, this.end);
}
