/// Chunk representation for RAG.
library;

import 'source_location.dart';

/// Source span for provenance tracking.
/// Records exact offset ranges within each source part.
class ChunkSpan {
  /// Source part ID.
  final String partId;

  /// Start offset within the part.
  final int startOffset;

  /// End offset within the part.
  final int endOffset;

  const ChunkSpan({
    required this.partId,
    required this.startOffset,
    required this.endOffset,
  });

  /// Length of this span.
  int get length => endOffset - startOffset;

  Map<String, dynamic> toJson() => {
        'partId': partId,
        'startOffset': startOffset,
        'endOffset': endOffset,
      };

  factory ChunkSpan.fromJson(Map<String, dynamic> json) => ChunkSpan(
        partId: json['partId'] as String,
        startOffset: json['startOffset'] as int,
        endOffset: json['endOffset'] as int,
      );
}

/// A chunk of document content with full provenance.
class Chunk {
  /// Chunk ID.
  final String id;

  /// Chunk text content.
  final String text;

  /// Source spans with exact offset tracking.
  /// This is the PRIMARY provenance mechanism.
  final List<ChunkSpan> sourceSpans;

  /// Source part IDs (derived from sourceSpans for convenience).
  List<String> get sourcePartIds =>
      sourceSpans.map((s) => s.partId).toSet().toList();

  /// Source location in original document.
  final SourceLocation location;

  /// Chunk index in sequence (0-indexed).
  final int index;

  /// Total number of chunks in document.
  final int totalChunks;

  /// Context prefix from parent sections.
  final String? contextPrefix;

  /// Chunk metadata.
  final Map<String, dynamic>? metadata;

  const Chunk({
    required this.id,
    required this.text,
    required this.sourceSpans,
    required this.location,
    required this.index,
    required this.totalChunks,
    this.contextPrefix,
    this.metadata,
  });

  /// Character count.
  int get length => text.length;

  /// Full text including context.
  String get fullText =>
      contextPrefix != null ? '$contextPrefix\n\n$text' : text;

  /// Check if this chunk spans multiple parts.
  bool get crossesParts => sourcePartIds.length > 1;

  /// Get the exact text range this chunk covers in each part.
  Map<String, (int, int)> get partRanges {
    final ranges = <String, (int, int)>{};
    for (final span in sourceSpans) {
      ranges[span.partId] = (span.startOffset, span.endOffset);
    }
    return ranges;
  }

  factory Chunk.fromJson(Map<String, dynamic> json) {
    return Chunk(
      id: json['id'] as String,
      text: json['text'] as String,
      sourceSpans: (json['sourceSpans'] as List<dynamic>?)
              ?.map((e) => ChunkSpan.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      location: json['location'] != null
          ? SourceLocation.fromJson(json['location'] as Map<String, dynamic>)
          : const SourceLocation(),
      index: json['index'] as int? ?? 0,
      totalChunks: json['totalChunks'] as int? ?? 0,
      contextPrefix: json['contextPrefix'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'sourceSpans': sourceSpans.map((s) => s.toJson()).toList(),
        'location': location.toJson(),
        'index': index,
        'totalChunks': totalChunks,
        if (contextPrefix != null) 'contextPrefix': contextPrefix,
        if (metadata != null) 'metadata': metadata,
      };

  Chunk copyWith({
    String? id,
    String? text,
    List<ChunkSpan>? sourceSpans,
    SourceLocation? location,
    int? index,
    int? totalChunks,
    String? contextPrefix,
    Map<String, dynamic>? metadata,
  }) {
    return Chunk(
      id: id ?? this.id,
      text: text ?? this.text,
      sourceSpans: sourceSpans ?? this.sourceSpans,
      location: location ?? this.location,
      index: index ?? this.index,
      totalChunks: totalChunks ?? this.totalChunks,
      contextPrefix: contextPrefix ?? this.contextPrefix,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() =>
      'Chunk($id, index: $index/$totalChunks, length: $length)';
}
