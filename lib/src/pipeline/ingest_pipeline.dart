/// Main ingestion pipeline.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mcp_bundle/ports.dart';
import 'package:mcp_fact_graph/mcp_fact_graph.dart';
import 'package:pool/pool.dart';

import '../chunkers/chunker.dart';
import '../chunkers/chunk_context_injector.dart';
import '../core/content_type.dart';
import '../core/exceptions.dart';
import '../core/ingest_input.dart';
import '../core/ingest_options.dart';
import '../core/ingest_result.dart';
import '../document/document_part.dart';
import '../extractors/extractor.dart';
import '../extractors/fragment_extractor.dart';
import 'ingest_context.dart';
import 'pipeline_stage.dart';

/// Main document ingestion pipeline.
///
/// Orchestrates the 9-stage ingestion process from file input
/// to mcp_fact_graph entities.
class IngestPipeline {
  /// Registered extractors.
  final ExtractorRegistry extractors;

  /// Chunker factory.
  final ChunkerFactory chunkerFactory;

  /// Optional OCR port.
  final OcrPort? ocrPort;

  /// Optional ASR port.
  final AsrPort? asrPort;

  /// Optional dedicated vision port (Google Vision, AWS Rekognition).
  final VisionPort? visionPort;

  /// Optional LLM port for vision (Claude Vision, GPT-4V).
  final LlmPort? llmPort;

  /// Optional binary storage port for assets.
  final BinaryStoragePort? storagePort;

  /// Custom pipeline stages.
  ///
  /// Stages are automatically invoked based on their `phase`:
  /// - [StagePhase.preChunk] stages run after Stage 5 (enhance) and before
  ///   Stage 6 (chunk) via [CustomPipelineStage.process].
  /// - [StagePhase.postChunk] stages run after Stage 6 (chunk) via
  ///   [CustomPipelineStage.processChunks].
  ///
  /// Multiple stages in the same phase are invoked in list order.
  /// Defaults to empty — existing pipelines behave unchanged.
  final List<CustomPipelineStage> customStages;

  IngestPipeline({
    required this.extractors,
    required this.chunkerFactory,
    this.ocrPort,
    this.asrPort,
    this.visionPort,
    this.llmPort,
    this.storagePort,
    this.customStages = const [],
  });

  /// Create with default configuration.
  factory IngestPipeline.defaults() {
    return IngestPipeline(
      extractors: ExtractorRegistry.defaults(),
      chunkerFactory: ChunkerFactory(),
    );
  }

  /// Create with all optional ports.
  factory IngestPipeline.full({
    required OcrPort ocrPort,
    required AsrPort asrPort,
    required VisionPort visionPort,
    required BinaryStoragePort storagePort,
    LlmPort? llmPort,
    List<CustomPipelineStage> customStages = const [],
  }) {
    return IngestPipeline(
      extractors: ExtractorRegistry.defaults(),
      chunkerFactory: ChunkerFactory(llmPort: llmPort),
      ocrPort: ocrPort,
      asrPort: asrPort,
      visionPort: visionPort,
      llmPort: llmPort,
      storagePort: storagePort,
      customStages: customStages,
    );
  }

  /// Run the full ingestion pipeline.
  Future<IngestResult> ingest(
    IngestInput input,
    IngestOptions options,
  ) async {
    final stopwatch = Stopwatch()..start();
    final context = IngestContext(input: input, options: options);

    try {
      // Check file size limit
      if (options.maxFileSize != null &&
          input.size != null &&
          input.size! > options.maxFileSize!) {
        throw FileSizeLimitException(input.size!, options.maxFileSize!);
      }

      // Stage 1: Detect content type
      await _detectContentType(context);

      // Stage 2: Select extractor
      await _selectExtractor(context);

      // Stage 3: Extract document
      await _extractDocument(context);

      // Stage 4: Cache assets (BEFORE enhance)
      await _cacheAssets(context);

      // Stage 5: Enhance with ports (OCR/ASR/Vision)
      await _enhanceDocument(context);

      // Custom preChunk stages (DocumentTransformer)
      await _runPreChunkStages(context);

      // Stage 6: Chunk document
      await _chunkDocument(context);

      // Custom postChunk stages (ChunkPostProcessor)
      await _runPostChunkStages(context);

      // Stage 7: Extract fragments
      await _extractFragments(context);

      // Stage 8: Store assets (move from cache to permanent storage)
      await _storeAssets(context);

      // Stage 9: Build FactGraph entities
      await _buildFactGraphEntities(context);

      stopwatch.stop();

      return IngestResult(
        evidence: context.evidence!,
        fragments: context.fragments ?? [],
        chunks: context.chunks ?? [],
        warnings: context.warnings,
        metrics: IngestMetrics(
          totalDuration: stopwatch.elapsed,
          extractionDuration: context.extractionDuration,
          chunkingDuration: context.chunkingDuration,
          inputBytes: context.inputBytes,
          outputChunks: context.chunks?.length ?? 0,
          outputFragments: context.fragments?.length ?? 0,
          ocrCalls: context.ocrCalls,
          asrCalls: context.asrCalls,
          visionPortCalls: context.visionPortCalls,
          llmVisionCalls: context.llmVisionCalls,
        ),
      );
    } catch (e, stackTrace) {
      stopwatch.stop();

      return IngestResult.failed(
        error: IngestError(
          stage: context.currentStage,
          message: e.toString(),
          stackTrace: stackTrace.toString(),
        ),
        warnings: context.warnings,
        metrics: IngestMetrics(
          totalDuration: stopwatch.elapsed,
          extractionDuration: context.extractionDuration,
          chunkingDuration: context.chunkingDuration,
          inputBytes: context.inputBytes,
          outputChunks: 0,
          outputFragments: 0,
          ocrCalls: context.ocrCalls,
          asrCalls: context.asrCalls,
          visionPortCalls: context.visionPortCalls,
          llmVisionCalls: context.llmVisionCalls,
        ),
      );
    }
  }

