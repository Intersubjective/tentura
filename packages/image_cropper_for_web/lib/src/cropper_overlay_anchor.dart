import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Positions a Cropper.js root [overlayElement] on `document.body` so it
/// aligns with this widget's screen rect.
///
/// HtmlElementView platform views do not receive pointer events under Flutter
/// web's skwasm renderer (flutter/flutter#166357). Mounting the cropper as a
/// body-level fixed overlay bypasses platform-view compositing.
class CropperOverlayAnchor extends StatefulWidget {
  const CropperOverlayAnchor({
    super.key,
    required this.overlayElement,
    required this.width,
    required this.height,
    required this.onLayoutReady,
  });

  final web.HTMLDivElement overlayElement;
  final double width;
  final double height;

  /// Called once the anchor has a stable layout (after first frame).
  final VoidCallback onLayoutReady;

  @override
  State<CropperOverlayAnchor> createState() => _CropperOverlayAnchorState();
}

class _CropperOverlayAnchorState extends State<CropperOverlayAnchor> {
  JSFunction? _resizeListener;
  Animation<double>? _routeAnimation;
  var _layoutReadyNotified = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverlay());
    _resizeListener = ((web.Event _) => _syncOverlay()).toJS;
    web.window.addEventListener('resize', _resizeListener);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeAnimation?.removeListener(_syncOverlay);
    _routeAnimation = ModalRoute.of(context)?.animation;
    _routeAnimation?.addListener(_syncOverlay);
  }

  @override
  void dispose() {
    _routeAnimation?.removeListener(_syncOverlay);
    if (_resizeListener != null) {
      web.window.removeEventListener('resize', _resizeListener);
    }
    widget.overlayElement.remove();
    super.dispose();
  }

  void _syncOverlay() {
    if (!mounted) {
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return;
    }

    final offset = box.localToGlobal(Offset.zero);
    final el = widget.overlayElement;
    el.style.position = 'fixed';
    el.style.left = '${offset.dx}px';
    el.style.top = '${offset.dy}px';
    el.style.width = '${box.size.width}px';
    el.style.height = '${box.size.height}px';
    el.style.zIndex = '9999';
    el.style.pointerEvents = 'auto';
    el.style.backgroundColor = 'transparent';

    final body = web.document.body;
    if (body != null && !body.contains(el)) {
      body.appendChild(el);
    }

    if (!_layoutReadyNotified) {
      _layoutReadyNotified = true;
      widget.onLayoutReady();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
    );
  }
}
