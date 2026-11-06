import 'package:tentura/features/my_work/domain/entity/my_work_filter.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Filter label for the My Desk top bar vs. the filter menu.
///
/// [#1107] On narrow widths the full «Help offered» string ellipsizes to
/// «Help off…»; the chip uses a shorter locale string while the menu keeps the
/// full wording.
String myWorkFilterDisplayLabel(
  L10n l10n,
  MyWorkFilter filter, {
  required bool forTopBarChip,
}) {
  if (forTopBarChip && filter == MyWorkFilter.helpOffered) {
    return l10n.myWorkFilterHelpOfferedChip;
  }
  return switch (filter) {
    MyWorkFilter.active => l10n.myWorkFilterActive,
    MyWorkFilter.all => l10n.myWorkFilterAll,
    MyWorkFilter.authored => l10n.myWorkFilterAuthored,
    MyWorkFilter.helpOffered => l10n.myWorkFilterHelpOffered,
    MyWorkFilter.drafts => l10n.myWorkFilterDrafts,
    MyWorkFilter.archived => l10n.myWorkFilterArchived,
  };
}
