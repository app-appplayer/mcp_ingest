/// OCR port - re-exported from mcp_bundle.
///
/// This file re-exports OcrPort from mcp_bundle for backward compatibility.
/// New code should import directly from mcp_bundle/ports.dart.
/// Note: BoundingBox is not exported here - use mcp_ingest's own BoundingBox.
library;

export 'package:mcp_bundle/ports.dart'
    show OcrPort, OcrResult, OcrRegion, OcrOptions, StubOcrPort;
