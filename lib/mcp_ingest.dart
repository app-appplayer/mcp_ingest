/// MCP Ingest - Document ingestion pipeline for MakeMind.
///
/// Converts any file format to standardized NormalizedDocument format
/// with support for chunking, OCR, ASR, and fragment extraction.
///
/// ## Basic Usage
///
/// ```dart
/// import 'package:mcp_ingest/mcp_ingest.dart';
///
/// final pipeline = IngestPipeline.defaults();
///
/// final result = await pipeline.ingest(
///   IngestInput.fromFile('document.pdf'),
///   IngestOptions.defaults,
/// );
///
/// print('Extracted ${result.chunks.length} chunks');
/// ```
///
/// ## With OCR/ASR Support
///
/// ```dart
/// import 'package:mcp_ingest/mcp_ingest.dart';
///
/// final pipeline = IngestPipeline(
///   ocrPort: TesseractOcrPlugin(),
///   asrPort: WhisperAsrPlugin(),
/// );
///
/// final result = await pipeline.ingest(
///   IngestInput.fromFile('scan.png'),
///   IngestOptions.full,
/// );
/// ```
library mcp_ingest;

// =============================================================================
// Core Types
// =============================================================================
export 'src/core/content_type.dart';
export 'src/core/cost_budget.dart';
export 'src/core/exceptions.dart';
export 'src/core/fragment_rule.dart';
export 'src/core/fragment_value_type.dart';
export 'src/core/ingest_input.dart';
export 'src/core/ingest_options.dart';
export 'src/core/ingest_result.dart';
export 'src/core/source_position.dart';

// =============================================================================
// Document Model
// =============================================================================
export 'src/document/chunk.dart';
export 'src/document/document_metadata.dart';
export 'src/document/document_part.dart';
export 'src/document/document_structure.dart';
export 'src/document/normalized_document.dart';
export 'src/document/source_location.dart';

// =============================================================================
// Extractors
// =============================================================================
export 'src/extractors/extractor.dart';
export 'src/extractors/text_extractor.dart';
export 'src/extractors/html_extractor.dart';
export 'src/extractors/json_extractor.dart';
export 'src/extractors/pdf_extractor.dart';
export 'src/extractors/office_extractor.dart';
export 'src/extractors/image_extractor.dart';
export 'src/extractors/audio_extractor.dart';
export 'src/extractors/fragment_extractor.dart';
export 'src/extractors/llm_fragment_extractor.dart';

// =============================================================================
// Chunkers
// =============================================================================
export 'src/chunkers/chunker.dart';
export 'src/chunkers/sentence_chunker.dart';
export 'src/chunkers/paragraph_chunker.dart';
export 'src/chunkers/page_chunker.dart';
export 'src/chunkers/table_chunker.dart';
export 'src/chunkers/semantic_chunker.dart';
export 'src/chunkers/fixed_size_chunker.dart';
export 'src/chunkers/no_chunker.dart';

// =============================================================================
// Pipeline
// =============================================================================
export 'src/pipeline/ingest_pipeline.dart';
export 'src/pipeline/pipeline_stage.dart';
export 'src/pipeline/ingest_context.dart';

// =============================================================================
// Ports (Abstract Interfaces)
// =============================================================================
export 'src/ports/ocr_port.dart';
export 'src/ports/asr_port.dart';
export 'src/ports/vision_port.dart';
export 'src/ports/storage_port.dart';
export 'src/ports/hybrid_port_factory.dart';
export 'src/ports/port_usage_tracker.dart';

// =============================================================================
// Plugins (Concrete Implementations)
// =============================================================================
export 'src/plugins/plugin.dart' hide OcrWord;
export 'src/plugins/plugin_registry.dart';
export 'src/plugins/tesseract_ocr_plugin.dart';
export 'src/plugins/whisper_asr_plugin.dart';
export 'src/plugins/pdfium_pdf_plugin.dart';
export 'src/plugins/local_storage_plugin.dart';

// =============================================================================
// Chunker Extensions
// =============================================================================
export 'src/chunkers/chunk_context_injector.dart';

// =============================================================================
// Output Formatters
// =============================================================================
export 'src/output/evidence_emitter.dart';
export 'src/output/fragment_emitter.dart';
