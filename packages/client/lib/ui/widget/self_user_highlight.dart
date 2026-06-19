import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Visual treatment when a [Profile] is the signed-in viewer.
abstract final class SelfUserHighlight {
  SelfUserHighlight._();

  static bool profileIsSelf(Profile profile, String viewerUserId) =>
      profile.id.isNotEmpty &&
      viewerUserId.isNotEmpty &&
      profile.id == viewerUserId;

  /// Accent label for the current user (distinct from [L10n.labelMe]).
  static String displayName(L10n l10n, Profile profile, String viewerUserId) =>
      profileIsSelf(profile, viewerUserId) ? l10n.labelYou : profile.shownName;

  static TextStyle selfNameStyle(ThemeData theme) {
    final scheme = theme.colorScheme;
    return TextStyle(
      color: scheme.primary,
      fontWeight: FontWeight.w600,
    );
  }

  /// Merges [base] with [selfNameStyle] when [isSelf].
  static TextStyle nameStyle(
    ThemeData theme,
    TextStyle? base,
    bool isSelf,
  ) {
    if (!isSelf) {
      return base ?? const TextStyle();
    }
    return (base ?? theme.textTheme.bodyMedium!).merge(selfNameStyle(theme));
  }
}
