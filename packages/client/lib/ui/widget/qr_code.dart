import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../utils/screen_size.dart';

class QrCode extends StatelessWidget {
  const QrCode({
    required this.data,
    super.key,
  });

  final String data;

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
        // Always high-contrast: black on white, independent of theme
        backgroundColor: Colors.white,
        dataModuleStyle: const QrDataModuleStyle(
          // We can`t read inverted QR
          color: Colors.black,
        ),
        // Same as QrImageView default; pin square finders if package defaults change
        // ignore: avoid_redundant_argument_values
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Colors.black,
        ),
      ),
    ),
  );
}
