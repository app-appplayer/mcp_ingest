/// Cost budget management for ingest operations.
library;

import '../ports/port_usage_tracker.dart';

/// Exception thrown when budget is exceeded.
class BudgetExceededException implements Exception {
  /// Requested cost that would exceed budget.
  final double requestedCost;

  /// Current spent amount.
  final double currentSpent;

  /// Maximum budget.
  final double maxBudget;

  /// Operation that would exceed budget.
  final String? operation;

  BudgetExceededException({
    required this.requestedCost,
    required this.currentSpent,
    required this.maxBudget,
    this.operation,
  });

  @override
  String toString() {
    final opStr = operation != null ? ' for $operation' : '';
    return 'BudgetExceededException: Requested \$$requestedCost$opStr would '
        'exceed budget (spent: \$$currentSpent, max: \$$maxBudget)';
  }
}

/// Cost budget configuration and tracking.
///
/// Allows setting budget limits for different operation types
/// and checking if operations would exceed the budget.
class CostBudget {
  /// Maximum total budget in USD.
  final double? maxTotalBudget;

  /// Maximum OCR budget in USD.
  final double? maxOcrBudget;

  /// Maximum ASR budget in USD.
  final double? maxAsrBudget;

  /// Maximum Vision budget in USD.
  final double? maxVisionBudget;

  /// Maximum LLM budget in USD.
  final double? maxLlmBudget;

  /// Usage tracker for cost tracking.
  final PortUsageTracker _tracker;

  /// Create a cost budget with optional limits.
  CostBudget({
    this.maxTotalBudget,
    this.maxOcrBudget,
    this.maxAsrBudget,
    this.maxVisionBudget,
    this.maxLlmBudget,
    PortUsageTracker? tracker,
  }) : _tracker = tracker ?? PortUsageTracker();

  /// Get the usage tracker.
  PortUsageTracker get tracker => _tracker;

  // ========================================================================
  // Current Costs
  // ========================================================================

  /// Current total cost.
  double get totalCost => _tracker.totalCost;

  /// Current OCR cost.
  double get ocrCost => _tracker.ocrCost;

  /// Current ASR cost.
  double get asrCost => _tracker.asrCost;

  /// Current Vision cost.
  double get visionCost => _tracker.visionCost;

  /// Current LLM cost.
  double get llmCost => _tracker.llmVisionCost;

  // ========================================================================
  // Remaining Budget
  // ========================================================================

  /// Remaining total budget (null if unlimited).
  double? get remainingTotalBudget =>
      maxTotalBudget != null ? maxTotalBudget! - totalCost : null;

  /// Remaining OCR budget (null if unlimited).
  double? get remainingOcrBudget =>
      maxOcrBudget != null ? maxOcrBudget! - ocrCost : null;

  /// Remaining ASR budget (null if unlimited).
  double? get remainingAsrBudget =>
      maxAsrBudget != null ? maxAsrBudget! - asrCost : null;

  /// Remaining Vision budget (null if unlimited).
  double? get remainingVisionBudget =>
      maxVisionBudget != null ? maxVisionBudget! - visionCost : null;

  /// Remaining LLM budget (null if unlimited).
  double? get remainingLlmBudget =>
      maxLlmBudget != null ? maxLlmBudget! - llmCost : null;

  // ========================================================================
  // Budget Checks
  // ========================================================================

  /// Check if total budget has been exceeded.
  bool get isTotalBudgetExceeded =>
      maxTotalBudget != null && totalCost >= maxTotalBudget!;

  /// Check if OCR budget has been exceeded.
  bool get isOcrBudgetExceeded =>
      maxOcrBudget != null && ocrCost >= maxOcrBudget!;

  /// Check if ASR budget has been exceeded.
  bool get isAsrBudgetExceeded =>
      maxAsrBudget != null && asrCost >= maxAsrBudget!;

  /// Check if Vision budget has been exceeded.
  bool get isVisionBudgetExceeded =>
      maxVisionBudget != null && visionCost >= maxVisionBudget!;

  /// Check if LLM budget has been exceeded.
  bool get isLlmBudgetExceeded =>
      maxLlmBudget != null && llmCost >= maxLlmBudget!;

  // ========================================================================
  // Cost Estimation
  // ========================================================================

  /// Estimate cost for OCR operation.
  double estimateOcrCost(int pages) {
    return pages * PortUsageTracker.ocrCostPerPage;
  }

  /// Estimate cost for ASR operation.
  double estimateAsrCost(Duration audioDuration) {
    return audioDuration.inMinutes * PortUsageTracker.asrCostPerMinute;
  }

  /// Estimate cost for Vision operation.
  double estimateVisionCost(int calls) {
    return calls * PortUsageTracker.visionCostPerCall;
  }

