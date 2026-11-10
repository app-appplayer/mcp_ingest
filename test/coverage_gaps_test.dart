// Branches the other tests do not reach: plugin metadata and lifecycle, the
// ASCII decoder, a failing post-chunk stage, and document metadata that is
// copied to the evidence.

import 'dart:io';
import 'dart:typed_data';

import 'package:mcp_ingest/mcp_ingest.dart';
import 'package:mcp_ingest/src/extractors/text_decoding.dart';
import 'package:test/test.dart';

class _FailingStage extends CustomPipelineStage {
  @override
  String get id => 'failing';
  @override
  String get name => 'Failing';
  @override
  StagePhase get phase => StagePhase.postChunk;
  @override
  Future<List<Chunk>> processChunks(List<Chunk> chunks) async =>
      throw StateError('boom');
}

class _MetaExtractor extends Extractor {
  @override
  String get id => 'meta';
  @override
  Set<String> get supportedTypes => {'text/x-meta'};
  @override
  int get priority => 100;
  @override
  Duration estimateDuration(int fileSize) => Duration.zero;
  @override
  Future<NormalizedDocument> extract(
      Stream<List<int>> input, ExtractOptions options) async {
    await input.drain<void>();
    return NormalizedDocument(
      id: 'doc_meta',
      metadata: const DocumentMetadata(
        title: 'A title',
        mimeType: 'text/x-meta',
        sha256: 'abc',
        fileSize: 3,
        pageCount: 7,
        language: 'ko',
      ),
      parts: [TextBlock(id: 'p1', text: 'Some text for the chunker.')],
      structure: DocumentStructure.empty,
      provenance: ExtractionProvenance(
        extractorId: 'meta',
        extractorVersion: '1',
        extractedAt: DateTime.utc(2026),
        extractionDuration: Duration.zero,
      ),
    );
  }
}

void main() {
  test('Whisper plugin: name, version and lifecycle', () async {
    final p = WhisperAsrPlugin();
    expect(p.name, isNotEmpty);
    expect(p.version, isNotEmpty);
    await p.initialize();
    await p.dispose();
  });

  test('local storage plugin: name, version, availability and lifecycle',
      () async {
    final dir = Directory.systemTemp.createTempSync('cov_store_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final p = LocalStoragePlugin(basePath: '${dir.path}/sub/dir');
    expect(p.name, isNotEmpty);
    expect(p.version, isNotEmpty);
    expect(await p.isAvailable(), isTrue); // creates the directory
    expect(await p.isAvailable(), isTrue); // exists already
    await Directory('${dir.path}/sub').delete(recursive: true);
    await p.initialize(); // creates it again
    expect(Directory('${dir.path}/sub/dir').existsSync(), isTrue);
    await p.initialize(); // exists already
    await p.dispose();
    // A base path that cannot be created is not available.
    final file = File('${dir.path}/file')..writeAsStringSync('x');
    expect(
        await LocalStoragePlugin(basePath: '${file.path}/nope').isAvailable(),
        isFalse);
  });

  test('ASCII text is decoded', () {
    expect(
        decodeTextBytes(Uint8List.fromList('hello'.codeUnits),
            extractorId: 't', encoding: 'ascii'),
        'hello');
    expect(
        decodeTextBytes(Uint8List.fromList('hi'.codeUnits),
            extractorId: 't', encoding: 'us-ascii'),
        'hi');
  });

  test('a post-chunk stage that fails is a warning, not a failure', () async {
    final pipeline = IngestPipeline(
      extractors: ExtractorRegistry.defaults(),
      chunkerFactory: ChunkerFactory(),
      customStages: [_FailingStage()],
    );
    final r = await pipeline.ingest(
        IngestInput.fromBytes(Uint8List.fromList('Hello world text.'.codeUnits),
            mimeType: 'text/plain'),
        IngestOptions.defaults);
    expect(r.success, isTrue);
    expect(r.warnings, contains(contains('postChunk stage failing failed')));
  });

  test('title, page count and language of the document reach the evidence',
      () async {
    final registry = ExtractorRegistry()..register(_MetaExtractor());
    final pipeline =
        IngestPipeline(extractors: registry, chunkerFactory: ChunkerFactory());
    final r = await pipeline.ingest(
        IngestInput.fromBytes(Uint8List.fromList([1, 2, 3]),
            mimeType: 'text/x-meta'),
        IngestOptions.defaults);
    expect(r.success, isTrue, reason: '${r.warnings}');
    final meta = r.evidence!.metadata;
    expect(meta['title'], 'A title');
    expect(meta['pageCount'], 7);
    expect(meta['language'], 'ko');
  });
}
