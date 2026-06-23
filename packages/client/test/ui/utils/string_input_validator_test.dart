import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/string_input_validator.dart';

class _Validator with StringInputValidator {}

void main() {
  final validator = _Validator();
  final l10n = lookupL10n(const Locale('en'));

  group('invitationCodeValidator', () {
    test('accepts valid code', () {
      expect(
        validator.invitationCodeValidator(l10n, 'I${'a' * (kIdLength - 1)}'),
        isNull,
      );
    });

    test('rejects null and short codes', () {
      expect(
        validator.invitationCodeValidator(l10n, null),
        l10n.invitationCodeTooShort,
      );
      expect(
        validator.invitationCodeValidator(l10n, 'I123'),
        l10n.invitationCodeTooShort,
      );
    });

    test('rejects codes longer than title max', () {
      expect(
        validator.invitationCodeValidator(l10n, 'I${'a' * kTitleMaxLength}'),
        l10n.invitationCodeTooLong,
      );
    });

    test('rejects codes not starting with I', () {
      expect(
        validator.invitationCodeValidator(l10n, 'X${'a' * (kIdLength - 1)}'),
        l10n.invitationCodeWrongFormat,
      );
    });
  });

  group('titleValidator', () {
    test('accepts valid title', () {
      expect(validator.titleValidator(l10n, 'abc'), isNull);
    });

    test('rejects too short and too long titles', () {
      expect(validator.titleValidator(l10n, 'ab'), l10n.titleTooShort);
      expect(
        validator.titleValidator(l10n, 'a' * (kTitleMaxLength + 1)),
        l10n.titleTooLong,
      );
    });
  });

  group('beaconDescriptionValidator', () {
    test('rejects empty and whitespace-only descriptions', () {
      expect(
        validator.beaconDescriptionValidator(l10n, null),
        l10n.beaconDescriptionRequired,
      );
      expect(
        validator.beaconDescriptionValidator(l10n, '   '),
        l10n.beaconDescriptionRequired,
      );
    });

    test('accepts trimmed non-empty description', () {
      expect(validator.beaconDescriptionValidator(l10n, '  Need help  '), isNull);
    });

    test('rejects descriptions over beacon max length', () {
      expect(
        validator.beaconDescriptionValidator(
          l10n,
          'a' * (kBeaconDescriptionMaxLength + 1),
        ),
        l10n.beaconDescriptionTooLong(kBeaconDescriptionMaxLength),
      );
    });
  });
}
