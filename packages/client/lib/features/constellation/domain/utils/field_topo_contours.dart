import 'dart:math' as math;
import 'dart:typed_data';

/// Pure, isolate-safe generator of the Field's topographic backdrop (#1022).
///
/// One seamless square tile of contour lines (isolines) of a periodic
/// gradient-noise field, built from a fixed seed so every launch and every
/// person sees the same terrain. No Flutter imports: the UI rasterises the
/// segments; this file only produces numbers.

/// Side of one backdrop tile in scene units; the tile repeats seamlessly.
const kFieldTopoTileSize = 1024.0;

/// The fixed seed: the same terrain for everyone, on every launch.
const kFieldTopoSeed = 1022;

/// Sample cells per tile side (one sample every 4 scene units).
const kFieldTopoGridCells = 256;

/// Evenly spaced contour levels over the normalised field (0..1).
const kFieldTopoLevelCount = 14;

/// Largest camera scale the Field allows (`GraphView.maxScale`).
const kFieldTopoMaxZoom = 3.0;

/// Smallest on-screen distance, in logical px, allowed between two drawn
/// contour lines (the issue's "no denser than ~1 line per 6 px").
const kFieldTopoMinScreenSpacing = 6.0;

/// Noise octaves as lattice periods per tile; integer periods keep the field
/// periodic in [kFieldTopoTileSize]. Amplitudes halve per octave.
const _octavePeriods = [3, 6, 12];
const _octaveAmplitudes = [1.0, 0.35, 0.1];

/// Zoom band of the backdrop: which levels draw and at what line width.
///
/// Every band spans at most a 2x zoom range, and its tile is baked with a
/// line width of one logical px at the band's geometric-mean zoom, so on
/// screen a line stays between ~0.7 and ~1.4 logical px (hairline) instead of
/// thickening as the camera zooms in.
enum FieldTopoBand {
  /// Far overview: the backdrop is gone.
  hidden(minZoom: 0, stride: 0),

  /// Overview (< 0.45): every 4th level.
  overview(minZoom: 0.25, stride: 4),

  /// District zoom: every 2nd level.
  district(minZoom: 0.45, stride: 2),

  /// Close zoom: every level.
  close(minZoom: 0.9, stride: 1),

  /// Closest zoom: every level, baked thinner and sharper.
  deep(minZoom: 1.8, stride: 1);

  const FieldTopoBand({required this.minZoom, required this.stride});

  /// Smallest camera scale that selects this band.
  final double minZoom;

  /// Every [stride]-th level is drawn; 0 draws nothing.
  final int stride;

  /// Exclusive upper camera scale of this band.
  double get maxZoom =>
      index + 1 < values.length ? values[index + 1].minZoom : kFieldTopoMaxZoom;

  bool get isVisible => stride > 0;

  /// Baked line width in scene units: one logical px at the band's
  /// geometric-mean zoom.
  double get lineWidth => isVisible ? 1 / math.sqrt(minZoom * maxZoom) : 0;

  /// Raster pixels per scene unit for this band's tile image on a screen
  /// with [devicePixelRatio]: enough for the band's mean zoom, in steps of
  /// 0.25 (so the image side is a whole number of px), capped to keep one
  /// image at most 1536 px square.
  double rasterScale(double devicePixelRatio) {
    if (!isVisible) return 0;
    final wanted = math.sqrt(minZoom * maxZoom) * devicePixelRatio;
    final stepped = (wanted * 4).ceil() / 4;
    return stepped.clamp(0.5, 1.5);
  }
}

/// The band the camera at scale [zoom] shows.
FieldTopoBand fieldTopoBandForZoom(double zoom) {
  var band = FieldTopoBand.hidden;
  for (final candidate in FieldTopoBand.values) {
    if (zoom >= candidate.minZoom) band = candidate;
  }
  return band;
}

/// A deterministic 256-entry permutation from [seed] (xorshift32, masked so
/// the VM, dart2js and wasm all produce the same table).
Uint8List _permutation(int seed) {
  var state = (seed * 2654435761 + 0x9E3779B9) & 0xFFFFFFFF;
  if (state == 0) state = 0x6D2B79F5;
  int next() {
    state ^= (state << 13) & 0xFFFFFFFF;
    state ^= state >> 17;
    state ^= (state << 5) & 0xFFFFFFFF;
    state &= 0xFFFFFFFF;
    return state;
  }

  final perm = Uint8List(256);
  for (var i = 0; i < 256; i++) {
    perm[i] = i;
  }
  for (var i = 255; i > 0; i--) {
    final j = next() % (i + 1);
    final t = perm[i];
    perm[i] = perm[j];
    perm[j] = t;
  }
  return perm;
}

const _gradientCount = 16;
final _gradX = Float64List.fromList([
  for (var k = 0; k < _gradientCount; k++)
    math.cos(2 * math.pi * k / _gradientCount),
]);
final _gradY = Float64List.fromList([
  for (var k = 0; k < _gradientCount; k++)
    math.sin(2 * math.pi * k / _gradientCount),
]);

