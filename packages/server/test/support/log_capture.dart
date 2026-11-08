import 'dart:async';

import 'package:logging/logging.dart';

/// Collects the [LogRecord]s published under [loggerName] from creation
/// until [cancel].
///
/// Opens the root level to [Level.ALL] while capturing (an `Env` built in
/// `setUp` resets it from `LOG_LEVEL`), so create it after `Env`, inside the
/// test, and `addTearDown(capture.cancel)`.
final class LogCapture {
  LogCapture(this.loggerName) : _previousLevel = Logger.root.level {
    Logger.root.level = Level.ALL;
    _sub = Logger.root.onRecord
        .where((r) => r.loggerName == loggerName)
        .listen(records.add);
  }

  final String loggerName;

  final records = <LogRecord>[];

  final Level _previousLevel;

  late final StreamSubscription<LogRecord> _sub;

  Future<void> cancel() async {
    await _sub.cancel();
    Logger.root.level = _previousLevel;
  }
}
