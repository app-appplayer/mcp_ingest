/// Text decoding shared by the text and HTML extractors.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../core/exceptions.dart';

/// Decodes [input] to text.
///
/// [encoding] names the byte encoding (`utf-8`, `utf-16`, `utf-16le`,
/// `utf-16be`, `latin1`, `ascii`). Without it a byte-order mark decides
/// (UTF-8, UTF-16) and the default is UTF-8. A byte-order mark is removed.
///
/// Bytes that are not valid in the encoding throw [ExtractionException]; they
/// are never replaced by substitute characters.
Future<String> decodeText(
  Stream<List<int>> input, {
  required String extractorId,
  String? encoding,
}) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in input) {
    builder.add(chunk);
  }
  return decodeTextBytes(
    builder.takeBytes(),
    extractorId: extractorId,
    encoding: encoding,
  );
}

/// Same as [decodeText] for bytes already in memory.
String decodeTextBytes(
  Uint8List bytes, {
  required String extractorId,
  String? encoding,
}) {
  var name = encoding?.toLowerCase().replaceAll('_', '-');
  var start = 0;

  final hasUtf8Bom = bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF;
  final hasUtf16LeBom =
      bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE;
  final hasUtf16BeBom =
      bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF;

  if (name == null || name == 'utf-8' || name == 'utf8') {
    if (hasUtf8Bom) {
      start = 3;
      name = 'utf-8';
    } else if (name == null && hasUtf16LeBom) {
      name = 'utf-16le';
    } else if (name == null && hasUtf16BeBom) {
      name = 'utf-16be';
    } else {
      name = 'utf-8';
    }
  } else if (name == 'utf-16') {
    if (hasUtf16BeBom) {
      name = 'utf-16be';
    } else {
      name = 'utf-16le';
    }
  }

  try {
    switch (name) {
      case 'utf-8':
      case 'utf8':
        return utf8.decode(bytes.sublist(start));
      case 'utf-16le':
        return _decodeUtf16(bytes, bigEndian: false, skipBom: hasUtf16LeBom);
      case 'utf-16be':
        return _decodeUtf16(bytes, bigEndian: true, skipBom: hasUtf16BeBom);
      case 'latin1':
      case 'iso-8859-1':
        return latin1.decode(bytes);
      case 'ascii':
      case 'us-ascii':
        return ascii.decode(bytes);
    }
  } on FormatException catch (e) {
    throw ExtractionException(
      extractorId,
      'bytes are not valid $name: ${e.message}',
      e,
    );
  }
  throw ExtractionException(
    extractorId,
    'unsupported encoding "$encoding"; convert the input to UTF-8',
  );
}

String _decodeUtf16(
  Uint8List bytes, {
  required bool bigEndian,
  required bool skipBom,
}) {
  var offset = skipBom ? 2 : 0;
  if ((bytes.length - offset).isOdd) {
    throw const FormatException('odd number of bytes');
  }
  final units = <int>[];
  for (; offset < bytes.length; offset += 2) {
    units.add(bigEndian
        ? (bytes[offset] << 8) | bytes[offset + 1]
        : (bytes[offset + 1] << 8) | bytes[offset]);
  }
  return String.fromCharCodes(units);
}
