/// Table-aware chunker.
library;

import '../document/chunk.dart';
import '../document/document_part.dart';
import '../document/normalized_document.dart';
import '../document/source_location.dart';
import 'chunker.dart';

/// Chunks documents preserving table boundaries.
class TableChunker implements Chunker {
  @override
  String get id => 'table_v1';

  @override
  String get name => 'Table Chunker';

  @override
  Future<List<Chunk>> chunk(NormalizedDocument document, ChunkOptions options) async {
    final chunks = <Chunk>[];
    var chunkIndex = 0;
    var currentText = StringBuffer();
    var currentSpans = <ChunkSpan>[];

    for (final part in document.parts) {
      if (part is TableBlock) {
        // Flush accumulated text first
        if (currentText.isNotEmpty) {
          chunks.add(_createChunk(
            chunkIndex++,
            currentText.toString().trim(),
            currentSpans,
            'text',
          ));
          currentText = StringBuffer();
          currentSpans = [];
        }

        // Create table chunk
        final tableText = part.toMarkdown();
        if (tableText.length > options.maxSize) {
          // Split large table by rows
          chunks.addAll(_splitTable(part, chunkIndex, options));
          chunkIndex += (tableText.length / options.maxSize).ceil();
        } else {
          chunks.add(_createChunk(
            chunkIndex++,
            tableText,
            [ChunkSpan(partId: part.id, startOffset: 0, endOffset: 0)],
            'table',
            tableMetadata: {
              'rowCount': part.rowCount,
              'columnCount': part.columnCount,
              'caption': part.caption,
            },
          ));
        }
      } else {
        // Accumulate non-table content
        final text = _extractPartText(part);
        if (text.isEmpty) continue;

        if (currentText.length + text.length > options.maxSize &&
            currentText.isNotEmpty) {
          // Flush current chunk
          chunks.add(_createChunk(
            chunkIndex++,
            currentText.toString().trim(),
            currentSpans,
            'text',
          ));
          currentText = StringBuffer();
          currentSpans = [];
        }

        currentText.write(text);
        currentText.write('\n\n');
        currentSpans.add(ChunkSpan(
          partId: part.id,
          startOffset: 0,
          endOffset: text.length,
        ));
      }
    }

    // Flush remaining text
    if (currentText.isNotEmpty) {
      chunks.add(_createChunk(
        chunkIndex,
        currentText.toString().trim(),
        currentSpans,
        'text',
      ));
    }

    return _updateTotalChunks(chunks);
  }

  String _extractPartText(DocumentPart part) {
    return switch (part) {
      TextBlock(:final text) => text,
      TableBlock() => part.toMarkdown(),
      ListBlock(:final items) => items.map((i) => '- ${i.text}').join('\n'),
      KeyValueBlock(:final key, :final value) => '$key: $value',
      ImageBlock(:final caption, :final ocrText, :final visionDescription) =>
        [caption, ocrText, visionDescription].whereType<String>().join('\n'),
      AudioBlock(:final transcript) => transcript ?? '',
    };
  }

  List<Chunk> _splitTable(
    TableBlock table,
    int startIndex,
    ChunkOptions options,
  ) {
    final chunks = <Chunk>[];
    var index = startIndex;

    // Keep header row with each chunk
    final headerRow = table.rows.isNotEmpty ? table.rows.first : null;
    final dataRows = table.rows.skip(1).toList();

    var currentRows = <TableRow>[];
    if (headerRow != null) {
      currentRows.add(headerRow);
    }

    for (final row in dataRows) {
      currentRows.add(row);

      final currentTable = TableBlock(
        id: '${table.id}_part$index',
        rows: currentRows,
        rowCount: currentRows.length,
        columnCount: table.columnCount,
        caption: table.caption,
      );

      if (currentTable.toMarkdown().length >= options.targetSize) {
        chunks.add(_createChunk(
          index++,
          currentTable.toMarkdown(),
          [ChunkSpan(partId: table.id, startOffset: 0, endOffset: 0)],
          'table',
          tableMetadata: {
            'rowCount': currentRows.length,
            'columnCount': table.columnCount,
            'isPartial': true,
          },
        ));

        // Reset with header
        currentRows = [];
        if (headerRow != null) {
          currentRows.add(headerRow);
        }
      }
    }

    // Emit remaining rows
    if (currentRows.length > 1 ||
        (currentRows.length == 1 && headerRow == null)) {
      final currentTable = TableBlock(
        id: '${table.id}_part$index',
        rows: currentRows,
        rowCount: currentRows.length,
        columnCount: table.columnCount,
        caption: table.caption,
      );

      chunks.add(_createChunk(
        index,
        currentTable.toMarkdown(),
        [ChunkSpan(partId: table.id, startOffset: 0, endOffset: 0)],
        'table',
        tableMetadata: {
          'rowCount': currentRows.length,
          'columnCount': table.columnCount,
          'isPartial': true,
        },
      ));
    }

    return chunks;
  }

  Chunk _createChunk(
    int index,
    String text,
    List<ChunkSpan> spans,
    String contentType, {
    Map<String, dynamic>? tableMetadata,
  }) {
    return Chunk(
      id: 'chunk_$index',
      text: text,
      index: index,
      totalChunks: 0,
      sourceSpans: spans,
      location: const SourceLocation(),
      metadata: {
        'chunker': id,
        'contentType': contentType,
        if (tableMetadata != null) ...tableMetadata,
      },
    );
  }

  List<Chunk> _updateTotalChunks(List<Chunk> chunks) {
    final total = chunks.length;
    return chunks.map((c) => c.copyWith(totalChunks: total)).toList();
  }
}
