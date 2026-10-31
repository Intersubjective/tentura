import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/platform/web_safe_text_field_enabled.dart';

void main() {
  setUp(() => debugWebTextInputConfigHold = false);
  tearDown(() => debugWebTextInputConfigHold = false);

  test('webSafeTextFieldEnabled passes through when target is enabled', () {
    expect(
      webSafeTextFieldEnabled(targetEnabled: true, hasFocus: true),
      isTrue,
    );
  });

  test(
    'webSafeTextFieldEnabled passes through when the field is unfocused',
    () {
      expect(
        webSafeTextFieldEnabled(targetEnabled: false, hasFocus: false),
        isFalse,
      );
    },
  );

  test('webSafeTextFieldEnabled keeps enabled while focused on web hold', () {
    debugWebTextInputConfigHold = true;
    expect(
      webSafeTextFieldEnabled(targetEnabled: false, hasFocus: true),
      isTrue,
    );
  });

  test(
    'unfocusBeforeReadOnlyFieldLock drops focus on first read-only lock',
    () {
      final node = FocusNode();
      addTearDown(node.dispose);
      node.requestFocus();
      unfocusBeforeReadOnlyFieldLock(
        focusNode: node,
        wasReadOnly: false,
        isReadOnly: true,
      );
      expect(node.hasFocus, isFalse);
    },
  );

  test('unfocusBeforeReadOnlyFieldLock skips when already read-only', () {
    final node = FocusNode();
    addTearDown(node.dispose);
    unfocusBeforeReadOnlyFieldLock(
      focusNode: node,
      wasReadOnly: true,
      isReadOnly: true,
    );
    expect(node.hasFocus, isFalse);
  });
}
