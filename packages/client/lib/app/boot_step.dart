import 'dart:async';

/// A startup that did not finish within the boot timeout, naming the startup
/// steps still running when it gave up (#878) — outermost first, so the last
/// one is the step that hung.
class BootTimeoutException extends TimeoutException {
  BootTimeoutException(Duration timeout, this.pendingSteps)
    : super(
        pendingSteps.isEmpty
            ? 'Startup not completed'
            : 'Startup step not completed: ${pendingSteps.join(' > ')}',
        timeout,
      );

  final List<String> pendingSteps;
}

/// Runs [body] as the startup step [name], so a boot timeout can name the
/// step that hung (#878). Outside `bootDependencies` it just runs [body].
Future<T> bootStep<T>(String name, Future<T> Function() body) async {
  final pending = Zone.current[_pendingStepsKey];
  if (pending is! List<String>) {
    return body();
  }
  pending.add(name);
  try {
    return await body();
  } finally {
    pending.remove(name);
  }
}

/// Runs [configure] with step tracking: the steps [bootStep] marks inside
/// it, and still running, are in [pendingSteps].
Future<T> runWithBootSteps<T>(
  Future<T> Function() configure,
  List<String> pendingSteps,
) => runZoned(configure, zoneValues: {_pendingStepsKey: pendingSteps});

const _pendingStepsKey = #tenturaBootSteps;
