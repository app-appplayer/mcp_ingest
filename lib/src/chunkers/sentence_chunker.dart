/// Sentence-based chunker.
library;

import '../document/chunk.dart';
import '../document/document_part.dart';
import '../document/normalized_document.dart';
import '../document/source_location.dart';
import 'chunker.dart';

/// Chunks documents by sentence boundaries.
class SentenceChunker implements Chunker {
  @override
  String get id => 'sentence_v1';

  @override
  String get name => 'Sentence Chunker';

  /// Sentence-ending punctuation pattern.
  static final _sentenceEnd = RegExp(r'[.!?]+[\s\n]+|[.!?]+$');

  /// Abbreviation patterns that don't end sentences.
  static final _abbreviations = RegExp(
    r'\b(Mr|Mrs|Ms|Dr|Prof|Sr|Jr|vs|etc|i\.e|e\.g|Fig|fig|No|no)\.$',
    caseSensitive: false,
  );

  @override
  Future<List<Chunk>> chunk(NormalizedDocument document, ChunkOptions options) async {
    final chunks = <Chunk>[];
    var currentText = StringBuffer();
    var currentSpans = <ChunkSpan>[];
    var chunkIndex = 0;
    SourceLocation? startLocation;

    for (final part in document.parts) {
      final partText = _getPartText(part);
      if (partText.isEmpty) continue;

      final sentences = _splitSentences(partText);

      for (final sentence in sentences) {
        if (sentence.trim().isEmpty) continue;

        final wouldExceed =
            currentText.length + sentence.length > options.maxSize;

        if (wouldExceed && currentText.isNotEmpty) {
          // Emit current chunk
          chunks.add(_createChunk(
            chunkIndex++,
            currentText.toString().trim(),
            currentSpans,
            startLocation,
          ));
          currentText = StringBuffer();
          currentSpans = [];
          startLocation = null;

          // Add overlap from previous content
          if (options.overlap > 0 && chunks.isNotEmpty) {
            final overlapText = _getOverlap(
              chunks.last.text,
              options.overlap,
            );
            currentText.write(overlapText);
          }
        }

        if (startLocation == null) {
          startLocation = part.location;
        }

        currentText.write(sentence);
        currentText.write(' ');

        currentSpans.add(ChunkSpan(
          partId: part.id,
          startOffset: 0,
          endOffset: partText.length,
        ));
      }
    }

    // Emit remaining content
    if (currentText.isNotEmpty) {
      chunks.add(_createChunk(
        chunkIndex,
        currentText.toString().trim(),
        currentSpans,
        startLocation,
      ));
    }

    // Update totalChunks in all chunks
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

  List<String> _splitSentences(String text) {
    final sentences = <String>[];
    var start = 0;

    for (final match in _sentenceEnd.allMatches(text)) {
      final end = match.end;
      final candidate = text.substring(start, end).trim();

      // Check if this is an abbreviation
      if (_abbreviations.hasMatch(candidate)) {
        continue;
      }

      if (candidate.isNotEmpty) {
        sentences.add(candidate);
      }
      start = end;
    }

    // Add remaining text
    if (start < text.length) {
      final remaining = text.substring(start).trim();
      if (remaining.isNotEmpty) {
        sentences.add(remaining);
      }
    }

    return sentences;
  }

  String _getOverlap(String text, int maxLength) {
    if (text.length <= maxLength) return text;

    // Find last sentence boundary within limit
    final truncated = text.substring(text.length - maxLength);
    final sentenceStart = truncated.indexOf(RegExp(r'[.!?]\s+'));
    if (sentenceStart > 0) {
      return truncated.substring(sentenceStart + 1).trim();
    }
    return truncated;
  }

  Chunk _createChunk(
    int index,
    String text,
    List<ChunkSpan> spans,
    SourceLocation? location,
  ) {
    return Chunk(
      id: 'chunk_$index',
      text: text,
      index: index,
      totalChunks: 0,
      sourceSpans: spans,
      location: location ?? const SourceLocation(),
      metadata: {
        'chunker': id,
        'sentenceCount': _countSentences(text),
      },
    );
  }

  List<Chunk> _updateTotalChunks(List<Chunk> chunks) {
    final total = chunks.length;
    return chunks.map((c) => c.copyWith(totalChunks: total)).toList();
  }

  int _countSentences(String text) {
    return _sentenceEnd.allMatches(text).length + 1;
  }
}
