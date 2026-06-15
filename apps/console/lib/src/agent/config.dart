import 'dart:convert';
import 'dart:io';

/// Connection settings for the swift-infer agent backend.
///
/// Resolved from the environment first — a token exported in the shell (e.g.
/// `SWIFT_INFER_AGENT_TOKEN` in `~/.zshenv`) is used directly — then from a
/// local, gitignored secrets file. The token is never logged or written
/// anywhere; only the variable *name* is referenced here.
class AgentConfig {
  /// Creates a config with an explicit [baseUrl], [model], and [agentToken].
  const AgentConfig({
    required this.baseUrl,
    required this.model,
    required this.agentToken,
  });

  /// The swift-infer base URL, without a trailing slash.
  final String baseUrl;

  /// The model id requested from `/v1/chat/completions`.
  final String model;

  /// The bearer token sent as `Authorization: Bearer <token>`.
  final String agentToken;

  /// Default swift-infer endpoint.
  static const String defaultBaseUrl = 'http://localhost:8080';

  /// Default model — a MoE that handles tool calls well (de-risk-verified).
  static const String defaultModel = 'qwen3.6-35b-a3b-8bit';

  /// The environment variable holding the agent bearer token.
  static const String tokenEnv = 'SWIFT_INFER_AGENT_TOKEN';

  /// Resolves config from [env] (the process environment by default) or, when
  /// the token is absent there, from [secretsFile] (`apps/console/.secrets.json`
  /// by default — a `{"agentToken","baseUrl","model"}` object).
  ///
  /// Throws [StateError] with remediation when no token can be found.
  static Future<AgentConfig> resolve({
    Map<String, String>? env,
    File? secretsFile,
  }) async {
    final e = env ?? Platform.environment;
    final envToken = e[tokenEnv];
    if (envToken != null && envToken.isNotEmpty) {
      return AgentConfig(
        baseUrl: e['SWIFT_INFER_URL'] ?? defaultBaseUrl,
        model: e['SWIFT_INFER_MODEL'] ?? defaultModel,
        agentToken: envToken,
      );
    }
    final file = secretsFile ?? File('apps/console/.secrets.json');
    if (file.existsSync()) {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final token = json['agentToken'] as String?;
      if (token != null && token.isNotEmpty) {
        return AgentConfig(
          baseUrl: (json['baseUrl'] as String?) ?? defaultBaseUrl,
          model: (json['model'] as String?) ?? defaultModel,
          agentToken: token,
        );
      }
    }
    throw StateError(
      'No swift-infer agent token found. Set $tokenEnv in your environment, '
      'or create apps/console/.secrets.json (see .secrets.example.json).',
    );
  }
}
