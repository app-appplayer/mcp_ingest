/// Port usage tracking for cost estimation.
library;

/// Tracks port usage for cost estimation.
///
/// Records API calls to OCR, ASR, Vision, and LLM services
/// to estimate costs and monitor usage.
class PortUsageTracker {
  // === OCR Tracking ===

  /// Number of OCR pages processed.
  int _ocrPages = 0;

  /// OCR processing time.
  Duration _ocrDuration = Duration.zero;

  // === ASR Tracking ===

  /// ASR audio duration processed.
  Duration _asrAudioDuration = Duration.zero;

  /// ASR processing time.
  Duration _asrProcessingDuration = Duration.zero;

  // === Vision Tracking ===

  /// Number of vision API calls.
  int _visionCalls = 0;

  /// Vision processing time.
  Duration _visionDuration = Duration.zero;

  // === LLM Vision Tracking ===

  /// Number of LLM vision calls.
  int _llmVisionCalls = 0;

  /// LLM input tokens.
  int _llmInputTokens = 0;

  /// LLM output tokens.
  int _llmOutputTokens = 0;

  // === Storage Tracking ===

  /// Bytes stored.
  int _storageBytes = 0;

  /// Number of store operations.
  int _storeOperations = 0;

  /// Number of retrieve operations.
  int _retrieveOperations = 0;

  // === Cost Rates (USD) ===

  /// Cost per OCR page.
  static const double ocrCostPerPage = 0.001;

  /// Cost per minute of ASR.
  static const double asrCostPerMinute = 0.006;

  /// Cost per vision API call.
  static const double visionCostPerCall = 0.001;

  /// Cost per LLM vision call.
  static const double llmVisionCostPerCall = 0.01;

  /// Cost per 1K input tokens.
  static const double llmInputCostPer1K = 0.003;

  /// Cost per 1K output tokens.
  static const double llmOutputCostPer1K = 0.015;

  /// Cost per GB stored (monthly).
  static const double storageCostPerGbMonth = 0.023;

  // === Recording Methods ===

  /// Record OCR usage.
  void recordOcr({
    required int pages,
    Duration? processingTime,
  }) {
    _ocrPages += pages;
    if (processingTime != null) {
      _ocrDuration += processingTime;
    }
  }

  /// Record ASR usage.
  void recordAsr({
    required Duration audioDuration,
    Duration? processingTime,
  }) {
    _asrAudioDuration += audioDuration;
    if (processingTime != null) {
      _asrProcessingDuration += processingTime;
    }
  }

  /// Record Vision API usage.
  void recordVision({
    int calls = 1,
    Duration? processingTime,
  }) {
    _visionCalls += calls;
    if (processingTime != null) {
      _visionDuration += processingTime;
    }
  }

  /// Record LLM Vision usage.
  void recordLlmVision({
    int calls = 1,
    int inputTokens = 0,
    int outputTokens = 0,
  }) {
    _llmVisionCalls += calls;
    _llmInputTokens += inputTokens;
    _llmOutputTokens += outputTokens;
  }

  /// Record storage operation.
  void recordStorage({
    int bytesStored = 0,
    bool isStore = true,
  }) {
    _storageBytes += bytesStored;
    if (isStore) {
      _storeOperations++;
    } else {
      _retrieveOperations++;
    }
  }

  // === Cost Calculations ===

  /// Estimated OCR cost.
  double get ocrCost => _ocrPages * ocrCostPerPage;

  /// Estimated ASR cost.
  double get asrCost => _asrAudioDuration.inMinutes * asrCostPerMinute;

  /// Estimated Vision API cost.
  double get visionCost => _visionCalls * visionCostPerCall;

  /// Estimated LLM Vision cost.
  double get llmVisionCost {
    final inputCost = (_llmInputTokens / 1000) * llmInputCostPer1K;
    final outputCost = (_llmOutputTokens / 1000) * llmOutputCostPer1K;
    return _llmVisionCalls * llmVisionCostPerCall + inputCost + outputCost;
  }

  /// Estimated monthly storage cost.
  double get storageCost {
    final gbStored = _storageBytes / (1024 * 1024 * 1024);
    return gbStored * storageCostPerGbMonth;
  }

  /// Total estimated cost.
  double get totalCost => ocrCost + asrCost + visionCost + llmVisionCost;

  // === Accessors ===

  /// OCR pages processed.
  int get ocrPages => _ocrPages;

  /// ASR audio duration.
  Duration get asrAudioDuration => _asrAudioDuration;

  /// Vision API calls.
  int get visionCalls => _visionCalls;

