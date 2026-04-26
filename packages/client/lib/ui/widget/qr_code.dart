import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// QR layout uses **height** breakpoints: under 800px expand; under 1200px half
/// viewport loose; else one-third (share-sheet style).
BoxConstraints _qrConstraintsForViewport(Size size) {
  final h = size.height;
  if (h < 800) {
    return const BoxConstraints.expand();
  }
  if (h < 1200) {
    return BoxConstraints.loose(size / 2);
  }
  return BoxConstraints.loose(size / 3);
}

class QrCode extends StatelessWidget {
  const QrCode({
    required this.data,
    super.key,
  });

  final String data;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: _qrConstraintsForViewport(MediaQuery.sizeOf(context)),
    child: AspectRatio(
      aspectRatio: 1,
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
    ),
  );
}
