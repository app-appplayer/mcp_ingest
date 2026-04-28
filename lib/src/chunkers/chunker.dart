/// Base chunker interface.
library;

import 'package:mcp_bundle/ports.dart';

import '../core/exceptions.dart';
import '../core/ingest_options.dart';
import '../document/chunk.dart';
import '../document/normalized_document.dart';
import 'fixed_size_chunker.dart';
import 'no_chunker.dart';
import 'page_chunker.dart';
import 'paragraph_chunker.dart';
import 'semantic_chunker.dart';
import 'sentence_chunker.dart';
import 'table_chunker.dart';

/// Configuration for chunking.
class ChunkOptions {
  /// Target chunk size in characters.
  final int targetSize;

  /// Maximum chunk size (hard limit).
  final int maxSize;

  /// Minimum chunk size (merge smaller chunks).
  final int minSize;

  /// Overlap between consecutive chunks in characters.
  final int overlap;

  /// Respect document structure boundaries.
  final bool respectBoundaries;

  /// Include context from parent sections in chunks.
  final bool includeContext;

  /// Maximum context length.
  final int maxContextLength;

  const ChunkOptions({
    this.targetSize = 1000,
    this.maxSize = 2000,
    this.minSize = 100,
    this.overlap = 200,
    this.respectBoundaries = true,
    this.includeContext = true,
    this.maxContextLength = 200,
  });

  /// Default options for general use.
  static const ChunkOptions defaults = ChunkOptions();

  /// Options optimized for embedding models (smaller chunks).
  static const ChunkOptions forEmbedding = ChunkOptions(
    targetSize: 512,
    maxSize: 768,
    minSize: 64,
    overlap: 50,
    respectBoundaries: true,
    includeContext: false,
  );

  /// Options optimized for RAG (larger context).
  static const ChunkOptions forRag = ChunkOptions(
    targetSize: 2000,
    maxSize: 4000,
    minSize: 500,
    overlap: 400,
    respectBoundaries: true,
    includeContext: true,
  );

  ChunkOptions copyWith({
    int? targetSize,
    int? maxSize,
    int? minSize,
    int? overlap,
    bool? respectBoundaries,
    bool? includeContext,
    int? maxContextLength,
  }) {
    return ChunkOptions(
      targetSize: targetSize ?? this.targetSize,
      maxSize: maxSize ?? this.maxSize,
      minSize: minSize ?? this.minSize,
      overlap: overlap ?? this.overlap,
      respectBoundaries: respectBoundaries ?? this.respectBoundaries,
      includeContext: includeContext ?? this.includeContext,
      maxContextLength: maxContextLength ?? this.maxContextLength,
    );
  }
}

/// Base interface for all chunkers.
abstract class Chunker {
  /// Unique identifier for this chunker.
  String get id;

  /// Human-readable name.
  String get name;

  /// Chunk a normalized document.
  ///
  /// Returns a Future to support async chunkers (e.g., LLM-based).
  Future<List<Chunk>> chunk(NormalizedDocument document, ChunkOptions options);
}

/// Registry for chunker lookup.
class ChunkerRegistry {
  final Map<String, Chunker> _chunkers = {};

  /// Register a chunker.
  void register(Chunker chunker) {
    _chunkers[chunker.id] = chunker;
  }

  /// Find chunker by ID.
  Chunker? find(String id) => _chunkers[id];

  /// Get all registered chunkers.
  List<Chunker> get all => _chunkers.values.toList();
}

/// Factory for creating chunkers based on strategy.
class ChunkerFactory {
  /// Optional LLM port for semantic chunking.
  final LlmPort? llmPort;

  /// Create factory with optional LLM port.
  ChunkerFactory({this.llmPort});

  /// Create chunker for the given strategy.
  Chunker create(ChunkingStrategy strategy) {
    return switch (strategy) {
      ChunkingStrategy.none => NoChunker(),
      ChunkingStrategy.sentence => SentenceChunker(),
      ChunkingStrategy.paragraph => ParagraphChunker(),
      ChunkingStrategy.page => PageChunker(),
      ChunkingStrategy.fixedSize => FixedSizeChunker(),
      ChunkingStrategy.table => TableChunker(),
      ChunkingStrategy.semantic => llmPort != null
          ? SemanticChunker(llmPort!)
          : throw PortNotConfiguredException('LlmPort'),
    };
  }
}
