import 'dart:convert';
import 'dart:io';

import 'package:genesis_console/genesis_console.dart';
import 'package:test/test.dart';

void main() {
  // A path guaranteed not to exist, so the secrets-file branch is skipped.
  final missing = File(
    '${Directory.systemTemp.path}/genesis-console-no-such.json',
  );

  test('environment token resolves, with defaults for url and model', () async {
    final config = await AgentConfig.resolve(
      env: {'SWIFT_INFER_AGENT_TOKEN': 'env-token'},
      secretsFile: missing,
    );
    expect(config.agentToken, 'env-token');
    expect(config.baseUrl, AgentConfig.defaultBaseUrl);
    expect(config.model, AgentConfig.defaultModel);
  });

  test('environment url and model override the defaults', () async {
    final config = await AgentConfig.resolve(
      env: {
        'SWIFT_INFER_AGENT_TOKEN': 'env-token',
        'SWIFT_INFER_URL': 'http://host:9000',
        'SWIFT_INFER_MODEL': 'gemma4',
      },
      secretsFile: missing,
    );
    expect(config.baseUrl, 'http://host:9000');
    expect(config.model, 'gemma4');
  });

  test('modelOverride wins over the env model and the default', () async {
    final config = await AgentConfig.resolve(
      env: {
        'SWIFT_INFER_AGENT_TOKEN': 'env-token',
        'SWIFT_INFER_MODEL': 'gemma4',
      },
      secretsFile: missing,
      modelOverride: 'qwen2.5-vl',
    );
    expect(config.model, 'qwen2.5-vl');
  });

  test('falls back to the secrets file when the env token is absent', () async {
    final dir = Directory.systemTemp.createTempSync('genesis-console-secrets');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/.secrets.json')
      ..writeAsStringSync(
        jsonEncode({
          'agentToken': 'file-token',
          'baseUrl': 'http://file-host:7',
          'model': 'file-model',
        }),
      );

    final config = await AgentConfig.resolve(env: const {}, secretsFile: file);
    expect(config.agentToken, 'file-token');
    expect(config.baseUrl, 'http://file-host:7');
    expect(config.model, 'file-model');
  });

  test('throws an actionable error when no token is available', () async {
    expect(
      () => AgentConfig.resolve(env: const {}, secretsFile: missing),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('SWIFT_INFER_AGENT_TOKEN'), contains('.secrets.json')),
        ),
      ),
    );
  });
}
