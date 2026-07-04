/// No-op on non-web platforms — this probe only makes sense against a
/// browser's Notification/ServiceWorker APIs.
Future<void> showDirectTestNotification() async {}
