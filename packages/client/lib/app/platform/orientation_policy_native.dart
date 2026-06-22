import 'dart:io' show Platform;
import 'dart:ui' show FlutterView;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'platform_info_native.dart';

/// Portrait lock applies when logical shortest side is below the compact threshold (600).
const kPortraitLockMaxLogicalShortestSide = 600.0;

bool shouldLockPortraitForLogicalShortestSide(double logicalShortestSide) =>
    logicalShortestSide < kPortraitLockMaxLogicalShortestSide;

Future<void> applyOrientationPolicyForView(FlutterView view) async {
  if (isDesktopPlatform) {
    return;
  }
  if (!Platform.isAndroid && !Platform.isIOS) {
    return;
  }

  final dpr = view.devicePixelRatio;
  if (dpr == 0) {
    return;
  }
  final logicalShortest = view.physicalSize.shortestSide / dpr;

  if (shouldLockPortraitForLogicalShortestSide(logicalShortest)) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  } else {
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }
}

Future<void> applyInitialOrientationPolicy() async {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) {
    return;
  }
  await applyOrientationPolicyForView(views.first);
}