  /// Estimate cost for LLM Vision operation.
  double estimateLlmVisionCost(int calls, {int inputTokens = 0, int outputTokens = 0}) {
    return calls * PortUsageTracker.llmVisionCostPerCall +
        (inputTokens / 1000) * PortUsageTracker.llmInputCostPer1K +
        (outputTokens / 1000) * PortUsageTracker.llmOutputCostPer1K;
  }

  // ========================================================================
  // Budget Validation
  // ========================================================================

  /// Check if OCR operation would fit in budget.
  ///
  /// Returns true if the operation can proceed, false otherwise.
  bool canAffordOcr(int pages) {
    final cost = estimateOcrCost(pages);
    return _canAfford(cost, ocrCost, maxOcrBudget, 'OCR');
  }

  /// Check if ASR operation would fit in budget.
  bool canAffordAsr(Duration audioDuration) {
    final cost = estimateAsrCost(audioDuration);
    return _canAfford(cost, asrCost, maxAsrBudget, 'ASR');
  }

  /// Check if Vision operation would fit in budget.
  bool canAffordVision(int calls) {
    final cost = estimateVisionCost(calls);
    return _canAfford(cost, visionCost, maxVisionBudget, 'Vision');
  }

  /// Check if LLM operation would fit in budget.
  bool canAffordLlm(int calls, {int inputTokens = 0, int outputTokens = 0}) {
    final cost = estimateLlmVisionCost(calls, inputTokens: inputTokens, outputTokens: outputTokens);
    return _canAfford(cost, llmCost, maxLlmBudget, 'LLM');
  }

  bool _canAfford(
    double requestedCost,
    double currentCost,
    double? maxBudget,
    String operation,
  ) {
    // Check category budget
    if (maxBudget != null && currentCost + requestedCost > maxBudget) {
      return false;
    }

    // Check total budget
    if (maxTotalBudget != null && totalCost + requestedCost > maxTotalBudget!) {
      return false;
    }

    return true;
  }

  // ========================================================================
  // Enforce Budget
  // ========================================================================

  /// Check OCR budget and throw if exceeded.
  void checkOcrBudget(int pages) {
    final cost = estimateOcrCost(pages);
    _checkBudget(cost, ocrCost, maxOcrBudget, 'OCR');
    _checkTotalBudget(cost, 'OCR');
  }

  /// Check ASR budget and throw if exceeded.
  void checkAsrBudget(Duration audioDuration) {
    final cost = estimateAsrCost(audioDuration);
    _checkBudget(cost, asrCost, maxAsrBudget, 'ASR');
    _checkTotalBudget(cost, 'ASR');
  }

  /// Check Vision budget and throw if exceeded.
  void checkVisionBudget(int calls) {
    final cost = estimateVisionCost(calls);
    _checkBudget(cost, visionCost, maxVisionBudget, 'Vision');
    _checkTotalBudget(cost, 'Vision');
  }

  /// Check LLM budget and throw if exceeded.
  void checkLlmBudget(int calls, {int inputTokens = 0, int outputTokens = 0}) {
    final cost = estimateLlmVisionCost(calls, inputTokens: inputTokens, outputTokens: outputTokens);
    _checkBudget(cost, llmCost, maxLlmBudget, 'LLM');
    _checkTotalBudget(cost, 'LLM');
  }

  void _checkBudget(
    double requestedCost,
    double currentCost,
    double? maxBudget,
    String operation,
  ) {
    if (maxBudget != null && currentCost + requestedCost > maxBudget) {
      throw BudgetExceededException(
        requestedCost: requestedCost,
        currentSpent: currentCost,
        maxBudget: maxBudget,
        operation: operation,
      );
    }
  }

  void _checkTotalBudget(double requestedCost, String operation) {
    if (maxTotalBudget != null && totalCost + requestedCost > maxTotalBudget!) {
      throw BudgetExceededException(
        requestedCost: requestedCost,
        currentSpent: totalCost,
        maxBudget: maxTotalBudget!,
        operation: '$operation (total budget)',
      );
    }
  }

  // ========================================================================
  // Usage Recording (Delegated to tracker)
  // ========================================================================

  /// Record OCR usage.
  void recordOcr({required int pages, Duration? processingTime}) {
    _tracker.recordOcr(pages: pages, processingTime: processingTime);
  }

  /// Record ASR usage.
  void recordAsr({required Duration audioDuration, Duration? processingTime}) {
    _tracker.recordAsr(audioDuration: audioDuration, processingTime: processingTime);
  }

  /// Record Vision usage.
  void recordVision({int calls = 1, Duration? processingTime}) {
    _tracker.recordVision(calls: calls, processingTime: processingTime);
  }

