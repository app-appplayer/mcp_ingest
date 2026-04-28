/// Chunk context injection utility.
library;

import '../document/chunk.dart';
import '../document/document_structure.dart';
import '../document/normalized_document.dart';

/// Helper to add section context to chunks.
///
/// Adds hierarchical context (breadcrumb) from parent sections
/// to help LLMs understand chunk positioning within the document.
class ChunkContextInjector {
  /// Maximum context length in characters.
  final int maxContextLength;

  /// Separator between context levels.
  final String separator;

  /// Prefix for truncated context.
  final String truncationPrefix;

  const ChunkContextInjector({
    this.maxContextLength = 200,
    this.separator = ' > ',
    this.truncationPrefix = '...',
  });

  /// Add section context to a single chunk.
  Chunk addContext(
    Chunk chunk,
    DocumentStructure structure,
  ) {
    final sectionPath = _getSectionPath(structure, chunk.sourcePartIds);
    if (sectionPath.isEmpty) return chunk;

    final context = sectionPath.join(separator);
    final truncated = context.length > maxContextLength
        ? '$truncationPrefix${context.substring(context.length - maxContextLength + truncationPrefix.length)}'
        : context;

    return chunk.copyWith(contextPrefix: truncated);
  }

  /// Add section context to all chunks.
  List<Chunk> addContextToAll(
    List<Chunk> chunks,
    DocumentStructure structure,
  ) {
    return chunks.map((c) => addContext(c, structure)).toList();
  }

  /// Add context from document.
  List<Chunk> addContextFromDocument(
    List<Chunk> chunks,
    NormalizedDocument document,
  ) {
    return addContextToAll(chunks, document.structure);
  }

  /// Get section path for part IDs.
  List<String> _getSectionPath(
    DocumentStructure structure,
    List<String> partIds,
  ) {
    if (partIds.isEmpty) return [];

    final path = <String>[];
    _findSectionPath(structure.nodes, partIds.first, path);
    return path;
  }

  bool _findSectionPath(
    List<StructureNode> nodes,
    String partId,
    List<String> path,
  ) {
    for (final node in nodes) {
      if (node.partIds.contains(partId)) {
        if (node.title != null && node.title!.isNotEmpty) {
          path.add(node.title!);
        }
        return true;
      }

      if (_findSectionPath(node.children, partId, path)) {
        if (node.title != null && node.title!.isNotEmpty) {
          path.insert(0, node.title!);
        }
        return true;
      }
    }
    return false;
  }

  /// Create context string from section titles.
  String buildContextString(List<String> sectionTitles) {
    if (sectionTitles.isEmpty) return '';

    final context = sectionTitles.join(separator);
    if (context.length <= maxContextLength) {
      return context;
    }

    // Truncate from the beginning
    return '$truncationPrefix${context.substring(context.length - maxContextLength + truncationPrefix.length)}';
  }

  /// Extract document outline for context building.
  List<OutlineEntry> extractOutline(DocumentStructure structure) {
    final outline = <OutlineEntry>[];
    _extractOutlineRecursive(structure.nodes, 0, outline);
    return outline;
  }

  void _extractOutlineRecursive(
    List<StructureNode> nodes,
    int depth,
    List<OutlineEntry> outline,
  ) {
    for (final node in nodes) {
      if (node.title != null && node.title!.isNotEmpty) {
        outline.add(OutlineEntry(
          title: node.title!,
          level: depth,
          type: node.type,
          partIds: node.partIds,
        ));
      }

      _extractOutlineRecursive(node.children, depth + 1, outline);
    }
  }
}

/// Document outline entry.
class OutlineEntry {
  /// Section title.
  final String title;

  /// Nesting level (0 = root).
  final int level;

  /// Structure type.
  final StructureType type;

  /// Part IDs in this section.
  final List<String> partIds;

  const OutlineEntry({
    required this.title,
    required this.level,
    required this.type,
    required this.partIds,
  });

  /// Indented title for display.
  String get indentedTitle => '${'  ' * level}$title';
}

/// Extension for easy context injection.
extension ChunkContextExtension on List<Chunk> {
  /// Add context to all chunks using document structure.
  List<Chunk> withContext(
    DocumentStructure structure, {
    int maxLength = 200,
    String separator = ' > ',
  }) {
    final injector = ChunkContextInjector(
      maxContextLength: maxLength,
      separator: separator,
    );
    return injector.addContextToAll(this, structure);
  }
}
