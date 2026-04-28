import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:mcp_ingest/mcp_ingest.dart';
import 'package:mcp_fact_graph/mcp_fact_graph.dart'
    show
        Evidence,
        Fragment,
        EvidenceSourceType,
        EvidenceStatus,
        SourceInfo,
        ExtractorType,
        FragmentStatus;

void main() {
  group('Exceptions', () {
    test('UnsupportedFormatException creates with content type', () {
      final contentType = ContentType('video/mp4');
      final ex = UnsupportedFormatException(contentType);
      expect(ex.message, contains('video/mp4'));
      expect(ex.contentType, equals(contentType));
    });

    test('ExtractionException creates with extractor id', () {
      final ex = ExtractionException('pdf_v1', 'Failed to parse');
      expect(ex.message, contains('pdf_v1'));
      expect(ex.message, contains('Failed to parse'));
      expect(ex.extractorId, equals('pdf_v1'));
    });

    test('ExtractionException with cause', () {
      final cause = FormatException('Invalid data');
      final ex = ExtractionException('json_v1', 'Parse error', cause);
      expect(ex.cause, equals(cause));
    });

    test('FileSizeLimitException creates with sizes', () {
      final ex = FileSizeLimitException(1000000, 500000);
      expect(ex.actualSize, equals(1000000));
      expect(ex.maxSize, equals(500000));
      expect(ex.message, contains('1000000'));
      expect(ex.message, contains('500000'));
    });

    test('PageLimitException creates with page counts', () {
      final ex = PageLimitException(100, 50);
      expect(ex.actualPages, equals(100));
      expect(ex.maxPages, equals(50));
      expect(ex.message, contains('100'));
    });

    test('PortNotConfiguredException creates with port name', () {
      final ex = PortNotConfiguredException('OcrPort');
      expect(ex.portName, equals('OcrPort'));
      expect(ex.message, contains('OcrPort'));
    });

    test('PluginNotAvailableException creates with plugin name', () {
      final ex = PluginNotAvailableException('TesseractOcr');
      expect(ex.pluginName, equals('TesseractOcr'));
      expect(ex.message, contains('TesseractOcr'));
    });

    test('ChunkingException creates with chunker id', () {
      final ex = ChunkingException('semantic_v1', 'LLM timeout');
      expect(ex.chunkerId, equals('semantic_v1'));
      expect(ex.message, contains('semantic_v1'));
    });

    test('PipelineStageException creates with stage name', () {
      final ex = PipelineStageException('extraction', 'Failed');
      expect(ex.stageName, equals('extraction'));
      expect(ex.message, contains('extraction'));
    });

    test('IngestException toString formats correctly', () {
      final ex = ExtractionException('test', 'error');
      expect(ex.toString(), contains('IngestException'));
    });
  });

  group('PortUsageTracker', () {
    late PortUsageTracker tracker;

    setUp(() {
      tracker = PortUsageTracker();
    });

    test('initial state is zero', () {
      expect(tracker.ocrPages, equals(0));
      expect(tracker.visionCalls, equals(0));
      expect(tracker.llmVisionCalls, equals(0));
      expect(tracker.storageBytes, equals(0));
      expect(tracker.totalCost, equals(0.0));
    });

    test('records OCR usage', () {
      tracker.recordOcr(pages: 10, processingTime: const Duration(seconds: 5));
      expect(tracker.ocrPages, equals(10));
      expect(tracker.ocrCost, closeTo(0.01, 0.001));
    });

    test('records ASR usage', () {
      tracker.recordAsr(
        audioDuration: const Duration(minutes: 5),
        processingTime: const Duration(seconds: 30),
      );
      expect(tracker.asrAudioDuration, equals(const Duration(minutes: 5)));
      expect(tracker.asrCost, closeTo(0.03, 0.001));
    });

    test('records Vision usage', () {
      tracker.recordVision(calls: 5, processingTime: const Duration(seconds: 2));
      expect(tracker.visionCalls, equals(5));
      expect(tracker.visionCost, closeTo(0.005, 0.001));
    });

    test('records LLM Vision usage', () {
      tracker.recordLlmVision(calls: 2, inputTokens: 1000, outputTokens: 500);
      expect(tracker.llmVisionCalls, equals(2));
      expect(tracker.llmVisionCost, greaterThan(0));
    });

    test('records storage usage', () {
      tracker.recordStorage(bytesStored: 1024 * 1024, isStore: true);
      tracker.recordStorage(bytesStored: 0, isStore: false);
      expect(tracker.storageBytes, equals(1024 * 1024));
    });

    test('calculates total cost', () {
      tracker.recordOcr(pages: 10);
      tracker.recordVision(calls: 5);
      expect(tracker.totalCost, greaterThan(0));
    });

    test('reset clears all counters', () {
      tracker.recordOcr(pages: 10);
      tracker.recordVision(calls: 5);
      tracker.reset();
      expect(tracker.ocrPages, equals(0));
      expect(tracker.visionCalls, equals(0));
      expect(tracker.totalCost, equals(0.0));
    });

    test('summary returns UsageSummary', () {
      tracker.recordOcr(pages: 5);
      tracker.recordAsr(audioDuration: const Duration(minutes: 2));
      final summary = tracker.summary;
      expect(summary.ocr.pages, equals(5));
      expect(summary.totalCost, greaterThan(0));
    });

    test('toJson exports summary', () {
      tracker.recordOcr(pages: 5);
      final json = tracker.toJson();
      expect(json['ocr'], isNotNull);
      expect(json['totalCost'], isNotNull);
    });
  });

  group('UsageSummary', () {
    test('toJson includes all fields', () {
      const summary = UsageSummary(
        ocr: OcrUsage(pages: 10, processingTime: Duration.zero, cost: 0.01),
        asr: AsrUsage(audioDuration: Duration.zero, processingTime: Duration.zero, cost: 0.0),
        vision: VisionUsage(calls: 5, processingTime: Duration.zero, cost: 0.005),
        llmVision: LlmVisionUsage(calls: 0, inputTokens: 0, outputTokens: 0, cost: 0.0),
        storage: StorageUsage(bytes: 0, storeOperations: 0, retrieveOperations: 0, monthlyCost: 0.0),
        totalCost: 0.015,
      );
      final json = summary.toJson();
      expect(json['ocr'], isNotNull);
      expect(json['asr'], isNotNull);
      expect(json['vision'], isNotNull);
      expect(json['totalCostFormatted'], contains('\$'));
    });
  });

  group('CostBudget', () {
    test('unlimited budget has no limits', () {
      final budget = CostBudget.unlimited();
      expect(budget.maxTotalBudget, isNull);
      expect(budget.maxOcrBudget, isNull);
      expect(budget.canAffordOcr(1000), isTrue);
    });

    test('total budget limits all operations', () {
      final budget = CostBudget.total(0.1);
      expect(budget.maxTotalBudget, equals(0.1));
      expect(budget.remainingTotalBudget, equals(0.1));
    });

    test('perCategory creates category limits', () {
      final budget = CostBudget.perCategory(
        ocr: 0.05,
        asr: 0.1,
        vision: 0.02,
      );
      expect(budget.maxOcrBudget, equals(0.05));
      expect(budget.maxAsrBudget, equals(0.1));
      expect(budget.maxVisionBudget, equals(0.02));
    });

    test('strict creates all limits', () {
      final budget = CostBudget.strict(
        maxTotal: 1.0,
        maxOcr: 0.2,
        maxAsr: 0.3,
      );
      expect(budget.maxTotalBudget, equals(1.0));
      expect(budget.maxOcrBudget, equals(0.2));
    });

    test('estimateOcrCost calculates correctly', () {
      final budget = CostBudget.unlimited();
      final cost = budget.estimateOcrCost(100);
      expect(cost, closeTo(0.1, 0.01));
    });

    test('estimateAsrCost calculates correctly', () {
      final budget = CostBudget.unlimited();
      final cost = budget.estimateAsrCost(const Duration(minutes: 10));
      expect(cost, closeTo(0.06, 0.01));
    });

    test('estimateVisionCost calculates correctly', () {
      final budget = CostBudget.unlimited();
      final cost = budget.estimateVisionCost(50);
      expect(cost, closeTo(0.05, 0.01));
    });

    test('canAffordOcr checks budget', () {
      final budget = CostBudget.perCategory(ocr: 0.01);
      expect(budget.canAffordOcr(5), isTrue);
      expect(budget.canAffordOcr(100), isFalse);
    });

    test('canAffordAsr checks budget', () {
      final budget = CostBudget.perCategory(asr: 0.01);
      expect(budget.canAffordAsr(const Duration(minutes: 1)), isTrue);
      expect(budget.canAffordAsr(const Duration(hours: 1)), isFalse);
    });

    test('canAffordVision checks budget', () {
      final budget = CostBudget.perCategory(vision: 0.01);
      expect(budget.canAffordVision(5), isTrue);
      expect(budget.canAffordVision(100), isFalse);
    });

    test('canAffordLlm checks budget', () {
      final budget = CostBudget.perCategory(llm: 0.1);
      expect(budget.canAffordLlm(1), isTrue);
      expect(budget.canAffordLlm(100), isFalse);
    });

    test('checkOcrBudget throws when exceeded', () {
      final budget = CostBudget.perCategory(ocr: 0.001);
      expect(
        () => budget.checkOcrBudget(100),
        throwsA(isA<BudgetExceededException>()),
      );
    });

    test('checkAsrBudget throws when exceeded', () {
      final budget = CostBudget.perCategory(asr: 0.001);
      expect(
        () => budget.checkAsrBudget(const Duration(hours: 1)),
        throwsA(isA<BudgetExceededException>()),
      );
    });

    test('checkVisionBudget throws when exceeded', () {
      final budget = CostBudget.perCategory(vision: 0.001);
      expect(
        () => budget.checkVisionBudget(100),
        throwsA(isA<BudgetExceededException>()),
      );
    });

    test('checkLlmBudget throws when exceeded', () {
      final budget = CostBudget.perCategory(llm: 0.001);
      expect(
        () => budget.checkLlmBudget(100),
        throwsA(isA<BudgetExceededException>()),
      );
    });

    test('recordOcr updates tracker', () {
      final budget = CostBudget.unlimited();
      budget.recordOcr(pages: 10);
      expect(budget.ocrCost, greaterThan(0));
    });

    test('recordAsr updates tracker', () {
      final budget = CostBudget.unlimited();
      budget.recordAsr(audioDuration: const Duration(minutes: 5));
      expect(budget.asrCost, greaterThan(0));
    });

    test('recordVision updates tracker', () {
      final budget = CostBudget.unlimited();
      budget.recordVision(calls: 5);
      expect(budget.visionCost, greaterThan(0));
    });

    test('recordLlm updates tracker', () {
      final budget = CostBudget.unlimited();
      budget.recordLlm(calls: 2, inputTokens: 100);
      expect(budget.llmCost, greaterThan(0));
    });

    test('recordStorage updates tracker', () {
      final budget = CostBudget.unlimited();
      budget.recordStorage(bytesStored: 1024);
      expect(budget.tracker.storageBytes, equals(1024));
    });

    test('isTotalBudgetExceeded checks correctly', () {
      final budget = CostBudget.total(0.001);
      expect(budget.isTotalBudgetExceeded, isFalse);
      budget.recordOcr(pages: 100);
      expect(budget.isTotalBudgetExceeded, isTrue);
    });

    test('status returns BudgetStatus', () {
      final budget = CostBudget.total(1.0);
      budget.recordOcr(pages: 10);
      final status = budget.status;
      expect(status.totalCost, greaterThan(0));
      expect(status.maxTotalBudget, equals(1.0));
    });

    test('reset clears all usage', () {
      final budget = CostBudget.unlimited();
      budget.recordOcr(pages: 10);
      budget.reset();
      expect(budget.totalCost, equals(0.0));
    });

    test('summary returns UsageSummary', () {
      final budget = CostBudget.unlimited();
      budget.recordOcr(pages: 5);
      final summary = budget.summary;
      expect(summary.ocr.pages, equals(5));
    });
  });

  group('BudgetExceededException', () {
    test('creates with required fields', () {
      final ex = BudgetExceededException(
        requestedCost: 0.5,
        currentSpent: 0.8,
        maxBudget: 1.0,
      );
      expect(ex.requestedCost, equals(0.5));
      expect(ex.currentSpent, equals(0.8));
      expect(ex.maxBudget, equals(1.0));
    });

    test('creates with operation', () {
      final ex = BudgetExceededException(
        requestedCost: 0.5,
        currentSpent: 0.8,
        maxBudget: 1.0,
        operation: 'OCR',
      );
      expect(ex.operation, equals('OCR'));
      expect(ex.toString(), contains('OCR'));
    });

    test('toString formats correctly', () {
      final ex = BudgetExceededException(
        requestedCost: 0.5,
        currentSpent: 0.8,
        maxBudget: 1.0,
      );
      final str = ex.toString();
      expect(str, contains('0.5'));
      expect(str, contains('0.8'));
      expect(str, contains('1.0'));
    });
  });

  group('BudgetStatus', () {
    test('isExceeded checks all limits', () {
      const status = BudgetStatus(
        totalCost: 1.5,
        maxTotalBudget: 1.0,
        ocrCost: 0.1,
        asrCost: 0.1,
        visionCost: 0.1,
        llmCost: 0.1,
      );
      expect(status.isExceeded, isTrue);
    });

    test('isExceeded false when under limits', () {
      const status = BudgetStatus(
        totalCost: 0.5,
        maxTotalBudget: 1.0,
        ocrCost: 0.1,
        asrCost: 0.1,
        visionCost: 0.1,
        llmCost: 0.1,
      );
      expect(status.isExceeded, isFalse);
    });

    test('totalUsagePercent calculates correctly', () {
      const status = BudgetStatus(
        totalCost: 0.5,
        maxTotalBudget: 1.0,
        ocrCost: 0.1,
        asrCost: 0.1,
        visionCost: 0.1,
        llmCost: 0.1,
      );
      expect(status.totalUsagePercent, equals(0.5));
    });

    test('totalUsagePercent null when unlimited', () {
      const status = BudgetStatus(
        totalCost: 0.5,
        ocrCost: 0.1,
        asrCost: 0.1,
        visionCost: 0.1,
        llmCost: 0.1,
      );
      expect(status.totalUsagePercent, isNull);
    });

    test('toJson includes all fields', () {
      const status = BudgetStatus(
        totalCost: 0.5,
        maxTotalBudget: 1.0,
        ocrCost: 0.1,
        maxOcrBudget: 0.2,
        asrCost: 0.1,
        visionCost: 0.1,
        llmCost: 0.1,
      );
      final json = status.toJson();
      expect(json['totalCost'], equals(0.5));
      expect(json['totalCostFormatted'], contains('\$'));
      expect(json['categories'], isNotNull);
      expect(json['isExceeded'], isFalse);
    });
  });

  group('FragmentRule', () {
    test('creates with required fields', () {
      const rule = FragmentRule(
        id: 'test_rule',
        field: 'amount',
        pattern: r'\d+',
      );
      expect(rule.id, equals('test_rule'));
      expect(rule.field, equals('amount'));
      expect(rule.pattern, equals(r'\d+'));
      expect(rule.minConfidence, equals(0.5));
    });

    test('creates with all fields', () {
      const rule = FragmentRule(
        id: 'test_rule',
        field: 'amount',
        valueType: FragmentValueType.currency,
        patternType: FragmentPatternType.regex,
        pattern: r'\$[\d,]+',
        transform: 'parseCurrency',
        minConfidence: 0.8,
        priority: 10,
      );
      expect(rule.valueType, equals(FragmentValueType.currency));
      expect(rule.patternType, equals(FragmentPatternType.regex));
      expect(rule.transform, equals('parseCurrency'));
      expect(rule.minConfidence, equals(0.8));
      expect(rule.priority, equals(10));
    });

    test('fromJson parses correctly', () {
      final json = {
        'id': 'rule1',
        'field': 'date',
        'valueType': 'date',
        'patternType': 'regex',
        'pattern': r'\d{4}-\d{2}-\d{2}',
        'minConfidence': 0.9,
        'priority': 5,
      };
      final rule = FragmentRule.fromJson(json);
      expect(rule.id, equals('rule1'));
      expect(rule.field, equals('date'));
      expect(rule.valueType, equals(FragmentValueType.date));
      expect(rule.minConfidence, equals(0.9));
    });

    test('toJson serializes correctly', () {
      const rule = FragmentRule(
        id: 'test',
        field: 'name',
        pattern: r'\w+',
        transform: 'uppercase',
      );
      final json = rule.toJson();
      expect(json['id'], equals('test'));
      expect(json['field'], equals('name'));
      expect(json['pattern'], equals(r'\w+'));
      expect(json['transform'], equals('uppercase'));
    });

    test('fromJson handles defaults', () {
      final json = {
        'id': 'rule1',
        'field': 'test',
        'pattern': 'test',
      };
      final rule = FragmentRule.fromJson(json);
      expect(rule.valueType, equals(FragmentValueType.string));
      expect(rule.patternType, equals(FragmentPatternType.regex));
      expect(rule.minConfidence, equals(0.5));
      expect(rule.priority, equals(0));
    });
  });

  group('FragmentPatternType', () {
    test('fromString parses valid types', () {
      expect(FragmentPatternType.fromString('regex'), equals(FragmentPatternType.regex));
      expect(FragmentPatternType.fromString('keyword'), equals(FragmentPatternType.keyword));
      expect(FragmentPatternType.fromString('keyValue'), equals(FragmentPatternType.keyValue));
      expect(FragmentPatternType.fromString('jsonPath'), equals(FragmentPatternType.jsonPath));
      expect(FragmentPatternType.fromString('xpath'), equals(FragmentPatternType.xpath));
      expect(FragmentPatternType.fromString('custom'), equals(FragmentPatternType.custom));
    });

    test('fromString returns regex for invalid', () {
      expect(FragmentPatternType.fromString('invalid'), equals(FragmentPatternType.regex));
    });
  });

  group('IngestInput extended', () {
    test('creates from bytes with filename', () {
      final input = IngestInput.fromBytes(
        Uint8List.fromList([1, 2, 3]),
        filename: 'test.bin',
        mimeType: 'application/octet-stream',
      );
      expect(input.filename, equals('test.bin'));
      expect(input.mimeType, equals('application/octet-stream'));
      expect(input.size, equals(3));
    });

    test('creates from string with custom mimeType', () {
      final input = IngestInput.fromString(
        '{"key": "value"}',
        mimeType: 'application/json',
        filename: 'data.json',
      );
      expect(input.mimeType, equals('application/json'));
      expect(input.filename, equals('data.json'));
    });

    test('collectBytes collects stream bytes', () async {
      final input = IngestInput.fromString('Hello World');
      final bytes = await input.collectBytes();
      expect(String.fromCharCodes(bytes), equals('Hello World'));
    });

    test('collectBytes handles multiple chunks', () async {
      final input = IngestInput(
        stream: Stream.fromIterable([
          [72, 101, 108, 108, 111], // Hello
          [32], // space
          [87, 111, 114, 108, 100], // World
        ]),
        size: 11,
      );
      final bytes = await input.collectBytes();
      expect(bytes.length, equals(11));
      expect(String.fromCharCodes(bytes), equals('Hello World'));
    });

    test('fromUri throws for unsupported scheme', () {
      expect(
        () => IngestInput.fromUri(Uri.parse('http://example.com')),
        throwsArgumentError,
      );
    });
  });

  group('IngestOptions extended', () {
    test('minimal preset disables all features', () {
      const options = IngestOptions.minimal;
      expect(options.enableOcr, isFalse);
      expect(options.enableAsr, isFalse);
      expect(options.enableVision, isFalse);
      expect(options.enableLlmVision, isFalse);
      expect(options.storeAssets, isFalse);
      expect(options.chunkingStrategy, equals(ChunkingStrategy.none));
    });

    test('cheapVision enables OCR and Vision', () {
      const options = IngestOptions.cheapVision;
      expect(options.enableOcr, isTrue);
      expect(options.enableVision, isTrue);
      expect(options.enableLlmVision, isFalse);
    });

    test('richVision enables OCR and LlmVision', () {
      const options = IngestOptions.richVision;
      expect(options.enableOcr, isTrue);
      expect(options.enableVision, isFalse);
      expect(options.enableLlmVision, isTrue);
    });

    test('full enables all features', () {
      const options = IngestOptions.full;
      expect(options.enableOcr, isTrue);
      expect(options.enableAsr, isTrue);
      expect(options.enableVision, isTrue);
      expect(options.enableLlmVision, isTrue);
      expect(options.extractFragments, isTrue);
      expect(options.chunkingStrategy, equals(ChunkingStrategy.semantic));
    });

    test('copyWith updates multiple fields', () {
      const original = IngestOptions.defaults;
      final modified = original.copyWith(
        enableOcr: true,
        enableAsr: true,
        maxPages: 100,
        maxFileSize: 1000000,
        language: 'ko',
        timeout: const Duration(minutes: 5),
      );
      expect(modified.enableOcr, isTrue);
      expect(modified.enableAsr, isTrue);
      expect(modified.maxPages, equals(100));
      expect(modified.maxFileSize, equals(1000000));
      expect(modified.language, equals('ko'));
      expect(modified.timeout, equals(const Duration(minutes: 5)));
    });

    test('copyWith updates chunk options', () {
      const original = IngestOptions.defaults;
      final modified = original.copyWith(
        chunkOptions: const ChunkOptions(
          targetSize: 500,
          maxSize: 1000,
          overlap: 50,
          includeContext: false,
        ),
      );
      expect(modified.chunkOptions.targetSize, equals(500));
      expect(modified.chunkOptions.maxSize, equals(1000));
      expect(modified.chunkOptions.overlap, equals(50));
      expect(modified.chunkOptions.includeContext, isFalse);
    });
  });

  group('IngestOptionsBuilder extended', () {
    test('enables all vision options', () {
      final options = IngestOptionsBuilder()
          .enableVision()
          .enableLlmVision()
          .build();
      expect(options.enableVision, isTrue);
      expect(options.enableLlmVision, isTrue);
    });

    test('sets storage and fragment options', () {
      final options = IngestOptionsBuilder()
          .storeAssets(false)
          .extractFragments()
          .build();
      expect(options.storeAssets, isFalse);
      expect(options.extractFragments, isTrue);
    });

    test('sets maxPages and maxFileSize', () {
      final options = IngestOptionsBuilder()
          .maxPages(50)
          .maxFileSize(5000000)
          .build();
      expect(options.maxPages, equals(50));
      expect(options.maxFileSize, equals(5000000));
    });

    test('sets language and fragment rules', () {
      final options = IngestOptionsBuilder()
          .language('en')
          .fragmentRules([
            const FragmentRule(id: 'r1', field: 'name', pattern: r'\w+'),
          ])
          .build();
      expect(options.language, equals('en'));
      expect(options.fragmentRules?.length, equals(1));
    });

    test('sets timeout', () {
      final options = IngestOptionsBuilder()
          .timeout(const Duration(seconds: 30))
          .build();
      expect(options.timeout, equals(const Duration(seconds: 30)));
    });

    test('sets chunkOptions', () {
      final options = IngestOptionsBuilder()
          .chunkOptions(const ChunkOptions(
            targetSize: 500,
            maxSize: 1000,
            includeContext: false,
          ))
          .build();
      expect(options.chunkOptions.targetSize, equals(500));
      expect(options.chunkOptions.maxSize, equals(1000));
      expect(options.chunkOptions.includeContext, isFalse);
    });

    test('enableAsr method', () {
      final options = IngestOptionsBuilder()
          .enableAsr()
          .build();
      expect(options.enableAsr, isTrue);
    });
  });

  group('ChunkingStrategy', () {
    test('has all expected values', () {
      expect(ChunkingStrategy.values, contains(ChunkingStrategy.none));
      expect(ChunkingStrategy.values, contains(ChunkingStrategy.sentence));
      expect(ChunkingStrategy.values, contains(ChunkingStrategy.paragraph));
      expect(ChunkingStrategy.values, contains(ChunkingStrategy.page));
      expect(ChunkingStrategy.values, contains(ChunkingStrategy.fixedSize));
      expect(ChunkingStrategy.values, contains(ChunkingStrategy.table));
      expect(ChunkingStrategy.values, contains(ChunkingStrategy.semantic));
    });
  });

  group('ContentType', () {
    test('creates from mimeType', () {
      final ct = ContentType('application/pdf');
      expect(ct.mimeType, equals('application/pdf'));
    });

    test('primaryType extracts primary type', () {
      final ct = ContentType('text/html');
      expect(ct.primaryType, equals('text'));
    });

    test('subType extracts sub type', () {
      final ct = ContentType('text/html');
      expect(ct.subType, equals('html'));
    });

    test('isText checks text types', () {
      expect(ContentType('text/plain').isText, isTrue);
      expect(ContentType('text/html').isText, isTrue);
      expect(ContentType('application/json').isText, isTrue);
      expect(ContentType('image/png').isText, isFalse);
    });

    test('isImage checks image types', () {
      expect(ContentType('image/png').isImage, isTrue);
      expect(ContentType('image/jpeg').isImage, isTrue);
      expect(ContentType('text/plain').isImage, isFalse);
    });

    test('isAudio checks audio types', () {
      expect(ContentType('audio/mpeg').isAudio, isTrue);
      expect(ContentType('audio/wav').isAudio, isTrue);
      expect(ContentType('text/plain').isAudio, isFalse);
    });

    test('isDocument checks document types', () {
      expect(ContentType('application/pdf').isDocument, isTrue);
      expect(ContentType('text/plain').isDocument, isFalse);
    });

    test('isVideo checks video types', () {
      expect(ContentType('video/mp4').isVideo, isTrue);
      expect(ContentType('text/plain').isVideo, isFalse);
    });

    test('equality and hashCode', () {
      final ct1 = ContentType('text/plain');
      final ct2 = ContentType('text/plain');
      final ct3 = ContentType('text/html');
      expect(ct1, equals(ct2));
      expect(ct1.hashCode, equals(ct2.hashCode));
      expect(ct1, isNot(equals(ct3)));
    });

    test('toString returns mimeType', () {
      final ct = ContentType('application/json');
      expect(ct.toString(), equals('application/json'));
    });
  });

  group('CommonFragmentRules', () {
    test('amount rule is configured', () {
      expect(CommonFragmentRules.amount.field, equals('amount'));
      expect(CommonFragmentRules.amount.valueType, equals(FragmentValueType.currency));
    });

    test('date rule is configured', () {
      expect(CommonFragmentRules.date.field, equals('date'));
      expect(CommonFragmentRules.date.valueType, equals(FragmentValueType.date));
    });

    test('merchant rule is configured', () {
      expect(CommonFragmentRules.merchant.field, equals('merchant'));
      expect(CommonFragmentRules.merchant.valueType, equals(FragmentValueType.string));
    });

    test('all returns all common rules', () {
      expect(CommonFragmentRules.all.length, equals(3));
    });
  });

  // =========================================================================
  // NEW TEST GROUPS
  // =========================================================================

  group('SourcePosition', () {
    test('constructor sets fields', () {
      const pos = SourcePosition(start: 10, end: 20, line: 3);
      expect(pos.start, equals(10));
      expect(pos.end, equals(20));
      expect(pos.line, equals(3));
    });

    test('toJson includes line when present', () {
      const pos = SourcePosition(start: 5, end: 15, line: 2);
      final json = pos.toJson();
      expect(json['start'], equals(5));
      expect(json['end'], equals(15));
      expect(json['line'], equals(2));
    });

    test('toJson omits line when null', () {
      const pos = SourcePosition(start: 0, end: 10);
      final json = pos.toJson();
      expect(json['start'], equals(0));
      expect(json['end'], equals(10));
      expect(json.containsKey('line'), isFalse);
    });

    test('fromJson with line', () {
      final json = {'start': 100, 'end': 200, 'line': 7};
      final pos = SourcePosition.fromJson(json);
      expect(pos.start, equals(100));
      expect(pos.end, equals(200));
      expect(pos.line, equals(7));
    });

    test('fromJson without line', () {
      final json = {'start': 50, 'end': 60};
      final pos = SourcePosition.fromJson(json);
      expect(pos.start, equals(50));
      expect(pos.end, equals(60));
      expect(pos.line, isNull);
    });

    test('round-trip toJson/fromJson preserves data', () {
      const original = SourcePosition(start: 42, end: 99, line: 11);
      final roundTripped = SourcePosition.fromJson(original.toJson());
      expect(roundTripped.start, equals(original.start));
      expect(roundTripped.end, equals(original.end));
      expect(roundTripped.line, equals(original.line));
    });

    test('round-trip without line preserves null', () {
      const original = SourcePosition(start: 0, end: 5);
      final roundTripped = SourcePosition.fromJson(original.toJson());
      expect(roundTripped.start, equals(0));
      expect(roundTripped.end, equals(5));
      expect(roundTripped.line, isNull);
    });
  });

  group('FragmentValueType', () {
    test('fromString with unknown value returns string (orElse path)', () {
      final result = FragmentValueType.fromString('nonexistent_type');
      expect(result, equals(FragmentValueType.string));
    });

    test('fromString with valid values', () {
      expect(
          FragmentValueType.fromString('number'), FragmentValueType.number);
      expect(
          FragmentValueType.fromString('boolean'), FragmentValueType.boolean);
      expect(FragmentValueType.fromString('date'), FragmentValueType.date);
      expect(FragmentValueType.fromString('datetime'),
          FragmentValueType.datetime);
      expect(FragmentValueType.fromString('currency'),
          FragmentValueType.currency);
      expect(FragmentValueType.fromString('percentage'),
          FragmentValueType.percentage);
      expect(FragmentValueType.fromString('array'), FragmentValueType.array);
      expect(
          FragmentValueType.fromString('object'), FragmentValueType.object);
      expect(
          FragmentValueType.fromString('unknown'), FragmentValueType.unknown);
    });
  });

  group('IngestResult', () {
    late Evidence testEvidence;
    late Fragment testFragment;
    late DateTime now;

    setUp(() {
      now = DateTime.now();
      testEvidence = Evidence(
        evidenceId: 'ev-1',
        workspaceId: 'ws-1',
        sourceType: EvidenceSourceType.file,
        content: 'test content',
        contentHash: 'abc123',
        source: const SourceInfo(name: 'test-source'),
        createdAt: now,
        ingestedAt: now,
        status: EvidenceStatus.extracted,
      );
      testFragment = Fragment(
        fragmentId: 'frag-1',
        workspaceId: 'ws-1',
        evidenceId: 'ev-1',
        fields: {'field': 'amount', 'value': '100.00'},
        confidence: 0.95,
        extractor: ExtractorType.rule,
        status: FragmentStatus.proposed,
        createdAt: now,
      );
    });

    test('IngestResult.success() factory creates successful result', () {
      final chunks = [
        Chunk(
          id: 'c1',
          text: 'Hello world',
          sourceSpans: const [
            ChunkSpan(partId: 'p1', startOffset: 0, endOffset: 11),
          ],
          location: const SourceLocation(),
          index: 0,
          totalChunks: 1,
        ),
      ];

      final result = IngestResult.success(
        evidence: testEvidence,
        fragments: [testFragment],
        chunks: chunks,
        warnings: ['minor warning'],
        metrics: const IngestMetrics(
          totalDuration: Duration(seconds: 1),
          inputBytes: 100,
          outputChunks: 1,
          outputFragments: 1,
        ),
      );

      expect(result.success, isTrue);
      expect(result.evidence, equals(testEvidence));
      expect(result.fragments.length, equals(1));
      expect(result.chunks.length, equals(1));
      expect(result.warnings, contains('minor warning'));
    });

    test('IngestResult.failed() factory creates failed result', () {
      final result = IngestResult.failed(
        error: const IngestError(
          stage: 'extraction',
          message: 'Parse failed',
        ),
        warnings: ['something happened'],
        metrics: IngestMetrics.empty,
      );

      expect(result.success, isFalse);
      expect(result.evidence, isNull);
      expect(result.error, isNotNull);
      expect(result.warnings, contains('something happened'));
    });

    test('success getter is false when error is set', () {
      final result = IngestResult(
        error: const IngestError(stage: 'test', message: 'err'),
        metrics: IngestMetrics.empty,
      );
      expect(result.success, isFalse);
    });

    test('errorMessage getter returns message from error', () {
      final result = IngestResult.failed(
        error: const IngestError(
          stage: 'extraction',
          message: 'File corrupt',
        ),
        metrics: IngestMetrics.empty,
      );
      expect(result.errorMessage, equals('File corrupt'));
    });

    test('errorMessage getter returns null when no error', () {
      final result = IngestResult.success(
        evidence: testEvidence,
        fragments: [],
        chunks: [],
        metrics: IngestMetrics.empty,
      );
      expect(result.errorMessage, isNull);
    });

    test('totalChunkLength sums chunk text lengths', () {
      final chunks = [
        Chunk(
          id: 'c1',
          text: 'Hello',
          sourceSpans: const [],
          location: const SourceLocation(),
          index: 0,
          totalChunks: 2,
        ),
        Chunk(
          id: 'c2',
          text: 'World!',
          sourceSpans: const [],
          location: const SourceLocation(),
          index: 1,
          totalChunks: 2,
        ),
      ];

      final result = IngestResult.success(
        evidence: testEvidence,
        fragments: [],
        chunks: chunks,
        metrics: IngestMetrics.empty,
      );
      expect(result.totalChunkLength, equals(11)); // 5 + 6
    });

    test('fragmentCount returns number of fragments', () {
      final result = IngestResult.success(
        evidence: testEvidence,
        fragments: [testFragment, testFragment],
        chunks: [],
        metrics: IngestMetrics.empty,
      );
      expect(result.fragmentCount, equals(2));
    });

    test('IngestMetrics.toJson() includes all fields', () {
      const metrics = IngestMetrics(
        totalDuration: Duration(milliseconds: 1500),
        extractionDuration: Duration(milliseconds: 1000),
        chunkingDuration: Duration(milliseconds: 500),
        inputBytes: 2048,
        outputChunks: 5,
        outputFragments: 3,
        ocrCalls: 2,
        asrCalls: 1,
        visionPortCalls: 4,
        llmVisionCalls: 1,
      );
      final json = metrics.toJson();
      expect(json['totalDurationMs'], equals(1500));
      expect(json['extractionDurationMs'], equals(1000));
      expect(json['chunkingDurationMs'], equals(500));
      expect(json['inputBytes'], equals(2048));
      expect(json['outputChunks'], equals(5));
      expect(json['outputFragments'], equals(3));
      expect(json['ocrCalls'], equals(2));
      expect(json['asrCalls'], equals(1));
      expect(json['visionPortCalls'], equals(4));
      expect(json['llmVisionCalls'], equals(1));
      expect(json['estimatedCost'], isA<double>());
    });

    test('IngestMetrics.estimatedCost formula', () {
      const metrics = IngestMetrics(
        totalDuration: Duration.zero,
        inputBytes: 0,
        outputChunks: 0,
        outputFragments: 0,
        ocrCalls: 10,
        asrCalls: 5,
        visionPortCalls: 20,
        llmVisionCalls: 3,
      );
      // 10 * 0.001 + 5 * 0.006 + 20 * 0.001 + 3 * 0.01 = 0.01 + 0.03 + 0.02 + 0.03 = 0.09
      expect(metrics.estimatedCost, closeTo(0.09, 0.0001));
    });

    test('IngestMetrics.empty has zero values', () {
      const metrics = IngestMetrics.empty;
      expect(metrics.totalDuration, equals(Duration.zero));
      expect(metrics.inputBytes, equals(0));
      expect(metrics.outputChunks, equals(0));
      expect(metrics.outputFragments, equals(0));
      expect(metrics.ocrCalls, equals(0));
      expect(metrics.asrCalls, equals(0));
      expect(metrics.visionPortCalls, equals(0));
      expect(metrics.llmVisionCalls, equals(0));
      expect(metrics.estimatedCost, equals(0.0));
    });

    test('IngestError.toString() formats correctly', () {
      const error = IngestError(stage: 'chunking', message: 'Too large');
      expect(error.toString(), equals('IngestError[chunking]: Too large'));
    });

    test('IngestError.toJson() with stackTrace', () {
      const error = IngestError(
        stage: 'extraction',
        message: 'Failed',
        stackTrace: 'line 42\nline 43',
      );
      final json = error.toJson();
      expect(json['stage'], equals('extraction'));
      expect(json['message'], equals('Failed'));
      expect(json['stackTrace'], equals('line 42\nline 43'));
    });

    test('IngestError.toJson() without stackTrace', () {
      const error = IngestError(
        stage: 'extraction',
        message: 'Failed',
      );
      final json = error.toJson();
      expect(json['stage'], equals('extraction'));
      expect(json['message'], equals('Failed'));
      expect(json.containsKey('stackTrace'), isFalse);
    });

    test('AssetRef fields', () {
      const ref = AssetRef(id: 'asset-1', type: 'image', size: 1024);
      expect(ref.id, equals('asset-1'));
      expect(ref.type, equals('image'));
      expect(ref.size, equals(1024));
    });
  });

  group('IngestInput factories', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ingest_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('fromFile with temp file', () {
      final file = File('${tempDir.path}/test.txt');
      file.writeAsStringSync('Hello from file');
      final input = IngestInput.fromFile(file.path);
      expect(input.filename, equals('test.txt'));
      expect(input.sourceUri, equals(file.path));
      expect(input.size, equals(15));
      expect(input.contentRef, contains('file://'));
    });

    test('fromFileSync with temp file', () {
      final file = File('${tempDir.path}/sync_test.txt');
      file.writeAsStringSync('Sync content');
      final input = IngestInput.fromFileSync(file);
      expect(input.filename, equals('sync_test.txt'));
      expect(input.sourceUri, contains('sync_test.txt'));
      expect(input.size, equals(12));
    });

    test('fromUri with file:// URI', () {
      final file = File('${tempDir.path}/uri_test.txt');
      file.writeAsStringSync('URI content');
      final uri = Uri.file(file.path);
      final input = IngestInput.fromUri(uri);
      expect(input.filename, equals('uri_test.txt'));
      expect(input.size, equals(11));
    });

    test('collectBytes top-level function', () async {
      final stream = Stream.fromIterable([
        [65, 66, 67], // ABC
        [68, 69],     // DE
      ]);
      final bytes = await collectBytes(stream);
      expect(bytes.length, equals(5));
      expect(String.fromCharCodes(bytes), equals('ABCDE'));
    });
  });

  group('ContentTypeDetector', () {
    test('detect PNG magic bytes', () {
      final bytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      final ct = ContentTypeDetector.detect(bytes, 'test.png');
      expect(ct, isNotNull);
      expect(ct!.mimeType, equals('image/png'));
    });

    test('detect JPEG magic bytes', () {
      final bytes = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
      final ct = ContentTypeDetector.detect(bytes, 'photo.jpg');
      expect(ct, isNotNull);
      expect(ct!.mimeType, equals('image/jpeg'));
    });

    test('detect GIF magic bytes', () {
      final bytes = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61];
      final ct = ContentTypeDetector.detect(bytes, 'anim.gif');
      expect(ct, isNotNull);
      expect(ct!.mimeType, equals('image/gif'));
    });

    test('detect WebP magic bytes', () {
      // RIFF....WEBP
      final bytes = [
        0x52, 0x49, 0x46, 0x46,
        0x00, 0x00, 0x00, 0x00,
        0x57, 0x45, 0x42, 0x50,
      ];
      final ct = ContentTypeDetector.detect(bytes, 'img.webp');
      expect(ct, isNotNull);
      expect(ct!.mimeType, equals('image/webp'));
    });

    test('detect MP3 with ID3 header', () {
      final bytes = [0x49, 0x44, 0x33, 0x04, 0x00, 0x00];
      final ct = ContentTypeDetector.detect(bytes, 'song.mp3');
      expect(ct, isNotNull);
      expect(ct!.mimeType, equals('audio/mpeg'));
    });

    test('detect MP3 with 0xFF 0xFB header', () {
      final bytes = [0xFF, 0xFB, 0x90, 0x04, 0x00, 0x00];
      final ct = ContentTypeDetector.detect(bytes, 'song.mp3');
      expect(ct, isNotNull);
      expect(ct!.mimeType, equals('audio/mpeg'));
    });

    test('detect WAV magic bytes', () {
      // RIFF....WAVE
      final bytes = [
        0x52, 0x49, 0x46, 0x46,
        0x00, 0x00, 0x00, 0x00,
        0x57, 0x41, 0x56, 0x45,
      ];
      final ct = ContentTypeDetector.detect(bytes, 'audio.wav');
      expect(ct, isNotNull);
      expect(ct!.mimeType, equals('audio/wav'));
    });

    test('detect OGG magic bytes', () {
      final bytes = [0x4F, 0x67, 0x67, 0x53, 0x00, 0x02];
      final ct = ContentTypeDetector.detect(bytes, 'audio.ogg');
      expect(ct, isNotNull);
      expect(ct!.mimeType, equals('audio/ogg'));
    });

    test('detect FLAC magic bytes', () {
      final bytes = [0x66, 0x4C, 0x61, 0x43, 0x00, 0x00];
      final ct = ContentTypeDetector.detect(bytes, 'music.flac');
      expect(ct, isNotNull);
      expect(ct!.mimeType, equals('audio/flac'));
    });

    test('detect ZIP/PK magic bytes', () {
      final bytes = [0x50, 0x4B, 0x03, 0x04, 0x00, 0x00];
      final ct = ContentTypeDetector.detect(bytes, 'archive.zip');
      expect(ct, isNotNull);
      expect(ct!.mimeType, equals('application/zip'));
    });

    test('extension fallback when no magic bytes match', () {
      // Random bytes that do not match any magic
      final bytes = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05];
      final ct = ContentTypeDetector.detect(bytes, 'document.pdf');
      expect(ct, isNotNull);
      expect(ct!.mimeType, equals('application/pdf'));
    });

    test('detect returns null for unknown bytes and no filename', () {
      final bytes = [0x00, 0x01, 0x02, 0x03];
      final ct = ContentTypeDetector.detect(bytes, null);
      expect(ct, isNull);
    });

    test('detect returns null for unknown bytes and unknown extension', () {
      final bytes = [0x00, 0x01, 0x02, 0x03];
      final ct = ContentTypeDetector.detect(bytes, 'file.xyz');
      expect(ct, isNull);
    });

    test('detectFromFilename for various extensions', () {
      expect(
        ContentTypeDetector.detectFromFilename('file.txt').mimeType,
        equals('text/plain'),
      );
      expect(
        ContentTypeDetector.detectFromFilename('file.md').mimeType,
        equals('text/markdown'),
      );
      expect(
        ContentTypeDetector.detectFromFilename('file.html').mimeType,
        equals('text/html'),
      );
      expect(
        ContentTypeDetector.detectFromFilename('file.json').mimeType,
        equals('application/json'),
      );
      expect(
        ContentTypeDetector.detectFromFilename('file.pdf').mimeType,
        equals('application/pdf'),
      );
      expect(
        ContentTypeDetector.detectFromFilename('file.docx').mimeType,
        equals(
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
      );
      expect(
        ContentTypeDetector.detectFromFilename('file.png').mimeType,
        equals('image/png'),
      );
      expect(
        ContentTypeDetector.detectFromFilename('file.jpg').mimeType,
        equals('image/jpeg'),
      );
      expect(
        ContentTypeDetector.detectFromFilename('file.mp3').mimeType,
        equals('audio/mpeg'),
      );
      expect(
        ContentTypeDetector.detectFromFilename('file.wav').mimeType,
        equals('audio/wav'),
      );
    });

    test('detectFromFilename returns octet-stream for unknown extension', () {
      expect(
        ContentTypeDetector.detectFromFilename('file.xyz').mimeType,
        equals('application/octet-stream'),
      );
    });

    test('subType returns empty for invalid mimeType', () {
      final ct = ContentType('nosubtype');
      expect(ct.subType, equals(''));
    });
  });

  group('CostBudget edge cases', () {
    test('isOcrBudgetExceeded when OCR budget set and exceeded', () {
      final budget = CostBudget.perCategory(ocr: 0.001);
      expect(budget.isOcrBudgetExceeded, isFalse);
      budget.recordOcr(pages: 100);
      expect(budget.isOcrBudgetExceeded, isTrue);
    });

    test('isAsrBudgetExceeded when ASR budget set and exceeded', () {
      final budget = CostBudget.perCategory(asr: 0.001);
      expect(budget.isAsrBudgetExceeded, isFalse);
      budget.recordAsr(audioDuration: const Duration(hours: 1));
      expect(budget.isAsrBudgetExceeded, isTrue);
    });

    test('isVisionBudgetExceeded when vision budget set and exceeded', () {
      final budget = CostBudget.perCategory(vision: 0.001);
      expect(budget.isVisionBudgetExceeded, isFalse);
      budget.recordVision(calls: 100);
      expect(budget.isVisionBudgetExceeded, isTrue);
    });

    test('isLlmBudgetExceeded when LLM budget set and exceeded', () {
      final budget = CostBudget.perCategory(llm: 0.001);
      expect(budget.isLlmBudgetExceeded, isFalse);
      budget.recordLlm(calls: 100, inputTokens: 10000);
      expect(budget.isLlmBudgetExceeded, isTrue);
    });

    test('remainingOcrBudget returns remaining when limit set', () {
      final budget = CostBudget.perCategory(ocr: 1.0);
      expect(budget.remainingOcrBudget, equals(1.0));
      budget.recordOcr(pages: 10);
      expect(budget.remainingOcrBudget, closeTo(0.99, 0.001));
    });

    test('remainingOcrBudget returns null when unlimited', () {
      final budget = CostBudget.unlimited();
      expect(budget.remainingOcrBudget, isNull);
    });

    test('remainingAsrBudget returns remaining when limit set', () {
      final budget = CostBudget.perCategory(asr: 1.0);
      expect(budget.remainingAsrBudget, equals(1.0));
      budget.recordAsr(audioDuration: const Duration(minutes: 10));
      expect(budget.remainingAsrBudget, closeTo(0.94, 0.01));
    });

    test('remainingAsrBudget returns null when unlimited', () {
      final budget = CostBudget.unlimited();
      expect(budget.remainingAsrBudget, isNull);
    });

    test('remainingVisionBudget returns remaining when limit set', () {
      final budget = CostBudget.perCategory(vision: 1.0);
      expect(budget.remainingVisionBudget, equals(1.0));
      budget.recordVision(calls: 10);
      expect(budget.remainingVisionBudget, closeTo(0.99, 0.001));
    });

    test('remainingVisionBudget returns null when unlimited', () {
      final budget = CostBudget.unlimited();
      expect(budget.remainingVisionBudget, isNull);
    });

    test('remainingLlmBudget returns remaining when limit set', () {
      final budget = CostBudget.perCategory(llm: 1.0);
      expect(budget.remainingLlmBudget, equals(1.0));
      budget.recordLlm(calls: 2, inputTokens: 1000);
      expect(budget.remainingLlmBudget, lessThan(1.0));
    });

    test('remainingLlmBudget returns null when unlimited', () {
      final budget = CostBudget.unlimited();
      expect(budget.remainingLlmBudget, isNull);
    });

    test('estimateLlmVisionCost with tokens', () {
      final budget = CostBudget.unlimited();
      final cost = budget.estimateLlmVisionCost(
        1,
        inputTokens: 1000,
        outputTokens: 500,
      );
      // 1 * 0.01 + (1000/1000) * 0.003 + (500/1000) * 0.015
      // = 0.01 + 0.003 + 0.0075 = 0.0205
      expect(cost, closeTo(0.0205, 0.0001));
    });

    test('checkTotalBudget throws when total budget exceeded', () {
      final budget = CostBudget.strict(maxTotal: 0.001, maxOcr: 10.0);
      expect(
        () => budget.checkOcrBudget(100),
        throwsA(isA<BudgetExceededException>()),
      );
    });

    test('checkAsrBudget throws when total budget exceeded', () {
      // Small total budget, no ASR category limit
      final budget = CostBudget.strict(maxTotal: 0.001, maxAsr: 10.0);
      expect(
        () => budget.checkAsrBudget(const Duration(minutes: 10)),
        throwsA(isA<BudgetExceededException>().having(
          (e) => e.operation, 'operation', contains('ASR (total budget)'),
        )),
      );
    });

    test('checkVisionBudget throws when total budget exceeded', () {
      // Small total budget, no Vision category limit
      final budget = CostBudget.strict(maxTotal: 0.001, maxVision: 10.0);
      expect(
        () => budget.checkVisionBudget(100),
        throwsA(isA<BudgetExceededException>().having(
          (e) => e.operation, 'operation', contains('Vision (total budget)'),
        )),
      );
    });

    test('checkLlmBudget throws when total budget exceeded', () {
      // Small total budget, no LLM category limit
      final budget = CostBudget.strict(maxTotal: 0.001, maxLlm: 10.0);
      expect(
        () => budget.checkLlmBudget(100),
        throwsA(isA<BudgetExceededException>().having(
          (e) => e.operation, 'operation', contains('LLM (total budget)'),
        )),
      );
    });

    test('BudgetStatus.isExceeded for OCR category', () {
      const status = BudgetStatus(
        totalCost: 0.5,
        ocrCost: 0.3,
        maxOcrBudget: 0.2,
        asrCost: 0.0,
        visionCost: 0.0,
        llmCost: 0.0,
      );
      expect(status.isExceeded, isTrue);
    });

    test('BudgetStatus.isExceeded for ASR category', () {
      const status = BudgetStatus(
        totalCost: 0.5,
        ocrCost: 0.0,
        asrCost: 0.3,
        maxAsrBudget: 0.2,
        visionCost: 0.0,
        llmCost: 0.0,
      );
      expect(status.isExceeded, isTrue);
    });

    test('BudgetStatus.isExceeded for Vision category', () {
      const status = BudgetStatus(
        totalCost: 0.5,
        ocrCost: 0.0,
        asrCost: 0.0,
        visionCost: 0.3,
        maxVisionBudget: 0.2,
        llmCost: 0.0,
      );
      expect(status.isExceeded, isTrue);
    });

    test('BudgetStatus.isExceeded for LLM category', () {
      const status = BudgetStatus(
        totalCost: 0.5,
        ocrCost: 0.0,
        asrCost: 0.0,
        visionCost: 0.0,
        llmCost: 0.3,
        maxLlmBudget: 0.2,
      );
      expect(status.isExceeded, isTrue);
    });
  });

  group('NormalizedDocument', () {
    NormalizedDocument _createTestDocument({
      List<DocumentPart>? parts,
    }) {
      return NormalizedDocument(
        id: 'doc-1',
        metadata: const DocumentMetadata(
          mimeType: 'text/plain',
          sha256: 'abc123hash',
          title: 'Test Document',
        ),
        parts: parts ??
            [
              const TextBlock(id: 'p1', text: 'Hello world'),
              const TextBlock(
                  id: 'p2',
                  text: 'Second paragraph',
                  type: TextBlockType.heading,
                  headingLevel: 2),
            ],
        structure: DocumentStructure.empty,
        provenance: ExtractionProvenance(
          extractorId: 'text_v1',
          extractorVersion: '1.0.0',
          extractedAt: DateTime(2024, 1, 1),
          extractionDuration: const Duration(milliseconds: 100),
        ),
      );
    }

    test('fromJson/toJson round-trip', () {
      final doc = _createTestDocument();
      final json = doc.toJson();
      final restored = NormalizedDocument.fromJson(json);
      expect(restored.id, equals(doc.id));
      expect(restored.metadata.mimeType, equals('text/plain'));
      expect(restored.metadata.sha256, equals('abc123hash'));
      expect(restored.parts.length, equals(2));
      expect((restored.parts[0] as TextBlock).text, equals('Hello world'));
      final restoredJson = restored.toJson();
      expect(restoredJson['id'], equals(json['id']));
    });

    test('copyWithParts returns new document with replaced parts', () {
      final doc = _createTestDocument();
      final newParts = [
        const TextBlock(id: 'p3', text: 'Replaced content'),
      ];
      final updated = doc.copyWithParts(newParts);
      expect(updated.id, equals('doc-1'));
      expect(updated.parts.length, equals(1));
      expect((updated.parts[0] as TextBlock).text, equals('Replaced content'));
      // Original is unchanged
      expect(doc.parts.length, equals(2));
    });

    test('updatePart replaces specific part by ID', () {
      final doc = _createTestDocument();
      const newPart = TextBlock(id: 'p1', text: 'Updated first');
      final updated = doc.updatePart('p1', newPart);
      expect((updated.parts[0] as TextBlock).text, equals('Updated first'));
      expect((updated.parts[1] as TextBlock).text, equals('Second paragraph'));
    });

    test('findPart returns matching part', () {
      final doc = _createTestDocument();
      final found = doc.findPart('p2');
      expect(found, isNotNull);
      expect(found!.id, equals('p2'));
    });

    test('findPart returns null for non-existent ID', () {
      final doc = _createTestDocument();
      final found = doc.findPart('nonexistent');
      expect(found, isNull);
    });

    test('fullText with text blocks', () {
      final doc = _createTestDocument();
      final text = doc.fullText;
      expect(text, contains('Hello world'));
      expect(text, contains('Second paragraph'));
    });

    test('fullText with table block', () {
      final doc = _createTestDocument(parts: [
        const TableBlock(
          id: 'tbl1',
          rows: [
            TableRow(cells: [
              TableCell(text: 'Name'),
              TableCell(text: 'Age'),
            ]),
            TableRow(cells: [
              TableCell(text: 'Alice'),
              TableCell(text: '30'),
            ]),
          ],
          rowCount: 2,
          columnCount: 2,
        ),
      ]);
      final text = doc.fullText;
      expect(text, contains('Name'));
      expect(text, contains('Alice'));
    });

    test('fullText with key-value block', () {
      final doc = _createTestDocument(parts: [
        const KeyValueBlock(
          id: 'kv1',
          key: 'amount',
          value: '\$100.00',
        ),
      ]);
      final text = doc.fullText;
      expect(text, contains('amount: \$100.00'));
    });

    test('fullText with image block (caption and ocrText)', () {
      final doc = _createTestDocument(parts: [
        const ImageBlock(
          id: 'img1',
          assetRef: 'images/test.png',
          caption: 'A test image',
          ocrText: 'Text from OCR',
        ),
      ]);
      final text = doc.fullText;
      expect(text, contains('A test image'));
      expect(text, contains('Text from OCR'));
    });

    test('fullText with audio block (transcript)', () {
      final doc = _createTestDocument(parts: [
        const AudioBlock(
          id: 'aud1',
          assetRef: 'audio/test.mp3',
          transcript: 'Hello this is a transcript',
        ),
      ]);
      final text = doc.fullText;
      expect(text, contains('Hello this is a transcript'));
    });

    test('textBlocks getter filters correctly', () {
      final doc = _createTestDocument(parts: [
        const TextBlock(id: 't1', text: 'Text one'),
        const KeyValueBlock(id: 'kv1', key: 'k', value: 'v'),
        const TextBlock(id: 't2', text: 'Text two'),
      ]);
      expect(doc.textBlocks.length, equals(2));
      expect(doc.textBlocks[0].text, equals('Text one'));
    });

    test('tableBlocks getter filters correctly', () {
      final doc = _createTestDocument(parts: [
        const TextBlock(id: 't1', text: 'Some text'),
        const TableBlock(
          id: 'tbl1',
          rows: [],
          rowCount: 0,
          columnCount: 0,
        ),
      ]);
      expect(doc.tableBlocks.length, equals(1));
    });

    test('imageBlocks getter filters correctly', () {
      final doc = _createTestDocument(parts: [
        const TextBlock(id: 't1', text: 'Some text'),
        const ImageBlock(id: 'img1', assetRef: 'test.png'),
      ]);
      expect(doc.imageBlocks.length, equals(1));
    });

    test('audioBlocks getter filters correctly', () {
      final doc = _createTestDocument(parts: [
        const TextBlock(id: 't1', text: 'Some text'),
        const AudioBlock(id: 'aud1', assetRef: 'test.mp3'),
      ]);
      expect(doc.audioBlocks.length, equals(1));
    });

    test('keyValueBlocks getter filters correctly', () {
      final doc = _createTestDocument(parts: [
        const TextBlock(id: 't1', text: 'Some text'),
        const KeyValueBlock(id: 'kv1', key: 'name', value: 'John'),
        const KeyValueBlock(id: 'kv2', key: 'age', value: '30'),
      ]);
      expect(doc.keyValueBlocks.length, equals(2));
    });

    test('partCount returns total parts', () {
      final doc = _createTestDocument();
      expect(doc.partCount, equals(2));
    });

    test('characterCount returns length of fullText', () {
      final doc = _createTestDocument(parts: [
        const TextBlock(id: 'p1', text: 'ABC'),
      ]);
      expect(doc.characterCount, equals(doc.fullText.length));
    });
  });

  group('StorageUsage _formatBytes', () {
    test('formats bytes < 1024 as B', () {
      const usage = StorageUsage(
        bytes: 500,
        storeOperations: 0,
        retrieveOperations: 0,
        monthlyCost: 0.0,
      );
      final json = usage.toJson();
      expect(json['bytesFormatted'], equals('500 B'));
    });

    test('formats KB range', () {
      const usage = StorageUsage(
        bytes: 2048,
        storeOperations: 0,
        retrieveOperations: 0,
        monthlyCost: 0.0,
      );
      final json = usage.toJson();
      expect(json['bytesFormatted'], equals('2.0 KB'));
    });

    test('formats MB range', () {
      const usage = StorageUsage(
        bytes: 1048576 * 5, // 5 MB
        storeOperations: 0,
        retrieveOperations: 0,
        monthlyCost: 0.0,
      );
      final json = usage.toJson();
      expect(json['bytesFormatted'], equals('5.0 MB'));
    });

    test('formats GB range', () {
      const usage = StorageUsage(
        bytes: 1073741824 * 2, // 2 GB
        storeOperations: 0,
        retrieveOperations: 0,
        monthlyCost: 0.0,
      );
      final json = usage.toJson();
      expect(json['bytesFormatted'], equals('2.00 GB'));
    });

    test('formats 0 bytes', () {
      const usage = StorageUsage(
        bytes: 0,
        storeOperations: 0,
        retrieveOperations: 0,
        monthlyCost: 0.0,
      );
      final json = usage.toJson();
      expect(json['bytesFormatted'], equals('0 B'));
    });

    test('formats exactly 1024 bytes as KB', () {
      const usage = StorageUsage(
        bytes: 1024,
        storeOperations: 0,
        retrieveOperations: 0,
        monthlyCost: 0.0,
      );
      final json = usage.toJson();
      expect(json['bytesFormatted'], equals('1.0 KB'));
    });
  });

  group('SourceLocation.fromJson with bbox', () {
    test('parses bbox field from JSON', () {
      final json = {
        'pageNumber': 1,
        'bbox': {
          'x': 10.0,
          'y': 20.0,
          'width': 100.0,
          'height': 50.0,
        },
        'bboxUnit': 'px',
      };
      final location = SourceLocation.fromJson(json);
      expect(location.pageNumber, equals(1));
      expect(location.bbox, isNotNull);
      expect(location.bbox!.x, equals(10.0));
      expect(location.bbox!.y, equals(20.0));
      expect(location.bbox!.width, equals(100.0));
      expect(location.bbox!.height, equals(50.0));
      expect(location.bboxUnit, equals('px'));
    });

    test('round-trip toJson/fromJson preserves bbox', () {
      final original = SourceLocation.fromJson({
        'pageNumber': 3,
        'bbox': {
          'x': 5.5,
          'y': 10.5,
          'width': 200.0,
          'height': 150.0,
        },
        'bboxUnit': 'pt',
      });
      final json = original.toJson();
      final restored = SourceLocation.fromJson(json);
      expect(restored.bbox, isNotNull);
      expect(restored.bbox!.x, equals(5.5));
      expect(restored.bbox!.y, equals(10.5));
      expect(restored.bbox!.width, equals(200.0));
      expect(restored.bbox!.height, equals(150.0));
      expect(restored.bboxUnit, equals('pt'));
    });
  });
}
