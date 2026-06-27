import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Upper bound for QR in dialogs and share sheets (avoids viewport-scale blow-up).
const double kQrMaxDimension = 280;

/// QR side length from viewport: shorter viewports use the cap; taller ones scale
/// down by height tier, always clamped to [kQrMaxDimension].
double _qrSideForViewport(Size size) {
  final h = size.height;
  final raw = switch (h) {
    < 800 => kQrMaxDimension,
    < 1200 => size.shortestSide / 2,
    _ => size.shortestSide / 3,
  };
  return raw.clamp(160, kQrMaxDimension);
}

class QrCode extends StatelessWidget {
  const QrCode({
    required this.data,
    super.key,
  });

  final String data;

  @override
  Widget build(BuildContext context) {
    final side = _qrSideForViewport(MediaQuery.sizeOf(context));
    return SizedBox.square(
      dimension: side,
      child: QrImageView(
        data: data,
        backgroundColor: Colors.white,
        dataModuleStyle: const QrDataModuleStyle(
          color: Colors.black,
        ),
        // Explicit square eyes: keep if package defaults change (lint wants omission).
        // ignore: avoid_redundant_argument_values
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Colors.black,
        ),
      ),
    );
  }
}
