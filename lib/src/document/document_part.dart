/// Document parts (blocks).
library;

import 'package:mcp_fact_graph/mcp_fact_graph.dart'
    show ExtractorType, Fragment, FragmentStatus;

import '../core/fragment_value_type.dart';

import 'source_location.dart';

/// Document part type discriminator for JSON serialization.
enum DocumentPartType {
  text,
  table,
  list,
  keyValue,
  image,
  audio,
}

/// Base class for document parts.
sealed class DocumentPart {
  /// Unique part identifier within document.
  final String id;

  /// Location in source document.
  final SourceLocation? location;

  /// Additional metadata.
  final Map<String, dynamic>? metadata;

  const DocumentPart({
    required this.id,
    this.location,
    this.metadata,
  });

  /// Get the part type for JSON serialization.
  DocumentPartType get partType;

  /// Convert to JSON map.
  Map<String, dynamic> toJson();

  /// Create a DocumentPart from JSON with type discriminator.
  static DocumentPart fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String?;
    if (typeStr == null) {
      throw ArgumentError('Missing "type" field in DocumentPart JSON');
    }

    final type = DocumentPartType.values.byName(typeStr);

    return switch (type) {
      DocumentPartType.text => TextBlock.fromJson(json),
      DocumentPartType.table => TableBlock.fromJson(json),
      DocumentPartType.list => ListBlock.fromJson(json),
      DocumentPartType.keyValue => KeyValueBlock.fromJson(json),
      DocumentPartType.image => ImageBlock.fromJson(json),
      DocumentPartType.audio => AudioBlock.fromJson(json),
    };
  }
}

/// Text block type.
enum TextBlockType {
  /// Paragraph.
  paragraph,

  /// Heading.
  heading,

  /// Code block.
  code,

  /// Quote/blockquote.
  quote,

  /// List item.
  listItem,

  /// Caption.
  caption,

  /// Footnote.
  footnote,
}

/// Inline text formatting span.
class TextSpan {
  /// Start character offset within text.
  final int start;

  /// End character offset within text.
  final int end;

  /// Span type.
  final TextSpanType type;

  /// Optional value (URL for links, etc.).
  final String? value;

  const TextSpan({
    required this.start,
    required this.end,
    required this.type,
    this.value,
  });

  /// Length of this span.
  int get length => end - start;

  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        'type': type.name,
        if (value != null) 'value': value,
      };

  factory TextSpan.fromJson(Map<String, dynamic> json) => TextSpan(
        start: json['start'] as int,
        end: json['end'] as int,
        type: TextSpanType.values.byName(json['type'] as String),
        value: json['value'] as String?,
      );
}

/// Span type for inline formatting.
enum TextSpanType {
  /// Bold text.
  bold,

  /// Italic text.
  italic,

  /// Underlined text.
  underline,

  /// Strikethrough text.
  strikethrough,

  /// Hyperlink.
  link,

  /// Inline code.
  code,

  /// Highlighted text.
  highlight,
}

/// Text content block.
class TextBlock extends DocumentPart {
  /// Text content.
  final String text;

  /// Block type.
  final TextBlockType type;

  /// Heading level (1-6, for headings only).
  final int? headingLevel;

  /// Inline formatting spans.
  final List<TextSpan>? spans;

  /// Code language (for code blocks).
  final String? language;

  const TextBlock({
    required super.id,
    super.location,
    super.metadata,
    required this.text,
    this.type = TextBlockType.paragraph,
    this.headingLevel,
    this.spans,
    this.language,
  });

  @override
  DocumentPartType get partType => DocumentPartType.text;

  @override
  Map<String, dynamic> toJson() => {
        'type': partType.name,
        'id': id,
        if (location != null) 'location': location!.toJson(),
        if (metadata != null) 'metadata': metadata,
        'text': text,
        'blockType': type.name,
        if (headingLevel != null) 'headingLevel': headingLevel,
        if (spans != null) 'spans': spans!.map((s) => s.toJson()).toList(),
        if (language != null) 'language': language,
      };

  factory TextBlock.fromJson(Map<String, dynamic> json) => TextBlock(
        id: json['id'] as String,
        location: json['location'] != null
            ? SourceLocation.fromJson(json['location'] as Map<String, dynamic>)
            : null,
        metadata: json['metadata'] as Map<String, dynamic>?,
        text: json['text'] as String,
        type: json['blockType'] != null
            ? TextBlockType.values.byName(json['blockType'] as String)
            : TextBlockType.paragraph,
        headingLevel: json['headingLevel'] as int?,
        spans: (json['spans'] as List<dynamic>?)
            ?.map((s) => TextSpan.fromJson(s as Map<String, dynamic>))
            .toList(),
        language: json['language'] as String?,
      );

