/// Internal pipeline context for state management.
library;

import 'package:mcp_fact_graph/mcp_fact_graph.dart';

import '../core/content_type.dart';
import '../core/ingest_input.dart';
import '../core/ingest_options.dart';
import '../core/ingest_result.dart';
import '../document/chunk.dart';
import '../document/document_part.dart';
import '../document/normalized_document.dart';
import '../extractors/extractor.dart';

/// Internal pipeline context.
///
/// Maintains state throughout the ingestion pipeline stages.
class IngestContext {
  /// Original input.
  final IngestInput input;

  /// Ingestion options.
  final IngestOptions options;

  /// Current processing stage.
  String currentStage = 'init';

  /// Detected content type.
  ContentType? contentType;

  /// Selected extractor.
  Extractor? extractor;

  /// Extracted document (intermediate representation).
  NormalizedDocument? document;

  /// Generated chunks (for RAG).
  List<Chunk>? chunks;

  // === FactGraph Entities ===

  /// Evidence entity (built from document).
  Evidence? evidence;

  /// Fragment entities (extracted fields).
  List<Fragment>? fragments;

  // === Asset Management ===

  /// Cached assets (before permanent storage).
  Map<String, List<int>> assetCache = {};

  /// Stored asset references.
  List<AssetRef>? assets;

  // === Metrics ===

  /// Warnings collected during processing.
  final List<String> warnings = [];

  /// Input size in bytes.
  int inputBytes = 0;

  /// Extraction duration.
  Duration extractionDuration = Duration.zero;

  /// Chunking duration.
  Duration chunkingDuration = Duration.zero;

  /// OCR call count.
  int ocrCalls = 0;

  /// ASR call count.
  int asrCalls = 0;

  /// VisionPort call count (~$0.001/image).
  int visionPortCalls = 0;

  /// LlmPort vision call count (~$0.01/image).
  int llmVisionCalls = 0;

  /// Stage durations.
  final Map<String, Duration> stageDurations = {};

  IngestContext({
    required this.input,
    required this.options,
  });

  /// Update a document part by ID.
  void updatePart(String partId, DocumentPart newPart) {
    if (document == null) return;

    final newParts = document!.parts.map((p) {
      return p.id == partId ? newPart : p;
    }).toList();

    document = NormalizedDocument(
      id: document!.id,
      metadata: document!.metadata,
      parts: newParts,
      structure: document!.structure,
      provenance: document!.provenance,
    );
  }

  /// Add warning message.
  void addWarning(String message) {
    warnings.add(message);
  }

  /// Record stage duration.
  void recordStageDuration(String stage, Duration duration) {
    stageDurations[stage] = duration;
  }

  /// Increment OCR call counter.
  void incrementOcrCalls([int count = 1]) {
    ocrCalls += count;
  }

  /// Increment ASR call counter.
  void incrementAsrCalls([int count = 1]) {
    asrCalls += count;
  }

  /// Increment VisionPort call counter.
  void incrementVisionPortCalls([int count = 1]) {
    visionPortCalls += count;
  }

  /// Increment LlmPort vision call counter.
  void incrementLlmVisionCalls([int count = 1]) {
    llmVisionCalls += count;
  }

  /// Whether any external services were used.
  bool get usedExternalServices =>
      ocrCalls > 0 || asrCalls > 0 || visionPortCalls > 0 || llmVisionCalls > 0;

  /// Estimated API cost in USD.
  double get estimatedCost {
    return ocrCalls * 0.001 +
           asrCalls * 0.006 +
           visionPortCalls * 0.001 +
           llmVisionCalls * 0.01;
  }
}
