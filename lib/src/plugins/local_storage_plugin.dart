/// Local file system storage plugin.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../core/ingest_input.dart';
import '../ports/storage_port.dart';
import 'plugin.dart';

/// Local filesystem storage implementation.
///
/// Implements both [BinaryStoragePort] (for pipeline injection) and
/// [NativePlugin] (for `PluginRegistry` lifecycle management).
class LocalStoragePlugin implements BinaryStoragePort, NativePlugin {
  /// Base directory for storage.
  final String basePath;

  LocalStoragePlugin({
    required this.basePath,
  });

  // === NativePlugin ===

  @override
  String get id => 'local_storage';

  @override
  String get name => 'Local Filesystem Storage';

  @override
  String get version => '1.0';

  @override
  Future<bool> isAvailable() async {
    // Filesystem is always available on supported platforms.
    // Verify that basePath is writable.
    try {
      final dir = Directory(basePath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> initialize() async {
    // Ensure basePath exists.
    final dir = Directory(basePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  @override
  Future<void> dispose() async {
    // Filesystem handles are per-operation; nothing to dispose.
  }

  @override
  Future<String> store(
    Stream<List<int>> data,
    String mimeType, [
    StorageOptions options = const StorageOptions(),
  ]) async {
    final bytes = await collectBytes(data);

    String key;
    if (options.contentAddressable) {
      // Use content hash as key
      final hash = sha256.convert(bytes).toString();
      key = hash.substring(0, 16);
    } else {
      // Generate unique key
      key = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    }

    if (options.prefix != null) {
      key = '${options.prefix}/$key';
    }

    // Determine file extension
    final ext = _mimeToExtension(mimeType);
    final filePath = '$basePath/$key$ext';

    // Create directory if needed
    final dir = Directory('$basePath/${options.prefix ?? ''}');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Write file
    final file = File(filePath);
    await file.writeAsBytes(bytes);

    // Write metadata
    final metaFile = File('$filePath.meta');
    await metaFile.writeAsString([
      'mimeType=$mimeType',
      'size=${bytes.length}',
      'sha256=${sha256.convert(bytes)}',
      'createdAt=${DateTime.now().toIso8601String()}',
      if (options.ttlSeconds > 0)
        'expiresAt=${DateTime.now().add(Duration(seconds: options.ttlSeconds)).toIso8601String()}',
    ].join('\n'));

    return key;
  }

  @override
  Future<Uint8List> retrieve(String reference) async {
    final files = await _findFile(reference);
    if (files.isEmpty) {
      throw StorageException('File not found: $reference');
    }

    return files.first.readAsBytes();
  }

  @override
  Future<bool> exists(String reference) async {
    final files = await _findFile(reference);
    return files.isNotEmpty;
  }

  @override
  Future<StorageMetadata?> metadata(String reference) async {
    final files = await _findFile(reference);
    if (files.isEmpty) return null;

    final file = files.first;
    final metaFile = File('${file.path}.meta');

    if (!await metaFile.exists()) {
      // Generate basic metadata
      final stat = await file.stat();
      final bytes = await file.readAsBytes();
      return StorageMetadata(
        key: reference,
        mimeType: _guessContentType(file.path),
        size: stat.size,
        sha256: sha256.convert(bytes).toString(),
        createdAt: stat.modified,
      );
    }

    // Parse metadata file
    final content = await metaFile.readAsString();
    final props = <String, String>{};
    for (final line in content.split('\n')) {
      final idx = line.indexOf('=');
      if (idx > 0) {
        props[line.substring(0, idx)] = line.substring(idx + 1);
      }
    }

    return StorageMetadata(
      key: reference,
      mimeType: props['mimeType'] ?? 'application/octet-stream',
      size: int.tryParse(props['size'] ?? '0') ?? 0,
      sha256: props['sha256'] ?? '',
      createdAt: props['createdAt'] != null
          ? DateTime.parse(props['createdAt']!)
          : DateTime.now(),
      expiresAt: props['expiresAt'] != null
          ? DateTime.parse(props['expiresAt']!)
          : null,
    );
  }

  @override
  Future<bool> delete(String reference) async {
    final files = await _findFile(reference);
    if (files.isEmpty) return false;

    for (final file in files) {
      await file.delete();
      final metaFile = File('${file.path}.meta');
      if (await metaFile.exists()) {
        await metaFile.delete();
      }
    }

    return true;
  }

  @override
  Future<List<String>> list([String? prefix]) async {
    final dir = Directory(prefix != null ? '$basePath/$prefix' : basePath);
    if (!await dir.exists()) return [];

    final refs = <String>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && !entity.path.endsWith('.meta')) {
        final ref = entity.path
            .substring(basePath.length + 1)
            .replaceAll(RegExp(r'\.[^.]+$'), '');
        refs.add(ref);
      }
    }

    return refs;
  }

  Future<List<File>> _findFile(String reference) async {
    final dir = Directory(basePath);
    if (!await dir.exists()) return [];

    final files = <File>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && !entity.path.endsWith('.meta')) {
        final name = entity.path.substring(basePath.length + 1);
        final refName = name.replaceAll(RegExp(r'\.[^.]+$'), '');
        if (refName == reference) {
          files.add(entity);
        }
      }
    }

    return files;
  }

  String _mimeToExtension(String mimeType) {
    return switch (mimeType) {
      'image/png' => '.png',
      'image/jpeg' => '.jpg',
      'image/gif' => '.gif',
      'image/webp' => '.webp',
      'audio/mpeg' => '.mp3',
      'audio/wav' => '.wav',
      'audio/ogg' => '.ogg',
      'audio/flac' => '.flac',
      'application/pdf' => '.pdf',
      'text/plain' => '.txt',
      _ => '.bin',
    };
  }

  String _guessContentType(String path) {
    final ext = path.substring(path.lastIndexOf('.'));
    return switch (ext) {
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      '.mp3' => 'audio/mpeg',
      '.wav' => 'audio/wav',
      '.ogg' => 'audio/ogg',
      '.flac' => 'audio/flac',
      '.pdf' => 'application/pdf',
      '.txt' => 'text/plain',
      _ => 'application/octet-stream',
    };
  }
}

/// Storage-specific exception.
class StorageException implements Exception {
  final String message;
  StorageException(this.message);

  @override
  String toString() => 'StorageException: $message';
}
