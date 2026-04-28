/// Document structure representation.
library;

/// Structure node type.
enum StructureType {
  /// Document root.
  document,

  /// Chapter.
  chapter,

  /// Section.
  section,

  /// Subsection.
  subsection,

  /// Page.
  page,

  /// Slide.
  slide,

  /// Sheet (spreadsheet).
  sheet,
}

/// Node in document structure tree.
class StructureNode {
  /// Node identifier.
  final String id;

  /// Node type.
  final StructureType type;

  /// Node title.
  final String? title;

  /// Nesting level (0 = top level).
  final int level;

  /// Part IDs contained in this node.
  final List<String> partIds;

  /// Child nodes.
  final List<StructureNode> children;

  const StructureNode({
    required this.id,
    required this.type,
    this.title,
    this.level = 0,
    this.partIds = const [],
    this.children = const [],
  });

  factory StructureNode.fromJson(Map<String, dynamic> json) {
    return StructureNode(
      id: json['id'] as String,
      type: StructureType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => StructureType.section,
      ),
      title: json['title'] as String?,
      level: json['level'] as int? ?? 0,
      partIds: (json['partIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      children: (json['children'] as List<dynamic>?)
              ?.map((e) => StructureNode.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        if (title != null) 'title': title,
        'level': level,
        if (partIds.isNotEmpty) 'partIds': partIds,
        if (children.isNotEmpty)
          'children': children.map((c) => c.toJson()).toList(),
      };
}

/// Document structure (hierarchy).
class DocumentStructure {
  /// Root nodes.
  final List<StructureNode> nodes;

  const DocumentStructure({
    this.nodes = const [],
  });

  /// Empty structure.
  static const empty = DocumentStructure();

  /// Flatten to list of part IDs in order.
  List<String> get flatPartIds {
    final ids = <String>[];
    _collectPartIds(nodes, ids);
    return ids;
  }

  void _collectPartIds(List<StructureNode> nodes, List<String> ids) {
    for (final node in nodes) {
      ids.addAll(node.partIds);
      _collectPartIds(node.children, ids);
    }
  }

  /// Get node by ID.
  StructureNode? getNode(String id) => findNode(id);

  /// Find node by ID.
  StructureNode? findNode(String id) {
    return _findInNodes(nodes, id);
  }

  StructureNode? _findInNodes(List<StructureNode> nodes, String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
      final found = _findInNodes(node.children, id);
      if (found != null) return found;
    }
    return null;
  }

  /// Find section containing a part ID.
  String? findSectionForPart(String partId) {
    return _findSectionInNodes(nodes, partId);
  }

  String? _findSectionInNodes(List<StructureNode> nodes, String partId) {
    for (final node in nodes) {
      if (node.partIds.contains(partId)) {
        return node.title;
      }
      final found = _findSectionInNodes(node.children, partId);
      if (found != null) return found;
    }
    return null;
  }

  /// Get section path for a part.
  List<String> getSectionPath(String partId) {
    final path = <String>[];
    _buildPath(nodes, partId, path);
    return path;
  }

  bool _buildPath(List<StructureNode> nodes, String partId, List<String> path) {
    for (final node in nodes) {
      if (node.partIds.contains(partId)) {
        if (node.title != null) path.add(node.title!);
        return true;
      }
      if (_buildPath(node.children, partId, path)) {
        if (node.title != null) path.insert(0, node.title!);
        return true;
      }
    }
    return false;
  }

  factory DocumentStructure.fromJson(Map<String, dynamic> json) {
    return DocumentStructure(
      nodes: (json['nodes'] as List<dynamic>?)
              ?.map((e) => StructureNode.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        if (nodes.isNotEmpty) 'nodes': nodes.map((n) => n.toJson()).toList(),
      };
}
