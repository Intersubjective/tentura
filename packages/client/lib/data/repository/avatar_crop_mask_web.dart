import 'package:web/web.dart' as web;

const _kAvatarCropBodyClass = 'tentura-avatar-crop';

/// Toggles circular cropperjs preview on web (see `web/index.html`).
void setAvatarCropMaskEnabled(bool enabled) {
  final body = web.document.body;
  if (body == null) {
    return;
  }
  if (enabled) {
    body.classList.add(_kAvatarCropBodyClass);
  } else {
    body.classList.remove(_kAvatarCropBodyClass);
  }
}
