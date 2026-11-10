// Text in, a normalized document with chunks and fragments out.

import 'package:mcp_ingest/mcp_ingest.dart';

Future<void> main() async {
  final pipeline = IngestPipeline.defaults();

  final result = await pipeline.ingest(
    IngestInput.fromString(
      '{"total": 12, "vendor": "Kiwi Cafe"}',
      filename: 'receipt.json',
      mimeType: 'application/json',
    ),
    IngestOptions.defaults.copyWith(
      workspaceId: 'demo',
      extractFragments: true,
      fragmentRules: const [
        FragmentRule(
          id: 'total',
          field: 'total',
          pattern: 'total',
          patternType: FragmentPatternType.keyword,
          valueType: FragmentValueType.currency,
        ),
      ],
    ),
  );

  if (result.error != null) {
    print('ingestion failed: ${result.error}');
    return;
  }
  print(
      '${result.chunks.length} chunk(s), ${result.fragments.length} fragment(s)');
  print(
      'evidence ${result.evidence!.evidenceId} in ${result.evidence!.workspaceId}');
}
