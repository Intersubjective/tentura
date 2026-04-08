import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:tentura/app/platform/platform_info.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../utils/screen_size.dart';

class QRScanDialog extends StatefulWidget {
  static Future<String?> show(BuildContext context) =>
      showAdaptiveDialog<String>(
        context: context,
        useSafeArea: false,
        builder: (context) => const QRScanDialog(),
      );

  const QRScanDialog({super.key});

  @override
  State<QRScanDialog> createState() => _QRScanDialogState();
}

class _QRScanDialogState extends State<QRScanDialog> {
  late final _l10n = L10n.of(context)!;

  Rect get _scanWindow => _getScanWindow();

  var _hasResult = false;

  final _desktopController = TextEditingController();

  @override
  void dispose() {
    _desktopController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: Text(_l10n.scanQrCode),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      extendBodyBehindAppBar: !isDesktopPlatform,
      body: isDesktopPlatform
          ? _buildDesktopBody()
          : kIsWeb
              ? MobileScanner(onDetect: _handleBarcode)
              : Stack(
                  children: [
                    MobileScanner(
                      onDetect: _handleBarcode,
                      scanWindow: kIsWeb ? null : _scanWindow,
                    ),
                    CustomPaint(painter: _ScannerOverlay(frame: _scanWindow)),
                  ],
                ),
    ),
  );

  Widget _buildDesktopBody() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextField(
            controller: _desktopController,
            decoration: InputDecoration(
              hintText: _l10n.pleaseEnterCode,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty && context.mounted) {
                Navigator.of(context).pop(value.trim());
              }
            },
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  final text = data?.text?.trim();
                  if (text != null && text.isNotEmpty && mounted) {
                    _desktopController.text = text;
                  }
                },
                icon: const Icon(Icons.paste_rounded),
                label: Text(_l10n.buttonPaste),
              ),
              const SizedBox(width: 16),
              FilledButton(
                onPressed: () {
                  final value = _desktopController.text.trim();
                  if (value.isNotEmpty && context.mounted) {
                    Navigator.of(context).pop(value);
                  }
                },
                child: Text(_l10n.buttonOk),
              ),
              const SizedBox(width: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(_l10n.buttonCancel),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Rect _getScanWindow() {
    final size = MediaQuery.of(context).size;
    final scanAreaSize = switch (ScreenSize.get(size)) {
      ScreenSmall _ => size.width * 0.75,
      ScreenMedium _ => size.width * 0.7,
      ScreenLarge _ => size.width * 0.6,
      ScreenBig _ => size.width * 0.5,
    };
    return Rect.fromCenter(
      center: size.center(Offset.zero),
      width: scanAreaSize,
      height: scanAreaSize,
    );
  }

  void _handleBarcode(BarcodeCapture captured) {
    if (_hasResult || captured.barcodes.isEmpty) return;
    if (context.mounted) {
      _hasResult = true;
      Navigator.of(context).pop(captured.barcodes.first.rawValue);
    }
  }
}

class _ScannerOverlay extends CustomPainter {
  _ScannerOverlay({required this.frame});

  final Rect frame;

  final _framePaint = Paint()
    ..color = Colors.white
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 8;

  final _maskPaint = Paint()
    ..color = Colors.deepPurple.withValues(alpha: 0.5)
    ..style = PaintingStyle.fill
    ..blendMode = BlendMode.dstOut;

  late final _maskPath = Path.combine(
    PathOperation.difference,
    Path()..addRect(Rect.largest),
    Path()..addRect(frame),
  );

  late final _frameSize = frame.height / 5;

  late final _leftTop = Offset(frame.left, frame.top);
  late final _leftTopH = Offset(frame.left + _frameSize, frame.top);
  late final _leftTopV = Offset(frame.left, frame.top + _frameSize);

  late final _rightTop = Offset(frame.right, frame.top);
  late final _rightTopH = Offset(frame.right - _frameSize, frame.top);
  late final _rightTopV = Offset(frame.right, frame.top + _frameSize);

  late final _leftBottom = Offset(frame.left, frame.bottom);
  late final _leftBottomH = Offset(frame.left + _frameSize, frame.bottom);
  late final _leftBottomV = Offset(frame.left, frame.bottom - _frameSize);

  late final _rightBottom = Offset(frame.right, frame.bottom);
  late final _rightBottomH = Offset(frame.right - _frameSize, frame.bottom);
  late final _rightBottomV = Offset(frame.right, frame.bottom - _frameSize);

  @override
  bool shouldRepaint(_) => false;

  @override
  void paint(Canvas canvas, Size size) => canvas
    ..drawPath(_maskPath, _maskPaint)
    ..drawLine(_leftTop, _leftTopH, _framePaint)
    ..drawLine(_leftTop, _leftTopV, _framePaint)
    ..drawLine(_rightTop, _rightTopH, _framePaint)
    ..drawLine(_rightTop, _rightTopV, _framePaint)
    ..drawLine(_leftBottom, _leftBottomH, _framePaint)
    ..drawLine(_leftBottom, _leftBottomV, _framePaint)
    ..drawLine(_rightBottom, _rightBottomH, _framePaint)
    ..drawLine(_rightBottom, _rightBottomV, _framePaint);
}
