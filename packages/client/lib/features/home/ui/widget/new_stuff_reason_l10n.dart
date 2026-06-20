import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/ui/l10n/l10n.dart';

String l10nInboxNewStuffReason(L10n l10n, InboxNewStuffReason r) => switch (r) {
      InboxNewStuffReason.newForward => l10n.newStuffReasonNewForward,
      InboxNewStuffReason.coordinationStatusChanged =>
        l10n.newStuffReasonCoordinationStatusChanged,
      InboxNewStuffReason.beaconUpdated => l10n.newStuffReasonBeaconUpdated,
    };

List<String> l10nInboxNewStuffReasons(
  L10n l10n,
  List<InboxNewStuffReason> reasons,
) =>
    [for (final r in reasons) l10nInboxNewStuffReason(l10n, r)];
