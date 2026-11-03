import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Real production GraphQL + disposable PostgreSQL + production NOTIFY fanout
/// in a server-package process. This adapter neither stores receipts nor
/// manufactures entity-change envelopes.
final class ProductionReceiptTransport {
  ProductionReceiptTransport._(this._process);
  final Process _process;
  final _ready = Completer<int>();
  final _frames = StreamController<({String viewer, Object frame})>.broadcast();
  final _errors = StringBuffer();
  // Widget bindings replace the global HttpClient with a canned 400 client.
  // This fixture needs a real loopback connection to its server process.
  final _client = HttpOverrides.runWithHttpOverrides(
    HttpClient.new,
    _LoopbackHttpOverrides(),
  );
  late final int _port;
  late final StreamSubscription<String> _output;
  late final StreamSubscription<String> _stderr;
  Stream<({String viewer, Object frame})> get frames => _frames.stream;

  static Future<ProductionReceiptTransport> start({
    String? postLifecycleFixture,
  }) async {
    final process = await Process.start(
      'dart',
      ['run', 'test/support/request_update_seen_transport.dart'],
      workingDirectory: '../server',
      environment: {
        'TENTURA_RECEIPT_POST_LIFECYCLE_FIXTURE': ?postLifecycleFixture,
      },
    );
    final bridge = ProductionReceiptTransport._(process);
    bridge._output = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          const prefix = 'TENTURA_RECEIPT_TRANSPORT ';
          if (!line.startsWith(prefix)) return;
          final event =
              jsonDecode(line.substring(prefix.length)) as Map<String, dynamic>;
          if (event['ready'] case final int port) bridge._ready.complete(port);
          if (event case {
            'viewer': final String viewer,
            'frame': final Object frame,
          }) {
            bridge._frames.add((viewer: viewer, frame: frame));
          }
        });
    bridge._stderr = process.stderr
        .transform(utf8.decoder)
        .listen(bridge._errors.write);
    unawaited(
      process.exitCode.then((code) {
        if (!bridge._ready.isCompleted) {
          bridge._ready.completeError(
            StateError(
              'Production receipt server exited $code: ${bridge._errors}',
            ),
          );
        }
      }),
    );
    try {
      bridge._port = await bridge._ready.future.timeout(
        const Duration(seconds: 45),
      );
      return bridge;
    } on Object {
      process.kill();
      await bridge._output.cancel();
      await bridge._stderr.cancel();
      bridge._client.close(force: true);
      await bridge._frames.close();
      rethrow;
    }
  }

  Future<http.Response> graphql(
    String viewer,
    Map<String, dynamic> body,
  ) async {
    final request = await _client.postUrl(
      Uri.parse('http://127.0.0.1:$_port/graphql?viewer=$viewer'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    return http.Response(
      await utf8.decoder.bind(response).join(),
      response.statusCode,
      headers: {'content-type': 'application/json'},
    );
  }

  Future<void> close() async {
    try {
      final request = await _client.postUrl(
        Uri.parse('http://127.0.0.1:$_port/close'),
      );
      final response = await request.close();
      await response.drain<void>();
      await _process.exitCode.timeout(const Duration(seconds: 10));
    } finally {
      _process.kill();
      _client.close(force: true);
      await _output.cancel();
      await _stderr.cancel();
      await _frames.close();
    }
  }
}

final class _LoopbackHttpOverrides extends HttpOverrides {}
