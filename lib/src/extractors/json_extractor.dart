/// JSON/YAML extractor.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';
import 'package:mcp_fact_graph/mcp_fact_graph.dart' show ExtractorType;

import '../core/fragment_value_type.dart';

import '../document/document_metadata.dart';
import '../document/document_part.dart';
import '../document/document_structure.dart';
import '../document/normalized_document.dart';
import 'extractor.dart';

/// Extracts JSON and YAML structured data.
class JsonExtractor extends Extractor {
  @override
  String get id => 'json_schema_v1';

  @override
  Set<String> get supportedTypes => {
        'application/json',
        'text/json',
        'application/x-yaml',
        'text/yaml',
        'text/x-yaml',
      };

  @override
  int get priority => 0;

  @override
  Duration estimateDuration(int fileSize) =>
      Duration(milliseconds: fileSize ~/ 10000); // ~100ms per MB

  @override
  Future<NormalizedDocument> extract(
    Stream<List<int>> input,
    ExtractOptions options,
  ) async {
    final stopwatch = Stopwatch()..start();
    final content = await utf8.decodeStream(input);
    final isYaml = options.custom?['isYaml'] == true ||
        options.custom?['mimeType']?.contains('yaml') == true;

    dynamic data;
    try {
      data = isYaml ? loadYaml(content) : jsonDecode(content);
    } catch (e) {
      // Try YAML if JSON fails
      try {
        data = loadYaml(content);
      } catch (_) {
        rethrow;
      }
    }

    final parts = <DocumentPart>[];
    var partIndex = 0;
    _extractValue(data, '', parts, partIndex);

    stopwatch.stop();
    final hash = sha256.convert(utf8.encode(content)).toString();

    return NormalizedDocument(
      id: const Uuid().v4(),
      metadata: DocumentMetadata(
        mimeType: isYaml ? 'application/x-yaml' : 'application/json',
        sha256: hash,
        fileSize: content.length,
      ),
      parts: parts,
      structure: DocumentStructure.empty,
      provenance: ExtractionProvenance(
        extractorId: id,
        extractorVersion: '1.0.0',
        extractedAt: DateTime.now(),
        extractionDuration: stopwatch.elapsed,
      ),
    );
  }

  int _extractValue(
    dynamic value,
    String path,
    List<DocumentPart> parts,
    int partIndex,
  ) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final newPath = path.isEmpty ? key : '$path.$key';

        if (_isLeafValue(entry.value)) {
          parts.add(KeyValueBlock(
            id: 'kv$partIndex',
            key: newPath,
            value: entry.value.toString(),
            normalizedValue: entry.value,
            valueType: _inferType(entry.value),
            extractor: ExtractorType.rule,
            confidence: 1.0,
          ));
          partIndex++;
        } else {
          partIndex = _extractValue(entry.value, newPath, parts, partIndex);
        }
      }
    } else if (value is List) {
      for (var i = 0; i < value.length; i++) {
        final newPath = '$path[$i]';
        if (_isLeafValue(value[i])) {
          parts.add(KeyValueBlock(
            id: 'kv$partIndex',
            key: newPath,
            value: value[i].toString(),
            normalizedValue: value[i],
            valueType: _inferType(value[i]),
            extractor: ExtractorType.rule,
            confidence: 1.0,
          ));
          partIndex++;
        } else {
          partIndex = _extractValue(value[i], newPath, parts, partIndex);
        }
      }
    }
    return partIndex;
  }

  bool _isLeafValue(dynamic value) {
    return value == null || value is String || value is num || value is bool;
  }

  FragmentValueType _inferType(dynamic value) {
    if (value == null) return FragmentValueType.string;
    if (value is bool) return FragmentValueType.boolean;
    if (value is int) return FragmentValueType.number;
    if (value is double) return FragmentValueType.number;
    if (value is String) {
      // Try to detect date format
      if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(value)) {
        return FragmentValueType.date;
      }
      // Try to detect percentage
      if (RegExp(r'^\d+\.?\d*%$').hasMatch(value)) {
        return FragmentValueType.percentage;
      }
      // Try to detect currency
      if (RegExp(r'^[\$€£¥₩]\s*\d').hasMatch(value)) {
        return FragmentValueType.currency;
      }
      return FragmentValueType.string;
    }
    return FragmentValueType.unknown;
  }
}
