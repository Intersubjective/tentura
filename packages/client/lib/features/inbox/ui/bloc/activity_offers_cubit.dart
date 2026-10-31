import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/domain/attention/attention_actor_ids.dart';
import 'package:tentura/domain/attention/attention_actor_profiles_case.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/activity_offer_sort_row.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/author_invite.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/author_invite_case.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../domain/entity/inbox_item.dart';
import '../../domain/use_case/inbox_case.dart';
import '../message/author_invite_declined_message.dart';
import 'activity_offers_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';
export 'activity_offers_state.dart';

/// Paged open forwards for the Activity pinned zone (design §5.1 / §5.6).
final class ActivityOffersCubit extends Cubit<ActivityOffersState> {
  ActivityOffersCubit({
    required String userId,
    InboxCase? inboxCase,
    AttentionCase? attentionCase,
    AttentionActorProfilesCase? actorProfiles,
    AuthorInviteCase? authorInviteCase,
    UiEffectPort? effects,
    int pageSize = 20,
  }) : _inviteCaseOverride = authorInviteCase,
       _effectsOverride = effects,
       _userId = userId,
       _inboxCase = inboxCase ?? GetIt.I<InboxCase>(),
       _attention = attentionCase ?? GetIt.I<AttentionCase>(),
       _actorProfiles = actorProfiles ?? GetIt.I<AttentionActorProfilesCase>(),
       _demotedController = StreamController<String>.broadcast(),
       _pageSize = pageSize,
       super(const ActivityOffersState()) {
    _deskRelevantChanges = _inboxCase.deskRelevantChanges.listen(
      _scheduleBeaconRefresh,
      cancelOnError: false,
    );
    _helpOfferChanges = _inboxCase.helpOfferChanges.listen(
      (event) => _scheduleBeaconRefresh(event.beaconId),
      cancelOnError: false,
    );
    // The zone renders what the attention owner holds; it keeps no copy of
    // its own to drift out of step with it (§0.3).
    _offerGroups = _attention.activityOfferGroups.listen(
      (groups) {
        if (isClosed) return;
        emit(state.copyWith(eventsByBeacon: groups));
      },
      cancelOnError: false,
    );
  }

  static const _deskRelevantDebounce = Duration(milliseconds: 50);

  final int _pageSize;

  final String _userId;
  final InboxCase _inboxCase;
  final AttentionCase _attention;
  final AttentionActorProfilesCase _actorProfiles;

  // Resolved lazily: only a zone holding an invite row needs them.
  final AuthorInviteCase? _inviteCaseOverride;
  final UiEffectPort? _effectsOverride;

  AuthorInviteCase get _invites =>
      _inviteCaseOverride ?? GetIt.I<AuthorInviteCase>();

  UiEffectPort get _effects => _effectsOverride ?? GetIt.I<UiEffectPort>();

  int _invitesGeneration = 0;
  final StreamController<String> _demotedController;
  final _heldBackItems = <String, InboxItem>{};
  final _deskRelevantTimers = <String, Timer>{};
  final _heldBackOrder = <String>[];

  bool _scrolledAway = false;
  int _loadGeneration = 0;
  int _unseenGeneration = 0;
  int _actorsGeneration = 0;

  late final StreamSubscription<String> _deskRelevantChanges;
  late final StreamSubscription<HelpOfferEvent> _helpOfferChanges;
  late final StreamSubscription<Map<String, ActivityOfferBeaconMeta>>
  _offerGroups;

  /// Emits when an open forward leaves the pinned zone (UNIT 17 motion).
  Stream<String> get demotedBeaconIds => _demotedController.stream;

  void setScrolledAway(bool scrolledAway) {
    _scrolledAway = scrolledAway;
  }

