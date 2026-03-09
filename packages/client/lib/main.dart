import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app/app.dart';

Future<void> main() async {
  kDebugMode
      ? await App.runner()
      : await SentryFlutter.init(
          (options) => options
            ..debug = kDebugMode
            ..denyUrls = []
            ..dsn = const String.fromEnvironment('SENTRY_URL')
            ..ignoreErrors = [
              'SocketException',
            ]
            ..tracesSampleRate = 1.0,
          appRunner: App.runner,
        );
}
