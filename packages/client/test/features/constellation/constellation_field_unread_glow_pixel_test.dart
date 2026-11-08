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
Color _glowColorFor(TenturaTokens tt) => tt.attentionHighlight;

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
      final glowColor = _glowColorFor(tt);
      final glow = await _rasterGlow(
        background: background,
        isDark: isDark,
        frame: frame,
        atlas: atlas,
        spread: tt.fieldUnreadGlowSpread,
        alphaDark: tt.fieldUnreadGlowAlphaDark,
        alphaLight: tt.fieldUnreadGlowAlphaLight,
        glowColor: glowColor,
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
        glowColor: glowColor,
        withGlow: false,
      );

      // Picture-raster harness understates dark [BlendMode.plus]; QA saw 63–84.
      final minContrast = isDark ? 12 : 14;
      var maxContrast = 0;
      var maxAt = '';
      var peakX = 0;
      var peakY = 0;
      for (final r in _sampleRadii) {
        for (var deg = 0; deg < 360; deg += 45) {
          final rad = deg * 3.141592653589793 / 180;
          final x = (100 + r * math.cos(rad)).round();
          final y = (100 + r * math.sin(rad)).round();
          final diff = _maxChannelDelta(glow, flat, x, y);
          if (diff > maxContrast) {
            maxContrast = diff;
            maxAt = '($x, $y) r=$r';
            peakX = x;
            peakY = y;
          }
        }
      }
      expect(
        maxContrast,
        greaterThanOrEqualTo(minContrast),
        reason: 'peak outside-node contrast on $label at $maxAt',
      );

      if (!isDark) {
        // Light halo must be tinted (brand / tag accent), not a grey/black shadow.
        final spread = _channelSpread(glow, peakX, peakY);
        expect(
          spread,
          greaterThanOrEqualTo(8),
          reason: 'light glow RGB spread (chromatic) at peak $maxAt',
        );
        final glowDelta = _rgbDelta(glow, flat, peakX, peakY);
        final greyDelta = _maxAbs(glowDelta.r, glowDelta.g, glowDelta.b);
        final chromaticDelta = _maxAbs(
          glowDelta.r - glowDelta.g,
          glowDelta.g - glowDelta.b,
          glowDelta.r - glowDelta.b,
        );
        expect(
          chromaticDelta,
          greaterThan(greyDelta * 0.35),
          reason:
              'light glow change vs flat is chromatic at $maxAt '
              '(Δr=${glowDelta.r} Δg=${glowDelta.g} Δb=${glowDelta.b})',
        );
      }
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
  required Color glowColor,
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
      colorForAuthor: (_) => glowColor,
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

int _channelSpread(Uint8List rgba, int x, int y) {
  const width = 200;
  final i = (y * width + x) * 4;
  final r = rgba[i];
  final g = rgba[i + 1];
  final b = rgba[i + 2];
  return math.max(
    math.max((r - g).abs(), (g - b).abs()),
    (r - b).abs(),
  );
}

({int r, int g, int b}) _rgbDelta(Uint8List a, Uint8List b, int x, int y) {
  const width = 200;
  final i = (y * width + x) * 4;
  return (
    r: a[i] - b[i],
    g: a[i + 1] - b[i + 1],
    b: a[i + 2] - b[i + 2],
  );
}

int _maxAbs(int a, int b, int c) =>
    math.max(math.max(a.abs(), b.abs()), c.abs());
