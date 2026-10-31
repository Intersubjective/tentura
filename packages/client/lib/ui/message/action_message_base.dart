import 'package:tentura/ui/widget/undo_snack_bar.dart';
import 'package:tentura_root/domain/entity/localizable.dart';

export 'package:tentura_root/domain/entity/localizable.dart';

abstract class LocalizableActionMessage extends LocalizableMessage {
  const LocalizableActionMessage();

  LocalizableMessage get label;

  void Function() get onPressed;
}

/// An action message whose action is Undo: it stays as long as the shared
/// Undo bar ([kUndoSnackBarDuration]), longer than an ordinary bar.
abstract class LocalizableUndoMessage extends LocalizableActionMessage {
  const LocalizableUndoMessage();

  Duration get duration => kUndoSnackBarDuration;
}
