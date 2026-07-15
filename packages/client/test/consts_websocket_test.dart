import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';

void main() {
  test('websocket server uses its override or the public server origin', () {
    const hasOverride = bool.hasEnvironment('WS_SERVER_NAME');
    const override = String.fromEnvironment('WS_SERVER_NAME');

    expect(kWsServerName, hasOverride ? override : kServerName);
  });
}
