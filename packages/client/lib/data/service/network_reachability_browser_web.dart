import 'package:rxdart/rxdart.dart';
import 'package:web/web.dart' as web;

/// The browser's own idea of connectivity (`navigator.onLine`).
bool browserInitiallyOnline() => web.window.navigator.onLine;

/// `true` on the window's `online` event, `false` on `offline`.
Stream<bool>? browserOnlineChanges() => MergeStream([
  web.EventStreamProviders.onlineEvent.forTarget(web.window).map((_) => true),
  web.EventStreamProviders.offlineEvent.forTarget(web.window).map((_) => false),
]);
