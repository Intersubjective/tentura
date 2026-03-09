import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../utils/screen_size.dart';

class QrCode extends StatelessWidget {
  const QrCode({
    required this.data,
    this.backgroundColor = Colors.white24,
    this.foregroundColor = Colors.black87,
    super.key,
  });

  final String data;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: switch (ScreenSize.get(MediaQuery.of(context).size)) {
      final ScreenSmall _ => const BoxConstraints.expand(),
      final ScreenMedium _ => const BoxConstraints.expand(),
      final ScreenLarge screen => BoxConstraints.loose(screen.size / 2),
      final ScreenBig screen => BoxConstraints.loose(screen.size / 3),
    },
    child: AspectRatio(
      aspectRatio: 1,
      child: QrImageView(
        // key: ValueKey(data),
        data: data,
        backgroundColor: backgroundColor,
        dataModuleStyle: QrDataModuleStyle(
          // We can`t read inverted QR
          color: foregroundColor,
          dataModuleShape: QrDataModuleShape.square,
        ),
        eyeStyle: QrEyeStyle(
          // We can`t read inverted QR
          color: foregroundColor,
          eyeShape: QrEyeShape.square,
        ),
      ),
    ),
  );
}
