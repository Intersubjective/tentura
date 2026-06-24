import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app/app.dart';
import 'app/sentry/sentry_init.dart';

Future<void> main() async {
  if (kDebugMode) {
    await App.runner(debugErrors: true);
  } else if (sentryDsn.isEmpty) {
    await App.runner();
  } else {
    await SentryFlutter.init(
      configureSentryOptions,
      appRunner: () => App.runner(useSentryWidget: true),
    );
  }
}
