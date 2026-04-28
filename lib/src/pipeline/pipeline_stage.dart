/// Pipeline stage definitions.
library;

import '../document/chunk.dart';
import '../document/normalized_document.dart';

/// Pipeline stages matching the 9-stage architecture.
enum PipelineStage {
  /// Content type detection.
  detect,

  /// Extractor selection.
  select,

  /// Document extraction.
  extract,

  /// Asset caching.
  cacheAssets,

  /// Document enhancement (OCR/ASR/Vision).
  enhance,

  /// Document chunking.
  chunk,

  /// Fragment extraction.
  fragments,

  /// Asset storage.
  store,

  /// FactGraph entity building.
  factgraph,
}

/// Phase for custom stages.
enum StagePhase {
  /// Before chunking.
  preChunk,

  /// After chunking.
  postChunk,
}

/// Base class for custom pipeline stages.
abstract class CustomPipelineStage {
  /// Stage identifier.
  String get id;

  /// Stage name.
  String get name;

  /// Phase in pipeline.
  StagePhase get phase;

  /// Process document (pre-chunk phase).
  Future<NormalizedDocument> process(NormalizedDocument document) async {
    return document;
  }

  /// Process chunks (post-chunk phase).
  Future<List<Chunk>> processChunks(List<Chunk> chunks) async {
    return chunks;
  }
}

/// Document transformation stage.
abstract class DocumentTransformer extends CustomPipelineStage {
  @override
  StagePhase get phase => StagePhase.preChunk;
}

/// Chunk post-processor stage.
abstract class ChunkPostProcessor extends CustomPipelineStage {
  @override
  StagePhase get phase => StagePhase.postChunk;
}

/// Filter empty or short chunks.
class ChunkFilterStage extends ChunkPostProcessor {
  /// Minimum chunk length.
  final int minLength;

  ChunkFilterStage({this.minLength = 10});

  @override
  String get id => 'chunk_filter';

  @override
  String get name => 'Chunk Filter';

  @override
  Future<List<Chunk>> processChunks(List<Chunk> chunks) async {
    return chunks.where((c) => c.text.length >= minLength).toList();
  }
}

/// Normalize whitespace in chunks.
class WhitespaceNormalizerStage extends ChunkPostProcessor {
  @override
  String get id => 'whitespace_normalizer';

  @override
  String get name => 'Whitespace Normalizer';

  @override
  Future<List<Chunk>> processChunks(List<Chunk> chunks) async {
    return chunks.map((chunk) {
      final normalized = chunk.text
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim();
      return chunk.copyWith(text: normalized);
    }).toList();
  }
}

/// Add context prefix to chunks.
class ContextPrefixStage extends ChunkPostProcessor {
  /// Context template.
  final String Function(Chunk chunk)? contextBuilder;

  ContextPrefixStage({this.contextBuilder});

  @override
  String get id => 'context_prefix';

  @override
  String get name => 'Context Prefix';

  @override
  Future<List<Chunk>> processChunks(List<Chunk> chunks) async {
    if (contextBuilder == null) return chunks;

    return chunks.map((chunk) {
      final context = contextBuilder!(chunk);
      return chunk.copyWith(contextPrefix: context);
    }).toList();
  }
}

/// Metadata enrichment stage.
class MetadataEnrichmentStage extends ChunkPostProcessor {
  /// Metadata adder function.
  final Map<String, dynamic> Function(Chunk chunk) metadataAdder;

  MetadataEnrichmentStage({required this.metadataAdder});

  @override
  String get id => 'metadata_enrichment';

  @override
  String get name => 'Metadata Enrichment';

  @override
  Future<List<Chunk>> processChunks(List<Chunk> chunks) async {
    return chunks.map((chunk) {
      final additional = metadataAdder(chunk);
      final merged = {...?chunk.metadata, ...additional};
      return chunk.copyWith(metadata: merged);
    }).toList();
  }
}