  // ========================================================================
  // Stage 1: Detect content type
  // ========================================================================

  Future<void> _detectContentType(IngestContext context) async {
    context.currentStage = 'detect';

    final input = context.input;
    ContentType? contentType;

    // Try MIME type from input
    if (input.mimeType != null) {
      contentType = ContentType(input.mimeType!);
    }

    // Detect from magic bytes
    if (contentType == null) {
      final bytes = await _peekBytes(input.stream, 512);
      context.inputBytes = bytes.length;
      contentType = ContentTypeDetector.detect(bytes, input.filename);
    }

    context.contentType = contentType;
  }

  /// Read up to [maxBytes] from a stream without consuming it fully.
  Future<Uint8List> _peekBytes(Stream<List<int>> stream, int maxBytes) async {
    final chunks = <List<int>>[];
    var totalBytes = 0;

    await for (final chunk in stream) {
      chunks.add(chunk);
      totalBytes += chunk.length;
      if (totalBytes >= maxBytes) break;
    }

    final result = Uint8List(totalBytes);
    var offset = 0;
    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    return result;
  }

  // ========================================================================
  // Stage 2: Select extractor
  // ========================================================================

  Future<void> _selectExtractor(IngestContext context) async {
    context.currentStage = 'select';

    final extractor = extractors.find(context.contentType!);
    if (extractor == null) {
      throw UnsupportedFormatException(context.contentType!);
    }

    context.extractor = extractor;
  }

  // ========================================================================
  // Stage 3: Extract document
  // ========================================================================

  Future<void> _extractDocument(IngestContext context) async {
    context.currentStage = 'extract';

    final stopwatch = Stopwatch()..start();

    final extractOptions = ExtractOptions(
      maxPages: context.options.maxPages,
      extractImages: context.options.storeAssets,
      performOcr: false, // OCR handled by enhance stage
      extractTables: true,
    );

    context.document = await context.extractor!.extract(
      context.input.stream,
      extractOptions,
    );

    stopwatch.stop();
    context.extractionDuration = stopwatch.elapsed;
  }

  // ========================================================================
  // Stage 4: Cache assets
  // ========================================================================

  Future<void> _cacheAssets(IngestContext context) async {
    context.currentStage = 'cacheAssets';

    final document = context.document!;
    context.assetCache = {};

    for (final part in document.parts) {
      if (part is ImageBlock && part.assetRef.startsWith('inline:')) {
        final bytes = base64Decode(part.assetRef.substring(7));
        final cacheKey = 'cache:${part.id}';
        context.assetCache[cacheKey] = bytes;
        context.updatePart(part.id, part.copyWith(assetRef: cacheKey));
      }
      if (part is AudioBlock && part.assetRef.startsWith('inline:')) {
        final bytes = base64Decode(part.assetRef.substring(7));
        final cacheKey = 'cache:${part.id}';
        context.assetCache[cacheKey] = bytes;
        context.updatePart(part.id, part.copyWith(assetRef: cacheKey));
      }
    }
  }

  // ========================================================================
  // Stage 5: Enhance document with ports
  // ========================================================================

