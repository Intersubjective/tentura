import 'package:web/web.dart' as web;

import 'device_label_parser.dart';

/// The browser and OS this page runs in ("Chrome on Linux"), as a sign-in
/// method's device label (#467).
String? currentDeviceLabel() {
  try {
    return deviceLabelFromUserAgent(web.window.navigator.userAgent);
  } catch (_) {
    return null;
  }
}
