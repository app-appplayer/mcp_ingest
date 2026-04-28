/// Vision port - re-exported from mcp_bundle.
///
/// This file re-exports VisionPort from mcp_bundle for backward compatibility.
/// New code should import directly from mcp_bundle/ports.dart.
/// Note: BoundingBox is not exported here - use mcp_ingest's own BoundingBox.
library;

export 'package:mcp_bundle/ports.dart'
    show
        VisionPort,
        VisionResult,
        VisionOptions,
        VisionLabel,
        VisionFace,
        StubVisionPort;