double _fade(double t) => t * t * t * (t * (t * 6 - 15) + 10);

/// Periodic fractal gradient noise; `noise(x, y) == noise(x + tile, y)`.
class FieldTopoNoise {
  FieldTopoNoise({
    this.seed = kFieldTopoSeed,
    this.tileSize = kFieldTopoTileSize,
  }) : _perm = _permutation(seed);

  final int seed;
  final double tileSize;
  final Uint8List _perm;

  int _hash(int ix, int iy, int octave) {
    final a = _perm[(ix + octave * 61) & 255];
    return _perm[(a + iy + octave * 113) & 255] % _gradientCount;
  }

  double _octave(double x, double y, int period, int octave) {
    final u = x / tileSize * period;
    final v = y / tileSize * period;
    final fx = u.floorToDouble();
    final fy = v.floorToDouble();
    final dx = u - fx;
    final dy = v - fy;
    final x0 = fx.toInt() % period;
    final y0 = fy.toInt() % period;
    final x1 = (x0 + 1) % period;
    final y1 = (y0 + 1) % period;
    double corner(int cx, int cy, double ox, double oy) {
      final g = _hash(cx, cy, octave);
      return _gradX[g] * ox + _gradY[g] * oy;
    }

    final n00 = corner(x0, y0, dx, dy);
    final n10 = corner(x1, y0, dx - 1, dy);
    final n01 = corner(x0, y1, dx, dy - 1);
    final n11 = corner(x1, y1, dx - 1, dy - 1);
    final sx = _fade(dx);
    final sy = _fade(dy);
    final top = n00 + (n10 - n00) * sx;
    final bottom = n01 + (n11 - n01) * sx;
    return top + (bottom - top) * sy;
  }

  /// Field value at scene point ([x], [y]).
  double valueAt(double x, double y) {
    var sum = 0.0;
    for (var o = 0; o < _octavePeriods.length; o++) {
      sum += _octaveAmplitudes[o] * _octave(x, y, _octavePeriods[o], o);
    }
    return sum;
  }
}

/// One generated tile: normalised samples and contour segments per level.
class FieldTopoTile {
  FieldTopoTile._({
    required this.tileSize,
    required this.gridCells,
    required this.levelCount,
    required this.samples,
    required this.levels,
  });

  final double tileSize;
  final int gridCells;
  final int levelCount;

  /// `(gridCells + 1)²` samples, row-major, normalised to 0..1; the last row
  /// and column repeat the first (the field is periodic).
  final Float64List samples;

  /// Per level: line segments as `x1, y1, x2, y2` quadruples in scene units
  /// inside `[0, tileSize]²`.
  final List<Float32List> levels;

  double get cellSize => tileSize / gridCells;

  /// Spacing of adjacent levels in normalised field units.
  double get levelStep => 1 / levelCount;

  double sampleAt(int i, int j) => samples[j * (gridCells + 1) + i];

  /// Upper bound of the field's slope (normalised units per scene unit) on
  /// the piecewise-bilinear surface the contours are traced from.
  double get maxGradient {
    var maxDx = 0.0;
    var maxDy = 0.0;
    for (var j = 0; j <= gridCells; j++) {
      for (var i = 0; i < gridCells; i++) {
        final d = (sampleAt(i + 1, j) - sampleAt(i, j)).abs();
        if (d > maxDx) maxDx = d;
        final e = (sampleAt(j, i + 1) - sampleAt(j, i)).abs();
        if (e > maxDy) maxDy = e;
      }
    }
    return math.sqrt(maxDx * maxDx + maxDy * maxDy) / cellSize;
  }

  /// Density proxy: a lower bound, in scene units, on the distance between
  /// two drawn lines of different levels when every [stride]-th level draws.
  /// Two such lines differ by at least `stride * levelStep` in field value,
  /// and the field changes by at most [maxGradient] per scene unit, so they
  /// are at least `stride * levelStep / maxGradient` apart.
  double minLineSpacing(int stride) => stride * levelStep / maxGradient;

  /// The levels drawn at [stride] (every stride-th, starting at level 0).
  Iterable<int> levelsForStride(int stride) sync* {
    if (stride <= 0) return;
    for (var k = 0; k < levelCount; k += stride) {
      yield k;
    }
  }

  /// All segments drawn at [stride], concatenated.
  Float32List segmentsForStride(int stride) {
    final picked = [for (final k in levelsForStride(stride)) levels[k]];
    final out = Float32List(picked.fold(0, (n, l) => n + l.length));
    var offset = 0;
    for (final l in picked) {
      out.setAll(offset, l);
      offset += l.length;
    }
    return out;
  }
}

