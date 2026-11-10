// Every fragment a pipeline or the model extractor produces belongs to the
// workspace of its evidence.

import 'dart:typed_data';

import 'package:mcp_bundle/ports.dart';
import 'package:mcp_ingest/mcp_ingest.dart';
import 'package:test/test.dart';

class _Llm extends LlmPort {
  @override
  LlmCapabilities get capabilities => const LlmCapabilities.minimal();

  @override
  Future<LlmResponse> complete(LlmRequest request) async => LlmResponse(
      content:
          '{"extractions":[{"field":"total","value":"12","confidence":0.9}]}');

  @override
  Future<bool> isAvailable() async => true;
}

void main() {
  NormalizedDocument doc() => NormalizedDocument(
        id: 'd1',
        metadata: const DocumentMetadata(mimeType: 'text/plain', sha256: 'x'),
        parts: [TextBlock(id: 't', text: 'total 12')],
        structure: DocumentStructure.empty,
        provenance: ExtractionProvenance(
            extractorId: 'test',
            extractorVersion: '1',
            extractedAt: DateTime.utc(2026),
            extractionDuration: Duration.zero),
      );

  test('the pipeline gives its fragments the evidence workspace', () async {
    // Fragments come from key-value parts; a JSON document gives them.
    final r = await IngestPipeline.defaults().ingest(
      IngestInput.fromBytes(Uint8List.fromList('{"total": 12}'.codeUnits),
          filename: 'doc.json', mimeType: 'application/json'),
      IngestOptions.defaults.copyWith(
          workspaceId: 'ws-a',
          extractFragments: true,
          fragmentRules: const [
            FragmentRule(
              id: 'r1',
              field: 'total',
              pattern: 'total',
              patternType: FragmentPatternType.keyword,
              valueType: FragmentValueType.currency,
            ),
          ]),
    );
    expect(r.error, isNull);
    expect(r.fragments, isNotEmpty);
    expect(r.evidence!.workspaceId, 'ws-a');
    expect(r.fragments.every((f) => f.workspaceId == 'ws-a'), isTrue);
    expect(r.fragments.every((f) => f.evidenceId == r.evidence!.evidenceId),
        isTrue);
  });

  test('the model extractor takes the workspace on every entry', () async {
    final x = LlmFragmentExtractor(_Llm());
    final byFields = await x.extractFields(
        doc(),
        'ev',
        const [
          FieldDefinition(
              name: 'total',
              description: 'the total',
              valueType: FragmentValueType.currency)
        ],
        workspaceId: 'ws-b');
    expect(byFields.single.workspaceId, 'ws-b');
    final bySchema = await x.extractWithSchema(
        doc(), 'ev', const {'type': 'object'},
        workspaceId: 'ws-c');
    expect(bySchema.single.workspaceId, 'ws-c');
    expect(
        (await x.extractWithSchema(doc(), 'ev', const {})).single.workspaceId,
        'default');
  });
}
