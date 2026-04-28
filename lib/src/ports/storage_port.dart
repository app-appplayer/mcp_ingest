/// Binary storage port - re-exported from mcp_bundle.
///
/// This file re-exports BinaryStoragePort from mcp_bundle for backward compatibility.
/// New code should import directly from mcp_bundle/ports.dart.
library;

export 'package:mcp_bundle/ports.dart'
    show
        BinaryStoragePort,
        StorageMetadata,
        StorageOptions,
        InMemoryBinaryStoragePort;
