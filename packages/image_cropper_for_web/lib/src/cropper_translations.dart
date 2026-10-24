import 'package:image_cropper_platform_interface/image_cropper_platform_interface.dart';

/// [WebTranslations] plus the strings our cropper chrome adds (zoom slider).
///
/// Web-import-free so VM widget tests can use it.
class CropperWebTranslations extends WebTranslations {
  const CropperWebTranslations({
    required super.title,
    required super.rotateLeftTooltip,
    required super.rotateRightTooltip,
    required super.cancelButton,
    required super.cropButton,
    this.zoomLabel = defaultZoomLabel,
    this.cropErrorMessage = defaultCropErrorMessage,
  });

  static const defaultZoomLabel = 'Zoom';

  static const defaultCropErrorMessage =
      'Could not save the image. Please try again.';

  /// Label (text + semantics) of the zoom slider.
  final String zoomLabel;

  /// SnackBar text shown when saving the crop fails.
  final String cropErrorMessage;
}
