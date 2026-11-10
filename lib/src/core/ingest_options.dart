/// Ingest options and configuration.
library;

import '../chunkers/chunker.dart';
import 'fragment_rule.dart';

/// Chunking strategy for document splitting.
enum ChunkingStrategy {
  /// No chunking - return whole document as single chunk.
  none,

  /// Split by sentences.
  sentence,

  /// Split by paragraphs (default).
  paragraph,

  /// Split by pages.
  page,

  /// Split by fixed character count.
  fixedSize,

  /// Keep tables as separate chunks.
  table,

  /// LLM-based semantic chunking.
  semantic,
}

/// Options for ingestion.
class IngestOptions {
  // === Extraction ===

  /// Perform OCR on images (requires OcrPort).
  final bool enableOcr;

  /// Perform ASR on audio (requires AsrPort).
  final bool enableAsr;

  /// Use dedicated VisionPort for simple image analysis (cheaper).
  final bool enableVision;

  /// Use LlmPort for complex image understanding (Claude/GPT-4V, costlier).
  final bool enableLlmVision;

  /// Extract and store images/audio as assets.
  final bool storeAssets;

  /// Workspace the emitted Evidence belongs to.
  final String workspaceId;

  // === Chunking ===

  /// Chunking strategy.
  final ChunkingStrategy chunkingStrategy;

  /// Chunk options.
  final ChunkOptions chunkOptions;

  // === Fragments (FactGraph) ===

  /// Extract fragments (mcp_fact_graph Fragment entities).
  final bool extractFragments;

  /// Fragment extraction rules.
  final List<FragmentRule>? fragmentRules;

  // === Limits ===

  /// Maximum file size to process (bytes).
  final int? maxFileSize;

  /// Maximum pages to process.
  final int? maxPages;

  /// Target language for OCR/ASR.
  final String? language;

  /// Timeout for extraction.
  final Duration? timeout;

  const IngestOptions({
    this.enableOcr = false,
    this.enableAsr = false,
    this.enableVision = false,
    this.enableLlmVision = false,
    this.storeAssets = true,
    this.workspaceId = 'default',
    this.chunkingStrategy = ChunkingStrategy.paragraph,
    this.chunkOptions = const ChunkOptions(),
    this.extractFragments = false,
    this.fragmentRules,
    this.maxFileSize,
    this.maxPages,
    this.language,
    this.timeout,
  });

  /// Minimal extraction (fastest, no external services).
  static const minimal = IngestOptions(
    enableOcr: false,
    enableAsr: false,
    enableVision: false,
    enableLlmVision: false,
    storeAssets: false,
    extractFragments: false,
    chunkingStrategy: ChunkingStrategy.none,
  );

  /// Default extraction (balanced).
  static const defaults = IngestOptions(
    enableOcr: false,
    enableAsr: false,
    enableVision: false,
    enableLlmVision: false,
    storeAssets: true,
    extractFragments: false,
    chunkingStrategy: ChunkingStrategy.paragraph,
  );

  /// Cheap vision (VisionPort only, lower cost).
  static const cheapVision = IngestOptions(
    enableOcr: true,
    enableVision: true,
    enableLlmVision: false,
    storeAssets: true,
    chunkingStrategy: ChunkingStrategy.paragraph,
  );

  /// Rich vision (LlmPort for complex understanding).
  static const richVision = IngestOptions(
    enableOcr: true,
    enableVision: false,
    enableLlmVision: true,
    storeAssets: true,
    chunkingStrategy: ChunkingStrategy.paragraph,
  );

  /// Full extraction (slowest, may incur costs).
  static const full = IngestOptions(
    enableOcr: true,
    enableAsr: true,
    enableVision: true,
    enableLlmVision: true,
    storeAssets: true,
    extractFragments: true,
    chunkingStrategy: ChunkingStrategy.semantic,
  );

