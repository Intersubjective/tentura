import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// Copies [text] to the system clipboard.
///
/// Returns `false` when the platform rejects the write (common on Safari
/// without a transient user gesture / permission). Failures are swallowed so
/// they do not become unhandled zone errors (Sentry TENTURA-CLIENT-2F).
Future<bool> copyTextToClipboard(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } on PlatformException catch (e, st) {
    Logger('clipboard').fine('Clipboard.setData failed', e, st);
    return false;
  } on Object catch (e, st) {
    Logger('clipboard').fine('Clipboard.setData failed', e, st);
    return false;
  }
}
