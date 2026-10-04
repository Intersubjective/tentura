import 'package:flutter/services.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/invitation/domain/invite_code.dart';

/// Partial invite code while typing (`I` + up to 12 hex digits).
final kPartialInviteCodeRegExp = RegExp(r'^I[a-f0-9]{0,12}$');

/// Partial entity id while typing (`U`/`B`/`C`/`I` + up to 12 hex digits).
final kPartialEntityIdRegExp = RegExp(r'^[UBCI][0-9a-f]{0,12}$');

bool _looksLikePastedUrlOrLink(String text) =>
    text.contains('://') ||
    text.contains('/invite/') ||
    text.contains('/profile/view/') ||
    text.contains('/beacon/view/') ||
    text.contains('?id=');

/// Normalizes keyboard/context-menu paste of invite links into a bare code and
/// allows progressive `I…` entry. Replaces per-character [FilteringTextInputFormatter]
/// which strips pasted URLs down to a lone `I`.
class InviteCodeInputFormatter extends TextInputFormatter {
  const InviteCodeInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) {
      return newValue;
    }

    if (_looksLikePastedUrlOrLink(text) ||
        (text.length > kIdLength && !kPartialInviteCodeRegExp.hasMatch(text))) {
      final extracted = extractInviteCodeFromText(text, prefix: 'I');
      if (extracted != null) {
        return TextEditingValue(
          text: extracted,
          selection: TextSelection.collapsed(offset: extracted.length),
        );
      }
    }

    if (kPartialInviteCodeRegExp.hasMatch(text)) {
      return newValue;
    }

    return oldValue;
  }
}

/// Paste normalization for any shareable link (profile / request / invite)
/// plus manual entry of profile/beacon/coordination ids (`U`/`B`/`C`/`I`).
class EntityIdInputFormatter extends TextInputFormatter {
  const EntityIdInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) {
      return newValue;
    }

    if (_looksLikePastedUrlOrLink(text)) {
      final extracted = extractEntityIdFromText(text);
      if (extracted != null) {
        return TextEditingValue(
          text: extracted,
          selection: TextSelection.collapsed(offset: extracted.length),
        );
      }
    }

    if (kPartialEntityIdRegExp.hasMatch(text)) {
      return newValue;
    }

    return oldValue;
  }
}
