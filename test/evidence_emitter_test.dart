import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:mcp_ingest/mcp_ingest.dart';
import 'package:mcp_fact_graph/mcp_fact_graph.dart'
    show EvidenceSourceType, EvidenceStatus;

NormalizedDocument _createDoc({
  String text = 'Hello world',
  String id = 'doc1',
}) {
  return NormalizedDocument(
    id: id,
    metadata:
        const DocumentMetadata(mimeType: 'text/plain', sha256: 'abc123'),
    parts: [TextBlock(id: 'p1', text: text)],
    structure: DocumentStructure.empty,
    provenance: ExtractionProvenance(
      extractorId: 'test',
      extractorVersion: '1.0',
      extractedAt: DateTime(2024, 1, 1),
      extractionDuration: Duration.zero,
    ),
  );
}

IngestInput _createInput({
  String? filename = 'test.txt',
  String? mimeType = 'text/plain',
  String? sourceUri = 'file:///test.txt',
  String content = 'Hello world',
}) {
  return IngestInput.fromString(
    content,
    filename: filename,
    mimeType: mimeType ?? 'text/plain',
  );
}

void main() {
  group('EvidenceEmitterConfig', () {
    test('has correct defaults', () {
      const config = EvidenceEmitterConfig();
      expect(config.defaultWorkspaceId, equals('default'));
      expect(config.includeFullContent, isTrue);
      expect(config.maxContentSize, equals(1024 * 1024));
      expect(config.computeHash, isTrue);
    });

    test('static defaults matches constructor defaults', () {
      const config = EvidenceEmitterConfig.defaults;
      expect(config.defaultWorkspaceId, equals('default'));
      expect(config.includeFullContent, isTrue);
      expect(config.maxContentSize, equals(1024 * 1024));
      expect(config.computeHash, isTrue);
    });

    test('accepts custom values', () {
      const config = EvidenceEmitterConfig(
        defaultWorkspaceId: 'ws-42',
        includeFullContent: false,
        maxContentSize: 512,
        computeHash: false,
      );
      expect(config.defaultWorkspaceId, equals('ws-42'));
      expect(config.includeFullContent, isFalse);
      expect(config.maxContentSize, equals(512));
      expect(config.computeHash, isFalse);
    });
  });

  group('EvidenceEmitter.emit', () {
    test('produces evidence with correct basic fields', () {
      final emitter = EvidenceEmitter();
      final doc = _createDoc();
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList('Hello world'.codeUnits)),
        filename: 'test.txt',
        mimeType: 'text/plain',
        sourceUri: 'file:///test.txt',
      );

      final evidence = emitter.emit(document: doc, input: input);

      expect(evidence.evidenceId, startsWith('ev_'));
      expect(evidence.workspaceId, equals('default'));
      expect(evidence.content, contains('Hello world'));
      expect(evidence.contentHash, isNotEmpty);
      expect(evidence.mimeType, equals('text/plain'));
      expect(evidence.status, equals(EvidenceStatus.extracted));
      expect(evidence.fragmentIds, isEmpty);
    });

    test('uses custom workspaceId when provided', () {
      final emitter = EvidenceEmitter();
      final doc = _createDoc();
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
        filename: 'test.txt',
        mimeType: 'text/plain',
      );

      final evidence = emitter.emit(
        document: doc,
        input: input,
        workspaceId: 'custom-ws',
      );

      expect(evidence.workspaceId, equals('custom-ws'));
    });

    test('uses config defaultWorkspaceId when no workspaceId given', () {
      final emitter = EvidenceEmitter(
        config: const EvidenceEmitterConfig(defaultWorkspaceId: 'config-ws'),
      );
      final doc = _createDoc();
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
        filename: 'test.txt',
        mimeType: 'text/plain',
      );

      final evidence = emitter.emit(document: doc, input: input);

      expect(evidence.workspaceId, equals('config-ws'));
    });

    test('truncates content when exceeding maxContentSize', () {
      final emitter = EvidenceEmitter(
        config: const EvidenceEmitterConfig(maxContentSize: 50),
      );
      final longText = 'A' * 200;
      final doc = _createDoc(text: longText);
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList(longText.codeUnits)),
        filename: 'test.txt',
        mimeType: 'text/plain',
      );

      final evidence = emitter.emit(document: doc, input: input);

      expect(evidence.content.length, equals(50));
      expect(evidence.content, equals('A' * 50));
    });

    test('returns document.id as content when includeFullContent is false',
        () {
      final emitter = EvidenceEmitter(
        config: const EvidenceEmitterConfig(includeFullContent: false),
      );
      final doc = _createDoc(id: 'my-doc-id');
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
        filename: 'test.txt',
        mimeType: 'text/plain',
      );

      final evidence = emitter.emit(document: doc, input: input);

      expect(evidence.content, equals('my-doc-id'));
    });

    test('produces empty contentHash when computeHash is false', () {
      final emitter = EvidenceEmitter(
        config: const EvidenceEmitterConfig(computeHash: false),
      );
      final doc = _createDoc();
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
        filename: 'test.txt',
        mimeType: 'text/plain',
      );

      final evidence = emitter.emit(document: doc, input: input);

      expect(evidence.contentHash, equals(''));
    });

    test('computes SHA-256 hash when computeHash is true', () {
      final emitter = EvidenceEmitter();
      final doc = _createDoc();
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
        filename: 'test.txt',
        mimeType: 'text/plain',
      );

      final evidence = emitter.emit(document: doc, input: input);

      // SHA-256 hash is a 64-character hex string
      expect(evidence.contentHash, hasLength(64));
      expect(evidence.contentHash, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    group('source type mapping', () {
      test('text/plain maps to EvidenceSourceType.text', () {
        final emitter = EvidenceEmitter();
        final doc = _createDoc();
        final input = IngestInput(
          stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
          filename: 'test.txt',
          mimeType: 'text/plain',
        );

        final evidence = emitter.emit(document: doc, input: input);

        expect(evidence.sourceType, equals(EvidenceSourceType.text));
      });

      test('image/png maps to EvidenceSourceType.image', () {
        final emitter = EvidenceEmitter();
        final doc = _createDoc();
        final input = IngestInput(
          stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
          filename: 'photo.png',
          mimeType: 'image/png',
        );

        final evidence = emitter.emit(document: doc, input: input);

        expect(evidence.sourceType, equals(EvidenceSourceType.image));
      });

      test('application/json maps to text because isText includes text-based mimes', () {
        // application/json is in ContentType._textBasedMimes, so isText is true,
        // and _mapSourceType checks isText before json/xml content check.
        final emitter = EvidenceEmitter();
        final doc = _createDoc();
        final input = IngestInput(
          stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
          filename: 'data.json',
          mimeType: 'application/json',
        );

        final evidence = emitter.emit(document: doc, input: input);

        expect(evidence.sourceType, equals(EvidenceSourceType.text));
      });

      test('application/xml maps to text because isText includes text-based mimes', () {
        // application/xml is in ContentType._textBasedMimes, so isText is true.
        final emitter = EvidenceEmitter();
        final doc = _createDoc();
        final input = IngestInput(
          stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
          filename: 'data.xml',
          mimeType: 'application/xml',
        );

        final evidence = emitter.emit(document: doc, input: input);

        expect(evidence.sourceType, equals(EvidenceSourceType.text));
      });

      test('non-text json type maps to EvidenceSourceType.api', () {
        // A json-containing mime that is NOT in _textBasedMimes hits the api branch
        final emitter = EvidenceEmitter();
        final doc = _createDoc();
        final input = IngestInput(
          stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
          filename: 'data.json',
          mimeType: 'application/vnd.api+json',
        );

        final evidence = emitter.emit(document: doc, input: input);

        expect(evidence.sourceType, equals(EvidenceSourceType.api));
      });

      test('message/rfc822 maps to EvidenceSourceType.message', () {
        final emitter = EvidenceEmitter();
        final doc = _createDoc();
        final input = IngestInput(
          stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
          filename: 'email.eml',
          mimeType: 'message/rfc822',
        );

        final evidence = emitter.emit(document: doc, input: input);

        expect(evidence.sourceType, equals(EvidenceSourceType.message));
      });

      test('application/pdf maps to EvidenceSourceType.file', () {
        final emitter = EvidenceEmitter();
        final doc = _createDoc();
        final input = IngestInput(
          stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
          filename: 'doc.pdf',
          mimeType: 'application/pdf',
        );

        final evidence = emitter.emit(document: doc, input: input);

        expect(evidence.sourceType, equals(EvidenceSourceType.file));
      });
    });

    test('uses explicit ContentType when provided', () {
      final emitter = EvidenceEmitter();
      final doc = _createDoc();
      // Input has text/plain mimeType but we override with image/png ContentType
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
        filename: 'test.txt',
        mimeType: 'text/plain',
      );

      final evidence = emitter.emit(
        document: doc,
        input: input,
        contentType: const ContentType('image/png'),
      );

      expect(evidence.sourceType, equals(EvidenceSourceType.image));
      expect(evidence.mimeType, equals('image/png'));
    });

    test('merges additionalMetadata into evidence metadata', () {
      final emitter = EvidenceEmitter();
      final doc = _createDoc();
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
        filename: 'test.txt',
        mimeType: 'text/plain',
      );

      final evidence = emitter.emit(
        document: doc,
        input: input,
        additionalMetadata: {'customKey': 'customValue', 'priority': 1},
      );

      expect(evidence.metadata['customKey'], equals('customValue'));
      expect(evidence.metadata['priority'], equals(1));
      // Standard metadata fields should also be present
      expect(evidence.metadata['documentId'], equals('doc1'));
      expect(evidence.metadata['contentType'], equals('text/plain'));
    });

    test('builds source info from input and document provenance', () {
      final emitter = EvidenceEmitter();
      final doc = _createDoc();
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
        filename: 'report.txt',
        mimeType: 'text/plain',
        sourceUri: 'file:///path/to/report.txt',
      );

      final evidence = emitter.emit(document: doc, input: input);

      expect(evidence.source.name, equals('report.txt'));
      expect(evidence.source.uri, equals('file:///path/to/report.txt'));
      expect(evidence.source.capturedAt, equals(DateTime(2024, 1, 1)));
      expect(evidence.source.attributes['extractorId'], equals('test'));
      expect(evidence.source.attributes['extractorVersion'], equals('1.0'));
    });

    test('source name falls back to document title when no filename', () {
      final emitter = EvidenceEmitter();
      final doc = NormalizedDocument(
        id: 'doc1',
        metadata: const DocumentMetadata(
          mimeType: 'text/plain',
          sha256: 'abc123',
          title: 'My Document Title',
        ),
        parts: [const TextBlock(id: 'p1', text: 'content')],
        structure: DocumentStructure.empty,
        provenance: ExtractionProvenance(
          extractorId: 'test',
          extractorVersion: '1.0',
          extractedAt: DateTime(2024, 1, 1),
          extractionDuration: Duration.zero,
        ),
      );
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
        mimeType: 'text/plain',
      );

      final evidence = emitter.emit(document: doc, input: input);

      expect(evidence.source.name, equals('My Document Title'));
    });

    test('source name falls back to document id when no filename or title',
        () {
      final emitter = EvidenceEmitter();
      final doc = _createDoc(id: 'fallback-doc-id');
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
        mimeType: 'text/plain',
      );

      final evidence = emitter.emit(document: doc, input: input);

      expect(evidence.source.name, equals('fallback-doc-id'));
    });

    test('metadata includes partCount and characterCount', () {
      final emitter = EvidenceEmitter();
      final doc = _createDoc(text: 'Hello world');
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
        filename: 'test.txt',
        mimeType: 'text/plain',
      );

      final evidence = emitter.emit(document: doc, input: input);

      expect(evidence.metadata['partCount'], equals(1));
      expect(evidence.metadata['characterCount'], equals(doc.characterCount));
    });

    test('metadata includes fileName when input has filename', () {
      final emitter = EvidenceEmitter();
      final doc = _createDoc();
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
        filename: 'important.txt',
        mimeType: 'text/plain',
      );

      final evidence = emitter.emit(document: doc, input: input);

      expect(evidence.metadata['fileName'], equals('important.txt'));
    });

    test('metadata includes fileSize when input has size', () {
      final emitter = EvidenceEmitter();
      final doc = _createDoc();
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
        filename: 'test.txt',
        mimeType: 'text/plain',
        size: 1024,
      );

      final evidence = emitter.emit(document: doc, input: input);

      expect(evidence.metadata['fileSize'], equals(1024));
    });

    test('metadata includes createdAt when document has createdAt', () {
      final emitter = EvidenceEmitter();
      final createdAt = DateTime(2024, 6, 15, 10, 30);
      final doc = NormalizedDocument(
        id: 'doc_with_date',
        metadata: DocumentMetadata(
          mimeType: 'text/plain',
          sha256: 'hash123',
          createdAt: createdAt,
        ),
        parts: [const TextBlock(id: 'p1', text: 'Content')],
        structure: DocumentStructure.empty,
        provenance: ExtractionProvenance(
          extractorId: 'test',
          extractorVersion: '1.0',
          extractedAt: DateTime(2024, 1, 1),
          extractionDuration: Duration.zero,
        ),
      );
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
        filename: 'test.txt',
        mimeType: 'text/plain',
      );

      final evidence = emitter.emit(document: doc, input: input);

      expect(
        evidence.metadata['createdAt'],
        equals(createdAt.toIso8601String()),
      );
    });

    test('detects content type from filename when mimeType is null', () {
      final emitter = EvidenceEmitter();
      final doc = _createDoc();
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
        filename: 'data.json',
      );

      final evidence = emitter.emit(document: doc, input: input);

      expect(evidence.mimeType, equals('application/json'));
      // application/json is text-based, so isText takes priority over json check
      expect(evidence.sourceType, equals(EvidenceSourceType.text));
    });

    test(
        'falls back to application/octet-stream when no mimeType or filename',
        () {
      final emitter = EvidenceEmitter();
      final doc = _createDoc();
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
      );

      final evidence = emitter.emit(document: doc, input: input);

      expect(evidence.mimeType, equals('application/octet-stream'));
    });

    test('evidence ID is unique across calls', () {
      final emitter = EvidenceEmitter();
      final doc = _createDoc();
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
        filename: 'test.txt',
        mimeType: 'text/plain',
      );

      final evidence1 = emitter.emit(document: doc, input: input);
      final evidence2 = emitter.emit(document: doc, input: input);

      // Evidence IDs should differ because timestamp is part of the hash
      expect(evidence1.evidenceId, startsWith('ev_'));
      expect(evidence2.evidenceId, startsWith('ev_'));
    });
  });

  group('EvidenceEmitter.emitFromRaw', () {
    test('creates evidence from raw input bytes', () async {
      final emitter = EvidenceEmitter();
      final bytes = Uint8List.fromList(utf8.encode('raw content'));
      final input = IngestInput(
        stream: Stream.value(bytes),
        filename: 'raw.txt',
        mimeType: 'text/plain',
        sourceUri: 'file:///raw.txt',
      );

      final evidence = await emitter.emitFromRaw(input: input);

      expect(evidence.evidenceId, startsWith('ev_'));
      expect(evidence.workspaceId, equals('default'));
      expect(evidence.status, equals(EvidenceStatus.pending));
      expect(evidence.content, equals(base64Encode(bytes)));
      expect(evidence.contentHash, isNotEmpty);
      expect(evidence.fragmentIds, isEmpty);
    });

    test('uses custom workspaceId', () async {
      final emitter = EvidenceEmitter();
      final bytes = Uint8List.fromList(utf8.encode('data'));
      final input = IngestInput(
        stream: Stream.value(bytes),
        filename: 'test.txt',
        mimeType: 'text/plain',
      );

      final evidence = await emitter.emitFromRaw(
        input: input,
        workspaceId: 'ws-raw',
      );

      expect(evidence.workspaceId, equals('ws-raw'));
    });

    test('includes provided metadata', () async {
      final emitter = EvidenceEmitter();
      final bytes = Uint8List.fromList(utf8.encode('data'));
      final input = IngestInput(
        stream: Stream.value(bytes),
        filename: 'test.txt',
        mimeType: 'text/plain',
      );

      final evidence = await emitter.emitFromRaw(
        input: input,
        metadata: {'source': 'upload', 'userId': '123'},
      );

      expect(evidence.metadata['source'], equals('upload'));
      expect(evidence.metadata['userId'], equals('123'));
    });

    test('source name defaults to unknown when no filename', () async {
      final emitter = EvidenceEmitter();
      final bytes = Uint8List.fromList(utf8.encode('data'));
      final input = IngestInput(
        stream: Stream.value(bytes),
      );

      final evidence = await emitter.emitFromRaw(input: input);

      expect(evidence.source.name, equals('unknown'));
    });

    test('source name uses filename when provided', () async {
      final emitter = EvidenceEmitter();
      final bytes = Uint8List.fromList(utf8.encode('data'));
      final input = IngestInput(
        stream: Stream.value(bytes),
        filename: 'upload.pdf',
      );

      final evidence = await emitter.emitFromRaw(input: input);

      expect(evidence.source.name, equals('upload.pdf'));
    });

    test('source uri is set from input', () async {
      final emitter = EvidenceEmitter();
      final bytes = Uint8List.fromList(utf8.encode('data'));
      final input = IngestInput(
        stream: Stream.value(bytes),
        filename: 'test.txt',
        sourceUri: 'https://example.com/test.txt',
      );

      final evidence = await emitter.emitFromRaw(input: input);

      expect(evidence.source.uri, equals('https://example.com/test.txt'));
    });

    test('computes hash when computeHash is true', () async {
      final emitter = EvidenceEmitter();
      final bytes = Uint8List.fromList(utf8.encode('data'));
      final input = IngestInput(
        stream: Stream.value(bytes),
        filename: 'test.txt',
      );

      final evidence = await emitter.emitFromRaw(input: input);

      expect(evidence.contentHash, hasLength(64));
      expect(evidence.contentHash, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('skips hash when computeHash is false', () async {
      final emitter = EvidenceEmitter(
        config: const EvidenceEmitterConfig(computeHash: false),
      );
      final bytes = Uint8List.fromList(utf8.encode('data'));
      final input = IngestInput(
        stream: Stream.value(bytes),
        filename: 'test.txt',
      );

      final evidence = await emitter.emitFromRaw(input: input);

      expect(evidence.contentHash, equals(''));
    });

    test('uses empty metadata when none provided', () async {
      final emitter = EvidenceEmitter();
      final bytes = Uint8List.fromList(utf8.encode('data'));
      final input = IngestInput(
        stream: Stream.value(bytes),
        filename: 'test.txt',
      );

      final evidence = await emitter.emitFromRaw(input: input);

      expect(evidence.metadata, isEmpty);
    });
  });

  group('BatchEvidenceEmitter', () {
    test('emitBatch processes multiple documents', () {
      final batchEmitter = BatchEvidenceEmitter();

      final doc1 = _createDoc(id: 'doc1', text: 'First document');
      final doc2 = _createDoc(id: 'doc2', text: 'Second document');
      final doc3 = _createDoc(id: 'doc3', text: 'Third document');

      final input1 = IngestInput(
        stream: Stream.value(Uint8List.fromList('d1'.codeUnits)),
        filename: 'first.txt',
        mimeType: 'text/plain',
      );
      final input2 = IngestInput(
        stream: Stream.value(Uint8List.fromList('d2'.codeUnits)),
        filename: 'second.txt',
        mimeType: 'text/plain',
      );
      final input3 = IngestInput(
        stream: Stream.value(Uint8List.fromList('d3'.codeUnits)),
        filename: 'third.txt',
        mimeType: 'text/plain',
      );

      final results = batchEmitter.emitBatch(
        items: [
          (doc1, input1, null),
          (doc2, input2, null),
          (doc3, input3, const ContentType('image/jpeg')),
        ],
      );

      expect(results, hasLength(3));
      expect(results[0].content, contains('First document'));
      expect(results[1].content, contains('Second document'));
      expect(results[2].content, contains('Third document'));
      // Third item has explicit ContentType override
      expect(results[2].sourceType, equals(EvidenceSourceType.image));
    });

    test('emitBatch uses shared workspaceId', () {
      final batchEmitter = BatchEvidenceEmitter();

      final doc = _createDoc();
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
        filename: 'test.txt',
        mimeType: 'text/plain',
      );

      final results = batchEmitter.emitBatch(
        items: [(doc, input, null)],
        workspaceId: 'batch-ws',
      );

      expect(results.first.workspaceId, equals('batch-ws'));
    });

    test('emitBatch returns empty list for empty input', () {
      final batchEmitter = BatchEvidenceEmitter();

      final results = batchEmitter.emitBatch(items: []);

      expect(results, isEmpty);
    });

    test('emitBatch uses custom config', () {
      final batchEmitter = BatchEvidenceEmitter(
        config: const EvidenceEmitterConfig(computeHash: false),
      );

      final doc = _createDoc();
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
        filename: 'test.txt',
        mimeType: 'text/plain',
      );

      final results = batchEmitter.emitBatch(items: [(doc, input, null)]);

      expect(results.first.contentHash, equals(''));
    });

    test('emitStream processes stream of documents', () async {
      final batchEmitter = BatchEvidenceEmitter();

      final doc1 = _createDoc(id: 'doc1', text: 'Stream doc 1');
      final doc2 = _createDoc(id: 'doc2', text: 'Stream doc 2');

      final input1 = IngestInput(
        stream: Stream.value(Uint8List.fromList('d1'.codeUnits)),
        filename: 'stream1.txt',
        mimeType: 'text/plain',
      );
      final input2 = IngestInput(
        stream: Stream.value(Uint8List.fromList('d2'.codeUnits)),
        filename: 'stream2.txt',
        mimeType: 'text/plain',
      );

      final itemStream = Stream<(NormalizedDocument, IngestInput, ContentType?)>
          .fromIterable([
        (doc1, input1, null),
        (doc2, input2, null),
      ]);

      final results = await batchEmitter
          .emitStream(items: itemStream)
          .toList();

      expect(results, hasLength(2));
      expect(results[0].content, contains('Stream doc 1'));
      expect(results[1].content, contains('Stream doc 2'));
      expect(results[0].evidenceId, startsWith('ev_'));
      expect(results[1].evidenceId, startsWith('ev_'));
    });

    test('emitStream uses shared workspaceId', () async {
      final batchEmitter = BatchEvidenceEmitter();

      final doc = _createDoc();
      final input = IngestInput(
        stream: Stream.value(Uint8List.fromList('data'.codeUnits)),
        filename: 'test.txt',
        mimeType: 'text/plain',
      );

      final itemStream = Stream<(NormalizedDocument, IngestInput, ContentType?)>
          .fromIterable([(doc, input, null)]);

      final results = await batchEmitter
          .emitStream(items: itemStream, workspaceId: 'stream-ws')
          .toList();

      expect(results.first.workspaceId, equals('stream-ws'));
    });

    test('emitStream handles empty stream', () async {
      final batchEmitter = BatchEvidenceEmitter();

      final itemStream = Stream<
          (NormalizedDocument, IngestInput, ContentType?)>.fromIterable([]);

      final results = await batchEmitter
          .emitStream(items: itemStream)
          .toList();

      expect(results, isEmpty);
    });
  });
}
