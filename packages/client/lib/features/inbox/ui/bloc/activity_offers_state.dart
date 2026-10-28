import 'package:tentura/domain/attention/entity/activity_offer_beacon_meta.dart';
import 'package:tentura/domain/entity/author_invite.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/inbox_item.dart';

export 'package:tentura/domain/attention/entity/activity_offer_beacon_meta.dart';
export 'package:tentura/ui/bloc/state_base.dart';

part 'activity_offers_state.freezed.dart';

@freezed
abstract class ActivityOffersState extends StateBase
    with _$ActivityOffersState {
  const factory ActivityOffersState({
    @Default([]) List<InboxItem> items,
    @Default(false) bool firstLoadDone,
    int? totalCount,
    @Default(false) bool countLoadFailed,
    @Default(false) bool pageLoadFailed,
    @Default(true) bool hasMore,
    @Default(false) bool loadingMore,
    @Default(<String>{}) Set<String> heldBackIds,
    String? pendingMovedToStreamBeaconId,
    @Default(<String>{}) Set<String> unseenBeaconIds,
    @Default(false) bool unseenQueryComplete,
    @Default(<String, ActivityOfferBeaconMeta>{})
    Map<String, ActivityOfferBeaconMeta> eventsByBeacon,
    @Default(<String, Profile>{}) Map<String, Profile> actors,
    String? offersNextCursor,

    /// Plan D3: the viewer's pending author invite per pinned Request (from
    /// the zone rows' `inviteId`). A row listed here renders the invite card.
    @Default(<String, String>{}) Map<String, String> inviteIdByBeacon,

    /// Invite details (inviter, note) by invite id, from
    /// `myPendingAuthorInvites`; best-effort, the card renders without them.
    @Default(<String, PendingAuthorInvite>{})
    Map<String, PendingAuthorInvite> invites,

    /// Inviter profiles by user id, for the invite card.
    @Default(<String, Profile>{}) Map<String, Profile> inviters,

    /// #725: Requests whose author invitation the viewer answered «Can't make
    /// it» (the rows' `declinedInvite`, and declines made here). Their plain
    /// card keeps the invitation's words: «Can't make it» → "Can't make it?".
    @Default(<String>{}) Set<String> declinedInviteBeacons,
    @Default(StateIsLoading()) StateStatus status,
  }) = _ActivityOffersState;

  const ActivityOffersState._();
}
