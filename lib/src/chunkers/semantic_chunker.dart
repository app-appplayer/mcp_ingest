/// LLM-based semantic chunker.
library;

import 'dart:convert';

import 'package:mcp_bundle/ports.dart';

import '../document/chunk.dart';
import '../document/document_part.dart';
import '../document/normalized_document.dart';
import '../document/source_location.dart';
import 'chunker.dart';

/// LLM-based semantic chunking.
///
/// Uses LLM to identify natural topic boundaries.
/// CAUTION: This incurs LLM costs.
class SemanticChunker implements Chunker {
  /// LLM port for semantic analysis.
  final LlmPort llmPort;

  /// Create semantic chunker.
  SemanticChunker(this.llmPort);

  @override
  String get id => 'semantic_v1';

  @override
  String get name => 'Semantic Chunker';

  @override
  Future<List<Chunk>> chunk(
    NormalizedDocument document,
    ChunkOptions options,
  ) async {
    return _chunkWithLlm(document, options);
  }

  // ========================================================================
  // LLM-based Chunking
  // ========================================================================

  Future<List<Chunk>> _chunkWithLlm(
    NormalizedDocument document,
    ChunkOptions options,
  ) async {
    // FR-CHK-005: every emitted chunk must carry at least one ChunkSpan.
    // If the document has zero parts, nothing to emit.
    if (document.parts.isEmpty) return [];

    final fullText = document.fullText;

    // Build part offset map for provenance tracking
    final partOffsets = _buildPartOffsetMap(document);

    // For very short documents, return as single chunk
    if (fullText.length <= options.maxSize) {
      return [
        Chunk(
          id: 'chunk_0',
          text: fullText,
          sourceSpans: document.parts
              .map((p) => ChunkSpan(
                    partId: p.id,
                    startOffset: 0,
                    endOffset: _extractPartText(p).length,
                  ))
              .toList(),
          location: const SourceLocation(),
          index: 0,
          totalChunks: 1,
          metadata: {'chunker': id, 'method': 'llm'},
        ),
      ];
    }

    // Use LLM to identify chunk boundaries (messages pattern per docs)
    final response = await llmPort.complete(LlmRequest(
      messages: [
        LlmMessage.system(
          'You are a document chunking assistant. '
          'Given a document, identify natural topic boundaries for splitting. '
          'Return a JSON array of character offsets where splits should occur. '
          'Target chunk size: ${options.targetSize} characters. '
          'Maximum chunk size: ${options.maxSize} characters. '
          'Minimum chunk size: ${options.minSize} characters.',
        ),
        LlmMessage.user(
          'Split this document into semantic chunks:\n\n'
          '$fullText\n\n'
          'Return JSON: {"splits": [offset1, offset2, ...]}\n'
          'Only return the JSON, no explanation.',
        ),
      ],
      temperature: 0.0,
      responseFormat: 'json',
    ));

    // Parse LLM response
    final splits = _parseSplits(response.content);
    splits.sort();

    // Create chunks based on splits
    final chunks = <Chunk>[];
    var start = 0;

    for (final split in splits) {
      if (split > start && split < fullText.length) {
        final chunkText = fullText.substring(start, split).trim();
        if (chunkText.isNotEmpty && chunkText.length >= options.minSize) {
          final spans = _resolveSpans(partOffsets, start, split);
          chunks.add(Chunk(
            id: 'chunk_${chunks.length}',
            text: chunkText,
            sourceSpans: spans,
            location:
                SourceLocation(charOffset: start, charLength: split - start),
            index: chunks.length,
            totalChunks: 0,
            metadata: {
              'chunker': id,
              'method': 'llm',
              'startOffset': start,
              'endOffset': split,
            },
          ));
        }
        start = split;
      }
    }

    // Add final chunk
    if (start < fullText.length) {
      final chunkText = fullText.substring(start).trim();
      if (chunkText.isNotEmpty) {
        final spans = _resolveSpans(partOffsets, start, fullText.length);
        chunks.add(Chunk(
          id: 'chunk_${chunks.length}',
          text: chunkText,
          sourceSpans: spans,
          location: SourceLocation(
              charOffset: start, charLength: fullText.length - start),
          index: chunks.length,
          totalChunks: 0,
          metadata: {
            'chunker': id,
            'method': 'llm',
            'startOffset': start,
            'endOffset': fullText.length,
          },
        ));
      }
    }

    // Update total chunks
    return chunks.map((c) => c.copyWith(totalChunks: chunks.length)).toList();
  }

  List<int> _parseSplits(String response) {
    try {
      // Try to extract JSON from response
      final jsonStr = _extractJson(response);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final splits = json['splits'] as List<dynamic>?;
      if (splits == null) return [];
      return splits.map((e) => e as int).toList();
    } catch (e) {
      // Fallback: try to parse comma-separated numbers
      return _parseNumbers(response);
    }
  }

  String _extractJson(String response) {
    // Find JSON object in response
    final start = response.indexOf('{');
    final end = response.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return response.substring(start, end + 1);
    }
    return response;
  }

  List<int> _parseNumbers(String response) {
    final numbers = <int>[];
    final matches = RegExp(r'\d+').allMatches(response);
    for (final match in matches) {
      final num = int.tryParse(match.group(0)!);
      if (num != null && num > 0) {
        numbers.add(num);
      }
    }
    return numbers;
  }

  // ========================================================================
  // Part Offset Map for Provenance Tracking
  // ========================================================================

  /// Build map of part ID to (globalStart, globalEnd) from fullText offsets.
  List<_PartOffset> _buildPartOffsetMap(NormalizedDocument document) {
    final offsets = <_PartOffset>[];
    var pos = 0;
    for (final part in document.parts) {
      final text = _extractPartText(part);
      offsets.add(_PartOffset(part.id, pos, pos + text.length));
      pos += text.length + 1; // +1 for separator
    }
    return offsets;
  }

  /// Resolve which parts a character range [start, end] overlaps.
  List<ChunkSpan> _resolveSpans(
    List<_PartOffset> partOffsets,
    int start,
    int end,
  ) {
    final spans = <ChunkSpan>[];
    for (final po in partOffsets) {
      if (po.end > start && po.start < end) {
        spans.add(ChunkSpan(
          partId: po.partId,
          startOffset: (start - po.start).clamp(0, po.end - po.start),
          endOffset: (end - po.start).clamp(0, po.end - po.start),
        ));
      }
    }
    return spans;
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
}

/// Internal class for tracking part offsets in full text.
class _PartOffset {
  final String partId;
  final int start;
  final int end;
  _PartOffset(this.partId, this.start, this.end);
}
