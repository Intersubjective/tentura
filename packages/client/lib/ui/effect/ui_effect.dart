import 'package:tentura_root/domain/entity/localizable.dart';

/// One-shot UI side effect emitted by cubits and consumed by [UiEffectHandler].
sealed class UiEffect {
  const UiEffect();
}

/// Push an absolute route path on the root router.
final class NavigatePush extends UiEffect {
  const NavigatePush(this.path);

  final String path;
}

/// Pop the current route; optional [result] for dialog/fullscreen flows.
final class NavigateBack extends UiEffect {
  const NavigateBack({this.result});

  final Object? result;
}

/// Replace the entire navigation stack with a known root target.
final class NavigateReplace extends UiEffect {
  const NavigateReplace(this.target);

  final NavigateReplaceTarget target;
}

/// Known replace-all targets handled by the root adapter.
enum NavigateReplaceTarget {
  home,
  authLogin,
}

final class ShowMessage extends UiEffect {
  const ShowMessage(this.message);

  final LocalizableMessage message;
}

final class ShowError extends UiEffect {
  const ShowError(this.error);

  final Object error;
}
