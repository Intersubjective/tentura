import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Test-only: exercise the web input-config hold branch on the VM runner.
@visibleForTesting
bool debugWebTextInputConfigHold = false;

bool get _holdWebInputConfig => kIsWeb || debugWebTextInputConfigHold;

/// Whether TextField.enabled should be true for this build.
///
/// On Flutter web, EditableText calls updateConfig when readOnly changes while
/// the connection is open. If the engine strategy DOM element was torn down,
/// DefaultTextEditingStrategy.applyConfiguration uses domElement! and crashes
/// (#862).
bool webSafeTextFieldEnabled({
  required bool targetEnabled,
  required bool hasFocus,
}) {
  if (targetEnabled || !_holdWebInputConfig || !hasFocus) {
    return targetEnabled;
  }
  return true;
}

/// Unfocus before the field locks read-only so web never applies a config
/// change on an active connection.
void unfocusBeforeReadOnlyFieldLock({
  required FocusNode focusNode,
  required bool wasReadOnly,
  required bool isReadOnly,
}) {
  if (!wasReadOnly && isReadOnly && focusNode.hasFocus) {
    focusNode.unfocus();
  }
}
