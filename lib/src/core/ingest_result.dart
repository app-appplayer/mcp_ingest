/// Ingest result types.
library;

import 'package:mcp_fact_graph/mcp_fact_graph.dart';

import '../document/chunk.dart';

/// Result of ingestion - outputs FactGraph entities directly.
class IngestResult {
  // === FactGraph Entities (L0 Layer) ===

  /// Evidence entity (document-level).
  final Evidence? evidence;

  /// Fragment entities (field-level).
  final List<Fragment> fragments;

  // === RAG Support (mcp_ingest specific) ===

  /// Text chunks for embedding/search.
  final List<Chunk> chunks;

  // === Metadata ===

  /// Error if ingestion failed.
  final IngestError? error;

  /// Warnings generated during processing.
  final List<String> warnings;

  /// Processing metrics.
  final IngestMetrics metrics;

  /// Whether ingestion was successful.
  bool get success => evidence != null && error == null;

  /// Get error message.
  String? get errorMessage => error?.message;

  const IngestResult({
    this.evidence,
    this.fragments = const [],
    this.chunks = const [],
    this.error,
    this.warnings = const [],
    required this.metrics,
  });

  /// Create successful result.
  factory IngestResult.success({
    required Evidence evidence,
    required List<Fragment> fragments,
    required List<Chunk> chunks,
    List<String> warnings = const [],
    required IngestMetrics metrics,
  }) {
    return IngestResult(
      evidence: evidence,
      fragments: fragments,
      chunks: chunks,
      warnings: warnings,
      metrics: metrics,
    );
  }

  /// Create failed result.
  factory IngestResult.failed({
    required IngestError error,
    List<String> warnings = const [],
    required IngestMetrics metrics,
  }) {
    return IngestResult(
      error: error,
      warnings: warnings,
      metrics: metrics,
    );
  }

  /// Total text length in chunks.
  int get totalChunkLength =>
      chunks.fold(0, (sum, c) => sum + c.text.length);

  /// Total fragments extracted.
  int get fragmentCount => fragments.length;
}

/// Processing metrics.
class IngestMetrics {
  /// Total processing time.
  final Duration totalDuration;

  /// Time spent extracting.
  final Duration extractionDuration;

  /// Time spent chunking.
  final Duration chunkingDuration;

  /// Input file size in bytes.
  final int inputBytes;

  /// Number of chunks produced.
  final int outputChunks;

  /// Number of fragments extracted.
  final int outputFragments;

  /// Number of OCR API calls.
  final int ocrCalls;

  /// Number of ASR API calls.
  final int asrCalls;

  /// Number of VisionPort API calls (~$0.001/image).
  final int visionPortCalls;

  /// Number of LlmPort vision calls (~$0.01/image).
  final int llmVisionCalls;

  const IngestMetrics({
    required this.totalDuration,
    this.extractionDuration = Duration.zero,
    this.chunkingDuration = Duration.zero,
    required this.inputBytes,
    required this.outputChunks,
    required this.outputFragments,
    this.ocrCalls = 0,
    this.asrCalls = 0,
    this.visionPortCalls = 0,
    this.llmVisionCalls = 0,
  });

  /// Estimated cost based on API calls.
  double get estimatedCost =>
      ocrCalls * 0.001 +
      asrCalls * 0.006 +
      visionPortCalls * 0.001 +
      llmVisionCalls * 0.01;

  /// Empty metrics for initialization.
  static const empty = IngestMetrics(
    totalDuration: Duration.zero,
    extractionDuration: Duration.zero,
    chunkingDuration: Duration.zero,
    inputBytes: 0,
    outputChunks: 0,
    outputFragments: 0,
    ocrCalls: 0,
    asrCalls: 0,
    visionPortCalls: 0,
    llmVisionCalls: 0,
  );

  Map<String, dynamic> toJson() => {
        'totalDurationMs': totalDuration.inMilliseconds,
        'extractionDurationMs': extractionDuration.inMilliseconds,
        'chunkingDurationMs': chunkingDuration.inMilliseconds,
        'inputBytes': inputBytes,
        'outputChunks': outputChunks,
        'outputFragments': outputFragments,
        'ocrCalls': ocrCalls,
        'asrCalls': asrCalls,
        'visionPortCalls': visionPortCalls,
        'llmVisionCalls': llmVisionCalls,
        'estimatedCost': estimatedCost,
      };
}

/// Asset reference for stored binary content.
class AssetRef {
  /// Asset ID/reference.
  final String id;

  /// Asset type (image, audio, etc.).
  final String type;

  /// Size in bytes.
  final int size;

  const AssetRef({
    required this.id,
    required this.type,
    required this.size,
  });
}

/// Ingestion error.
class IngestError {
  /// Stage where error occurred.
  final String stage;

  /// Error message.
  final String message;

  /// Stack trace (if available).
  final String? stackTrace;

  const IngestError({
    required this.stage,
    required this.message,
    this.stackTrace,
  });

  @override
  String toString() => 'IngestError[$stage]: $message';

  Map<String, dynamic> toJson() => {
        'stage': stage,
        'message': message,
        if (stackTrace != null) 'stackTrace': stackTrace,
      };
}
