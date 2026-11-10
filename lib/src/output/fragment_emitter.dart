/// Fragment Emitter - Converts document chunks to FactGraph Fragments.
///
/// Transforms extracted chunks into Fragment entities for the L0 layer.
library;

import 'package:mcp_fact_graph/mcp_fact_graph.dart'
    show Fragment, ExtractorType, FragmentStatus;

import '../core/fragment_value_type.dart';
import '../core/source_position.dart';

import '../document/chunk.dart';
import '../document/normalized_document.dart';
import '../document/document_part.dart';

/// Configuration for fragment emission.
class FragmentEmitterConfig {
  /// Default workspace ID.
  final String defaultWorkspaceId;

  /// Default confidence for extracted fragments.
  final double defaultConfidence;

  /// Default extractor type.
  final ExtractorType defaultExtractor;

  /// Whether to extract key-value pairs as separate fragments.
  final bool extractKeyValues;

  /// Whether to extract table cells as fragments.
  final bool extractTableCells;

  const FragmentEmitterConfig({
    this.defaultWorkspaceId = 'default',
    this.defaultConfidence = 0.8,
    this.defaultExtractor = ExtractorType.rule,
    this.extractKeyValues = true,
    this.extractTableCells = false,
  });

  /// Default configuration.
  static const defaults = FragmentEmitterConfig();
}

/// Emits Fragment entities from document chunks and parts.
class FragmentEmitter {
  /// Emitter configuration.
  final FragmentEmitterConfig config;

  /// Fragment ID counter for uniqueness.
  int _idCounter = 0;

  FragmentEmitter({this.config = FragmentEmitterConfig.defaults});

  /// Emit fragments from a normalized document.
  List<Fragment> emitFromDocument({
    required NormalizedDocument document,
    required String evidenceId,
    String? workspaceId,
  }) {
    final fragments = <Fragment>[];
    final ws = workspaceId ?? config.defaultWorkspaceId;

    // Extract from key-value blocks
    if (config.extractKeyValues) {
      for (final kv in document.keyValueBlocks) {
        fragments.add(_createFragment(
          evidenceId: evidenceId,
          workspaceId: ws,
          field: kv.key,
          value: kv.value,
          confidence: kv.confidence,
          extractor: ExtractorType.rule,
          position: _partPosition(kv),
        ));
      }
    }

    // Extract from table blocks
    if (config.extractTableCells) {
      for (final table in document.tableBlocks) {
        fragments.addAll(_extractFromTable(table, evidenceId, ws));
      }
    }

    return fragments;
  }

  /// Emit fragments from chunks.
  List<Fragment> emitFromChunks({
    required List<Chunk> chunks,
    required String evidenceId,
    String? workspaceId,
    String fieldPrefix = 'chunk',
  }) {
    final ws = workspaceId ?? config.defaultWorkspaceId;

    return chunks.map((chunk) {
      return _createFragment(
        evidenceId: evidenceId,
        workspaceId: ws,
        field: '${fieldPrefix}_${chunk.index}',
        value: chunk.text,
        confidence: config.defaultConfidence,
        extractor: config.defaultExtractor,
        position: _chunkPosition(chunk),
        metadata: {
          'chunkId': chunk.id,
          'chunkIndex': chunk.index,
          'totalChunks': chunk.totalChunks,
          if (chunk.contextPrefix != null) 'contextPrefix': chunk.contextPrefix,
        },
      );
    }).toList();
  }

  /// Emit a single fragment with custom properties.
  Fragment emitSingle({
    required String evidenceId,
    required String field,
    required dynamic value,
    String? workspaceId,
    double? confidence,
    ExtractorType? extractor,
    SourcePosition? position,
    Map<String, dynamic>? metadata,
  }) {
    return _createFragment(
      evidenceId: evidenceId,
      workspaceId: workspaceId ?? config.defaultWorkspaceId,
      field: field,
      value: value,
      confidence: confidence ?? config.defaultConfidence,
      extractor: extractor ?? config.defaultExtractor,
      position: position,
      metadata: metadata,
    );
  }

  /// Extract fragments from a table block.
  List<Fragment> _extractFromTable(
    TableBlock table,
    String evidenceId,
    String workspaceId,
  ) {
    final fragments = <Fragment>[];
    if (table.rows.isEmpty) return fragments;

    // Extract headers from first row if it's a header row
    final headers = <String>[];
    if (table.rows.first.isHeader) {
      for (final cell in table.rows.first.cells) {
        headers.add(cell.text);
      }
    }

    // Process data rows
    final startRow = table.rows.first.isHeader ? 1 : 0;
    for (var rowIndex = startRow; rowIndex < table.rows.length; rowIndex++) {
      final row = table.rows[rowIndex];
      for (var colIndex = 0; colIndex < row.cells.length; colIndex++) {
        final cell = row.cells[colIndex];
        if (cell.text.isEmpty) continue;

        final fieldName = colIndex < headers.length
            ? '${headers[colIndex]}_row${rowIndex - startRow}'
            : 'cell_${rowIndex - startRow}_$colIndex';

        fragments.add(_createFragment(
          evidenceId: evidenceId,
          workspaceId: workspaceId,
          field: fieldName,
          value: cell.text,
          confidence: config.defaultConfidence,
          extractor: ExtractorType.rule,
          position: _partPosition(table),
          metadata: {
            'tableId': table.id,
            'row': rowIndex - startRow,
            'column': colIndex,
            if (colIndex < headers.length) 'header': headers[colIndex],
            if (cell.dataType != null) 'dataType': cell.dataType,
          },
        ));
      }
    }

    return fragments;
  }

