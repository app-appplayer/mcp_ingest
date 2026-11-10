import 'package:test/test.dart';
import 'package:mcp_ingest/mcp_ingest.dart';
// OcrWord is hidden from barrel export, import directly.
import 'package:mcp_ingest/src/plugins/plugin.dart' show OcrWord;

// =============================================================================
// Mock implementations
// =============================================================================

class MockPlugin extends NativePlugin {
  final String _id;
  final String _name;
  final bool _available;
  bool initialized = false;
  bool disposed = false;

  MockPlugin(this._id, {String? name, bool available = true})
      : _name = name ?? _id,
        _available = available;

  @override
  String get id => _id;
  @override
  String get name => _name;
  @override
  String get version => '1.0';
  @override
  Future<bool> isAvailable() async => _available;
  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class MockOcrPlugin extends MockPlugin implements OcrPlugin {
  MockOcrPlugin({super.available}) : super('mock_ocr');

  @override
  List<String> get supportedLanguages => ['eng'];

  @override
  Future<OcrPluginResult> recognize(
    List<int> imageBytes,
    OcrPluginOptions options,
  ) async {
    return const OcrPluginResult(text: 'mock text', confidence: 0.95);
  }
}

class MockAsrPlugin extends MockPlugin implements AsrPlugin {
  MockAsrPlugin({super.available}) : super('mock_asr');

  @override
  List<String> get supportedLanguages => ['en'];

  @override
  List<String> get supportedFormats => ['wav', 'mp3'];

  @override
  Future<AsrPluginResult> transcribe(
    List<int> audioBytes,
    AsrPluginOptions options,
  ) async {
    return const AsrPluginResult(
      text: 'mock transcript',
      confidence: 0.9,
      audioDuration: Duration(seconds: 10),
    );
  }
}

class MockPdfPlugin extends MockPlugin implements PdfPlugin {
  MockPdfPlugin({super.available}) : super('mock_pdf');

  @override
  Future<PdfPluginResult> extractText(
    List<int> pdfBytes,
    PdfPluginOptions options,
  ) async {
    return PdfPluginResult(
      pages: const [],
      metadata: const PdfMetadata(pageCount: 0),
    );
  }

  @override
  Future<List<int>> renderPage(
    List<int> pdfBytes,
    int pageIndex,
    RenderOptions options,
  ) async {
    return <int>[];
  }

  @override
  Future<int> getPageCount(List<int> pdfBytes) async => 0;

  @override
  Future<PdfMetadata> getMetadata(List<int> pdfBytes) async {
    return const PdfMetadata(pageCount: 0);
  }
}

// Mock ports for HybridPortFactory tests.

class MockOcrPort implements OcrPort {
  final bool available;
  final bool shouldFail;
  final List<String> langs;

  MockOcrPort({
    this.available = true,
    this.shouldFail = false,
    this.langs = const ['en'],
  });

  @override
  Future<OcrResult> recognize(
    Stream<List<int>> imageData,
    OcrOptions options,
  ) async {
    if (shouldFail) throw Exception('Mock OCR failed');
    return OcrResult(
      text: 'mock text',
      confidence: 0.95,
      processingTime: Duration.zero,
    );
  }

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<String>> supportedLanguages() async => langs;
}

class MockAsrPort implements AsrPort {
  final bool available;
  final bool shouldFail;
  final List<String> langs;

  MockAsrPort({
    this.available = true,
    this.shouldFail = false,
    this.langs = const ['en'],
  });

