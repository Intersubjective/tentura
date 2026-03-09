import 'dart:typed_data';
import 'package:shelf_plus/shelf_plus.dart';

import 'package:tentura_server/env.dart';

export 'package:shelf_plus/shelf_plus.dart';

abstract base class BaseController {
  const BaseController(this.env);

  final Env env;

  Future<Uint8List> readBodyAsBytes(
    Stream<List<int>> Function() getStream,
  ) async {
    final builder = BytesBuilder(copy: false);
    await getStream().forEach(builder.add);
    return builder.takeBytes();
  }

  Future<Response> handler(Request request);
}