  /// Record LLM usage.
  void recordLlm({int calls = 1, int inputTokens = 0, int outputTokens = 0}) {
    _tracker.recordLlmVision(calls: calls, inputTokens: inputTokens, outputTokens: outputTokens);
  }

  /// Record storage usage.
  void recordStorage({int bytesStored = 0, bool isStore = true}) {
    _tracker.recordStorage(bytesStored: bytesStored, isStore: isStore);
  }

  // ========================================================================
  // Summary
  // ========================================================================

  /// Get usage summary.
  UsageSummary get summary => _tracker.summary;

  /// Get budget status.
  BudgetStatus get status => BudgetStatus(
        totalCost: totalCost,
        maxTotalBudget: maxTotalBudget,
        ocrCost: ocrCost,
        maxOcrBudget: maxOcrBudget,
        asrCost: asrCost,
        maxAsrBudget: maxAsrBudget,
        visionCost: visionCost,
        maxVisionBudget: maxVisionBudget,
        llmCost: llmCost,
        maxLlmBudget: maxLlmBudget,
      );

  /// Reset all counters.
  void reset() {
    _tracker.reset();
  }

  // ========================================================================
  // Factory Constructors
  // ========================================================================

  /// Create unlimited budget (no limits).
  factory CostBudget.unlimited({PortUsageTracker? tracker}) {
    return CostBudget(tracker: tracker);
  }

  /// Create budget with total limit only.
  factory CostBudget.total(double maxBudget, {PortUsageTracker? tracker}) {
    return CostBudget(maxTotalBudget: maxBudget, tracker: tracker);
  }

  /// Create budget with per-category limits.
  factory CostBudget.perCategory({
    double? ocr,
    double? asr,
    double? vision,
    double? llm,
    PortUsageTracker? tracker,
  }) {
    return CostBudget(
      maxOcrBudget: ocr,
      maxAsrBudget: asr,
      maxVisionBudget: vision,
      maxLlmBudget: llm,
      tracker: tracker,
    );
  }

  /// Create strict budget with all limits.
  factory CostBudget.strict({
    required double maxTotal,
    double? maxOcr,
    double? maxAsr,
    double? maxVision,
    double? maxLlm,
    PortUsageTracker? tracker,
  }) {
    return CostBudget(
      maxTotalBudget: maxTotal,
      maxOcrBudget: maxOcr,
      maxAsrBudget: maxAsr,
      maxVisionBudget: maxVision,
      maxLlmBudget: maxLlm,
      tracker: tracker,
    );
  }
}

/// Budget status summary.
class BudgetStatus {
  final double totalCost;
  final double? maxTotalBudget;
  final double ocrCost;
  final double? maxOcrBudget;
  final double asrCost;
  final double? maxAsrBudget;
  final double visionCost;
  final double? maxVisionBudget;
  final double llmCost;
  final double? maxLlmBudget;

  const BudgetStatus({
    required this.totalCost,
    this.maxTotalBudget,
    required this.ocrCost,
    this.maxOcrBudget,
    required this.asrCost,
    this.maxAsrBudget,
    required this.visionCost,
    this.maxVisionBudget,
    required this.llmCost,
    this.maxLlmBudget,
  });

  /// Check if any budget is exceeded.
  bool get isExceeded =>
      (maxTotalBudget != null && totalCost >= maxTotalBudget!) ||
      (maxOcrBudget != null && ocrCost >= maxOcrBudget!) ||
      (maxAsrBudget != null && asrCost >= maxAsrBudget!) ||
      (maxVisionBudget != null && visionCost >= maxVisionBudget!) ||
      (maxLlmBudget != null && llmCost >= maxLlmBudget!);

  /// Percentage of total budget used (0-1, or null if unlimited).
  double? get totalUsagePercent =>
      maxTotalBudget != null ? totalCost / maxTotalBudget! : null;

  Map<String, dynamic> toJson() => {
        'totalCost': totalCost,
        'totalCostFormatted': '\$${totalCost.toStringAsFixed(4)}',
        if (maxTotalBudget != null) 'maxTotalBudget': maxTotalBudget,
        'categories': {
          'ocr': {
            'cost': ocrCost,
            if (maxOcrBudget != null) 'maxBudget': maxOcrBudget,
          },
          'asr': {
            'cost': asrCost,
            if (maxAsrBudget != null) 'maxBudget': maxAsrBudget,
          },
          'vision': {
            'cost': visionCost,
            if (maxVisionBudget != null) 'maxBudget': maxVisionBudget,
          },
          'llm': {
            'cost': llmCost,
            if (maxLlmBudget != null) 'maxBudget': maxLlmBudget,
          },
        },
        'isExceeded': isExceeded,
      };
}
