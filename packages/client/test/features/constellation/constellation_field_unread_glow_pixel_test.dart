import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_field_unread_glow_layer.dart';

/// QA on #256 samples 28–48 px from the node centre on an outside arc.
const _nodeRadius = 20.0;
const _sampleRadii = [32.0, 40.0, 48.0];
const _glowColor = Color(0xFF625B71);

void main() {
  tearDown(ConstellationFieldUnreadGlowAtlas.resetForTest);

  final frame = ConstellationPresentationFrame(
    snapshot: 'pixel',
    cameraRevision: 0,
    detail: ConstellationDetailLevel.close,
    paintOrder: const ['unread'],
    bodies: {
      'unread': Rect.fromCircle(
        center: const Offset(100, 100),
        radius: _nodeRadius,
      ),
    },
    labels: const {},
    tapTargets: const {},
    chips: const {},
    forcedLabels: const {},
  );

  for (final (label, isDark) in [('light', false), ('dark', true)]) {
    test('unread glow is visible outside the node on $label theme', () async {
      final tt = isDark ? TenturaTokens.dark : TenturaTokens.light;
      final background = isDark ? tt.bg : tt.bg;
      final atlas = ConstellationFieldUnreadGlowAtlas.instance;
      final glow = await _rasterGlow(
        background: background,
        isDark: isDark,
        frame: frame,
        atlas: atlas,
        spread: tt.fieldUnreadGlowSpread,
        alphaDark: tt.fieldUnreadGlowAlphaDark,
        alphaLight: tt.fieldUnreadGlowAlphaLight,
        withGlow: true,
      );
      final flat = await _rasterGlow(
        background: background,
        isDark: isDark,
        frame: frame,
        atlas: atlas,
        spread: tt.fieldUnreadGlowSpread,
        alphaDark: tt.fieldUnreadGlowAlphaDark,
        alphaLight: tt.fieldUnreadGlowAlphaLight,
        withGlow: false,
      );

      // Picture-raster harness understates dark [BlendMode.plus]; QA saw 63–84.
      final minContrast = isDark ? 12 : 14;
      var maxContrast = 0;
      var maxAt = '';
      for (final r in _sampleRadii) {
        for (var deg = 0; deg < 360; deg += 45) {
          final rad = deg * 3.141592653589793 / 180;
          final x = (100 + r * math.cos(rad)).round();
          final y = (100 + r * math.sin(rad)).round();
          final diff = _maxChannelDelta(glow, flat, x, y);
          if (diff > maxContrast) {
            maxContrast = diff;
            maxAt = '($x, $y) r=$r';
          }
        }
      }
      expect(
        maxContrast,
        greaterThanOrEqualTo(minContrast),
        reason: 'peak outside-node contrast on $label at $maxAt',
      );
    });
  }
}

Future<Uint8List> _rasterGlow({
  required Color background,
  required bool isDark,
  required ConstellationPresentationFrame frame,
  required ConstellationFieldUnreadGlowAtlas atlas,
  required double spread,
  required double alphaDark,
  required double alphaLight,
  required bool withGlow,
}) async {
  const size = 200.0;
  final sizeI = size.toInt();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, size, size),
    Paint()..color = background,
  );
  if (withGlow) {
    ConstellationFieldUnreadGlowPainter(
      frame: frame,
      glowSites: const {
        'unread': (authorId: 'author', opacity: 1),
      },
      colorForAuthor: (_) => _glowColor,
      atlas: atlas,
      spread: spread,
      alphaDark: alphaDark,
      alphaLight: alphaLight,
      unreadDotSize: 10,
      unreadDotColor: Colors.blue,
      isDark: isDark,
      highContrast: false,
      pulseBoost: 1,
    ).paint(canvas, const Size(size, size));
  }
  final image = await recorder.endRecording().toImage(sizeI, sizeI);
  final bytes = await image.toByteData();
  image.dispose();
  return bytes!.buffer.asUint8List();
}

int _maxChannelDelta(Uint8List a, Uint8List b, int x, int y) {
  const width = 200;
  final i = (y * width + x) * 4;
  var max = 0;
  for (var c = 0; c < 3; c++) {
    final d = (a[i + c] - b[i + c]).abs();
    if (d > max) max = d;
  }
  return max;
}
