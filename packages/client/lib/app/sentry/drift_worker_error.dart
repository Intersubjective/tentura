// TENTURA-CLIENT-6G (#1309) points to a generic rethrow in the compiled Drift
// worker. The original cause is unknown and a shutdown race is unconfirmed,
// so keep reporting the event and annotate the empty error with its source.
String? driftWorkerErrorDiagnostic({
  required String? type,
  required String? value,
  required String? mechanism,
  required Iterable<String?> Function() framePaths,
}) {
  if (type != 'Error' ||
      value != 'Uncaught ' ||
      (mechanism != 'onerror' &&
          mechanism != 'auto.browser.global_handlers.onerror')) {
    return null;
  }
  const workerAsset = 'packages/drift_worker.js';
  if (framePaths().any(
    (path) => path == workerAsset || (path?.endsWith('/$workerAsset') ?? false),
  )) {
    return 'Uncaught error in drift_worker.js';
  }
  return null;
}