  @override
  Future<AsrResult> transcribe(
    Stream<List<int>> audioData,
    AsrOptions options,
  ) async {
    if (shouldFail) throw Exception('Mock ASR failed');
    return AsrResult(
      text: 'mock text',
      confidence: 0.95,
      segments: const [],
      audioDuration: const Duration(seconds: 10),
      processingTime: Duration.zero,
    );
  }

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<String>> supportedLanguages() async => langs;
}

// =============================================================================
// Tests
// =============================================================================

void main() {
  // ===========================================================================
  // Plugin data classes
  // ===========================================================================

  group('OcrPluginOptions', () {
    test('defaults', () {
      const opts = OcrPluginOptions();
      expect(opts.language, 'eng');
      expect(opts.pageSegMode, isNull);
      expect(opts.preserveLayout, isFalse);
    });

    test('custom values', () {
      const opts = OcrPluginOptions(
        language: 'kor',
        pageSegMode: 6,
        preserveLayout: true,
      );
      expect(opts.language, 'kor');
      expect(opts.pageSegMode, 6);
      expect(opts.preserveLayout, isTrue);
    });
  });

  group('OcrPluginResult', () {
    test('required fields only', () {
      const result = OcrPluginResult(text: 'hello', confidence: 0.9);
      expect(result.text, 'hello');
      expect(result.confidence, 0.9);
      expect(result.language, isNull);
      expect(result.processingTime, Duration.zero);
      expect(result.words, isNull);
    });

    test('all fields', () {
      const words = [
        OcrWord(
            text: 'hi', confidence: 0.99, x: 0, y: 0, width: 50, height: 20),
      ];
      const result = OcrPluginResult(
        text: 'hi',
        confidence: 0.99,
        language: 'eng',
        processingTime: Duration(milliseconds: 100),
        words: words,
      );
      expect(result.text, 'hi');
      expect(result.confidence, 0.99);
      expect(result.language, 'eng');
      expect(result.processingTime, const Duration(milliseconds: 100));
      expect(result.words, hasLength(1));
      expect(result.words!.first.text, 'hi');
    });
  });

  group('OcrWord', () {
    test('all fields', () {
      const word = OcrWord(
        text: 'test',
        confidence: 0.95,
        x: 10,
        y: 20,
        width: 100,
        height: 30,
      );
      expect(word.text, 'test');
      expect(word.confidence, 0.95);
      expect(word.x, 10);
      expect(word.y, 20);
      expect(word.width, 100);
      expect(word.height, 30);
    });
  });

  group('AsrPluginOptions', () {
    test('defaults', () {
      const opts = AsrPluginOptions();
      expect(opts.language, 'en');
      expect(opts.modelSize, 'small');
      expect(opts.wordTimestamps, isTrue);
    });

    test('custom values', () {
      const opts = AsrPluginOptions(
        language: 'ko',
        modelSize: 'large',
        wordTimestamps: false,
      );
      expect(opts.language, 'ko');
      expect(opts.modelSize, 'large');
      expect(opts.wordTimestamps, isFalse);
    });
  });

  group('AsrPluginResult', () {
    test('required fields only', () {
      const result = AsrPluginResult(
        text: 'hello world',
        confidence: 0.88,
        audioDuration: Duration(seconds: 5),
      );
      expect(result.text, 'hello world');
      expect(result.confidence, 0.88);
      expect(result.language, isNull);
      expect(result.audioDuration, const Duration(seconds: 5));
      expect(result.processingTime, Duration.zero);
      expect(result.segments, isNull);
    });

    test('all fields', () {
      const segments = [
        AsrSegmentResult(
          text: 'hello',
          startTime: Duration.zero,
          endTime: Duration(seconds: 1),
          confidence: 0.9,
        ),
      ];
      const result = AsrPluginResult(
        text: 'hello',
        confidence: 0.9,
        language: 'en',
        audioDuration: Duration(seconds: 5),
        processingTime: Duration(milliseconds: 200),
        segments: segments,
      );
      expect(result.text, 'hello');
      expect(result.confidence, 0.9);
      expect(result.language, 'en');
      expect(result.audioDuration, const Duration(seconds: 5));
      expect(result.processingTime, const Duration(milliseconds: 200));
      expect(result.segments, hasLength(1));
    });
  });

  group('AsrSegmentResult', () {
    test('all fields', () {
      const segment = AsrSegmentResult(
        text: 'segment',
        startTime: Duration(seconds: 1),
        endTime: Duration(seconds: 2),
        confidence: 0.92,
      );
      expect(segment.text, 'segment');
      expect(segment.startTime, const Duration(seconds: 1));
      expect(segment.endTime, const Duration(seconds: 2));
      expect(segment.confidence, 0.92);
    });

    test('confidence is optional', () {
      const segment = AsrSegmentResult(
        text: 'no conf',
        startTime: Duration.zero,
        endTime: Duration(seconds: 1),
      );
      expect(segment.confidence, isNull);
    });
  });

  group('PdfPluginOptions', () {
    test('defaults', () {
      const opts = PdfPluginOptions();
      expect(opts.maxPages, isNull);
      expect(opts.extractImages, isTrue);
      expect(opts.extractTables, isTrue);
    });

    test('custom values', () {
      const opts = PdfPluginOptions(
        maxPages: 10,
        extractImages: false,
        extractTables: false,
      );
      expect(opts.maxPages, 10);
      expect(opts.extractImages, isFalse);
      expect(opts.extractTables, isFalse);
    });
  });

  group('PdfPluginResult', () {
    test('all fields', () {
      const meta = PdfMetadata(pageCount: 1);
      const pages = [
        PdfPageResult(index: 0, text: 'page 0', width: 612.0, height: 792.0),
      ];
      const result = PdfPluginResult(
        pages: pages,
        metadata: meta,
        processingTime: Duration(milliseconds: 50),
      );
      expect(result.pages, hasLength(1));
      expect(result.metadata.pageCount, 1);
      expect(result.processingTime, const Duration(milliseconds: 50));
    });

    test('default processing time is zero', () {
      const result = PdfPluginResult(
        pages: [],
        metadata: PdfMetadata(pageCount: 0),
      );
      expect(result.processingTime, Duration.zero);
    });
  });

  group('PdfPageResult', () {
    test('all fields', () {
      const images = [
        PdfImageRef(index: 0, x: 10, y: 20, width: 100, height: 200),
      ];
      const page = PdfPageResult(
        index: 2,
        text: 'page text',
        width: 595.0,
        height: 842.0,
        images: images,
        hasTextLayer: false,
      );
      expect(page.index, 2);
      expect(page.text, 'page text');
      expect(page.width, 595.0);
      expect(page.height, 842.0);
      expect(page.images, hasLength(1));
      expect(page.hasTextLayer, isFalse);
    });

    test('defaults', () {
      const page = PdfPageResult(
        index: 0,
        text: '',
        width: 612.0,
        height: 792.0,
      );
      expect(page.images, isNull);
      expect(page.hasTextLayer, isTrue);
    });
  });

  group('PdfImageRef', () {
    test('all fields', () {
      const ref = PdfImageRef(
        index: 3,
        x: 50,
        y: 100,
        width: 200,
        height: 150,
      );
      expect(ref.index, 3);
      expect(ref.x, 50);
      expect(ref.y, 100);
      expect(ref.width, 200);
      expect(ref.height, 150);
    });
  });

  group('PdfMetadata', () {
    test('all fields', () {
      final creation = DateTime(2024, 1, 15);
      final modification = DateTime(2024, 6, 20);
      final meta = PdfMetadata(
        title: 'Test Doc',
        author: 'Author',
        subject: 'Subject',
        creator: 'Creator App',
        creationDate: creation,
        modificationDate: modification,
        pageCount: 42,
      );
      expect(meta.title, 'Test Doc');
      expect(meta.author, 'Author');
      expect(meta.subject, 'Subject');
      expect(meta.creator, 'Creator App');
      expect(meta.creationDate, creation);
      expect(meta.modificationDate, modification);
      expect(meta.pageCount, 42);
    });

    test('optional fields default to null', () {
      const meta = PdfMetadata(pageCount: 5);
      expect(meta.title, isNull);
      expect(meta.author, isNull);
      expect(meta.subject, isNull);
      expect(meta.creator, isNull);
      expect(meta.creationDate, isNull);
      expect(meta.modificationDate, isNull);
      expect(meta.pageCount, 5);
    });
  });

  group('RenderOptions', () {
    test('defaults', () {
      const opts = RenderOptions();
      expect(opts.dpi, 150);
      expect(opts.format, 'png');
    });

    test('custom values', () {
      const opts = RenderOptions(dpi: 300, format: 'jpeg');
      expect(opts.dpi, 300);
      expect(opts.format, 'jpeg');
    });
  });

  // ===========================================================================
  // PluginRegistry
  // ===========================================================================

  group('PluginRegistry', () {
    late PluginRegistry registry;

    setUp(() {
      registry = PluginRegistry();
    });

    test('register and getPlugin', () {
      final plugin = MockOcrPlugin();
      registry.register<OcrPlugin>(plugin);
      expect(registry.getPlugin<OcrPlugin>(), same(plugin));
    });

    test('getPlugin returns null when no plugin registered', () {
      expect(registry.getPlugin<OcrPlugin>(), isNull);
    });

    test('getPluginById', () {
      final plugin = MockOcrPlugin();
      registry.register<OcrPlugin>(plugin);
      expect(registry.getPluginById<OcrPlugin>('mock_ocr'), same(plugin));
    });

    test('getPluginById returns null for unknown id', () {
      expect(registry.getPluginById<OcrPlugin>('unknown'), isNull);
    });

    test('getAllPlugins', () {
      final plugin1 = MockOcrPlugin();
      final plugin2 = MockOcrPlugin(available: false);
      registry.register<OcrPlugin>(plugin1);
      registry.register<OcrPlugin>(plugin2);
      final all = registry.getAllPlugins<OcrPlugin>();
      expect(all, hasLength(2));
    });

    test('getAllPlugins returns empty list when none registered', () {
      expect(registry.getAllPlugins<OcrPlugin>(), isEmpty);
    });

    test('getAvailablePlugin returns available plugin', () async {
      final plugin = MockOcrPlugin();
      registry.register<OcrPlugin>(plugin);
      final found = await registry.getAvailablePlugin<OcrPlugin>();
      expect(found, same(plugin));
    });

    test('getAvailablePlugin skips unavailable plugin', () async {
      final unavailable = MockOcrPlugin(available: false);
      final available = MockOcrPlugin();
      registry.register<OcrPlugin>(unavailable);
      registry.register<OcrPlugin>(available);
      final found = await registry.getAvailablePlugin<OcrPlugin>();
      expect(found, same(available));
    });

    test('getAvailablePlugin returns null when all unavailable', () async {
      final plugin = MockOcrPlugin(available: false);
      registry.register<OcrPlugin>(plugin);
      final found = await registry.getAvailablePlugin<OcrPlugin>();
      expect(found, isNull);
    });

    test('hasAvailablePlugin true when available', () async {
      registry.register<OcrPlugin>(MockOcrPlugin());
      expect(await registry.hasAvailablePlugin<OcrPlugin>(), isTrue);
    });

    test('hasAvailablePlugin false when unavailable', () async {
      registry.register<OcrPlugin>(MockOcrPlugin(available: false));
      expect(await registry.hasAvailablePlugin<OcrPlugin>(), isFalse);
    });

    test('unregister removes plugin', () {
      final plugin = MockOcrPlugin();
      registry.register<OcrPlugin>(plugin);
      registry.unregister('mock_ocr');
      expect(registry.getPlugin<OcrPlugin>(), isNull);
      expect(registry.getPluginById<OcrPlugin>('mock_ocr'), isNull);
      expect(registry.registeredPluginIds, isNot(contains('mock_ocr')));
    });

    test('unregister with unknown id does nothing', () {
      registry.unregister('nonexistent');
      expect(registry.registeredPluginIds, isEmpty);
    });

    test('initializeAll initializes only available plugins', () async {
      final available = MockOcrPlugin();
      final unavailable = MockOcrPlugin(available: false);
      registry.register<OcrPlugin>(available);
      registry.register<OcrPlugin>(unavailable);
      await registry.initializeAll();
      expect(available.initialized, isTrue);
      expect(unavailable.initialized, isFalse);
    });

    test('disposeAll disposes all and clears registry', () async {
      final p1 = MockOcrPlugin();
      final p2 = MockAsrPlugin();
      registry.register<OcrPlugin>(p1);
      registry.register<AsrPlugin>(p2);
      await registry.disposeAll();
      expect(p1.disposed, isTrue);
      expect(p2.disposed, isTrue);
      expect(registry.registeredPluginIds, isEmpty);
      expect(registry.getPlugin<OcrPlugin>(), isNull);
    });

    test('registeredPluginIds', () {
      registry.register<OcrPlugin>(MockOcrPlugin());
      registry.register<AsrPlugin>(MockAsrPlugin());
      final ids = registry.registeredPluginIds;
      expect(ids, containsAll(['mock_ocr', 'mock_asr']));
    });

    test('getAvailabilityStatus', () async {
      registry.register<OcrPlugin>(MockOcrPlugin());
      registry.register<AsrPlugin>(MockAsrPlugin(available: false));
      final status = await registry.getAvailabilityStatus();
      expect(status['mock_ocr'], isTrue);
      expect(status['mock_asr'], isFalse);
    });

    test('defaults() factory registers PdfiumPdfPlugin', () {
      final defaultRegistry = PluginRegistry.defaults();
      expect(defaultRegistry.getPlugin<PdfPlugin>(), isNotNull);
      expect(defaultRegistry.registeredPluginIds, contains('pdfium'));
    });
  });

  // ===========================================================================
  // PluginNotAvailableException
  // ===========================================================================

  group('PluginNotAvailableException', () {
    test('toString without reason', () {
      final ex = PluginNotAvailableException('OcrPlugin');
      expect(
        ex.toString(),
        contains('Plugin not available: OcrPlugin'),
      );
    });

    test('toString with reason', () {
      final ex = PluginNotAvailableException('OcrPlugin', 'binary not found');
      expect(
        ex.toString(),
        contains('Plugin not available: OcrPlugin (binary not found)'),
      );
    });

    test('is IngestException (unified with core/exceptions.dart)', () {
      final ex = PluginNotAvailableException('OcrPlugin');
      expect(ex, isA<IngestException>());
    });
  });

  // ===========================================================================
  // DEF-20260411-001: concrete plugins can register in PluginRegistry
  //   (Tesseract/Whisper/LocalStorage now implement NativePlugin in addition
  //    to their port interface)
  // ===========================================================================

  group('Concrete plugins implement NativePlugin (DEF-20260411-001)', () {
    test('TesseractOcrPlugin implements NativePlugin', () {
      final plugin = TesseractOcrPlugin();
      expect(plugin, isA<NativePlugin>());
      expect(plugin, isA<OcrPort>());
      expect(plugin.id, equals('tesseract'));
      expect(plugin.name, isNotEmpty);
      expect(plugin.version, isNotEmpty);
    });

    test('WhisperAsrPlugin implements NativePlugin', () {
      final plugin = WhisperAsrPlugin();
      expect(plugin, isA<NativePlugin>());
      expect(plugin, isA<AsrPort>());
      expect(plugin.id, equals('whisper'));
    });

    test('LocalStoragePlugin implements NativePlugin', () {
      final plugin = LocalStoragePlugin(basePath: '/tmp/mcp_ingest_test');
      expect(plugin, isA<NativePlugin>());
      expect(plugin, isA<BinaryStoragePort>());
      expect(plugin.id, equals('local_storage'));
    });

    test('TesseractOcrPlugin can be registered in PluginRegistry', () {
      final registry = PluginRegistry();
      final plugin = TesseractOcrPlugin();
      registry.register<NativePlugin>(plugin);
      expect(registry.getPluginById<NativePlugin>('tesseract'), same(plugin));
      expect(registry.registeredPluginIds, contains('tesseract'));
    });

    test('WhisperAsrPlugin can be registered in PluginRegistry', () {
      final registry = PluginRegistry();
      final plugin = WhisperAsrPlugin();
      registry.register<NativePlugin>(plugin);
      expect(registry.getPluginById<NativePlugin>('whisper'), same(plugin));
    });

    test('LocalStoragePlugin can be registered in PluginRegistry', () {
      final registry = PluginRegistry();
      final plugin = LocalStoragePlugin(basePath: '/tmp/mcp_ingest_test');
      registry.register<NativePlugin>(plugin);
      expect(
        registry.getPluginById<NativePlugin>('local_storage'),
        same(plugin),
      );
    });

    test('lifecycle methods are idempotent', () async {
      final plugin = TesseractOcrPlugin();
      await plugin.initialize();
      await plugin.initialize(); // idempotent
      await plugin.dispose();
      await plugin.dispose(); // idempotent
    });
  });

  // ===========================================================================
  // HybridOcrPort
  // ===========================================================================

  group('HybridOcrPort', () {
    final dummyStream = Stream<List<int>>.empty();
    const opts = OcrOptions();

    group('localOnly strategy', () {
      test('succeeds with local port', () async {
        final port = HybridOcrPort(
          local: MockOcrPort(),
          cloud: null,
          strategy: ProcessingStrategy.localOnly,
        );
        final result = await port.recognize(dummyStream, opts);
        expect(result.text, 'mock text');
      });

      test('throws PortNotConfiguredException when no local', () async {
        final port = HybridOcrPort(
          local: null,
          cloud: MockOcrPort(),
          strategy: ProcessingStrategy.localOnly,
        );
        expect(
          () => port.recognize(dummyStream, opts),
          throwsA(isA<PortNotConfiguredException>()),
        );
      });
    });

    group('cloudOnly strategy', () {
      test('succeeds with cloud port', () async {
        final port = HybridOcrPort(
          local: null,
          cloud: MockOcrPort(),
          strategy: ProcessingStrategy.cloudOnly,
        );
        final result = await port.recognize(dummyStream, opts);
        expect(result.text, 'mock text');
      });

      test('throws PortNotConfiguredException when no cloud', () async {
        final port = HybridOcrPort(
          local: MockOcrPort(),
          cloud: null,
          strategy: ProcessingStrategy.cloudOnly,
        );
        expect(
          () => port.recognize(dummyStream, opts),
          throwsA(isA<PortNotConfiguredException>()),
        );
      });
    });

    group('localFirst strategy', () {
      test('uses local when available', () async {
        final local = MockOcrPort(langs: ['local']);
        final cloud = MockOcrPort(langs: ['cloud']);
        final port = HybridOcrPort(
          local: local,
          cloud: cloud,
          strategy: ProcessingStrategy.localFirst,
        );
        final result = await port.recognize(dummyStream, opts);
        expect(result.text, 'mock text');
        expect(result.confidence, 0.95);
      });

      test('falls back to cloud when local fails', () async {
        final local = MockOcrPort(shouldFail: true);
        final cloud = MockOcrPort();
        final port = HybridOcrPort(
          local: local,
          cloud: cloud,
          strategy: ProcessingStrategy.localFirst,
        );
        final result = await port.recognize(dummyStream, opts);
        expect(result.text, 'mock text');
      });

      test('falls back to cloud when local unavailable', () async {
        final local = MockOcrPort(available: false);
        final cloud = MockOcrPort();
        final port = HybridOcrPort(
          local: local,
          cloud: cloud,
          strategy: ProcessingStrategy.localFirst,
        );
        final result = await port.recognize(dummyStream, opts);
        expect(result.text, 'mock text');
      });

      test('throws when both fail', () async {
        final local = MockOcrPort(shouldFail: true);
        final port = HybridOcrPort(
          local: local,
          cloud: null,
          strategy: ProcessingStrategy.localFirst,
        );
        expect(
          () => port.recognize(dummyStream, opts),
          throwsA(isA<Exception>()),
        );
      });

      test(
          'throws PortNotConfiguredException when local unavailable and cloud null',
          () async {
        final port = HybridOcrPort(
          local: MockOcrPort(available: false),
          cloud: null,
          strategy: ProcessingStrategy.localFirst,
        );
        expect(
          () => port.recognize(dummyStream, opts),
          throwsA(isA<PortNotConfiguredException>()),
        );
      });
    });

    group('cloudFirst strategy', () {
      test('uses cloud when available', () async {
        final local = MockOcrPort(langs: ['local']);
        final cloud = MockOcrPort(langs: ['cloud']);
        final port = HybridOcrPort(
          local: local,
          cloud: cloud,
          strategy: ProcessingStrategy.cloudFirst,
        );
        final result = await port.recognize(dummyStream, opts);
        expect(result.text, 'mock text');
      });

      test('falls back to local when cloud fails', () async {
        final local = MockOcrPort();
        final cloud = MockOcrPort(shouldFail: true);
        final port = HybridOcrPort(
          local: local,
          cloud: cloud,
          strategy: ProcessingStrategy.cloudFirst,
        );
        final result = await port.recognize(dummyStream, opts);
        expect(result.text, 'mock text');
      });

      test('throws when both fail', () async {
        final cloud = MockOcrPort(shouldFail: true);
        final port = HybridOcrPort(
          local: null,
          cloud: cloud,
          strategy: ProcessingStrategy.cloudFirst,
        );
        expect(
          () => port.recognize(dummyStream, opts),
          throwsA(isA<Exception>()),
        );
      });

      test('rethrows when cloud fails and local is unavailable', () async {
        final local = MockOcrPort(available: false);
        final cloud = MockOcrPort(shouldFail: true);
        final port = HybridOcrPort(
          local: local,
          cloud: cloud,
          strategy: ProcessingStrategy.cloudFirst,
        );
        expect(
          () => port.recognize(dummyStream, opts),
          throwsA(isA<Exception>()),
        );
      });

      test('uses local directly when cloud is null', () async {
        final local = MockOcrPort();
        final port = HybridOcrPort(
          local: local,
          cloud: null,
          strategy: ProcessingStrategy.cloudFirst,
        );
        final result = await port.recognize(dummyStream, opts);
        expect(result.text, 'mock text');
      });

      test(
          'throws PortNotConfiguredException when cloud null and local unavailable',
          () async {
        final port = HybridOcrPort(
          local: MockOcrPort(available: false),
          cloud: null,
          strategy: ProcessingStrategy.cloudFirst,
        );
        expect(
          () => port.recognize(dummyStream, opts),
          throwsA(isA<PortNotConfiguredException>()),
        );
      });
    });

    group('isAvailable', () {
      test('localOnly: true when local available', () async {
        final port = HybridOcrPort(
          local: MockOcrPort(),
          cloud: null,
          strategy: ProcessingStrategy.localOnly,
        );
        expect(await port.isAvailable(), isTrue);
      });

      test('localOnly: false when local null', () async {
        final port = HybridOcrPort(
          local: null,
          cloud: MockOcrPort(),
          strategy: ProcessingStrategy.localOnly,
        );
        expect(await port.isAvailable(), isFalse);
      });

      test('cloudOnly: true when cloud present', () async {
        final port = HybridOcrPort(
          local: null,
          cloud: MockOcrPort(),
          strategy: ProcessingStrategy.cloudOnly,
        );
        expect(await port.isAvailable(), isTrue);
      });

      test('cloudOnly: false when cloud null', () async {
        final port = HybridOcrPort(
          local: MockOcrPort(),
          cloud: null,
          strategy: ProcessingStrategy.cloudOnly,
        );
        expect(await port.isAvailable(), isFalse);
      });

      test('localFirst: true when either available', () async {
        final port = HybridOcrPort(
          local: MockOcrPort(available: false),
          cloud: MockOcrPort(),
          strategy: ProcessingStrategy.localFirst,
        );
        expect(await port.isAvailable(), isTrue);
      });

      test('cloudFirst: true when either available', () async {
        final port = HybridOcrPort(
          local: MockOcrPort(),
          cloud: null,
          strategy: ProcessingStrategy.cloudFirst,
        );
        expect(await port.isAvailable(), isTrue);
      });
    });

    test('supportedLanguages merges and deduplicates', () async {
      final local = MockOcrPort(langs: ['en', 'ko']);
      final cloud = MockOcrPort(langs: ['en', 'ja']);
      final port = HybridOcrPort(
        local: local,
        cloud: cloud,
        strategy: ProcessingStrategy.localFirst,
      );
      final langs = await port.supportedLanguages();
      expect(langs, unorderedEquals(['en', 'ko', 'ja']));
    });

    test('supportedLanguages with only local', () async {
      final local = MockOcrPort(langs: ['en']);
      final port = HybridOcrPort(
        local: local,
        cloud: null,
        strategy: ProcessingStrategy.localOnly,
      );
      final langs = await port.supportedLanguages();
      expect(langs, ['en']);
    });
  });

  // ===========================================================================
  // HybridAsrPort
  // ===========================================================================

  group('HybridAsrPort', () {
    final dummyStream = Stream<List<int>>.empty();
    const opts = AsrOptions();

    group('localOnly strategy', () {
      test('succeeds with local port', () async {
        final port = HybridAsrPort(
          local: MockAsrPort(),
          cloud: null,
          strategy: ProcessingStrategy.localOnly,
        );
        final result = await port.transcribe(dummyStream, opts);
        expect(result.text, 'mock text');
      });

      test('throws PortNotConfiguredException when no local', () async {
        final port = HybridAsrPort(
          local: null,
          cloud: MockAsrPort(),
          strategy: ProcessingStrategy.localOnly,
        );
        expect(
          () => port.transcribe(dummyStream, opts),
          throwsA(isA<PortNotConfiguredException>()),
        );
      });
    });

    group('cloudOnly strategy', () {
      test('succeeds with cloud port', () async {
        final port = HybridAsrPort(
          local: null,
          cloud: MockAsrPort(),
          strategy: ProcessingStrategy.cloudOnly,
        );
        final result = await port.transcribe(dummyStream, opts);
        expect(result.text, 'mock text');
      });

      test('throws PortNotConfiguredException when no cloud', () async {
        final port = HybridAsrPort(
          local: MockAsrPort(),
          cloud: null,
          strategy: ProcessingStrategy.cloudOnly,
        );
        expect(
          () => port.transcribe(dummyStream, opts),
          throwsA(isA<PortNotConfiguredException>()),
        );
      });
    });

    group('localFirst strategy', () {
      test('uses local when available', () async {
        final local = MockAsrPort(langs: ['local']);
        final cloud = MockAsrPort(langs: ['cloud']);
        final port = HybridAsrPort(
          local: local,
          cloud: cloud,
          strategy: ProcessingStrategy.localFirst,
        );
        final result = await port.transcribe(dummyStream, opts);
        expect(result.text, 'mock text');
      });

      test('falls back to cloud when local fails', () async {
        final local = MockAsrPort(shouldFail: true);
        final cloud = MockAsrPort();
        final port = HybridAsrPort(
          local: local,
          cloud: cloud,
          strategy: ProcessingStrategy.localFirst,
        );
        final result = await port.transcribe(dummyStream, opts);
        expect(result.text, 'mock text');
      });

      test('falls back to cloud when local unavailable', () async {
        final local = MockAsrPort(available: false);
        final cloud = MockAsrPort();
        final port = HybridAsrPort(
          local: local,
          cloud: cloud,
          strategy: ProcessingStrategy.localFirst,
        );
        final result = await port.transcribe(dummyStream, opts);
        expect(result.text, 'mock text');
      });

      test('throws when both fail', () async {
        final local = MockAsrPort(shouldFail: true);
        final port = HybridAsrPort(
          local: local,
          cloud: null,
          strategy: ProcessingStrategy.localFirst,
        );
        expect(
          () => port.transcribe(dummyStream, opts),
          throwsA(isA<Exception>()),
        );
      });

      test(
          'throws PortNotConfiguredException when local unavailable and cloud null',
          () async {
        final port = HybridAsrPort(
          local: MockAsrPort(available: false),
          cloud: null,
          strategy: ProcessingStrategy.localFirst,
        );
        expect(
          () => port.transcribe(dummyStream, opts),
          throwsA(isA<PortNotConfiguredException>()),
        );
      });
    });

    group('cloudFirst strategy', () {
      test('uses cloud when available', () async {
        final local = MockAsrPort(langs: ['local']);
        final cloud = MockAsrPort(langs: ['cloud']);
        final port = HybridAsrPort(
          local: local,
          cloud: cloud,
          strategy: ProcessingStrategy.cloudFirst,
        );
        final result = await port.transcribe(dummyStream, opts);
        expect(result.text, 'mock text');
      });

      test('falls back to local when cloud fails', () async {
        final local = MockAsrPort();
        final cloud = MockAsrPort(shouldFail: true);
        final port = HybridAsrPort(
          local: local,
          cloud: cloud,
          strategy: ProcessingStrategy.cloudFirst,
        );
        final result = await port.transcribe(dummyStream, opts);
        expect(result.text, 'mock text');
      });

      test('throws when both fail', () async {
        final cloud = MockAsrPort(shouldFail: true);
        final port = HybridAsrPort(
          local: null,
          cloud: cloud,
          strategy: ProcessingStrategy.cloudFirst,
        );
        expect(
          () => port.transcribe(dummyStream, opts),
          throwsA(isA<Exception>()),
        );
      });

      test('rethrows when cloud fails and local is unavailable', () async {
        final local = MockAsrPort(available: false);
        final cloud = MockAsrPort(shouldFail: true);
        final port = HybridAsrPort(
          local: local,
          cloud: cloud,
          strategy: ProcessingStrategy.cloudFirst,
        );
        expect(
          () => port.transcribe(dummyStream, opts),
          throwsA(isA<Exception>()),
        );
      });

      test('uses local directly when cloud is null', () async {
        final local = MockAsrPort();
        final port = HybridAsrPort(
          local: local,
          cloud: null,
          strategy: ProcessingStrategy.cloudFirst,
        );
        final result = await port.transcribe(dummyStream, opts);
        expect(result.text, 'mock text');
      });

      test(
          'throws PortNotConfiguredException when cloud null and local unavailable',
          () async {
        final port = HybridAsrPort(
          local: MockAsrPort(available: false),
          cloud: null,
          strategy: ProcessingStrategy.cloudFirst,
        );
        expect(
          () => port.transcribe(dummyStream, opts),
          throwsA(isA<PortNotConfiguredException>()),
        );
      });
    });

    group('isAvailable', () {
      test('localOnly: true when local available', () async {
        final port = HybridAsrPort(
          local: MockAsrPort(),
          cloud: null,
          strategy: ProcessingStrategy.localOnly,
        );
        expect(await port.isAvailable(), isTrue);
      });

      test('localOnly: false when local null', () async {
        final port = HybridAsrPort(
          local: null,
          cloud: MockAsrPort(),
          strategy: ProcessingStrategy.localOnly,
        );
        expect(await port.isAvailable(), isFalse);
      });

      test('cloudOnly: true when cloud present', () async {
        final port = HybridAsrPort(
          local: null,
          cloud: MockAsrPort(),
          strategy: ProcessingStrategy.cloudOnly,
        );
        expect(await port.isAvailable(), isTrue);
      });

      test('cloudOnly: false when cloud null', () async {
        final port = HybridAsrPort(
          local: MockAsrPort(),
          cloud: null,
          strategy: ProcessingStrategy.cloudOnly,
        );
        expect(await port.isAvailable(), isFalse);
      });

      test('localFirst: true when either available', () async {
        final port = HybridAsrPort(
          local: MockAsrPort(available: false),
          cloud: MockAsrPort(),
          strategy: ProcessingStrategy.localFirst,
        );
        expect(await port.isAvailable(), isTrue);
      });

      test('cloudFirst: true when either available', () async {
        final port = HybridAsrPort(
          local: MockAsrPort(),
          cloud: null,
          strategy: ProcessingStrategy.cloudFirst,
        );
        expect(await port.isAvailable(), isTrue);
      });
    });

    test('supportedLanguages merges and deduplicates', () async {
      final local = MockAsrPort(langs: ['en', 'ko']);
      final cloud = MockAsrPort(langs: ['en', 'ja']);
      final port = HybridAsrPort(
        local: local,
        cloud: cloud,
        strategy: ProcessingStrategy.localFirst,
      );
      final langs = await port.supportedLanguages();
      expect(langs, unorderedEquals(['en', 'ko', 'ja']));
    });

    test('supportedLanguages with only cloud', () async {
      final cloud = MockAsrPort(langs: ['en', 'fr']);
      final port = HybridAsrPort(
        local: null,
        cloud: cloud,
        strategy: ProcessingStrategy.cloudOnly,
      );
      final langs = await port.supportedLanguages();
      expect(langs, unorderedEquals(['en', 'fr']));
    });
  });

  // ===========================================================================
  // HybridPortFactory
  // ===========================================================================

  group('HybridPortFactory', () {
    test('createOcrPort returns null when both local and cloud ocr are null',
        () {
      final factory = HybridPortFactory(
        localPorts: const IngestPorts(),
        cloudPorts: const IngestPorts(),
      );
      expect(factory.createOcrPort(), isNull);
    });

    test('createAsrPort returns null when both local and cloud asr are null',
        () {
      final factory = HybridPortFactory(
        localPorts: const IngestPorts(),
        cloudPorts: const IngestPorts(),
      );
      expect(factory.createAsrPort(), isNull);
    });

    test('createOcrPort returns HybridOcrPort when local ocr exists', () {
      final factory = HybridPortFactory(
        localPorts: IngestPorts(ocr: MockOcrPort()),
        cloudPorts: const IngestPorts(),
      );
      final port = factory.createOcrPort();
      expect(port, isNotNull);
      expect(port, isA<HybridOcrPort>());
    });

    test('createAsrPort returns HybridAsrPort when cloud asr exists', () {
      final factory = HybridPortFactory(
        localPorts: const IngestPorts(),
        cloudPorts: IngestPorts(asr: MockAsrPort()),
      );
      final port = factory.createAsrPort();
      expect(port, isNotNull);
      expect(port, isA<HybridAsrPort>());
    });

    test('createPorts returns IngestPorts with hybrid ports', () {
      final factory = HybridPortFactory(
        localPorts: IngestPorts(ocr: MockOcrPort()),
        cloudPorts: IngestPorts(asr: MockAsrPort()),
      );
      final ports = factory.createPorts();
      expect(ports, isA<IngestPorts>());
      expect(ports.ocr, isA<HybridOcrPort>());
      expect(ports.asr, isA<HybridAsrPort>());
    });

    test('default strategy is localFirst', () {
      final factory = HybridPortFactory(
        localPorts: const IngestPorts(),
        cloudPorts: const IngestPorts(),
      );
      expect(factory.strategy, ProcessingStrategy.localFirst);
    });
  });
}
