import 'dart:math' show min;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:image_cropper/image_cropper.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/domain/entity/image_picked.dart';
import 'package:tentura/domain/port/beacon_image_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Platform crop chrome for the request cover, bound to a live [BuildContext]
/// because the web cropper needs an element host.
class BeaconCoverCropUi implements ImageCropUiPort {
  BeaconCoverCropUi(this._context, this._l10n, {ImageRepository? images})
    : _images = images ?? GetIt.I<ImageRepository>();

  final BuildContext _context;
  final L10n _l10n;
  final ImageRepository _images;

  @override
  Future<ImagePicked?> cropSquare(Uint8List bytes) =>
      _images.cropImageBytes(bytes, _uiSettings());

  List<PlatformUiSettings> _uiSettings() {
    final title = _l10n.beaconCoverAdjust;
    final webSide = _webSide();
    return [
      AndroidUiSettings(
        toolbarTitle: title,
        lockAspectRatio: true,
        initAspectRatio: CropAspectRatioPreset.square,
        aspectRatioPresets: const [CropAspectRatioPreset.square],
      ),
      IOSUiSettings(
        title: title,
        aspectRatioLockEnabled: true,
        aspectRatioPickerButtonHidden: true,
        resetAspectRatioEnabled: false,
        aspectRatioPresets: const [CropAspectRatioPreset.square],
      ),
      WebUiSettings(
        context: _context,
        presentStyle: WebPresentStyle.page,
        size: CropperSize(width: webSide, height: webSide),
        viewwMode: WebViewMode.mode_1,
        dragMode: WebDragMode.move,
        checkCrossOrigin: false,
        translations: WebTranslations(
          title: title,
          rotateLeftTooltip: _l10n.cropRotateLeftTooltip,
          rotateRightTooltip: _l10n.cropRotateRightTooltip,
          cancelButton: _l10n.buttonCancel,
          cropButton: _l10n.buttonCrop,
        ),
      ),
    ];
  }

  /// Fits the viewport so the default web dialog layout does not overflow.
  int _webSide() {
    final size = MediaQuery.sizeOf(_context);
    const horizontalPadding = 24.0;
    const bottomChrome = 140.0;
    final top = MediaQuery.paddingOf(_context).top + kToolbarHeight;
    final bottom = MediaQuery.paddingOf(_context).bottom + bottomChrome;
    final byHeight = (size.height - top - bottom).floor();
    final byWidth = (size.width - 2 * horizontalPadding).floor();
    return min(byHeight, byWidth).clamp(200, 500);
  }
}