  Future<void> loadFirst() async {
    final generation = ++_loadGeneration;
    emit(
      state.copyWith(
        status: StateStatus.isLoading,
        pageLoadFailed: false,
        countLoadFailed: false,
      ),
    );

    ActivityOfferPage? offerPage;
    var pageFailed = false;
    List<InboxItem> page = const [];

    try {
      offerPage = await _attention.activityOffers(limit: _pageSize);
      page = await _hydrateInboxItems(offerPage.items);
    } catch (_) {
      pageFailed = true;
    }

    if (generation != _loadGeneration || isClosed) return;

    final resolvedPage = offerPage;
    final nextCursor = resolvedPage?.nextCursor;
    final hasMore = !pageFailed && nextCursor != null && nextCursor.isNotEmpty;
    final eventsByBeacon = _attention.activityOfferGroupsSnapshot;
    final inviteIds = pageFailed
        ? state.inviteIdByBeacon
        : _inviteIdsOf(resolvedPage?.items ?? const []);
    emit(
      state.copyWith(
        firstLoadDone: state.firstLoadDone || !pageFailed,
        inviteIdByBeacon: inviteIds,
        declinedInviteBeacons: pageFailed
            ? state.declinedInviteBeacons
            : _declinedInvitesOf(resolvedPage?.items ?? const []),
        items: pageFailed ? state.items : page,
        totalCount: pageFailed ? state.totalCount : resolvedPage?.totalCount,
        countLoadFailed: false,
        pageLoadFailed: pageFailed,
        hasMore: hasMore,
        offersNextCursor: pageFailed ? state.offersNextCursor : nextCursor,
        eventsByBeacon: eventsByBeacon,
        loadingMore: false,
        status: const StateIsSuccess(),
      ),
    );
    if (!pageFailed) {
      unawaited(_refreshUnseenDots());
      unawaited(_hydrateActors(eventsByBeacon));
      unawaited(_hydrateInvites());
    }
  }

