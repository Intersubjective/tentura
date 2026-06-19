import 'dart:async';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';

import 'package:tentura/features/home/ui/bloc/new_stuff_cubit.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/beacon_room/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_room/domain/use_case/beacon_room_case.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_cards.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/use_case/my_work_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import 'my_work_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'my_work_state.dart';

class MyWorkCubit extends Cubit<MyWorkState> {
  MyWorkCubit({
    MyWorkCase? myWorkCase,
    ProfileCubit? profileCubit,
    ForwardRepository? forwardRepository,
    NewStuffCubit? newStuffCubit,
    BeaconRoomCase? beaconRoomCase,
    BeaconRoomHintsRepository? roomHints,
  }) : _myWorkCase = myWorkCase ?? GetIt.I<MyWorkCase>(),
       _profileCubit = profileCubit ?? GetIt.I<ProfileCubit>(),
       _forwardRepository = forwardRepository ?? GetIt.I<ForwardRepository>(),
       _newStuffCubit = newStuffCubit ?? GetIt.I<NewStuffCubit>(),
       _beaconRoomCase = beaconRoomCase ?? GetIt.I<BeaconRoomCase>(),
       _roomHints = roomHints ?? GetIt.I<BeaconRoomHintsRepository>(),
       super(const MyWorkState()) {
    _beaconChanges = (myWorkCase ?? GetIt.I<MyWorkCase>()).beaconChanges.listen(
      _onBeaconChanged,
      cancelOnError: false,
    );
    _helpOfferChanges = _forwardRepository.helpOfferChanges.listen(
      (_) => unawaited(fetch()),
      cancelOnError: false,
    );
    _forwardCompleted = _forwardRepository.forwardCompleted.listen(
      (_) => unawaited(fetch()),
      cancelOnError: false,
    );
    _readWatermarkSub = _beaconRoomCase.readWatermarkChanges.listen(
      (_) => unawaited(fetch()),
      cancelOnError: false,
    );
    unawaited(fetch());
  }

  final MyWorkCase _myWorkCase;
  final ProfileCubit _profileCubit;
  final ForwardRepository _forwardRepository;
  final NewStuffCubit _newStuffCubit;
  final BeaconRoomCase _beaconRoomCase;
  final BeaconRoomHintsRepository _roomHints;

  late final StreamSubscription<String> _readWatermarkSub;

  void _reportMyWorkActivity() {
    if (!state.isSuccess) return;
    int? maxMs;
    for (final c in state.nonArchivedCards) {
      final m = c.newStuffActivityEpochMs;
      if (maxMs == null || m > maxMs) maxMs = m;
    }
    for (final c in state.archivedCards) {
      final m = c.newStuffActivityEpochMs;
      if (maxMs == null || m > maxMs) maxMs = m;
    }
    _newStuffCubit.reportMyWorkActivity(maxMs);
  }

  /// Incremented on every [fetch]; stale async completions must not emit.
  int _fetchSeq = 0;

  late final StreamSubscription<RepositoryEvent<Beacon>> _beaconChanges;

  late final StreamSubscription<HelpOfferEvent> _helpOfferChanges;

  late final StreamSubscription<String> _forwardCompleted;

  Future<List<MyWorkCardViewModel>> _withAuthorForwardFlags(
    List<MyWorkCardViewModel> cards,
  ) async {
    final needsFlag = cards
        .where((c) => c.kind != MyWorkCardKind.authoredDraft)
        .toList();
    if (needsFlag.isEmpty) {
      return cards;
    }
    final results = await Future.wait(
      needsFlag.map(
        (c) => _myWorkCase.currentUserHasForwardedBeacon(c.beaconId),
      ),
    );
    final map = <String, bool>{
      for (var i = 0; i < needsFlag.length; i++)
        needsFlag[i].beaconId: results[i],
    };
    return [
      for (final c in cards)
        c.kind == MyWorkCardKind.authoredDraft
            ? c
            : c.copyWith(authorHasForwardedOnce: map[c.beaconId] ?? false),
    ];
  }

  @override
  Future<void> close() async {
    await _beaconChanges.cancel();
    await _helpOfferChanges.cancel();
    await _forwardCompleted.cancel();
    await _readWatermarkSub.cancel();
    return super.close();
  }

