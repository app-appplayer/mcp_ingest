/// ASR port - re-exported from mcp_bundle.
///
/// This file re-exports AsrPort from mcp_bundle for backward compatibility.
/// New code should import directly from mcp_bundle/ports.dart.
library;

export 'package:mcp_bundle/ports.dart'
    show AsrPort, AsrResult, AsrSegment, AsrOptions, StubAsrPort;
