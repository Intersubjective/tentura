import 'package:tentura/ui/l10n/l10n.dart';

/// The localized label for a help offer's withdraw reason wire key
/// (`beacon_help_offers.withdraw_reason`); an unknown key shows as is.
String? withdrawReasonLabel(L10n l10n, String? wireKey) {
  if (wireKey == null || wireKey.isEmpty) return null;
  return switch (wireKey) {
    'cannot_do_it' => l10n.withdrawCantDoIt,
    'timing' => l10n.withdrawTimingChanged,
    'wrong_fit' => l10n.withdrawWrongFit,
    'someone_else' => l10n.withdrawSomeoneElseTookOver,
    'other' => l10n.withdrawOther,
    _ => wireKey,
  };
}