  Future<void> loadMore() async {
    final cursor = state.offersNextCursor;
    if (state.loadingMore ||
        !state.hasMore ||
        cursor == null ||
        cursor.isEmpty) {
      return;
    }
    emit(state.copyWith(loadingMore: true));
    try {
      final offerPage = await _attention.activityOffers(
        cursor: cursor,
        limit: _pageSize,
      );
      final page = await _hydrateInboxItems(offerPage.items);
      if (isClosed) return;
      final existingIds = state.items.map((e) => e.beaconId).toSet();
      final merged = [
        ...state.items,
        for (final item in page)
          if (!existingIds.contains(item.beaconId)) item,
      ];
      final nextCursor = offerPage.nextCursor;
      final eventsByBeacon = _attention.activityOfferGroupsSnapshot;
      emit(
        state.copyWith(
          items: merged,
          inviteIdByBeacon: {
            ...state.inviteIdByBeacon,
            ..._inviteIdsOf(offerPage.items),
          },
          declinedInviteBeacons: _withDeclinedInvitesOf(
            state.declinedInviteBeacons,
            offerPage.items,
          ),
          eventsByBeacon: eventsByBeacon,
          offersNextCursor: nextCursor,
          hasMore: nextCursor != null && nextCursor.isNotEmpty,
          loadingMore: false,
        ),
      );
      unawaited(_refreshUnseenDots());
      unawaited(_hydrateActors(eventsByBeacon));
      unawaited(_hydrateInvites());
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(loadingMore: false, pageLoadFailed: true));
    }
  }

  /// «Принять» on the invite card (plan D3). The row leaves the pinned zone
  /// at once — the Request is now in the viewer's scope — and comes back,
  /// with its invite, if the server refuses (expired, withdrawn, …).
  Future<void> acceptInvite(String beaconId) => _answerInvite(
    beaconId,
    (inviteId) => _invites.accept(inviteId),
  );

  /// «Не смогу» on the invite card: the existing decline (the rejection
  /// dialog's optional note is kept on the inbox row, as for any decline).
  ///
  /// A taken decline offers Undo: the server puts the invitation back and the
  /// row returns to where it was.
  Future<void> declineInvite(String beaconId, {String message = ''}) async {
    final inviteId = state.inviteIdByBeacon[beaconId];
    final invite = state.invites[inviteId];
    final index = state.items.indexWhere((e) => e.beaconId == beaconId);
    final item = index < 0 ? null : state.items[index];
    final declined = await _answerInvite(beaconId, (inviteId) async {
      await _invites.decline(inviteId);
      // #725: the Request now carries an answered invitation; if it comes
      // back to the zone (restored, forwarded), its card keeps these words.
      if (!isClosed) {
        emit(
          state.copyWith(
            declinedInviteBeacons: {
              ...state.declinedInviteBeacons,
              beaconId,
            },
          ),
        );
      }
      await _inboxCase.recordInviteDeclineNote(
        beaconId: beaconId,
        message: message,
      );
    });
    if (!declined || isClosed || inviteId == null) return;
    var undone = false;
    _effects.emit(
      ShowMessage(
        AuthorInviteDeclinedMessage(() {
          if (undone) return;
          undone = true;
          unawaited(
            _undoDecline(
              beaconId,
              inviteId,
              message: message,
              invite: invite,
              item: item,
              index: index,
            ),
          );
        }),
      ),
    );
  }

  Future<void> _undoDecline(
    String beaconId,
    String inviteId, {
    required String message,
    required PendingAuthorInvite? invite,
    required InboxItem? item,
    required int index,
  }) async {
    try {
      await _invites.revertDecline(inviteId);
    } on Object catch (error) {
      if (!isClosed) _effects.emit(ShowError(error));
      return;
    }
    if (isClosed) return;
    _putBack(beaconId, inviteId, item, index);
    emit(
      state.copyWith(
        invites: invite == null
            ? state.invites
            : {...state.invites, inviteId: invite},
        declinedInviteBeacons: {...state.declinedInviteBeacons}
          ..remove(beaconId),
      ),
    );
    await _inboxCase.forgetInviteDeclineNote(
      beaconId: beaconId,
      message: message,
    );
  }

  /// The row [item] and its invite back in the pinned zone at [index].
  void _putBack(String beaconId, String inviteId, InboxItem? item, int index) {
    final items = [...state.items];
    if (item != null && !items.any((e) => e.beaconId == beaconId)) {
      items.insert(index.clamp(0, items.length), item);
    }
    emit(
      state.copyWith(
        items: items,
        inviteIdByBeacon: {...state.inviteIdByBeacon, beaconId: inviteId},
      ),
    );
  }

  /// False when the server refused and the row was put back.
  Future<bool> _answerInvite(
    String beaconId,
    Future<void> Function(String inviteId) send,
  ) async {
    final inviteId = state.inviteIdByBeacon[beaconId];
    if (inviteId == null) return false;
    final index = state.items.indexWhere((e) => e.beaconId == beaconId);
    final item = index < 0 ? null : state.items[index];
    emit(
      state.copyWith(
        items: [
          for (final e in state.items)
            if (e.beaconId != beaconId) e,
        ],
        inviteIdByBeacon: {...state.inviteIdByBeacon}..remove(beaconId),
      ),
    );
    try {
      await send(inviteId);
    } on Object catch (error) {
      if (isClosed) return false;
      // Roll the optimistic removal back: the row and its invite return
      // where they were.
      _putBack(beaconId, inviteId, item, index);
      _effects.emit(ShowError(error));
      return false;
    }
    if (isClosed) return false;
    _attention.forgetOfferGroup(beaconId);
    emit(
      state.copyWith(
        invites: {...state.invites}..remove(inviteId),
        eventsByBeacon: _attention.activityOfferGroupsSnapshot,
      ),
    );
    unawaited(_refreshOpenForwardsCount());
    return true;
  }

  static Set<String> _declinedInvitesOf(List<ActivityOfferSortRow> rows) => {
    for (final row in rows)
      if (row.declinedInvite) row.beaconId,
  };

  /// [current] with each returned row's answer applied: a row says whether
  /// its Request carries a declined invitation now (a re-invite, withdrawn
  /// or pending, clears it), so a stale mark never outlives its row.
  static Set<String> _withDeclinedInvitesOf(
    Set<String> current,
    Iterable<ActivityOfferSortRow> rows,
  ) {
    final next = {...current};
    for (final row in rows) {
      if (row.declinedInvite) {
        next.add(row.beaconId);
      } else {
        next.remove(row.beaconId);
      }
    }
    return next;
  }

  static Map<String, String> _inviteIdsOf(List<ActivityOfferSortRow> rows) => {
    for (final row in rows)
      if (row.inviteId case final inviteId? when inviteId.isNotEmpty)
        row.beaconId: inviteId,
  };

  /// #725: a row that arrives live carries no invite facts (the zone's page
  /// does). Ask for its one row: a pending invite turns it into the invite
  /// card, a declined one keeps the invitation's words on its plain card.
  /// Best-effort: without an answer the row stays the plain card.
  Future<void> _learnInviteFacts(String beaconId) async {
    // A reload that lands meanwhile carries fresher facts than this answer.
    final generation = _loadGeneration;
    final ActivityOfferSortRow? row;
    try {
      row = await _attention.activityOfferRow(beaconId);
    } on Object {
      return;
    }
    if (isClosed || row == null || generation != _loadGeneration) return;
    final inviteId = row.inviteId;
    final hasInvite = inviteId != null && inviteId.isNotEmpty;
    emit(
      state.copyWith(
        inviteIdByBeacon: hasInvite
            ? {...state.inviteIdByBeacon, beaconId: inviteId}
            : state.inviteIdByBeacon,
        declinedInviteBeacons: _withDeclinedInvitesOf(
          state.declinedInviteBeacons,
          [row],
        ),
      ),
    );
    if (hasInvite) await _hydrateInvites();
  }

  /// Inviter and note for the invite rows; best-effort, like actor avatars.
  Future<void> _hydrateInvites() async {
    final wanted = state.inviteIdByBeacon.values.toSet();
    if (wanted.isEmpty) return;
    final generation = ++_invitesGeneration;
    try {
      final pending = await _invites.myPending();
      if (isClosed || generation != _invitesGeneration) return;
      final invites = {
        for (final invite in pending)
          if (wanted.contains(invite.id)) invite.id: invite,
      };
      emit(state.copyWith(invites: {...state.invites, ...invites}));
      final inviterIds = {for (final i in invites.values) i.inviterId};
      if (inviterIds.isEmpty) return;
      final resolved = await _actorProfiles.resolve(inviterIds);
      if (isClosed || generation != _invitesGeneration) return;
      emit(state.copyWith(inviters: {...state.inviters, ...resolved}));
    } on Object {
      // The card renders without inviter and note.
    }
  }

  void stageMovedToStreamNudge(String beaconId) {
    if (beaconId.isEmpty) return;
    emit(state.copyWith(pendingMovedToStreamBeaconId: beaconId));
  }

  void clearMovedToStreamNudge() {
    if (state.pendingMovedToStreamBeaconId == null) return;
    emit(state.copyWith(pendingMovedToStreamBeaconId: null));
  }

  void revealHeldBack() {
    if (state.heldBackIds.isEmpty) return;
    final ids = state.heldBackIds;
    final toReveal = [
      for (final id in _heldBackOrder)
        if (ids.contains(id)) _heldBackItems[id]!,
    ];
    final existing = [
      for (final item in state.items)
        if (!ids.contains(item.beaconId)) item,
    ];
    for (final id in ids) {
      _heldBackItems.remove(id);
    }
    _heldBackOrder.removeWhere(ids.contains);
    emit(
      state.copyWith(
        items: [...toReveal, ...existing],
        heldBackIds: const {},
      ),
    );
    unawaited(_refreshUnseenDots());
  }

  Future<void> _refreshOpenForwardsCount() async {
    try {
      final totalCount = await _attention.activityOffersCount();
      if (isClosed) return;
      emit(
        state.copyWith(
          totalCount: totalCount,
          countLoadFailed: false,
        ),
      );
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(countLoadFailed: true));
    }
  }

  void _scheduleBeaconRefresh(String beaconId) {
    if (isClosed || beaconId.isEmpty) return;
    _deskRelevantTimers.remove(beaconId)?.cancel();
    _deskRelevantTimers[beaconId] = Timer(_deskRelevantDebounce, () {
      _deskRelevantTimers.remove(beaconId);
      if (!isClosed) {
        unawaited(_refreshBeaconRow(beaconId));
      }
    });
  }

  Future<void> _refreshBeaconRow(String beaconId) async {
    InboxItem? row;
    try {
      row = await _inboxCase.fetchOpenForwardForBeacon(
        userId: _userId,
        beaconId: beaconId,
      );
    } catch (_) {
      return;
    }
    if (isClosed) return;

    if (row == null) {
      _demoteBeacon(beaconId);
    } else {
      final arrived =
          !state.items.any((e) => e.beaconId == beaconId) &&
          !state.heldBackIds.contains(beaconId);
      _upsertOpenForward(row);
      if (arrived) unawaited(_learnInviteFacts(beaconId));
    }
    unawaited(_refreshOpenForwardsCount());
    unawaited(_refreshUnseenDots());
  }

  void _upsertOpenForward(InboxItem item) {
    final id = item.beaconId;
    final without = [
      for (final existing in state.items)
        if (existing.beaconId != id) existing,
    ];
    if (_scrolledAway) {
      _heldBackItems[id] = item;
      if (!_heldBackOrder.contains(id)) {
        _heldBackOrder.add(id);
      }
      emit(
        state.copyWith(
          items: without,
          heldBackIds: {...state.heldBackIds, id},
        ),
      );
      return;
    }
    _heldBackItems.remove(id);
    _heldBackOrder.remove(id);
    final heldBackIds = {...state.heldBackIds}..remove(id);
    emit(
      state.copyWith(
        items: [item, ...without],
        heldBackIds: heldBackIds,
      ),
    );
  }

  void _demoteBeacon(String beaconId) {
    final hadItem =
        state.items.any((e) => e.beaconId == beaconId) ||
        state.heldBackIds.contains(beaconId);
    _heldBackItems.remove(beaconId);
    _heldBackOrder.remove(beaconId);
    _attention.forgetOfferGroup(beaconId);
    final eventsByBeacon = _attention.activityOfferGroupsSnapshot;
    emit(
      state.copyWith(
        items: [
          for (final item in state.items)
            if (item.beaconId != beaconId) item,
        ],
        heldBackIds: {...state.heldBackIds}..remove(beaconId),
        eventsByBeacon: eventsByBeacon,
      ),
    );
    if (hadItem && !_demotedController.isClosed) {
      _demotedController.add(beaconId);
    }
  }

  Future<void> _refreshUnseenDots() async {
    final generation = ++_unseenGeneration;
    final beaconIds = state.items
        .map((e) => e.beaconId)
        .toList(growable: false);
    if (beaconIds.isEmpty) {
      emit(
        state.copyWith(
          unseenBeaconIds: const {},
          unseenQueryComplete: true,
        ),
      );
      return;
    }
    try {
      final unread = await _attention.unseenForBeacons(beaconIds.toSet());
      if (isClosed || generation != _unseenGeneration) return;
      emit(
        state.copyWith(
          unseenBeaconIds: unread.intersection(beaconIds.toSet()),
          unseenQueryComplete: true,
        ),
      );
    } catch (_) {
      if (isClosed || generation != _unseenGeneration) return;
      emit(state.copyWith(unseenQueryComplete: false));
    }
  }

  Future<List<InboxItem>> _hydrateInboxItems(
    List<ActivityOfferSortRow> rows,
  ) async {
    if (rows.isEmpty) return const [];
    final ids = rows.map((e) => e.beaconId).toList(growable: false);
    final hydrated = await _inboxCase.fetchInboxItemsForBeacons(
      userId: _userId,
      beaconIds: ids,
    );
    final byId = {for (final item in hydrated) item.beaconId: item};
    return [
      for (final id in ids)
        if (byId.containsKey(id)) byId[id]!,
    ];
  }

  Future<void> _hydrateActors(
    Map<String, ActivityOfferBeaconMeta> eventsByBeacon,
  ) async {
    final previews = <AttentionReceipt>[
      for (final meta in eventsByBeacon.values) ...meta.eventsPreview,
    ];
    final ids = attentionActorIds(previews);
    if (ids.isEmpty) {
      if (state.actors.isNotEmpty) {
        emit(state.copyWith(actors: const {}));
      }
      return;
    }
    final generation = ++_actorsGeneration;
    try {
      final resolved = await _actorProfiles.resolve(ids);
      if (isClosed || generation != _actorsGeneration) return;
      final next = <String, Profile>{
        ...state.actors,
        ...resolved,
      };
      next.removeWhere((id, _) => !ids.contains(id));
      emit(state.copyWith(actors: next));
    } on Object {
      // Avatar hydrate is best-effort; keep glyph fallback.
    }
  }

  @override
  Future<void> close() async {
    for (final timer in _deskRelevantTimers.values) {
      timer.cancel();
    }
    _deskRelevantTimers.clear();
    await _deskRelevantChanges.cancel();
    await _helpOfferChanges.cancel();
    await _offerGroups.cancel();
    await _demotedController.close();
    return super.close();
  }
}
