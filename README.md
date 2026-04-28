# MCP Ingest

A document ingestion pipeline for MakeMind. Converts any file format into a standardized `NormalizedDocument` with chunking, OCR/ASR support, and fragment extraction.

## Features

- **Universal input** — files, raw bytes, URLs, streams.
- **Format coverage** — HTML, XML, YAML, JSON, Markdown, archives, plus pluggable handlers for PDF, audio, image (via OCR/ASR ports).
- **Chunking** — configurable strategies for downstream embedding / retrieval.
- **Fragment extraction** — semantic fragment splitting.
- **Pluggable OCR / ASR ports** — bridge to your provider of choice.
- **Pipeline composition** — `IngestPipeline.defaults()` for common cases, fully customizable for advanced use.

## Quick Start

```dart
import 'package:mcp_ingest/mcp_ingest.dart';

final pipeline = IngestPipeline.defaults();

final result = await pipeline.ingest(
  IngestInput.fromFile('document.pdf'),
  IngestOptions.defaults,
);

print('Extracted ${result.chunks.length} chunks');
```

With OCR/ASR plugins:

```dart
final pipeline = IngestPipeline(
  ocrPort: tesseractOcrPlugin,
  asrPort: whisperAsrPlugin,
);
```

## Support

- [Issue Tracker](https://github.com/app-appplayer/mcp_ingest/issues)
- [Discussions](https://github.com/app-appplayer/mcp_ingest/discussions)

## License

MIT — see [LICENSE](LICENSE).
