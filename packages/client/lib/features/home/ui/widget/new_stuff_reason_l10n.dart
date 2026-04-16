import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/ui/l10n/l10n.dart';

String l10nInboxNewStuffReason(L10n l10n, InboxNewStuffReason r) => switch (r) {
      InboxNewStuffReason.newForward => l10n.newStuffReasonNewForward,
      InboxNewStuffReason.coordinationStatusChanged =>
        l10n.newStuffReasonCoordinationStatusChanged,
      InboxNewStuffReason.beaconUpdated => l10n.newStuffReasonBeaconUpdated,
    };

String l10nMyWorkNewStuffReason(L10n l10n, MyWorkNewStuffReason r) => switch (r) {
      MyWorkNewStuffReason.newBeacon => l10n.newStuffReasonNewBeacon,
      MyWorkNewStuffReason.authorResponseChanged =>
        l10n.newStuffReasonAuthorResponseChanged,
      MyWorkNewStuffReason.commitmentUpdated =>
        l10n.newStuffReasonCommitmentUpdated,
      MyWorkNewStuffReason.coordinationStatusChanged =>
        l10n.newStuffReasonCoordinationStatusChanged,
      MyWorkNewStuffReason.beaconUpdated => l10n.newStuffReasonBeaconUpdated,
    };

List<String> l10nInboxNewStuffReasons(
  L10n l10n,
  List<InboxNewStuffReason> reasons,
) =>
    [for (final r in reasons) l10nInboxNewStuffReason(l10n, r)];

List<String> l10nMyWorkNewStuffReasons(
  L10n l10n,
  List<MyWorkNewStuffReason> reasons,
) =>
    [for (final r in reasons) l10nMyWorkNewStuffReason(l10n, r)];