  Future<void> _enhanceDocument(IngestContext context) async {
    context.currentStage = 'enhance';

    final document = context.document!;

    for (final part in document.parts) {
      // OCR for images
      if (part is ImageBlock &&
          context.options.enableOcr &&
          ocrPort != null &&
          part.ocrText == null) {
        try {
          final bytes = context.assetCache[part.assetRef];
          if (bytes == null) {
            context.addWarning('Asset not cached: ${part.assetRef}');
            continue;
          }
          final result = await ocrPort!.recognize(
            Stream.value(bytes),
            OcrOptions(language: context.options.language ?? 'eng'),
          );
          context.updatePart(part.id, part.copyWith(ocrText: result.text));
          context.incrementOcrCalls();
        } catch (e) {
          context.addWarning('OCR failed for ${part.id}: $e');
        }
      }

      // ASR for audio
      if (part is AudioBlock &&
          context.options.enableAsr &&
          asrPort != null &&
          part.transcript == null) {
        try {
          final bytes = context.assetCache[part.assetRef];
          if (bytes == null) {
            context.addWarning('Asset not cached: ${part.assetRef}');
            continue;
          }
          final result = await asrPort!.transcribe(
            Stream.value(bytes),
            AsrOptions(language: context.options.language ?? 'en'),
          );
          context.updatePart(
              part.id,
              part.copyWith(
                transcript: result.text,
                segments: result.segments
                    ?.map((s) => TranscriptSegment(
                          startTime: s.startTime,
                          endTime: s.endTime,
                          text: s.text,
                          confidence: s.confidence,
                          speaker: s.speakerId,
                        ))
                    .toList(),
              ));
          context.incrementAsrCalls();
        } catch (e) {
          context.addWarning('ASR failed for ${part.id}: $e');
        }
      }

      // VisionPort for simple image analysis (~$0.001/image)
      if (part is ImageBlock &&
          context.options.enableVision &&
          visionPort != null &&
          part.visionDescription == null) {
        try {
          final bytes = context.assetCache[part.assetRef];
          if (bytes == null) {
            context.addWarning('Asset not cached: ${part.assetRef}');
            continue;
          }
          final result = await visionPort!.describe(
            Stream.value(bytes),
            const VisionOptions(),
          );
          context.updatePart(
              part.id,
              part.copyWith(
                visionDescription: result.description,
              ));
          context.incrementVisionPortCalls();
        } catch (e) {
          context.addWarning('Vision failed for ${part.id}: $e');
        }
      }

      // LlmPort for complex image understanding (~$0.01/image)
      if (part is ImageBlock &&
          context.options.enableLlmVision &&
          llmPort != null &&
          part.visionDescription == null) {
        try {
          final bytes = context.assetCache[part.assetRef];
          if (bytes == null) {
            context.addWarning('Asset not cached: ${part.assetRef}');
            continue;
          }
          final b64 = base64Encode(bytes);
          final response = await llmPort!.complete(LlmRequest(
            messages: [
              LlmMessage.user(
                'Describe this image in detail, including any text, charts, '
                'diagrams, or structured data.\n\n[image:$b64]',
              ),
            ],
            temperature: 0.0,
          ));
          context.updatePart(
              part.id,
              part.copyWith(
                visionDescription: response.content,
              ));
          context.incrementLlmVisionCalls();
        } catch (e) {
          context.addWarning('LLM Vision failed for ${part.id}: $e');
        }
      }
    }
  }

  // ========================================================================
  // Custom preChunk stages (DocumentTransformer)
  // ========================================================================

  Future<void> _runPreChunkStages(IngestContext context) async {
    if (customStages.isEmpty) return;
    context.currentStage = 'preChunkCustom';
    for (final stage in customStages) {
      if (stage.phase != StagePhase.preChunk) continue;
      try {
        context.document = await stage.process(context.document!);
      } catch (e) {
        context.addWarning('preChunk stage ${stage.id} failed: $e');
      }
    }
  }

  // ========================================================================
  // Custom postChunk stages (ChunkPostProcessor)
  // ========================================================================

  Future<void> _runPostChunkStages(IngestContext context) async {
    if (customStages.isEmpty) return;
    context.currentStage = 'postChunkCustom';
    for (final stage in customStages) {
      if (stage.phase != StagePhase.postChunk) continue;
      try {
        context.chunks = await stage.processChunks(context.chunks ?? []);
      } catch (e) {
        context.addWarning('postChunk stage ${stage.id} failed: $e');
      }
    }
  }

  // ========================================================================
  // Stage 6: Chunk document
  // ========================================================================

  Future<void> _chunkDocument(IngestContext context) async {
    context.currentStage = 'chunk';

    if (context.options.chunkingStrategy == ChunkingStrategy.none) {
      context.chunks = [];
      return;
    }

    final stopwatch = Stopwatch()..start();

    final chunker = chunkerFactory.create(context.options.chunkingStrategy);
    context.chunks = await chunker.chunk(
      context.document!,
      context.options.chunkOptions,
    );

    // Add context if enabled
    if (context.options.chunkOptions.includeContext) {
      final injector = ChunkContextInjector(
        maxContextLength: context.options.chunkOptions.maxContextLength,
      );
      context.chunks = injector.addContextToAll(
        context.chunks!,
        context.document!.structure,
      );
    }

    stopwatch.stop();
    context.chunkingDuration = stopwatch.elapsed;
  }

