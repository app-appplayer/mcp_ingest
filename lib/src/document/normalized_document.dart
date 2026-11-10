/// Normalized document model.
library;

import 'document_metadata.dart';
import 'document_part.dart';
import 'document_structure.dart';

/// Normalized document representation.
///
/// This is the intermediate representation between raw file input
/// and output entities (Evidence, Fragment, Chunk).
class NormalizedDocument {
  /// Document identifier.
  final String id;

  /// Document metadata.
  final DocumentMetadata metadata;

  /// Flat list of document parts.
  final List<DocumentPart> parts;

  /// Document structure (hierarchy).
  final DocumentStructure structure;

  /// Extraction provenance.
  final ExtractionProvenance provenance;

  const NormalizedDocument({
    required this.id,
    required this.metadata,
    required this.parts,
    required this.structure,
    required this.provenance,
  });

  /// Get full text content.
  String get fullText {
    final buffer = StringBuffer();
    for (final part in parts) {
      final text = _getPartText(part);
      if (text.isNotEmpty) {
        buffer.writeln(text);
        buffer.writeln();
      }
    }
    return buffer.toString().trim();
  }

  /// Total character count.
  int get characterCount => fullText.length;

  /// Total part count.
  int get partCount => parts.length;

  /// Get all parts of a specific type.
  List<T> partsOfType<T extends DocumentPart>() =>
      parts.whereType<T>().toList();

  String _getPartText(DocumentPart part) {
    return switch (part) {
      TextBlock(:final text) => text,
      TableBlock() => part.toMarkdown(),
      ListBlock(:final items) => items.map((i) => '- ${i.text}').join('\n'),
      KeyValueBlock(:final key, :final value) => '$key: $value',
      ImageBlock(:final caption, :final ocrText) =>
        [caption, ocrText].whereType<String>().join('\n'),
      AudioBlock(:final transcript) => transcript ?? '',
    };
  }

  /// Get all text blocks.
  List<TextBlock> get textBlocks => parts.whereType<TextBlock>().toList();

  /// Get all table blocks.
  List<TableBlock> get tableBlocks => parts.whereType<TableBlock>().toList();

  /// Get all image blocks.
  List<ImageBlock> get imageBlocks => parts.whereType<ImageBlock>().toList();

  /// Get all audio blocks.
  List<AudioBlock> get audioBlocks => parts.whereType<AudioBlock>().toList();

  /// Get all key-value blocks.
  List<KeyValueBlock> get keyValueBlocks =>
      parts.whereType<KeyValueBlock>().toList();

  /// Find part by ID.
  DocumentPart? findPart(String id) {
    for (final part in parts) {
      if (part.id == id) return part;
    }
    return null;
  }

  /// Create a copy with updated parts.
  NormalizedDocument copyWithParts(List<DocumentPart> newParts) {
    return NormalizedDocument(
      id: id,
      metadata: metadata,
      parts: newParts,
      structure: structure,
      provenance: provenance,
    );
  }

  /// Update a specific part.
  NormalizedDocument updatePart(String partId, DocumentPart newPart) {
    final newParts = parts.map((p) => p.id == partId ? newPart : p).toList();
    return copyWithParts(newParts);
  }

  factory NormalizedDocument.fromJson(Map<String, dynamic> json) {
    return NormalizedDocument(
      id: json['id'] as String,
      metadata:
          DocumentMetadata.fromJson(json['metadata'] as Map<String, dynamic>),
      parts: _parsePartsFromJson(json['parts'] as List<dynamic>? ?? []),
      structure: json['structure'] != null
          ? DocumentStructure.fromJson(
              json['structure'] as Map<String, dynamic>)
          : DocumentStructure.empty,
      provenance: ExtractionProvenance.fromJson(
          json['provenance'] as Map<String, dynamic>),
    );
  }

  static List<DocumentPart> _parsePartsFromJson(List<dynamic> json) {
    return json
        .map((p) => DocumentPart.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'metadata': metadata.toJson(),
        'parts': parts.map((p) => p.toJson()).toList(),
        'structure': structure.toJson(),
        'provenance': provenance.toJson(),
      };
}
