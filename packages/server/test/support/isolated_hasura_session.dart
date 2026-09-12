import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:tentura_server/env.dart';

/// Disposable Hasura engine for PG tests — never mutates the long-running
/// compose instance on :8080.
final class IsolatedHasuraSession {
  IsolatedHasuraSession._({
    required this.baseUrl,
    required this.adminSecret,
    required this.containerName,
    required this.port,
  });

  final String baseUrl;
  final String adminSecret;
  final String containerName;
  final int port;

  static Future<bool> isDockerAvailable() async {
    try {
      final result = await Process.run('docker', ['info']);
      return result.exitCode == 0;
    } on Object catch (_) {
      return false;
    }
  }

  static Future<IsolatedHasuraSession> start({
    required Env databaseEnv,
    required String jwtPublicPem,
    String adminSecret = 'password',
  }) async {
    if (!await isDockerAvailable()) {
      throw StateError('Docker is required for isolated Hasura tests');
    }

    final port = await _findFreePort();
    final containerName =
        'tentura_test_hasura_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    final databaseUrl = _postgresDatabaseUrl(databaseEnv);
    final jwtSecret = jsonEncode({
      'type': 'Ed25519',
      'key': jwtPublicPem,
      'claims_map': {
        'x-hasura-allowed-roles': ['user', 'admin'],
        'x-hasura-default-role': 'user',
        'x-hasura-user-id': {'path': r'$.sub'},
      },
    });

    final run = await Process.run('docker', [
      'run',
      '-d',
      '--rm',
      '--name',
      containerName,
      '--network',
      'host',
      '-e',
      'HASURA_GRAPHQL_SERVER_PORT=$port',
      '-e',
      'HASURA_GRAPHQL_DATABASE_URL=$databaseUrl',
      '-e',
      'HASURA_GRAPHQL_ADMIN_SECRET=$adminSecret',
      '-e',
      'HASURA_GRAPHQL_JWT_SECRET=$jwtSecret',
      '-e',
      'HASURA_GRAPHQL_ENABLE_TELEMETRY=false',
      '-e',
      'HASURA_GRAPHQL_DEV_MODE=true',
      '-e',
      'HASURA_GRAPHQL_ENABLE_CONSOLE=false',
      'hasura/graphql-engine',
    ]);
    if (run.exitCode != 0) {
      throw StateError(
        'Failed to start isolated Hasura container '
        '(exit ${run.exitCode})',
      );
    }

    final session = IsolatedHasuraSession._(
      baseUrl: 'http://127.0.0.1:$port',
      adminSecret: adminSecret,
      containerName: containerName,
      port: port,
    );
    final healthy = await session._waitForHealthy();
    if (!healthy) {
      await session.stop();
      throw StateError('Isolated Hasura on port $port did not become healthy');
    }
    return session;
  }

  Future<void> applyRepoMetadata() async {
    final metadataFile = File(
      '${Directory.current.path}/../../hasura/metadata.json',
    );
    final metadata =
        jsonDecode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
    await _postMetadata(
      'replace_metadata',
      args: {
        'allow_inconsistent_metadata': true,
        'metadata': metadata['metadata'],
      },
    );
  }

  Future<void> stop() async {
    await Process.run('docker', ['rm', '-f', containerName]);
  }

  Future<bool> _waitForHealthy() async {
    for (var attempt = 0; attempt < 60; attempt++) {
      try {
        final response = await http
            .get(Uri.parse('$baseUrl/healthz'))
            .timeout(const Duration(seconds: 1));
        if (response.statusCode == 200) {
          return true;
        }
      } on Object catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  Future<Map<String, dynamic>> _postMetadata(
    String type, {
    Map<String, dynamic> args = const {},
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/v1/metadata'),
      headers: {
        'Content-Type': 'application/json',
        'X-Hasura-Admin-Secret': adminSecret,
      },
      body: jsonEncode({'type': type, 'args': args}),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 || body['error'] != null) {
      throw StateError(
        'Hasura metadata $type failed (HTTP ${response.statusCode})',
      );
    }
    return body;
  }

  static Future<int> _findFreePort() async {
    for (var port = 18080; port < 18280; port++) {
      try {
        final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
        await socket.close();
        return port;
      } on SocketException catch (_) {}
    }
    throw StateError('No free localhost port for isolated Hasura');
  }

  static String _postgresDatabaseUrl(Env env) => Uri(
    scheme: 'postgres',
    userInfo: '${env.pgUsername}:${env.pgPassword}',
    host: env.pgHost,
    port: env.pgPort,
    path: env.pgDatabase,
  ).toString();
}
