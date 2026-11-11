@Tags(['pg', 'repo-files'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'production_receipt_transport.dart';

// Ready cap for the production receipt subprocess lives in
// production_receipt_transport.dart. Under client-all load that subprocess
// can still report ready only after the old forty-five-second ceiling.
void main() {
  test(
    'Production receipt transport keeps waiting when the server needs longer than forty-five seconds',
    () async {
      ProductionReceiptTransport? transport;
      try {
        transport = await ProductionReceiptTransport.start(
          postLifecycleFixture: 'slowReady',
        ).timeout(const Duration(seconds: 130));
      } on TimeoutException catch (error) {
        fail(
          'The transport should not time out waiting for a loaded receipt server: $error',
        );
      }
      addTearDown(() => transport?.close());
      expect(transport, isNotNull);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
