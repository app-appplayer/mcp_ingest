/// No-op chunker that returns the entire document as a single chunk.
library;

import '../document/chunk.dart';
import '../document/document_part.dart';
import '../document/normalized_document.dart';
import '../document/source_location.dart';
import 'chunker.dart';

/// Returns the entire document as a single chunk.
class NoChunker implements Chunker {
  @override
  String get id => 'none_v1';

  @override
  String get name => 'No Chunker';

  @override
  Future<List<Chunk>> chunk(NormalizedDocument document, ChunkOptions options) async {
    final fullText = document.fullText;

    if (fullText.isEmpty) return [];

    return [
      Chunk(
        id: 'chunk_0',
        text: fullText,
        index: 0,
        totalChunks: 1,
        sourceSpans: document.parts
            .map((p) => ChunkSpan(
                  partId: p.id,
                  startOffset: 0,
                  endOffset: _getPartLength(p),
                ))
            .toList(),
        location: const SourceLocation(),
        metadata: {
          'chunker': id,
          'partCount': document.parts.length,
        },
      ),
    ];
  }

  int _getPartLength(DocumentPart part) {
    return switch (part) {
      TextBlock(:final text) => text.length,
      TableBlock() => part.toMarkdown().length,
      ListBlock(:final items) =>
        items.map((i) => i.text.length).fold<int>(0, (a, b) => a + b),
      KeyValueBlock(:final key, :final value) => key.length + value.length,
      ImageBlock() => 0,
      AudioBlock() => 0,
    };
  }
}
