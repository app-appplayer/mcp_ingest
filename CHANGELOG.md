## [0.1.0] - 2026-04-28 - Initial Release

### Added
- `IngestPipeline` for converting files / bytes / URLs / streams into a `NormalizedDocument`.
- Format coverage — HTML, XML, YAML, JSON, Markdown, archives, with pluggable OCR / ASR ports for PDF / audio / image.
- Chunking strategies and semantic fragment extraction.
- `IngestPipeline.defaults()` factory plus full customization hooks.
