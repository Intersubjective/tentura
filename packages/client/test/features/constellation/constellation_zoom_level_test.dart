import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';

void main() {
  test('semantic zoom stays gated off by default', () {
    expect(kFieldSemanticZoomEnabled, isFalse);
  });

  group('settledConstellationDetailLevel', () {
    test('levels are close, district and overview', () {
      expect(
        ConstellationDetailLevel.values.map((e) => e.name),
        ['close', 'district', 'overview'],
      );
    });

    test('splits at 0.85 and 0.45, lower bound inclusive', () {
      expect(
        settledConstellationDetailLevel(0.85),
        ConstellationDetailLevel.close,
      );
      expect(
        settledConstellationDetailLevel(2),
        ConstellationDetailLevel.close,
      );
      expect(
        settledConstellationDetailLevel(0.8499),
        ConstellationDetailLevel.district,
      );
      expect(
        settledConstellationDetailLevel(0.45),
        ConstellationDetailLevel.district,
      );
      expect(
        settledConstellationDetailLevel(0.4499),
        ConstellationDetailLevel.overview,
      );
      expect(
        settledConstellationDetailLevel(0.1),
        ConstellationDetailLevel.overview,
      );
    });
  });

  group('label policy across levels', () {
    bool candidate(ConstellationDetailLevel d, int priority, int ring) =>
        constellationLabelCandidateForDetail(
          detail: d,
          priority: priority,
          ring: ring,
        );

    test('labels never disappear when zooming in', () {
      for (var priority = 0; priority <= 4; priority++) {
        for (var ring = 0; ring <= 4; ring++) {
          final o = candidate(ConstellationDetailLevel.overview, priority, ring);
          final d = candidate(ConstellationDetailLevel.district, priority, ring);
          final c = candidate(ConstellationDetailLevel.close, priority, ring);
          if (o) expect(d, isTrue, reason: 'p$priority r$ring');
          if (d) expect(c, isTrue, reason: 'p$priority r$ring');
        }
      }
    });

    test('label count is monotonic in scale between 0.3 and 0.85', () {
      int count(double scale) {
        final level = settledConstellationDetailLevel(scale);
        var n = 0;
        for (var priority = 0; priority <= 4; priority++) {
          for (var ring = 0; ring <= 4; ring++) {
            if (constellationLabelCandidateForDetail(
              detail: level,
              priority: priority,
              ring: ring,
            )) {
              n++;
            }
          }
        }
        return n;
      }

      var previous = count(0.3);
      for (var i = 31; i <= 85; i++) {
        final now = count(i / 100);
        expect(now, greaterThanOrEqualTo(previous), reason: 'scale ${i / 100}');
        previous = now;
      }
    });
  });
}
