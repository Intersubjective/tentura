import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app/app.dart';
import 'app/sentry/install_web_script_error_filter.dart';
import 'app/sentry/sentry_init.dart';
import 'app/tentura_widgets_binding.dart';

Future<void> main() async {
  TenturaWidgetsBinding.ensureInitialized();
  if (kDebugMode) {
    await App.runner(debugErrors: true);
  } else if (sentryDsn.isEmpty) {
    await App.runner();
  } else {
    await SentryFlutter.init(
      configureSentryOptions,
      appRunner: () {
        installWebScriptErrorFilter();
        return App.runner(useSentryWidget: true);
      },
    );
  }
}
