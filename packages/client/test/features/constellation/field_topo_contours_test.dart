import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/domain/util/field_topo_contours.dart';

/// Endpoint coordinates (the other axis) of segments touching a tile edge.
List<double> _edgeHits(
  FieldTopoTile tile,
  int level, {
  required bool vertical,
  required double at,
}) {
  final s = tile.levels[level];
  final hits = <double>[];
  for (var k = 0; k < s.length; k += 2) {
    final x = s[k];
    final y = s[k + 1];
    if (vertical && (x - at).abs() < 1e-3) hits.add(y);
    if (!vertical && (y - at).abs() < 1e-3) hits.add(x);
  }
  return hits..sort();
}

void main() {
  late FieldTopoTile tile;

  setUpAll(() {
    tile = generateFieldTopoTile();
  });

  group('Field topographic backdrop generator (#1022)', () {
    test('the same seed gives the same tile', () {
      final again = generateFieldTopoTile();
      expect(again.samples, tile.samples);
      expect(again.levels.length, tile.levels.length);
      for (var k = 0; k < tile.levels.length; k++) {
        expect(again.levels[k], tile.levels[k], reason: 'level $k');
      }
    });

    test('another seed gives another tile', () {
      final other = generateFieldTopoTile(kFieldTopoSeed + 1);
      expect(other.samples, isNot(tile.samples));
    });

    test('the noise field is periodic in the tile size', () {
      final noise = FieldTopoNoise();
      for (final (x, y) in [(0.0, 0.0), (13.5, 700.25), (511.0, 3.0)]) {
        final v = noise.valueAt(x, y);
        expect(noise.valueAt(x + kFieldTopoTileSize, y), closeTo(v, 1e-9));
        expect(noise.valueAt(x, y + kFieldTopoTileSize), closeTo(v, 1e-9));
        expect(
          noise.valueAt(x - kFieldTopoTileSize, y + 2 * kFieldTopoTileSize),
          closeTo(v, 1e-9),
        );
      }
    });

    test('the last sample row and column repeat the first', () {
      final n = tile.gridCells;
      for (var i = 0; i <= n; i++) {
        expect(tile.sampleAt(i, n), tile.sampleAt(i, 0));
        expect(tile.sampleAt(n, i), tile.sampleAt(0, i));
      }
    });

    test('contours meet seamlessly across the tile edges', () {
      final size = tile.tileSize;
      var crossings = 0;
      for (var level = 0; level < tile.levelCount; level++) {
        final left = _edgeHits(tile, level, vertical: true, at: 0);
        final right = _edgeHits(tile, level, vertical: true, at: size);
        expect(right.length, left.length, reason: 'level $level left/right');
        for (var k = 0; k < left.length; k++) {
          expect(right[k], closeTo(left[k], 1e-3));
        }
        final top = _edgeHits(tile, level, vertical: false, at: 0);
        final bottom = _edgeHits(tile, level, vertical: false, at: size);
        expect(bottom.length, top.length, reason: 'level $level top/bottom');
        for (var k = 0; k < top.length; k++) {
          expect(bottom[k], closeTo(top[k], 1e-3));
        }
        crossings += left.length + top.length;
      }
      // The check is not vacuous: lines do cross the edges.
      expect(crossings, greaterThan(10));
    });

    test('every level has lines and all segments stay inside the tile', () {
      for (var level = 0; level < tile.levelCount; level++) {
        final s = tile.levels[level];
        expect(s, isNotEmpty, reason: 'level $level');
        for (final v in s) {
          expect(v, inInclusiveRange(-1e-3, tile.tileSize + 1e-3));
        }
      }
    });

    test('LOD band by zoom: close, district, overview and gone', () {
      expect(fieldTopoBandForZoom(3), FieldTopoBand.deep);
      expect(fieldTopoBandForZoom(1.8), FieldTopoBand.deep);
      expect(fieldTopoBandForZoom(1), FieldTopoBand.close);
      expect(fieldTopoBandForZoom(0.9), FieldTopoBand.close);
      expect(fieldTopoBandForZoom(0.89), FieldTopoBand.district);
      expect(fieldTopoBandForZoom(0.45), FieldTopoBand.district);
      expect(fieldTopoBandForZoom(0.44), FieldTopoBand.overview);
      expect(fieldTopoBandForZoom(0.25), FieldTopoBand.overview);
      expect(fieldTopoBandForZoom(0.2), FieldTopoBand.hidden);
      expect(fieldTopoBandForZoom(0.1), FieldTopoBand.hidden);

      expect(FieldTopoBand.close.stride, 1);
      expect(FieldTopoBand.deep.stride, 1);
      expect(FieldTopoBand.district.stride, 2);
      expect(FieldTopoBand.overview.stride, 4);
      expect(FieldTopoBand.hidden.isVisible, isFalse);
    });

    test("coarser bands draw a subset of the finer bands' levels", () {
      final close = tile.levelsForStride(1).toSet();
      final district = tile.levelsForStride(2).toSet();
      final overview = tile.levelsForStride(4).toSet();
      expect(close.containsAll(district), isTrue);
      expect(district.containsAll(overview), isTrue);
      expect(overview.length, lessThan(district.length));
      expect(district.length, lessThan(close.length));
      expect(tile.levelsForStride(0), isEmpty);
    });

    test('no band draws lines closer than 6 logical px on screen', () {
      // Proxy: minLineSpacing(stride) is a lower bound (scene units) on the
      // distance between two drawn lines of different levels; at the band's
      // smallest zoom it is smallest on screen.
      for (final band in FieldTopoBand.values.where((b) => b.isVisible)) {
        final screenSpacing = tile.minLineSpacing(band.stride) * band.minZoom;
        expect(
          screenSpacing,
          greaterThanOrEqualTo(kFieldTopoMinScreenSpacing),
          reason: '$band',
        );
      }
    });

    test('bands span at most 2x zoom and keep the line near hairline', () {
      for (final band in FieldTopoBand.values.where((b) => b.isVisible)) {
        expect(band.maxZoom / band.minZoom, lessThanOrEqualTo(2.0));
        // On-screen width across the band: lineWidth * zoom.
        expect(band.lineWidth * band.minZoom, inInclusiveRange(0.6, 1.0));
        expect(band.lineWidth * band.maxZoom, inInclusiveRange(1.0, 1.5));
      }
    });

    test('raster scale gives whole-pixel tiles and stays bounded', () {
      for (final band in FieldTopoBand.values.where((b) => b.isVisible)) {
        for (final dpr in [1.0, 2.0, 3.0]) {
          final r = band.rasterScale(dpr);
          expect(r, inInclusiveRange(0.5, 1.5));
          final side = kFieldTopoTileSize * r;
          expect(side, side.roundToDouble());
        }
      }
    });

    test('the generator works in bounded steps', () {
      final generator = FieldTopoGenerator();
      var steps = 0;
      while (!generator.step()) {
        steps++;
      }
      expect(steps, greaterThan(kFieldTopoGridCells));
      expect(generator.result.samples, tile.samples);
    });
  });
}
