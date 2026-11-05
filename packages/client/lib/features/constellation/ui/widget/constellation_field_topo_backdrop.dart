import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_field_backdrop_colors.dart';

import '../../domain/utils/field_topo_contours.dart';

/// Topographic contour backdrop of the Field (#1022).
///
/// Painted inside the graph scene (under the tag hulls), so it moves and
/// scales with the camera for free and a pan or zoom never repaints it. The
/// contour tile is generated once per app run from a fixed seed, in small
/// time slices after the first frame, then baked per zoom band into an alpha
/// mask image that repeats over the whole canvas through an [ImageShader].
/// The theme colour is applied as a [ColorFilter] at paint time, so a theme
/// switch is one repaint and no rebake. A repaint happens only when the zoom
/// band, the theme or the device pixel ratio changes.
class ConstellationFieldTopoBackdrop extends StatefulWidget {
  const ConstellationFieldTopoBackdrop({
    required this.camera,
    required this.cameraScale,
    super.key,
  });

  /// Off in widget tests (`test/flutter_test_config.dart`), so golden and
  /// layout tests stay as they were; a dedicated test turns it on.
  static bool enabled = true;

  /// Key of the backdrop's [CustomPaint].
  static const backdropKey = ValueKey('constellation-field-topo-backdrop');

  /// Paints of the backdrop so far (debug builds only).
  @visibleForTesting
  static int debugPaintCount = 0;

  /// Tile images baked so far (debug builds only).
  @visibleForTesting
  static int debugBakeCount = 0;

  /// Notifies on every camera change (the graph controller's revision).
  final Listenable camera;

  /// Current camera scale.
  final double Function() cameraScale;

  @override
  State<ConstellationFieldTopoBackdrop> createState() =>
      ConstellationFieldTopoBackdropState();
}

/// One baked band tile: an alpha mask image and its repeating shader.
class _BakedTile {
  _BakedTile(this.band, this.rasterScale, this.image)
    : shader = ui.ImageShader(
        image,
        TileMode.repeated,
        TileMode.repeated,
        Float64List.fromList([
          1 / rasterScale, 0, 0, 0, //
          0, 1 / rasterScale, 0, 0, //
          0, 0, 1, 0, //
          0, 0, 0, 1, //
        ]),
        filterQuality: FilterQuality.medium,
      );

  final FieldTopoBand band;
  final double rasterScale;
  final ui.Image image;
  final ui.Shader shader;

  void dispose() {
    shader.dispose();
    image.dispose();
  }
}

/// Time budget of one generation slice on the UI thread.
const _sliceBudget = Duration(milliseconds: 4);

/// Baked tiles a backdrop keeps (the one shown and the one coming).
const _maxBakedTiles = 2;