  TextBlock copyWith({
    String? id,
    SourceLocation? location,
    Map<String, dynamic>? metadata,
    String? text,
    TextBlockType? type,
    int? headingLevel,
    List<TextSpan>? spans,
    String? language,
  }) {
    return TextBlock(
      id: id ?? this.id,
      location: location ?? this.location,
      metadata: metadata ?? this.metadata,
      text: text ?? this.text,
      type: type ?? this.type,
      headingLevel: headingLevel ?? this.headingLevel,
      spans: spans ?? this.spans,
      language: language ?? this.language,
    );
  }
}

/// Cell type for table cells.
enum CellType {
  /// Header cell.
  header,

  /// Data cell.
  data,
}

/// Table cell.
class TableCell {
  /// Cell text content.
  final String text;

  /// Row span.
  final int rowSpan;

  /// Column span.
  final int colSpan;

  /// Cell type.
  final CellType type;

  /// Inferred data type (number, date, currency, etc.).
  final String? dataType;

  const TableCell({
    required this.text,
    this.rowSpan = 1,
    this.colSpan = 1,
    this.type = CellType.data,
    this.dataType,
  });

  /// Whether this is a header cell.
  bool get isHeader => type == CellType.header;

  factory TableCell.fromJson(Map<String, dynamic> json) {
    return TableCell(
      text: json['text'] as String? ?? json['content'] as String? ?? '',
      rowSpan: json['rowSpan'] as int? ?? 1,
      colSpan: json['colSpan'] as int? ?? 1,
      type: json['type'] != null
          ? CellType.values.byName(json['type'] as String)
          : (json['isHeader'] as bool? ?? false)
              ? CellType.header
              : CellType.data,
      dataType: json['dataType'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        if (rowSpan != 1) 'rowSpan': rowSpan,
        if (colSpan != 1) 'colSpan': colSpan,
        'type': type.name,
        if (dataType != null) 'dataType': dataType,
      };
}

/// Table row.
class TableRow {
  /// Cells in this row.
  final List<TableCell> cells;

  /// Whether this is a header row.
  final bool isHeader;

  const TableRow({
    required this.cells,
    this.isHeader = false,
  });

  factory TableRow.fromJson(Map<String, dynamic> json) {
    return TableRow(
      cells: (json['cells'] as List<dynamic>?)
              ?.map((c) => TableCell.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      isHeader: json['isHeader'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'cells': cells.map((c) => c.toJson()).toList(),
        if (isHeader) 'isHeader': isHeader,
      };
}

/// Table block.
class TableBlock extends DocumentPart {
  /// Table rows.
  final List<TableRow> rows;

  /// Row count.
  final int rowCount;

  /// Column count.
  final int columnCount;

  /// Table caption.
  final String? caption;

  const TableBlock({
    required super.id,
    super.location,
    super.metadata,
    required this.rows,
    required this.rowCount,
    required this.columnCount,
    this.caption,
  });

  @override
  DocumentPartType get partType => DocumentPartType.table;

  @override
  Map<String, dynamic> toJson() => {
        'type': partType.name,
        'id': id,
        if (location != null) 'location': location!.toJson(),
        if (metadata != null) 'metadata': metadata,
        'rows': rows.map((r) => r.toJson()).toList(),
        'rowCount': rowCount,
        'columnCount': columnCount,
        if (caption != null) 'caption': caption,
      };

  factory TableBlock.fromJson(Map<String, dynamic> json) => TableBlock(
        id: json['id'] as String,
        location: json['location'] != null
            ? SourceLocation.fromJson(json['location'] as Map<String, dynamic>)
            : null,
        metadata: json['metadata'] as Map<String, dynamic>?,
        rows: (json['rows'] as List<dynamic>)
            .map((r) => TableRow.fromJson(r as Map<String, dynamic>))
            .toList(),
        rowCount: json['rowCount'] as int,
        columnCount: json['columnCount'] as int,
        caption: json['caption'] as String?,
      );

  /// Convert to markdown format.
  String toMarkdown() {
    if (rows.isEmpty) return '';

    final buffer = StringBuffer();

    // Header row
    if (rows.isNotEmpty) {
      final headerCells = rows.first.cells.map((c) => c.text).toList();
      buffer.writeln('| ${headerCells.join(' | ')} |');
      buffer.writeln('| ${headerCells.map((_) => '---').join(' | ')} |');
    }

    // Data rows
    for (var i = 1; i < rows.length; i++) {
      final cells = rows[i].cells.map((c) => c.text).toList();
      buffer.writeln('| ${cells.join(' | ')} |');
    }

    return buffer.toString();
  }

  /// Convert to CSV format.
  String toCsv() {
    if (rows.isEmpty) return '';

    final buffer = StringBuffer();
    for (final row in rows) {
      final cells = row.cells.map((c) => _escapeCsv(c.text)).toList();
      buffer.writeln(cells.join(','));
    }
    return buffer.toString();
  }

  /// Escape CSV value.
  String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  TableBlock copyWith({
    String? id,
    SourceLocation? location,
    Map<String, dynamic>? metadata,
    List<TableRow>? rows,
    int? rowCount,
    int? columnCount,
    String? caption,
  }) {
    return TableBlock(
      id: id ?? this.id,
      location: location ?? this.location,
      metadata: metadata ?? this.metadata,
      rows: rows ?? this.rows,
      rowCount: rowCount ?? this.rowCount,
      columnCount: columnCount ?? this.columnCount,
      caption: caption ?? this.caption,
    );
  }
}

/// List item.
class ListItem {
  /// Item text.
  final String text;

  /// Whether checked (for checklists).
  final bool? checked;

  /// Nested list items.
  final List<ListItem>? children;

  const ListItem({
    required this.text,
    this.checked,
    this.children,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        if (checked != null) 'checked': checked,
        if (children != null)
          'children': children!.map((c) => c.toJson()).toList(),
      };

  factory ListItem.fromJson(Map<String, dynamic> json) => ListItem(
        text: json['text'] as String? ?? json['content'] as String? ?? '',
        checked: json['checked'] as bool?,
        children: (json['children'] as List<dynamic>?)
            ?.map((c) => ListItem.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

/// List type.
enum ListType {
  /// Unordered (bullet) list.
  unordered,

  /// Ordered (numbered) list.
  ordered,

  /// Checklist.
  checklist,
}

/// List block.
class ListBlock extends DocumentPart {
  /// List type.
  final ListType type;

  /// List items.
  final List<ListItem> items;

  /// Starting number (for ordered lists).
  final int? startNumber;

  const ListBlock({
    required super.id,
    super.location,
    super.metadata,
    required this.type,
    required this.items,
    this.startNumber,
  });

  @override
  DocumentPartType get partType => DocumentPartType.list;

  @override
  Map<String, dynamic> toJson() => {
        'type': partType.name,
        'id': id,
        if (location != null) 'location': location!.toJson(),
        if (metadata != null) 'metadata': metadata,
        'listType': type.name,
        'items': items.map((i) => i.toJson()).toList(),
        if (startNumber != null) 'startNumber': startNumber,
      };

  factory ListBlock.fromJson(Map<String, dynamic> json) => ListBlock(
        id: json['id'] as String,
        location: json['location'] != null
            ? SourceLocation.fromJson(json['location'] as Map<String, dynamic>)
            : null,
        metadata: json['metadata'] as Map<String, dynamic>?,
        type: ListType.values.byName(json['listType'] as String),
        items: (json['items'] as List<dynamic>)
            .map((i) => ListItem.fromJson(i as Map<String, dynamic>))
            .toList(),
        startNumber: json['startNumber'] as int?,
      );

  ListBlock copyWith({
    String? id,
    SourceLocation? location,
    Map<String, dynamic>? metadata,
    ListType? type,
    List<ListItem>? items,
    int? startNumber,
  }) {
    return ListBlock(
      id: id ?? this.id,
      location: location ?? this.location,
      metadata: metadata ?? this.metadata,
      type: type ?? this.type,
      items: items ?? this.items,
      startNumber: startNumber ?? this.startNumber,
    );
  }
}

/// Key-value block (metadata, form field, etc.).
/// Designed to map directly to mcp_fact_graph.Fragment.
class KeyValueBlock extends DocumentPart {
  /// Key/label (-> Fragment.field).
  final String key;

  /// Raw value string (-> Fragment.value).
  final String value;

  /// Normalized value if applicable (-> Fragment.normalizedValue).
  final dynamic normalizedValue;

  /// Value type aligned with Fragment schema.
  final FragmentValueType valueType;

  /// Extractor type used for extraction.
  final ExtractorType extractor;

  /// Extraction confidence (0.0-1.0).
  final double confidence;

  const KeyValueBlock({
    required super.id,
    super.location,
    super.metadata,
    required this.key,
    required this.value,
    this.normalizedValue,
    this.valueType = FragmentValueType.string,
    this.extractor = ExtractorType.rule,
    this.confidence = 0.8,
  });

  @override
  DocumentPartType get partType => DocumentPartType.keyValue;

  @override
  Map<String, dynamic> toJson() => {
        'type': partType.name,
        'id': id,
        if (location != null) 'location': location!.toJson(),
        if (metadata != null) 'metadata': metadata,
        'key': key,
        'value': value,
        if (normalizedValue != null) 'normalizedValue': normalizedValue,
        'valueType': valueType.name,
        'extractor': extractor.name,
        'confidence': confidence,
      };

  factory KeyValueBlock.fromJson(Map<String, dynamic> json) => KeyValueBlock(
        id: json['id'] as String,
        location: json['location'] != null
            ? SourceLocation.fromJson(json['location'] as Map<String, dynamic>)
            : null,
        metadata: json['metadata'] as Map<String, dynamic>?,
        key: json['key'] as String,
        value: json['value'] as String,
        normalizedValue: json['normalizedValue'],
        valueType: json['valueType'] != null
            ? FragmentValueType.values.byName(json['valueType'] as String)
            : FragmentValueType.string,
        extractor: json['extractor'] != null
            ? ExtractorType.values.byName(json['extractor'] as String)
            : ExtractorType.rule,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.8,
      );

  /// Convert to Fragment entity.
  Fragment toFragment(String evidenceId, {String workspaceId = 'default'}) {
    return Fragment(
      fragmentId: '${evidenceId}_$id',
      workspaceId: workspaceId,
      evidenceId: evidenceId,
      fields: {
        'field': key,
        'value': value,
        if (normalizedValue != null) 'normalizedValue': normalizedValue,
        'valueType': valueType.name,
        if (location != null)
          'position': {
            'start': location!.charOffset ?? 0,
            'end': (location!.charOffset ?? 0) + (location!.charLength ?? 0),
            if (location!.lineNumber != null) 'line': location!.lineNumber,
          },
      },
      confidence: confidence,
      extractor: extractor,
      status: FragmentStatus.proposed,
      createdAt: DateTime.now(),
    );
  }

  KeyValueBlock copyWith({
    String? id,
    SourceLocation? location,
    Map<String, dynamic>? metadata,
    String? key,
    String? value,
    dynamic normalizedValue,
    FragmentValueType? valueType,
    ExtractorType? extractor,
    double? confidence,
  }) {
    return KeyValueBlock(
      id: id ?? this.id,
      location: location ?? this.location,
      metadata: metadata ?? this.metadata,
      key: key ?? this.key,
      value: value ?? this.value,
      normalizedValue: normalizedValue ?? this.normalizedValue,
      valueType: valueType ?? this.valueType,
      extractor: extractor ?? this.extractor,
      confidence: confidence ?? this.confidence,
    );
  }
}

/// Image block.
class ImageBlock extends DocumentPart {
  /// Asset reference (storage path or inline data).
  final String assetRef;

  /// Image width.
  final int? width;

  /// Image height.
  final int? height;

  /// Image format (png, jpeg, etc.).
  final String? format;

  /// Alt text.
  final String? altText;

  /// Caption.
  final String? caption;

  /// OCR extracted text.
  final String? ocrText;

  /// Vision API description.
  final String? visionDescription;

  const ImageBlock({
    required super.id,
    super.location,
    super.metadata,
    required this.assetRef,
    this.width,
    this.height,
    this.format,
    this.altText,
    this.caption,
    this.ocrText,
    this.visionDescription,
  });

  @override
  DocumentPartType get partType => DocumentPartType.image;

  @override
  Map<String, dynamic> toJson() => {
        'type': partType.name,
        'id': id,
        if (location != null) 'location': location!.toJson(),
        if (metadata != null) 'metadata': metadata,
        'assetRef': assetRef,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (format != null) 'format': format,
        if (altText != null) 'altText': altText,
        if (caption != null) 'caption': caption,
        if (ocrText != null) 'ocrText': ocrText,
        if (visionDescription != null) 'visionDescription': visionDescription,
      };

  factory ImageBlock.fromJson(Map<String, dynamic> json) => ImageBlock(
        id: json['id'] as String,
        location: json['location'] != null
            ? SourceLocation.fromJson(json['location'] as Map<String, dynamic>)
            : null,
        metadata: json['metadata'] as Map<String, dynamic>?,
        assetRef: json['assetRef'] as String,
        width: json['width'] as int?,
        height: json['height'] as int?,
        format: json['format'] as String?,
        altText: json['altText'] as String?,
        caption: json['caption'] as String?,
        ocrText: json['ocrText'] as String?,
        visionDescription: json['visionDescription'] as String?,
      );

  /// Whether this image has been OCR processed.
  bool get hasOcr => ocrText != null;

  /// Whether this image has been vision processed.
  bool get hasVision => visionDescription != null;

  ImageBlock copyWith({
    String? id,
    SourceLocation? location,
    Map<String, dynamic>? metadata,
    String? assetRef,
    int? width,
    int? height,
    String? format,
    String? altText,
    String? caption,
    String? ocrText,
    String? visionDescription,
  }) {
    return ImageBlock(
      id: id ?? this.id,
      location: location ?? this.location,
      metadata: metadata ?? this.metadata,
      assetRef: assetRef ?? this.assetRef,
      width: width ?? this.width,
      height: height ?? this.height,
      format: format ?? this.format,
      altText: altText ?? this.altText,
      caption: caption ?? this.caption,
      ocrText: ocrText ?? this.ocrText,
      visionDescription: visionDescription ?? this.visionDescription,
    );
  }
}

/// Transcript segment for audio.
class TranscriptSegment {
  /// Start time.
  final Duration startTime;

  /// End time.
  final Duration endTime;

  /// Text content.
  final String text;

  /// Confidence score.
  final double? confidence;

  /// Speaker ID.
  final String? speaker;

  const TranscriptSegment({
    required this.startTime,
    required this.endTime,
    required this.text,
    this.confidence,
    this.speaker,
  });

  Map<String, dynamic> toJson() => {
        'startTimeMs': startTime.inMilliseconds,
        'endTimeMs': endTime.inMilliseconds,
        'text': text,
        if (confidence != null) 'confidence': confidence,
        if (speaker != null) 'speaker': speaker,
      };

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) =>
      TranscriptSegment(
        startTime: Duration(milliseconds: json['startTimeMs'] as int),
        endTime: Duration(milliseconds: json['endTimeMs'] as int),
        text: json['text'] as String,
        confidence: (json['confidence'] as num?)?.toDouble(),
        speaker: json['speaker'] as String?,
      );
}

/// Audio block.
class AudioBlock extends DocumentPart {
  /// Asset reference.
  final String assetRef;

  /// Duration.
  final Duration? duration;

  /// Audio format.
  final String? format;

  /// Sample rate.
  final int? sampleRate;

  /// Full transcript.
  final String? transcript;

  /// Transcript segments with timestamps.
  final List<TranscriptSegment>? segments;

  const AudioBlock({
    required super.id,
    super.location,
    super.metadata,
    required this.assetRef,
    this.duration,
    this.format,
    this.sampleRate,
    this.transcript,
    this.segments,
  });

  @override
  DocumentPartType get partType => DocumentPartType.audio;

  @override
  Map<String, dynamic> toJson() => {
        'type': partType.name,
        'id': id,
        if (location != null) 'location': location!.toJson(),
        if (metadata != null) 'metadata': metadata,
        'assetRef': assetRef,
        if (duration != null) 'durationMs': duration!.inMilliseconds,
        if (format != null) 'format': format,
        if (sampleRate != null) 'sampleRate': sampleRate,
        if (transcript != null) 'transcript': transcript,
        if (segments != null)
          'segments': segments!.map((s) => s.toJson()).toList(),
      };

  factory AudioBlock.fromJson(Map<String, dynamic> json) => AudioBlock(
        id: json['id'] as String,
        location: json['location'] != null
            ? SourceLocation.fromJson(json['location'] as Map<String, dynamic>)
            : null,
        metadata: json['metadata'] as Map<String, dynamic>?,
        assetRef: json['assetRef'] as String,
        duration: json['durationMs'] != null
            ? Duration(milliseconds: json['durationMs'] as int)
            : null,
        format: json['format'] as String?,
        sampleRate: json['sampleRate'] as int?,
        transcript: json['transcript'] as String?,
        segments: (json['segments'] as List<dynamic>?)
            ?.map((s) => TranscriptSegment.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  AudioBlock copyWith({
    String? id,
    SourceLocation? location,
    Map<String, dynamic>? metadata,
    String? assetRef,
    Duration? duration,
    String? format,
    int? sampleRate,
    String? transcript,
    List<TranscriptSegment>? segments,
  }) {
    return AudioBlock(
      id: id ?? this.id,
      location: location ?? this.location,
      metadata: metadata ?? this.metadata,
      assetRef: assetRef ?? this.assetRef,
      duration: duration ?? this.duration,
      format: format ?? this.format,
      sampleRate: sampleRate ?? this.sampleRate,
      transcript: transcript ?? this.transcript,
      segments: segments ?? this.segments,
    );
  }
}