  /// LLM Vision calls.
  int get llmVisionCalls => _llmVisionCalls;

  /// Storage bytes.
  int get storageBytes => _storageBytes;

  // === Summary ===

  /// Get usage summary.
  UsageSummary get summary => UsageSummary(
        ocr: OcrUsage(
          pages: _ocrPages,
          processingTime: _ocrDuration,
          cost: ocrCost,
        ),
        asr: AsrUsage(
          audioDuration: _asrAudioDuration,
          processingTime: _asrProcessingDuration,
          cost: asrCost,
        ),
        vision: VisionUsage(
          calls: _visionCalls,
          processingTime: _visionDuration,
          cost: visionCost,
        ),
        llmVision: LlmVisionUsage(
          calls: _llmVisionCalls,
          inputTokens: _llmInputTokens,
          outputTokens: _llmOutputTokens,
          cost: llmVisionCost,
        ),
        storage: StorageUsage(
          bytes: _storageBytes,
          storeOperations: _storeOperations,
          retrieveOperations: _retrieveOperations,
          monthlyCost: storageCost,
        ),
        totalCost: totalCost,
      );

  /// Reset all counters.
  void reset() {
    _ocrPages = 0;
    _ocrDuration = Duration.zero;
    _asrAudioDuration = Duration.zero;
    _asrProcessingDuration = Duration.zero;
    _visionCalls = 0;
    _visionDuration = Duration.zero;
    _llmVisionCalls = 0;
    _llmInputTokens = 0;
    _llmOutputTokens = 0;
    _storageBytes = 0;
    _storeOperations = 0;
    _retrieveOperations = 0;
  }

  /// Export as JSON.
  Map<String, dynamic> toJson() => summary.toJson();
}

/// Complete usage summary.
class UsageSummary {
  final OcrUsage ocr;
  final AsrUsage asr;
  final VisionUsage vision;
  final LlmVisionUsage llmVision;
  final StorageUsage storage;
  final double totalCost;

  const UsageSummary({
    required this.ocr,
    required this.asr,
    required this.vision,
    required this.llmVision,
    required this.storage,
    required this.totalCost,
  });

  Map<String, dynamic> toJson() => {
        'ocr': ocr.toJson(),
        'asr': asr.toJson(),
        'vision': vision.toJson(),
        'llmVision': llmVision.toJson(),
        'storage': storage.toJson(),
        'totalCost': totalCost,
        'totalCostFormatted': '\$${totalCost.toStringAsFixed(4)}',
      };
}

/// OCR usage details.
class OcrUsage {
  final int pages;
  final Duration processingTime;
  final double cost;

  const OcrUsage({
    required this.pages,
    required this.processingTime,
    required this.cost,
  });

  Map<String, dynamic> toJson() => {
        'pages': pages,
        'processingTimeMs': processingTime.inMilliseconds,
        'cost': cost,
      };
}

/// ASR usage details.
class AsrUsage {
  final Duration audioDuration;
  final Duration processingTime;
  final double cost;

  const AsrUsage({
    required this.audioDuration,
    required this.processingTime,
    required this.cost,
  });

  Map<String, dynamic> toJson() => {
        'audioDurationSeconds': audioDuration.inSeconds,
        'processingTimeMs': processingTime.inMilliseconds,
        'cost': cost,
      };
}

/// Vision API usage details.
class VisionUsage {
  final int calls;
  final Duration processingTime;
  final double cost;

  const VisionUsage({
    required this.calls,
    required this.processingTime,
    required this.cost,
  });

  Map<String, dynamic> toJson() => {
        'calls': calls,
        'processingTimeMs': processingTime.inMilliseconds,
        'cost': cost,
      };
}

/// LLM Vision usage details.
class LlmVisionUsage {
  final int calls;
  final int inputTokens;
  final int outputTokens;
  final double cost;

  const LlmVisionUsage({
    required this.calls,
    required this.inputTokens,
    required this.outputTokens,
    required this.cost,
  });

  Map<String, dynamic> toJson() => {
        'calls': calls,
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        'cost': cost,
      };
}

/// Storage usage details.
class StorageUsage {
  final int bytes;
  final int storeOperations;
  final int retrieveOperations;
  final double monthlyCost;

  const StorageUsage({
    required this.bytes,
    required this.storeOperations,
    required this.retrieveOperations,
    required this.monthlyCost,
  });

  Map<String, dynamic> toJson() => {
        'bytes': bytes,
        'bytesFormatted': _formatBytes(bytes),
        'storeOperations': storeOperations,
        'retrieveOperations': retrieveOperations,
        'monthlyCost': monthlyCost,
      };

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
