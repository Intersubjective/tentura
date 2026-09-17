import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'package:image_cropper_platform_interface/image_cropper_platform_interface.dart';

import 'cropper_editor_scaffold.dart';
import 'cropper_overlay_anchor.dart';

class CropperPage extends StatelessWidget {
  final web.HTMLDivElement overlayElement;
  final Function() initCropper;
  final Future<String?> Function() crop;
  final void Function(RotationAngle) rotate;
  final void Function(num) scale;
  final double cropperContainerWidth;
  final double cropperContainerHeight;
  final WebTranslations translations;
  final WebThemeData? themeData;

  const CropperPage({
    super.key,
    required this.overlayElement,
    required this.initCropper,
    required this.crop,
    required this.rotate,
    required this.scale,
    required this.cropperContainerWidth,
    required this.cropperContainerHeight,
    required this.translations,
    this.themeData,
  });

  @override
  Widget build(BuildContext context) {
    final maxSide = cropperContainerWidth < cropperContainerHeight
        ? cropperContainerWidth
        : cropperContainerHeight;
    return CropperEditorScaffold(
      translations: translations,
      maxCanvasSide: maxSide,
      themeData: themeData,
      onCrop: crop,
      onRotate: rotate,
      onScale: scale,
      canvasBuilder: (context, side) => CropperOverlayAnchor(
        overlayElement: overlayElement,
        width: side,
        height: side,
        onLayoutReady: initCropper,
      ),
    );
  }
}