  // ========================================================================
  // Stage 7: Extract fragments
  // ========================================================================

  Future<void> _extractFragments(IngestContext context) async {
    context.currentStage = 'fragments';

    if (!context.options.extractFragments) {
      context.fragments = [];
      return;
    }

    final extractor = FragmentExtractor();
    context.fragments = extractor.extract(
      context.document!,
      context.options.fragmentRules ?? [],
    );
  }

  // ========================================================================
  // Stage 8: Store assets
  // ========================================================================

  Future<void> _storeAssets(IngestContext context) async {
    context.currentStage = 'store';

    if (!context.options.storeAssets || storagePort == null) {
      return;
    }

    final assets = <AssetRef>[];

    for (final part in context.document!.parts) {
      if (part is ImageBlock && part.assetRef.startsWith('cache:')) {
        final bytes = context.assetCache[part.assetRef];
        if (bytes != null) {
          final ref = await storagePort!.store(
            Stream.value(bytes),
            'image/png',
          );
          context.updatePart(part.id, part.copyWith(assetRef: ref));
          assets.add(AssetRef(id: ref, type: 'image', size: bytes.length));
        }
      }
      if (part is AudioBlock && part.assetRef.startsWith('cache:')) {
        final bytes = context.assetCache[part.assetRef];
        if (bytes != null) {
          final ref = await storagePort!.store(
            Stream.value(bytes),
            'audio/mpeg',
          );
          context.updatePart(part.id, part.copyWith(assetRef: ref));
          assets.add(AssetRef(id: ref, type: 'audio', size: bytes.length));
        }
      }
    }

    context.assets = assets;
    context.assetCache.clear();
  }

  // ========================================================================
  // Stage 9: Build FactGraph entities
  // ========================================================================

  Future<void> _buildFactGraphEntities(IngestContext context) async {
    context.currentStage = 'factgraph';

    final document = context.document!;
    final input = context.input;
    final now = DateTime.now();

    // Build Evidence entity
    context.evidence = Evidence(
      evidenceId: document.id,
      workspaceId: context.options.workspaceId,
      sourceType: _mapSourceType(document.metadata.mimeType),
      content: input.contentRef ?? '',
      contentHash: document.metadata.sha256,
      mimeType: document.metadata.mimeType,
      source: SourceInfo(
        name: input.filename ?? 'unknown',
        uri: input.sourceUri,
        capturedAt: document.metadata.createdAt,
      ),
      createdAt: now,
      ingestedAt: now,
      status: EvidenceStatus.extracted,
      fragmentIds: context.fragments?.map((f) => f.fragmentId).toList() ?? [],
      metadata: {
        if (document.metadata.title != null) 'title': document.metadata.title,
        if (document.metadata.pageCount != null)
          'pageCount': document.metadata.pageCount,
        if (document.metadata.language != null)
          'language': document.metadata.language,
        'provenance': {
          'extractorId': document.provenance.extractorId,
          'extractorVersion': document.provenance.extractorVersion,
        },
      },
    );

    // A fragment belongs to its evidence and to the evidence's workspace.
    if (context.fragments != null) {
      context.fragments = context.fragments!
          .map((f) => f.copyWith(
                evidenceId: context.evidence!.evidenceId,
                workspaceId: context.options.workspaceId,
              ))
          .toList();
    }
  }

  /// Map MIME type to EvidenceSourceType.
  EvidenceSourceType _mapSourceType(String mimeType) {
    if (mimeType.startsWith('text/')) return EvidenceSourceType.text;
    if (mimeType.startsWith('image/')) return EvidenceSourceType.image;
    if (mimeType.contains('json') || mimeType.contains('xml')) {
      return EvidenceSourceType.api;
    }
    return EvidenceSourceType.file;
  }

  // ========================================================================
  // Batch Processing
  // ========================================================================

  /// Ingest multiple files as a stream with actual concurrency.
  Stream<IngestResult> ingestBatch(
    Stream<IngestInput> inputs,
    IngestOptions options, {
    int concurrency = 4,
  }) async* {
    // Use Pool for actual concurrent processing
    final pool = Pool(concurrency);
    final futures = <Future<IngestResult>>[];

    await for (final input in inputs) {
      futures.add(pool.withResource(() => ingest(input, options)));
    }

    // Yield results as they complete
    for (final result in await Future.wait(futures)) {
      yield result;
    }

    await pool.close();
  }

  /// Ingest multiple inputs and collect all results.
  Future<List<IngestResult>> ingestAll(
    List<IngestInput> inputs,
    IngestOptions options, {
    int concurrency = 4,
  }) async {
    final results = <IngestResult>[];
    await for (final result in ingestBatch(
      Stream.fromIterable(inputs),
      options,
      concurrency: concurrency,
    )) {
      results.add(result);
    }
    return results;
  }
}
