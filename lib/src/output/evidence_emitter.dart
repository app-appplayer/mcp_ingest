/// Evidence Emitter - Converts NormalizedDocument to FactGraph Evidence.
///
/// Transforms ingested documents into Evidence entities for the L0 layer.
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:mcp_fact_graph/mcp_fact_graph.dart';

import '../document/normalized_document.dart';
import '../core/ingest_input.dart';
import '../core/content_type.dart';

/// Configuration for evidence emission.
class EvidenceEmitterConfig {
  /// Default workspace ID.
  final String defaultWorkspaceId;

  /// Whether to include full content in evidence.
  final bool includeFullContent;

  /// Maximum content size before truncation.
  final int maxContentSize;

  /// Whether to compute content hash.
  final bool computeHash;

  const EvidenceEmitterConfig({
    this.defaultWorkspaceId = 'default',
    this.includeFullContent = true,
    this.maxContentSize = 1024 * 1024, // 1MB
    this.computeHash = true,
  });

  /// Default configuration.
  static const defaults = EvidenceEmitterConfig();
}

/// Emits Evidence entities from NormalizedDocument.
class EvidenceEmitter {
  /// Emitter configuration.
  final EvidenceEmitterConfig config;

  EvidenceEmitter({this.config = EvidenceEmitterConfig.defaults});

  /// Emit evidence from a normalized document.
  Evidence emit({
    required NormalizedDocument document,
    required IngestInput input,
    ContentType? contentType,
    String? workspaceId,
    Map<String, dynamic>? additionalMetadata,
  }) {
    final content = _buildContent(document);
    final contentHash = config.computeHash ? _computeHash(content) : '';
    final detectedType = contentType ?? _detectContentType(input);

    final now = DateTime.now();
    return Evidence(
      evidenceId: _generateEvidenceId(document, input),
      workspaceId: workspaceId ?? config.defaultWorkspaceId,
      sourceType: _mapSourceType(detectedType),
      content: content,
      contentHash: contentHash,
      mimeType: detectedType.mimeType,
      source: _buildSourceInfo(input, document),
      createdAt: now,
      ingestedAt: now,
      status: EvidenceStatus.extracted,
      fragmentIds: const [],
      metadata:
          _buildMetadata(document, input, detectedType, additionalMetadata),
    );
  }

  /// Emit evidence from raw input (before document normalization).
  Future<Evidence> emitFromRaw({
    required IngestInput input,
    String? workspaceId,
    Map<String, dynamic>? metadata,
  }) async {
    final bytes = await input.collectBytes();
    final content = base64Encode(bytes);
    final contentHash = config.computeHash ? _computeHash(content) : '';
    final contentType = ContentTypeDetector.detect(bytes, input.filename) ??
        const ContentType('application/octet-stream');

    final now = DateTime.now();
    return Evidence(
      evidenceId: 'ev_${_computeHash(content).substring(0, 12)}',
      workspaceId: workspaceId ?? config.defaultWorkspaceId,
      sourceType: _mapSourceType(contentType),
      content: content,
      contentHash: contentHash,
      mimeType: contentType.mimeType,
      source: SourceInfo(
        name: input.filename ?? 'unknown',
        uri: input.sourceUri,
        capturedAt: now,
      ),
      createdAt: now,
      ingestedAt: now,
      status: EvidenceStatus.pending,
      fragmentIds: const [],
      metadata: metadata ?? const {},
    );
  }

  /// Build content from normalized document.
  String _buildContent(NormalizedDocument document) {
    if (!config.includeFullContent) {
      return document.id;
    }

    final content = document.fullText;
    if (content.length > config.maxContentSize) {
      return content.substring(0, config.maxContentSize);
    }
    return content;
  }

  /// Detect content type from input.
  ContentType _detectContentType(IngestInput input) {
    if (input.mimeType != null) {
      return ContentType(input.mimeType!, filename: input.filename);
    }
    if (input.filename != null) {
      return ContentTypeDetector.detectFromFilename(input.filename!);
    }
    return const ContentType('application/octet-stream');
  }

  /// Generate evidence ID.
  String _generateEvidenceId(NormalizedDocument document, IngestInput input) {
    final uniqueData =
        '${document.id}:${input.sourceUri ?? ''}:${DateTime.now().millisecondsSinceEpoch}';
    final hash = _computeHash(uniqueData);
    return 'ev_${hash.substring(0, 12)}';
  }

  /// Compute SHA-256 hash.
  String _computeHash(String content) {
    final bytes = utf8.encode(content);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Map content type to evidence source type.
  EvidenceSourceType _mapSourceType(ContentType contentType) {
    if (contentType.isText) {
      return EvidenceSourceType.text;
    }
    if (contentType.isImage) {
      return EvidenceSourceType.image;
    }
    if (contentType.mimeType.contains('json') ||
        contentType.mimeType.contains('xml')) {
      return EvidenceSourceType.api;
    }
    if (contentType.mimeType.contains('email') ||
        contentType.mimeType.contains('message')) {
      return EvidenceSourceType.message;
    }
    return EvidenceSourceType.file;
  }

  /// Build source info from input.
  SourceInfo _buildSourceInfo(IngestInput input, NormalizedDocument document) {
    return SourceInfo(
      name: input.filename ?? document.metadata.title ?? document.id,
      uri: input.sourceUri,
      capturedAt: document.provenance.extractedAt,
      attributes: {
        'extractorId': document.provenance.extractorId,
        'extractorVersion': document.provenance.extractorVersion,
      },
    );
  }

  /// Build metadata from document and input.
  Map<String, dynamic> _buildMetadata(
    NormalizedDocument document,
    IngestInput input,
    ContentType contentType,
    Map<String, dynamic>? additional,
  ) {
    return {
      'documentId': document.id,
      'partCount': document.partCount,
      'characterCount': document.characterCount,
      'contentType': contentType.mimeType,
      if (input.filename != null) 'fileName': input.filename,
      if (input.size != null) 'fileSize': input.size,
      if (document.metadata.author != null) 'author': document.metadata.author,
      if (document.metadata.createdAt != null)
        'createdAt': document.metadata.createdAt!.toIso8601String(),
      ...?additional,
    };
  }
}

/// Batch evidence emitter for multiple documents.
class BatchEvidenceEmitter {
  /// Single emitter instance.
  final EvidenceEmitter _emitter;

  BatchEvidenceEmitter({EvidenceEmitterConfig? config})
      : _emitter =
            EvidenceEmitter(config: config ?? EvidenceEmitterConfig.defaults);

  /// Emit evidence for multiple documents.
  List<Evidence> emitBatch({
    required List<(NormalizedDocument, IngestInput, ContentType?)> items,
    String? workspaceId,
  }) {
    return items.map((item) {
      return _emitter.emit(
        document: item.$1,
        input: item.$2,
        contentType: item.$3,
        workspaceId: workspaceId,
      );
    }).toList();
  }

  /// Emit evidence stream for large batches.
  Stream<Evidence> emitStream({
    required Stream<(NormalizedDocument, IngestInput, ContentType?)> items,
    String? workspaceId,
  }) async* {
    await for (final item in items) {
      yield _emitter.emit(
        document: item.$1,
        input: item.$2,
        contentType: item.$3,
        workspaceId: workspaceId,
      );
    }
  }
}
