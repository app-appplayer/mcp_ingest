## [0.2.0] - 2026-11-04 - Korean, Japanese and Chinese input, compressed PDFs, workspace

### Breaking (behaviour of the same call)
- Text and HTML bytes that are not valid UTF-8 throw `ExtractionException` (a `FormatException` before).
- `SentenceChunker` splits at `。`, `！`, `？`, so Japanese and Chinese text that was one sentence gives several chunks.
- `PdfExtractor` returns the text of compressed streams it used to skip.
- `IngestInput.fromString` produces UTF-8 bytes; the bytes of a string with characters above U+00FF change.

### Changed (dependency)
- `mcp_fact_graph` floor `^0.3.0` and `mcp_bundle` `^0.4.14` (the current releases; a fragment's workspace is checked by 0.3.0, which requires bundle 0.4.14). The other floors are raised to the latest that resolves (`xml` stays on 6.x: 7.x needs Dart 3.13). `archive` is accepted from 3.6.1 up to and excluding 5.0.0: the extractors use the same API on 3.x and 4.x (tested on both), so a host moves to archive 4 at its own pace. `mime`, which nothing used, is no longer a dependency.

### Fixed
- `IngestInput.fromString` turned the string into bytes with its UTF-16 code units, so every character above U+00FF (all Hangul, kana and Han) was corrupted. It encodes UTF-8, which is what the text extractors read.
- Text and HTML extraction used `utf8.decodeStream` only. They now read a stated encoding (`ExtractOptions.custom['encoding']`: `utf-8`, `utf-16`, `utf-16le`, `utf-16be`, `latin1`, `ascii`), recognise UTF-8 and UTF-16 byte-order marks, and throw `ExtractionException` naming the encoding when the bytes are not valid in it, instead of an unnamed format error. Other encodings (EUC-KR, CP949) are not decoded; convert the input to UTF-8.
- `SentenceChunker` ended a sentence only at `.`, `!`, `?` followed by whitespace; `。`, `！` and `？` now end a sentence on their own.
- `PdfExtractor` read the raw file, so a Flate-compressed content stream (most PDFs) gave no text. `/FlateDecode` streams are inflated before reading; one that cannot be inflated is skipped. Text in CID/ToUnicode fonts (most Korean, Japanese and Chinese PDFs) still needs `PdfiumPdfPlugin`.
- The Evidence built at the last stage always belonged to the workspace `'default'`, and so did its fragments, whatever `IngestOptions.workspaceId` said; both now carry that workspace (a fragment of another workspace than its evidence is refused by the fact graph).

### Added
- `IngestOptions.workspaceId` (builder and `copyWith`); `LlmFragmentExtractor.extract(workspaceId:)`, `extractFields(workspaceId:)` and `extractWithSchema(workspaceId:)`.

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