  Future<void> fetch() async {
    final seq = ++_fetchSeq;
    final userId = _profileCubit.state.profile.id;
    if (userId.isEmpty) {
      emit(
        state.copyWith(
          status: const StateIsSuccess(),
          nonArchivedCards: const [],
          archivedCards: const [],
          authoredClosedIdHints: const [],
          helpOfferedClosedIdHints: const [],
          closedDataFetched: false,
          closedFetchInProgress: false,
        ),
      );
      _reportMyWorkActivity();
      return;
    }
    final filterBefore = state.filter;
    emit(
      state.copyWith(
        status: StateStatus.isLoading,
        closedFetchInProgress: false,
      ),
    );
    try {
      final init = await _myWorkCase.fetchInit(userId: userId);
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      final nonArchived = buildNonArchivedViewModels(
        authoredNonClosed: init.authoredNonClosed,
        helpOfferedNonClosed: init.helpOfferedNonClosed,
      ).map((c) {
        final at = init.lastItemDiscussionMessageAtByBeaconId[c.beaconId];
        return at == null
            ? c
            : c.copyWith(lastCoordinationItemMessageAt: at);
      }).toList();
      final withLastEvents =
          await _myWorkCase.attachLastActivityEvents(nonArchived);
      final withResponsibility =
          await _myWorkCase.attachResponsibilityCounts(withLastEvents);
      final hints = await _roomHints.fetchByBeaconIds(
        withResponsibility.map((c) => c.beaconId),
      );
      final withHints = withResponsibility
          .map((c) {
            final h = hints[c.beaconId];
            if (h == null || !h.isRoomMember) {
              return c;
            }
            final parts = <String>[];
            if (h.myNextMove.isNotEmpty) {
              parts.add(h.myNextMove);
            }
            if (h.currentLineSnippet.isNotEmpty) {
              parts.add(h.currentLineSnippet);
            }
            if (h.roomUnreadCount > 0) {
              final unread = _beaconRoomCase.resolveUnread(
                beaconId: c.beaconId,
                serverCount: h.roomUnreadCount,
                serverSeenAt: h.lastSeenAt,
              );
              if (unread > 0) {
                parts.add('+$unread');
              }
            }
            if (parts.isEmpty) return c;
            return c.copyWith(roomInboxSubtitle: parts.join(' · '));
          })
          .toList();
      final withForwardFlags = await _withAuthorForwardFlags(withHints);
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      emit(
        state.copyWith(
          status: const StateIsSuccess(),
          nonArchivedCards: withForwardFlags,
          authoredClosedIdHints: init.authoredClosedIds,
          helpOfferedClosedIdHints: init.helpOfferedClosedIds,
          closedDataFetched: false,
          archivedCards: const [],
        ),
      );
      _reportMyWorkActivity();
      if (filterBefore == MyWorkFilter.archived) {
        emit(state.copyWith(closedFetchInProgress: true));
        unawaited(_fetchClosed(seq));
      }
    } catch (e) {
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  void setFilter(MyWorkFilter filter) {
    if (filter == MyWorkFilter.archived &&
        !state.closedDataFetched &&
        !state.closedFetchInProgress) {
      emit(state.copyWith(filter: filter, closedFetchInProgress: true));
      unawaited(_fetchClosed(_fetchSeq));
      return;
    }
    emit(state.copyWith(filter: filter));
  }

  void setSort(MyWorkSort sort) {
    if (state.sort == sort) return;
    emit(state.copyWith(sort: sort));
  }

  Future<void> _fetchClosed(int seq) async {
    final userId = _profileCubit.state.profile.id;
    if (userId.isEmpty) {
      if (!isClosed && seq == _fetchSeq) {
        emit(state.copyWith(closedFetchInProgress: false));
      }
      return;
    }
    try {
      final closed = await _myWorkCase.fetchClosed(userId: userId);
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      final archived = buildArchivedViewModels(
        authoredClosed: closed.authoredClosed,
        helpOfferedClosed: closed.helpOfferedClosed,
      );
      final archivedWithEvents =
          await _myWorkCase.attachLastActivityEvents(archived);
      final archivedWithResponsibility =
          await _myWorkCase.attachResponsibilityCounts(archivedWithEvents);
      final archHints = await _roomHints.fetchByBeaconIds(
        archivedWithResponsibility.map((c) => c.beaconId),
      );
      final archivedWithHints = archivedWithResponsibility
          .map((c) {
            final h = archHints[c.beaconId];
            if (h == null || !h.isRoomMember) {
              return c;
            }
            final parts = <String>[];
            if (h.myNextMove.isNotEmpty) {
              parts.add(h.myNextMove);
            }
            if (h.currentLineSnippet.isNotEmpty) {
              parts.add(h.currentLineSnippet);
            }
            if (h.roomUnreadCount > 0) {
              final unread = _beaconRoomCase.resolveUnread(
                beaconId: c.beaconId,
                serverCount: h.roomUnreadCount,
                serverSeenAt: h.lastSeenAt,
              );
              if (unread > 0) {
                parts.add('+$unread');
              }
            }
            if (parts.isEmpty) return c;
            return c.copyWith(roomInboxSubtitle: parts.join(' · '));
          })
          .toList();
      final archivedWithForwardFlags =
          await _withAuthorForwardFlags(archivedWithHints);
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      emit(
        state.copyWith(
          closedFetchInProgress: false,
          closedDataFetched: true,
          archivedCards: archivedWithForwardFlags,
          status: const StateIsSuccess(),
        ),
      );
      _reportMyWorkActivity();
    } catch (e) {
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      emit(
        state.copyWith(
          closedFetchInProgress: false,
          status: StateHasError(e),
        ),
      );
    }
  }

  void _onBeaconChanged(RepositoryEvent<Beacon> event) => switch (event) {
    RepositoryEventCreate<Beacon>() ||
    RepositoryEventUpdate<Beacon>() ||
    RepositoryEventInvalidate<Beacon>() => unawaited(fetch()),
    RepositoryEventDelete<Beacon>(value: final b) => _removeBeaconFromState(
      b.id,
    ),
    _ => null,
  };

  void _removeBeaconFromState(String beaconId) {
    emit(
      state.copyWith(
        nonArchivedCards: state.nonArchivedCards
            .where((c) => c.beaconId != beaconId)
            .toList(),
        archivedCards: state.archivedCards
            .where((c) => c.beaconId != beaconId)
            .toList(),
        authoredClosedIdHints: state.authoredClosedIdHints
            .where((id) => id != beaconId)
            .toList(),
        helpOfferedClosedIdHints: state.helpOfferedClosedIdHints
            .where((id) => id != beaconId)
            .toList(),
      ),
    );
    _reportMyWorkActivity();
  }
}