class ConstellationFieldTopoBackdropState
    extends State<ConstellationFieldTopoBackdrop> {
  /// Shared across backdrops: the tile is the same for everyone.
  static FieldTopoGenerator? _generator;
  static final _segmentsByStride = <int, Float32List>{};
  static final _edgeSegmentsByStride = <int, Float32List>{};

  final _baked = <(FieldTopoBand, double), _BakedTile>{};
  final _baking = <(FieldTopoBand, double)>{};
  late FieldTopoBand _band;
  double _devicePixelRatio = 1;
  _BakedTile? _shown;
  var _driving = false;

  static FieldTopoTile? get _tile {
    final generator = _generator;
    return generator != null && generator.isDone ? generator.result : null;
  }

  /// True once the tile exists and the current band's image is shown.
  @visibleForTesting
  bool get debugIsSettled =>
      _tile != null &&
      _baking.isEmpty &&
      (!_band.isVisible || _shown?.band == _band);

  (FieldTopoBand, double) get _wanted =>
      (_band, _band.rasterScale(_devicePixelRatio));

  @override
  void initState() {
    super.initState();
    _band = fieldTopoBandForZoom(widget.cameraScale());
    widget.camera.addListener(_onCamera);
    // Off the first frame: the Field shows its plain surface first.
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_drive()));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    if (ratio != _devicePixelRatio) {
      _devicePixelRatio = ratio;
      _show();
    }
  }

  @override
  void didUpdateWidget(ConstellationFieldTopoBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.camera != widget.camera) {
      oldWidget.camera.removeListener(_onCamera);
      widget.camera.addListener(_onCamera);
      _onCamera();
    }
  }

  @override
  void dispose() {
    widget.camera.removeListener(_onCamera);
    for (final tile in _baked.values) {
      tile.dispose();
    }
    _baked.clear();
    super.dispose();
  }

  void _onCamera() {
    final band = fieldTopoBandForZoom(widget.cameraScale());
    if (band == _band) return;
    setState(() => _band = band);
    _show();
  }

  /// Steps the shared generator in short slices until the tile exists.
  Future<void> _drive() async {
    if (_driving) return;
    _driving = true;
    final generator = _generator ??= FieldTopoGenerator();
    final watch = Stopwatch();
    while (mounted && !generator.isDone) {
      watch
        ..reset()
        ..start();
      while (watch.elapsed < _sliceBudget && !generator.step()) {}
      if (!generator.isDone) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    _driving = false;
    if (mounted) _show();
  }

  /// Shows the wanted band's tile, baking it first if needed; until it is
  /// ready the previous tile stays up (no blank frame).
  void _show() {
    if (!_band.isVisible) {
      if (_shown != null) setState(() => _shown = null);
      return;
    }
    final wanted = _wanted;
    final ready = _baked[wanted];
    if (ready != null) {
      if (!identical(ready, _shown)) setState(() => _shown = ready);
      return;
    }
    final tile = _tile;
    if (tile != null && !_baking.contains(wanted)) {
      unawaited(_bake(tile, wanted));
    }
  }

  Future<void> _bake(FieldTopoTile tile, (FieldTopoBand, double) key) async {
    _baking.add(key);
    final (band, rasterScale) = key;
    final size = tile.tileSize;
    final segments = _segmentsByStride[band.stride] ??= tile.segmentsForStride(
      band.stride,
    );
    final edges = _edgeSegmentsByStride[band.stride] ??= _nearEdges(
      segments,
      size,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(rasterScale);
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = band.lineWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawRawPoints(ui.PointMode.lines, segments, paint);
    // Strokes crossing an edge continue from the neighbouring tiles.
    for (final dx in [-size, 0.0, size]) {
      for (final dy in [-size, 0.0, size]) {
        if (dx == 0 && dy == 0) continue;
        canvas
          ..save()
          ..translate(dx, dy)
          ..drawRawPoints(ui.PointMode.lines, edges, paint)
          ..restore();
      }
    }
    final picture = recorder.endRecording();
    final side = (size * rasterScale).round();
    final ui.Image image;
    try {
      image = await picture.toImage(side, side);
    } finally {
      picture.dispose();
      _baking.remove(key);
    }
    assert(() {
      ConstellationFieldTopoBackdrop.debugBakeCount++;
      return true;
    }(), 'debug counter');
    if (!mounted) {
      image.dispose();
      return;
    }
    _baked[key]?.dispose();
    _baked[key] = _BakedTile(band, rasterScale, image);
    if (key == _wanted) {
      setState(() => _shown = _baked[key]);
    }
    _evict();
  }

  void _evict() {
    final spare = [
      for (final MapEntry(:key, :value) in _baked.entries)
        if (!identical(value, _shown) && key != _wanted) key,
    ];
    while (_baked.length > _maxBakedTiles && spare.isNotEmpty) {
      _baked.remove(spare.removeAt(0))?.dispose();
    }
  }

  /// Segments within a stroke of a tile edge (largest line width is 3).
  static Float32List _nearEdges(Float32List segments, double size) {
    const margin = 4.0;
    final out = <double>[];
    for (var k = 0; k < segments.length; k += 4) {
      var near = false;
      for (var c = 0; c < 4; c++) {
        final v = segments[k + c];
        if (v < margin || v > size - margin) near = true;
      }
      if (near) out.addAll(segments.sublist(k, k + 4));
    }
    return Float32List.fromList(out);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _band.isVisible ? _shown : null;
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          key: ConstellationFieldTopoBackdrop.backdropKey,
          isComplex: true,
          painter: FieldTopoBackdropPainter(
            shader: shown?.shader,
            color: context.fieldBackdropColors.line,
            band: shown?.band ?? _band,
          ),
        ),
      ),
    );
  }
}

/// Fills its box with the repeating contour tile, tinted with [color].
class FieldTopoBackdropPainter extends CustomPainter {
  const FieldTopoBackdropPainter({
    required this.shader,
    required this.color,
    required this.band,
  });

  /// The baked band tile as a repeating shader; null paints nothing.
  final ui.Shader? shader;

  /// Contour line colour from the design system.
  final Color color;

  /// The zoom band of the tile being painted.
  final FieldTopoBand band;

  @override
  void paint(Canvas canvas, Size size) {
    assert(() {
      ConstellationFieldTopoBackdrop.debugPaintCount++;
      return true;
    }(), 'debug counter');
    final tile = shader;
    if (tile == null) return;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = tile
        ..colorFilter = ColorFilter.mode(color, BlendMode.srcIn),
    );
  }

  @override
  bool shouldRepaint(FieldTopoBackdropPainter oldDelegate) =>
      !identical(shader, oldDelegate.shader) ||
      color != oldDelegate.color ||
      band != oldDelegate.band;
}
