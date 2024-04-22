import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';

final _fYMD = DateFormat.yMd();

String fYMD(DateTime? dateTime) =>
    dateTime == null ? '' : _fYMD.format(dateTime);

sealed class ScreenSize {
  static ScreenSize get(Size size) => switch (size.height) {
        < ScreenSmall.height => const ScreenSmall(),
        < ScreenMedium.height => const ScreenMedium(),
        < ScreenLarge.height => const ScreenLarge(),
        _ => const ScreenBig(),
      };

  const ScreenSize();
}

class ScreenSmall extends ScreenSize {
  static const height = 600;

  const ScreenSmall();
}

class ScreenMedium extends ScreenSize {
  static const height = 800;

  const ScreenMedium();
}

class ScreenLarge extends ScreenSize {
  static const height = 1200;

  const ScreenLarge();
}

class ScreenBig extends ScreenSize {
  static const height = 1600;

  const ScreenBig();
}

ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
  BuildContext context, {
  String? text,
  List<TextSpan>? textSpans,
  Duration duration = snackBarDuration,
  bool isFloating = false,
  bool isError = false,
  Color? color,
}) {
  final theme = Theme.of(context);
  ScaffoldMessenger.of(context).clearSnackBars();
  return ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    duration: duration,
    behavior: isFloating ? SnackBarBehavior.floating : null,
    margin: const EdgeInsets.all(16),
    backgroundColor: isError
        ? theme.colorScheme.error
        : color ?? theme.snackBarTheme.backgroundColor,
    content: RichText(
      text: TextSpan(
        text: text,
        children: textSpans,
        style: isError
            ? theme.snackBarTheme.contentTextStyle!.copyWith(
                color: theme.colorScheme.onError,
              )
            : theme.snackBarTheme.contentTextStyle,
      ),
    ),
  ));
}