  /// Create a fragment with generated ID.
  Fragment _createFragment({
    required String evidenceId,
    required String workspaceId,
    required String field,
    required dynamic value,
    required double confidence,
    required ExtractorType extractor,
    SourcePosition? position,
    Map<String, dynamic>? metadata,
  }) {
    _idCounter++;
    final fragmentId = 'frag_${evidenceId.replaceFirst('ev_', '')}_$_idCounter';

    return Fragment(
      fragmentId: fragmentId,
      workspaceId: workspaceId,
      evidenceId: evidenceId,
      fields: {
        'field': field,
        'value': value?.toString() ?? '',
        'normalizedValue': _normalizeValue(value),
        'valueType': _detectValueType(value).name,
        if (position != null) 'position': position.toJson(),
      },
      confidence: confidence,
      extractor: extractor,
      status: FragmentStatus.proposed,
      createdAt: DateTime.now(),
      metadata: metadata ?? const {},
    );
  }

  /// Detect the type of a value.
  FragmentValueType _detectValueType(dynamic value) {
    if (value == null) return FragmentValueType.unknown;
    if (value is bool) return FragmentValueType.boolean;
    if (value is int || value is double) return FragmentValueType.number;
    if (value is DateTime) return FragmentValueType.datetime;
    if (value is List) return FragmentValueType.array;
    if (value is Map) return FragmentValueType.object;

    final str = value.toString();

    // Check for date patterns
    if (_datePattern.hasMatch(str)) return FragmentValueType.date;

    // Check for currency patterns
    if (_currencyPattern.hasMatch(str)) return FragmentValueType.currency;

    // Check for percentage patterns
    if (_percentagePattern.hasMatch(str)) return FragmentValueType.percentage;

    // Check for numeric strings
    if (double.tryParse(str.replaceAll(',', '')) != null) {
      return FragmentValueType.number;
    }

    return FragmentValueType.string;
  }

  /// Normalize a value based on its type.
  dynamic _normalizeValue(dynamic value) {
    if (value == null) return null;

    final str = value.toString().trim();

    // Try parsing as number
    final numValue =
        double.tryParse(str.replaceAll(',', '').replaceAll(r'$', ''));
    if (numValue != null) return numValue;

    // Try parsing as date
    final dateValue = DateTime.tryParse(str);
    if (dateValue != null) return dateValue.toIso8601String();

    // Return original for other types
    return value;
  }

  /// Get source position from document part.
  SourcePosition? _partPosition(DocumentPart part) {
    final loc = part.location;
    if (loc == null) return null;
    if (loc.charOffset == null) return null;

    final endOffset = loc.charLength != null
        ? loc.charOffset! + loc.charLength!
        : loc.charOffset!;

    return SourcePosition(
      start: loc.charOffset!,
      end: endOffset,
      line: loc.lineNumber,
    );
  }

  /// Get source position from chunk.
  SourcePosition? _chunkPosition(Chunk chunk) {
    if (chunk.sourceSpans.isEmpty) return null;

    final firstSpan = chunk.sourceSpans.first;
    final lastSpan = chunk.sourceSpans.last;

    return SourcePosition(
      start: firstSpan.startOffset,
      end: lastSpan.endOffset,
    );
  }

  // Common regex patterns
  static final _datePattern = RegExp(
    r'^\d{4}[-/]\d{2}[-/]\d{2}|^\d{2}[-/]\d{2}[-/]\d{4}',
  );

  static final _currencyPattern = RegExp(
    r'^[$€£¥₩]\s*[\d,]+\.?\d*|^[\d,]+\.?\d*\s*[$€£¥₩]',
  );

  static final _percentagePattern = RegExp(
    r'^[\d.]+\s*%$',
  );
}

/// Batch fragment emitter for multiple documents.
class BatchFragmentEmitter {
  /// Single emitter instance.
  final FragmentEmitter _emitter;

  BatchFragmentEmitter({FragmentEmitterConfig? config})
      : _emitter =
            FragmentEmitter(config: config ?? FragmentEmitterConfig.defaults);

  /// Emit fragments for multiple documents.
  Map<String, List<Fragment>> emitBatch({
    required List<(NormalizedDocument, String)> items,
    String? workspaceId,
  }) {
    return {
      for (final item in items)
        item.$2: _emitter.emitFromDocument(
          document: item.$1,
          evidenceId: item.$2,
          workspaceId: workspaceId,
        ),
    };
  }

  /// Emit fragments for chunks grouped by evidence.
  Map<String, List<Fragment>> emitChunksBatch({
    required Map<String, List<Chunk>> chunksByEvidence,
    String? workspaceId,
  }) {
    return {
      for (final entry in chunksByEvidence.entries)
        entry.key: _emitter.emitFromChunks(
          chunks: entry.value,
          evidenceId: entry.key,
          workspaceId: workspaceId,
        ),
    };
  }
}
