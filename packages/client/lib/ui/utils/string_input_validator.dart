import 'package:tentura/ui/l10n/l10n.dart';

import 'package:tentura/consts.dart';

mixin StringInputValidator {
  String? invitationCodeValidator(L10n l10n, String? code) {
    if (code == null || code.length < kIdLength) {
      return l10n.invitationCodeTooShort;
    }
    if (code.length > kTitleMaxLength) {
      return l10n.invitationCodeTooLong;
    }
    if (!code.startsWith('I')) {
      return l10n.invitationCodeWrongFormat;
    }
    return null;
  }

  String? titleValidator(L10n l10n, String? title) {
    if (title == null || title.length < kTitleMinLength) {
      return l10n.titleTooShort;
    }
    if (title.length > kTitleMaxLength) {
      return l10n.titleTooLong;
    }
    return null;
  }

  String? beaconTitleValidator(L10n l10n, String? title) {
    if (title == null || title.length < kTitleMinLength) {
      return l10n.titleTooShort;
    }
    if (title.length > kBeaconTitleMaxLength) {
      return l10n.titleTooLong;
    }
    return null;
  }

  String? descriptionValidator(L10n l10n, String? description) {
    if (description != null && description.length > kDescriptionMaxLength) {
      return l10n.descriptionTooLong;
    }
    return null;
  }

  String? beaconDescriptionValidator(L10n l10n, String? description) {
    final t = (description ?? '').trim();
    if (t.isEmpty) {
      return l10n.beaconDescriptionRequired;
    }
    if (t.length > kBeaconDescriptionMaxLength) {
      return l10n.beaconDescriptionTooLong(kBeaconDescriptionMaxLength);
    }
    return null;
  }
}