/// Builds a [FieldTopoTile] in small steps, so the UI can spread the work
/// over idle slices (one sample row or one contour level per [step]).
class FieldTopoGenerator {
  FieldTopoGenerator({
    int seed = kFieldTopoSeed,
    this.tileSize = kFieldTopoTileSize,
    this.gridCells = kFieldTopoGridCells,
    this.levelCount = kFieldTopoLevelCount,
  }) : _noise = FieldTopoNoise(seed: seed, tileSize: tileSize),
       _samples = Float64List((gridCells + 1) * (gridCells + 1));

  final double tileSize;
  final int gridCells;
  final int levelCount;
  final FieldTopoNoise _noise;
  final Float64List _samples;
  final _levels = <Float32List>[];
  var _row = 0;
  var _normalised = false;
  FieldTopoTile? _result;

  bool get isDone => _result != null;

  /// The finished tile; only valid once [isDone].
  FieldTopoTile get result => _result!;

  /// Does one bounded piece of work; returns [isDone].
  bool step() {
    if (_result != null) return true;
    final n = gridCells + 1;
    final cell = tileSize / gridCells;
    if (_row < n) {
      // Row `gridCells` samples y == tileSize, i.e. row 0 again.
      final y = (_row % gridCells) * cell;
      for (var i = 0; i < n; i++) {
        _samples[_row * n + i] = _noise.valueAt((i % gridCells) * cell, y);
      }
      _row++;
      return false;
    }
    if (!_normalised) {
      var lo = double.infinity;
      var hi = double.negativeInfinity;
      for (final v in _samples) {
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
      final span = hi - lo;
      for (var k = 0; k < _samples.length; k++) {
        _samples[k] = span == 0 ? 0 : (_samples[k] - lo) / span;
      }
      _normalised = true;
      return false;
    }
    if (_levels.length < levelCount) {
      _levels.add(_trace((_levels.length + 0.5) / levelCount));
      return false;
    }
    _result = FieldTopoTile._(
      tileSize: tileSize,
      gridCells: gridCells,
      levelCount: levelCount,
      samples: _samples,
      levels: List.unmodifiable(_levels),
    );
    return true;
  }

  /// Runs every step at once (for isolates and tests).
  FieldTopoTile run() {
    while (!step()) {}
    return result;
  }

  /// Marching squares for one threshold over the sample grid.
  Float32List _trace(double t) {
    final n = gridCells + 1;
    final cell = tileSize / gridCells;
    final out = <double>[];
    double lerp(double a, double b) => (t - a) / (b - a);
    for (var j = 0; j < gridCells; j++) {
      for (var i = 0; i < gridCells; i++) {
        final a = _samples[j * n + i]; // top-left
        final b = _samples[j * n + i + 1]; // top-right
        final c = _samples[(j + 1) * n + i + 1]; // bottom-right
        final d = _samples[(j + 1) * n + i]; // bottom-left
        final code =
            (a > t ? 8 : 0) |
            (b > t ? 4 : 0) |
            (c > t ? 2 : 0) |
            (d > t ? 1 : 0);
        if (code == 0 || code == 15) continue;
        final x0 = i * cell;
        final y0 = j * cell;
        // Edge crossings: top, right, bottom, left.
        double topX() => x0 + lerp(a, b) * cell;
        double rightY() => y0 + lerp(b, c) * cell;
        double bottomX() => x0 + lerp(d, c) * cell;
        double leftY() => y0 + lerp(a, d) * cell;
        void seg(double ax, double ay, double bx, double by) =>
            out.addAll([ax, ay, bx, by]);
        void topLeft() => seg(topX(), y0, x0, leftY());
        void topRight() => seg(topX(), y0, x0 + cell, rightY());
        void bottomLeft() => seg(bottomX(), y0 + cell, x0, leftY());
        void bottomRight() => seg(bottomX(), y0 + cell, x0 + cell, rightY());
        void vertical() => seg(topX(), y0, bottomX(), y0 + cell);
        void horizontal() => seg(x0, leftY(), x0 + cell, rightY());
        switch (code) {
          case 1 || 14:
            bottomLeft();
          case 2 || 13:
            bottomRight();
          case 3 || 12:
            horizontal();
          case 4 || 11:
            topRight();
          case 6 || 9:
            vertical();
          case 7 || 8:
            topLeft();
          case 5 || 10:
            // Saddle: the cell centre decides which corners connect.
            final centreHigh = (a + b + c + d) / 4 > t;
            final aHigh = code == 10;
            if (centreHigh == aHigh) {
              // a and c joined through the centre.
              topRight();
              bottomLeft();
            } else {
              topLeft();
              bottomRight();
            }
        }
      }
    }
    return Float32List.fromList(out);
  }
}

/// The tile for [seed], generated in one go (isolate entry point).
FieldTopoTile generateFieldTopoTile([int seed = kFieldTopoSeed]) =>
    FieldTopoGenerator(seed: seed).run();
