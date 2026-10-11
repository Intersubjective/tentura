part of 'beacon_author_invites_cubit.dart';

/// A refused «Позвать» (the server answered with an outcome other than
/// invited). [seq] makes every refusal a distinct state for a listener.
@freezed
abstract class BeaconAuthorInviteRefusal with _$BeaconAuthorInviteRefusal {
  const factory BeaconAuthorInviteRefusal({
    required String userId,
    required PostBudInviteOutcome outcome,
    required int seq,
  }) = _BeaconAuthorInviteRefusal;
}

/// One person in the author's invites section.
@freezed
abstract class BeaconAuthorInviteRow with _$BeaconAuthorInviteRow {
  const factory BeaconAuthorInviteRow({
    required String userId,
    required bool canInvite,
    Profile? profile,

    /// The person's latest invite when it is pending or declined.
    AuthorInvite? invite,
  }) = _BeaconAuthorInviteRow;

  const BeaconAuthorInviteRow._();

  bool get canWithdraw => invite?.status.isPending ?? false;
}

@freezed
abstract class BeaconAuthorInvitesState extends StateBase
    with _$BeaconAuthorInvitesState {
  const factory BeaconAuthorInvitesState({
    required String beaconId,
    @Default(StateIsLoading()) StateStatus status,
    @Default([]) List<AuthorInvite> invites,
    @Default([]) List<String> observerIds,
    @Default({}) Map<String, Profile> profiles,
    @Default({}) Set<String> busyUserIds,
    BeaconAuthorInviteRefusal? notInvited,
  }) = _BeaconAuthorInvitesState;

  const BeaconAuthorInvitesState._();

  /// The rows to show, observers first in their server order, then invitees
  /// who are not observers. A person whose latest invite was accepted or
  /// superseded is a helper now, and anyone in [excludedUserIds] (the
  /// admitted helpers) is shown elsewhere on the tab: both are left out.
  /// «Позвать» is offered to an observer without a pending invite; a
  /// declined invite may be repeated.
  List<BeaconAuthorInviteRow> rows({
    Set<String> excludedUserIds = const {},
  }) {
    final latest = <String, AuthorInvite>{};
    final ordered = [...invites]
      ..sort((a, b) {
        final at = a.createdAt;
        final bt = b.createdAt;
        if (at == null || bt == null) return 0;
        return at.compareTo(bt);
      });
    for (final i in ordered) {
      final id = i.inviteeId;
      if (id != null) latest[id] = i;
    }
    final observers = observerIds.toSet();
    final ids = [
      ...observerIds,
      for (final id in latest.keys)
        if (!observers.contains(id)) id,
    ];
    return [
      for (final id in ids)
        if (!excludedUserIds.contains(id))
          ?_row(id, latest[id], isObserver: observers.contains(id)),
    ];
  }

  BeaconAuthorInviteRow? _row(
    String userId,
    AuthorInvite? latest, {
    required bool isObserver,
  }) {
    final status = latest?.status;
    if (status == AuthorInviteStatus.accepted ||
        status == AuthorInviteStatus.superseded) {
      return null;
    }
    final shown =
        status == AuthorInviteStatus.pending ||
            status == AuthorInviteStatus.declined
        ? latest
        : null;
    final canInvite = isObserver && !(shown?.status.isPending ?? false);
    if (shown == null && !canInvite) return null;
    return BeaconAuthorInviteRow(
      userId: userId,
      canInvite: canInvite,
      profile: profiles[userId],
      invite: shown,
    );
  }
}