  IngestOptions copyWith({
    bool? enableOcr,
    bool? enableAsr,
    bool? enableVision,
    bool? enableLlmVision,
    bool? storeAssets,
    String? workspaceId,
    bool? extractFragments,
    ChunkingStrategy? chunkingStrategy,
    ChunkOptions? chunkOptions,
    int? maxPages,
    int? maxFileSize,
    String? language,
    List<FragmentRule>? fragmentRules,
    Duration? timeout,
  }) {
    return IngestOptions(
      enableOcr: enableOcr ?? this.enableOcr,
      enableAsr: enableAsr ?? this.enableAsr,
      enableVision: enableVision ?? this.enableVision,
      enableLlmVision: enableLlmVision ?? this.enableLlmVision,
      storeAssets: storeAssets ?? this.storeAssets,
      workspaceId: workspaceId ?? this.workspaceId,
      extractFragments: extractFragments ?? this.extractFragments,
      chunkingStrategy: chunkingStrategy ?? this.chunkingStrategy,
      chunkOptions: chunkOptions ?? this.chunkOptions,
      maxPages: maxPages ?? this.maxPages,
      maxFileSize: maxFileSize ?? this.maxFileSize,
      language: language ?? this.language,
      fragmentRules: fragmentRules ?? this.fragmentRules,
      timeout: timeout ?? this.timeout,
    );
  }
}

/// Builder for IngestOptions.
class IngestOptionsBuilder {
  bool _enableOcr = false;
  bool _enableAsr = false;
  bool _enableVision = false;
  bool _enableLlmVision = false;
  bool _storeAssets = true;
  String _workspaceId = 'default';
  bool _extractFragments = false;
  ChunkingStrategy _chunkingStrategy = ChunkingStrategy.paragraph;
  ChunkOptions _chunkOptions = const ChunkOptions();
  int? _maxPages;
  int? _maxFileSize;
  String? _language;
  List<FragmentRule>? _fragmentRules;
  Duration? _timeout;

  IngestOptionsBuilder enableOcr([bool value = true]) {
    _enableOcr = value;
    return this;
  }

  IngestOptionsBuilder enableAsr([bool value = true]) {
    _enableAsr = value;
    return this;
  }

  IngestOptionsBuilder enableVision([bool value = true]) {
    _enableVision = value;
    return this;
  }

  IngestOptionsBuilder enableLlmVision([bool value = true]) {
    _enableLlmVision = value;
    return this;
  }

  IngestOptionsBuilder workspaceId(String value) {
    _workspaceId = value;
    return this;
  }

  IngestOptionsBuilder storeAssets([bool value = true]) {
    _storeAssets = value;
    return this;
  }

  IngestOptionsBuilder extractFragments([bool value = true]) {
    _extractFragments = value;
    return this;
  }

  IngestOptionsBuilder chunkBy(ChunkingStrategy strategy) {
    _chunkingStrategy = strategy;
    return this;
  }

  IngestOptionsBuilder chunkOptions(ChunkOptions options) {
    _chunkOptions = options;
    return this;
  }

  IngestOptionsBuilder maxPages(int value) {
    _maxPages = value;
    return this;
  }

  IngestOptionsBuilder maxFileSize(int value) {
    _maxFileSize = value;
    return this;
  }

  IngestOptionsBuilder language(String value) {
    _language = value;
    return this;
  }

  IngestOptionsBuilder fragmentRules(List<FragmentRule> value) {
    _fragmentRules = value;
    return this;
  }

  IngestOptionsBuilder timeout(Duration value) {
    _timeout = value;
    return this;
  }

  IngestOptions build() => IngestOptions(
        enableOcr: _enableOcr,
        enableAsr: _enableAsr,
        enableVision: _enableVision,
        enableLlmVision: _enableLlmVision,
        storeAssets: _storeAssets,
        workspaceId: _workspaceId,
        extractFragments: _extractFragments,
        chunkingStrategy: _chunkingStrategy,
        chunkOptions: _chunkOptions,
        maxPages: _maxPages,
        maxFileSize: _maxFileSize,
        language: _language,
        fragmentRules: _fragmentRules,
        timeout: _timeout,
      );
}
