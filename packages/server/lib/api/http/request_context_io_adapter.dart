import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf_plus/shelf_plus.dart';
import 'package:tentura_server/domain/request_context.dart';
import 'package:uuid/uuid.dart';

/// HttpResponse.done only observes errors once a response is written. Hijacking
/// after reading the body lets us observe the peer closing during the handler,
/// while Shelf still parses the incoming HTTP request and supports WebSockets.
Handler requestContextIoAdapter(Handler handler) => (request) async {
  final context = RequestContext(requestId: const Uuid().v4());
  if (request.url.path.startsWith('api/v2/session/')) {
    context.classify(RequestOperationClass.auth);
  }
  if (request.url.path != 'api/v2/graphql' || !request.canHijack) {
    try {
      return await context.run(() async => handler(request));
    } finally {
      context.dispose();
    }
  }

  final body = BytesBuilder(copy: false);
  try {
    await for (final bytes in request.read()) {
      context.check();
      body.add(bytes);
    }
  } on Object {
    context.dispose();
    rethrow;
  }
  final bufferedRequest = request.change(body: body.takeBytes());
  request.hijack((channel) async {
    var disconnected = false;
    final input = channel.stream.listen(
      (_) {},
      onError: (Object error) {
        disconnected = true;
        context.cancel(error);
      },
      onDone: () {
        disconnected = true;
        context.cancel();
      },
    );
    try {
      Response response;
      try {
        response = await context.run(() async => handler(bufferedRequest));
      } on Object {
        response = Response.internalServerError();
      }
      if (disconnected) return;
      final output = BytesBuilder(copy: false);
      await response.read().forEach(output.add);
      final headers = StringBuffer('HTTP/1.1 ${response.statusCode} \r\n');
      response.headersAll.forEach((name, values) {
        if (const {
          'content-length',
          'transfer-encoding',
          'connection',
        }.contains(name.toLowerCase())) {
          return;
        }
        for (final value in values) {
          headers.write('$name: $value\r\n');
        }
      });
      headers.write(
        'content-length: ${output.length}\r\nconnection: close\r\n\r\n',
      );
      channel.sink
        ..add(utf8.encode(headers.toString()))
        ..add(output.takeBytes());
      await channel.sink.close();
    } on Object catch (error) {
      context.cancel(error);
    } finally {
      context.dispose();
      await input.cancel();
      await channel.sink.close();
    }
  });
};
