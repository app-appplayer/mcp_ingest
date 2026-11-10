import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:mcp_ingest/mcp_ingest.dart';

void main() {
  late Directory tempDir;
  late LocalStoragePlugin plugin;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('storage_test_');
    plugin = LocalStoragePlugin(basePath: tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Helper to create a byte stream from a string.
  Stream<List<int>> streamFromString(String s) {
    return Stream.value(Uint8List.fromList(s.codeUnits));
  }

  group('LocalStoragePlugin', () {
    test('store and retrieve returns same bytes', () async {
      final content = 'Hello, storage!';
      final bytes = Uint8List.fromList(content.codeUnits);

      final key = await plugin.store(
        streamFromString(content),
        'text/plain',
      );

      final retrieved = await plugin.retrieve(key);
      expect(retrieved, equals(bytes));
    });

    test('store with content-addressable produces same key for same content',
        () async {
      final content = 'deterministic content';

      final key1 = await plugin.store(
        streamFromString(content),
        'text/plain',
        const StorageOptions(contentAddressable: true),
      );

      final key2 = await plugin.store(
        streamFromString(content),
        'text/plain',
        const StorageOptions(contentAddressable: true),
      );

      expect(key1, equals(key2));
    });

    test(
        'store with non-content-addressable produces different keys '
        'for same content', () async {
      final content = 'same content twice';

      final key1 = await plugin.store(
        streamFromString(content),
        'text/plain',
        const StorageOptions(contentAddressable: false),
      );

      // Small delay to ensure different timestamps
      await Future<void>.delayed(const Duration(milliseconds: 2));

      final key2 = await plugin.store(
        streamFromString(content),
        'text/plain',
        const StorageOptions(contentAddressable: false),
      );

      expect(key1, isNot(equals(key2)));
    });

    test('store with prefix includes prefix/ in key', () async {
      final key = await plugin.store(
        streamFromString('prefixed data'),
        'text/plain',
        const StorageOptions(prefix: 'images'),
      );

      expect(key, startsWith('images/'));
    });

    test('store detects mimeType extension correctly', () async {
      // image/png -> .png
      final pngKey = await plugin.store(
        streamFromString('fake png'),
        'image/png',
      );
      final pngFile = File('${tempDir.path}/$pngKey.png');
      expect(pngFile.existsSync(), isTrue);

      // text/plain -> .txt
      final txtKey = await plugin.store(
        streamFromString('plain text'),
        'text/plain',
      );
      final txtFile = File('${tempDir.path}/$txtKey.txt');
      expect(txtFile.existsSync(), isTrue);

      // unknown type -> .bin
      final binKey = await plugin.store(
        streamFromString('binary stuff'),
        'application/x-custom',
      );
      final binFile = File('${tempDir.path}/$binKey.bin');
      expect(binFile.existsSync(), isTrue);
    });

    test('store with ttlSeconds writes expiresAt in meta file', () async {
      final key = await plugin.store(
        streamFromString('expiring data'),
        'text/plain',
        const StorageOptions(ttlSeconds: 3600),
      );

      final metaFile = File('${tempDir.path}/$key.txt.meta');
      expect(metaFile.existsSync(), isTrue);

      final metaContent = metaFile.readAsStringSync();
      expect(metaContent, contains('expiresAt='));
    });

    test('store without ttlSeconds does not write expiresAt', () async {
      final key = await plugin.store(
        streamFromString('no expiry'),
        'text/plain',
        const StorageOptions(ttlSeconds: 0),
      );

      final metaFile = File('${tempDir.path}/$key.txt.meta');
      expect(metaFile.existsSync(), isTrue);

      final metaContent = metaFile.readAsStringSync();
      expect(metaContent, isNot(contains('expiresAt=')));
    });

    test('retrieve non-existent reference throws StorageException', () async {
      expect(
        () => plugin.retrieve('nonexistent'),
        throwsA(isA<StorageException>()),
      );
    });

    test('exists returns true for stored reference', () async {
      final key = await plugin.store(
        streamFromString('exists test'),
        'text/plain',
      );

      expect(await plugin.exists(key), isTrue);
    });

    test('exists returns false for non-existent reference', () async {
      expect(await plugin.exists('does-not-exist'), isFalse);
    });

    test('metadata returns StorageMetadata with correct fields', () async {
      final content = 'metadata test content';
      final key = await plugin.store(
        streamFromString(content),
        'text/plain',
      );

      final meta = await plugin.metadata(key);
      expect(meta, isNotNull);
      expect(meta!.key, equals(key));
      expect(meta.mimeType, equals('text/plain'));
      expect(meta.size, equals(content.codeUnits.length));
      expect(meta.sha256, isNotEmpty);
      expect(meta.createdAt, isA<DateTime>());
    });

    test('metadata without .meta file generates from file stat', () async {
      final content = 'no meta file';
      final key = await plugin.store(
        streamFromString(content),
        'text/plain',
      );

      // Delete the .meta file manually
      final metaFile = File('${tempDir.path}/$key.txt.meta');
      expect(metaFile.existsSync(), isTrue);
      metaFile.deleteSync();
      expect(metaFile.existsSync(), isFalse);

      final meta = await plugin.metadata(key);
      expect(meta, isNotNull);
      expect(meta!.key, equals(key));
      expect(meta.mimeType, equals('text/plain'));
      expect(meta.size, equals(content.codeUnits.length));
      expect(meta.sha256, isNotEmpty);
      expect(meta.createdAt, isA<DateTime>());
    });

    test('metadata for non-existent reference returns null', () async {
      final meta = await plugin.metadata('ghost-reference');
      expect(meta, isNull);
    });

    test('delete removes file and meta file', () async {
      final key = await plugin.store(
        streamFromString('to be deleted'),
        'text/plain',
      );

      expect(await plugin.exists(key), isTrue);

      final deleted = await plugin.delete(key);
      expect(deleted, isTrue);
      expect(await plugin.exists(key), isFalse);

      // Both file and meta should be gone
      final dataFile = File('${tempDir.path}/$key.txt');
      final metaFile = File('${tempDir.path}/$key.txt.meta');
      expect(dataFile.existsSync(), isFalse);
      expect(metaFile.existsSync(), isFalse);
    });

    test('delete non-existent reference returns false', () async {
      final result = await plugin.delete('nothing-here');
      expect(result, isFalse);
    });

    test('list returns stored references', () async {
      await plugin.store(streamFromString('file1'), 'text/plain');
      await plugin.store(streamFromString('file2'), 'image/png');
      await plugin.store(streamFromString('file3'), 'application/pdf');

      final refs = await plugin.list();
      expect(refs, hasLength(3));
    });

    test('list with prefix filter returns only matching references', () async {
      await plugin.store(
        streamFromString('doc1'),
        'text/plain',
        const StorageOptions(prefix: 'docs'),
      );
      await plugin.store(
        streamFromString('img1'),
        'image/png',
        const StorageOptions(prefix: 'images'),
      );
      await plugin.store(
        streamFromString('doc2'),
        'text/plain',
        const StorageOptions(prefix: 'docs'),
      );

      final docRefs = await plugin.list('docs');
      // Content-addressable: 'doc1' and 'doc2' have different content
      // so they produce different keys
      expect(docRefs, hasLength(2));
      for (final ref in docRefs) {
        expect(ref, startsWith('docs/'));
      }

      final imgRefs = await plugin.list('images');
      expect(imgRefs, hasLength(1));
      for (final ref in imgRefs) {
        expect(ref, startsWith('images/'));
      }
    });

    test('list on empty directory returns empty list', () async {
      final refs = await plugin.list();
      expect(refs, isEmpty);
    });

    test('list with non-existent prefix returns empty list', () async {
      await plugin.store(streamFromString('some data'), 'text/plain');

      final refs = await plugin.list('no-such-prefix');
      expect(refs, isEmpty);
    });

    test('StorageException toString formats correctly', () {
      final exception = StorageException('test error');
      expect(exception.toString(), equals('StorageException: test error'));
      expect(exception.message, equals('test error'));
    });

    test('metadata with ttlSeconds has expiresAt field', () async {
      final key = await plugin.store(
        streamFromString('expiring soon'),
        'text/plain',
        const StorageOptions(ttlSeconds: 60),
      );

      final meta = await plugin.metadata(key);
      expect(meta, isNotNull);
      expect(meta!.expiresAt, isNotNull);
      expect(meta.expiresAt!.isAfter(meta.createdAt), isTrue);
    });

    test('metadata without ttlSeconds has null expiresAt', () async {
      final key = await plugin.store(
        streamFromString('no expiry content'),
        'text/plain',
      );

      final meta = await plugin.metadata(key);
      expect(meta, isNotNull);
      expect(meta!.expiresAt, isNull);
    });

    test(
        'metadata falls back to DateTime.now when createdAt missing from meta file',
        () async {
      final content = 'test for missing createdAt';
      final key = await plugin.store(
        streamFromString(content),
        'text/plain',
      );

      // Rewrite the meta file without createdAt line
      final metaFile = File('${tempDir.path}/$key.txt.meta');
      expect(metaFile.existsSync(), isTrue);
      final original = metaFile.readAsStringSync();
      final lines =
          original.split('\n').where((l) => !l.startsWith('createdAt='));
      metaFile.writeAsStringSync(lines.join('\n'));

      final before = DateTime.now();
      final meta = await plugin.metadata(key);
      final after = DateTime.now();
      expect(meta, isNotNull);
      // createdAt should be approximately now since the fallback uses DateTime.now()
      expect(
          meta!.createdAt.isAfter(before.subtract(const Duration(seconds: 1))),
          isTrue);
      expect(meta.createdAt.isBefore(after.add(const Duration(seconds: 1))),
          isTrue);
    });
  });
}
