## [0.1.1] - 2026-05-23 - mcp_bundle 0.4.0 + mcp_fact_graph 0.2.2 cascade

### Changed (cascade)
- `mcp_bundle` `^0.3.0` → `^0.4.0`.
- `mcp_fact_graph` `^0.2.0` → `^0.2.2`.

mcp_ingest does not touch `UiSection.pages` directly — caret-only cascade. Consumers should bump to `^0.1.1`.

## [0.1.0] - 2026-04-28 - Initial Release

### Added
- `IngestPipeline` for converting files / bytes / URLs / streams into a `NormalizedDocument`.
- Format coverage — HTML, XML, YAML, JSON, Markdown, archives, with pluggable OCR / ASR ports for PDF / audio / image.
- Chunking strategies and semantic fragment extraction.
- `IngestPipeline.defaults()` factory plus full customization hooks.
