// Shared harness for the issue #178 part 2 author-seen tests. The offerer sees "Sent · not seen by the author yet" vs
// "Seen by the author · awaiting decision" on a pending help offer, and a
// `people_seen` realtime frame flips it without reloading the offers. The
// label is fed either by `authorSeenAt` on the initial help-offer query or by
// the realtime patch. Opening the People surface as the author or a steward
// marks it seen via `CoordinationRepository.markBeaconPeopleSeen` (mirrors
// `markThreadSeen`; V2 mutation `MarkBeaconPeopleSeen`).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_people_surface.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_people_tab_body.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';

export 'beacon_view_case_test_support.dart';

const kNotSeenLabel = 'Sent · not seen by the author yet';
const kSeenLabel = 'Seen by the author · awaiting decision';

const kAuthorSeenBeaconId = 'Bauthorseen01';
const kOfferer = Profile(id: 'Uofferer00001', displayName: 'Offerer');
const kAuthor = Profile(id: 'Uauthor000001', displayName: 'Author');
const kSteward = Profile(id: 'Usteward00001', displayName: 'Steward');
final kOfferCreatedAt = DateTime.utc(2026, 6, 15, 12);

class AuthorSeenProfileCubitStub extends Mock implements ProfileCubit {
  AuthorSeenProfileCubitStub([this._profile = kOfferer]);

  final Profile _profile;

  @override
  ProfileState get state => ProfileState(profile: _profile);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

/// Freezes a [BeaconViewState] for rendering, so the People tab does not
/// drive the real cubit's side effects.
class FrozenBeaconViewCubit extends Mock implements BeaconViewCubit {
  FrozenBeaconViewCubit(this._state);

  final BeaconViewState _state;

  @override
  BeaconViewState get state => _state;

  @override
  Stream<BeaconViewState> get stream => Stream<BeaconViewState>.value(_state);

  @override
  Future<void> loadForwards() async {}
}

class CountingCoordinationRepository
    extends FakeBeaconViewCoordinationRepository {
  CountingCoordinationRepository({super.rows});

  int fetchCalls = 0;
  final markPeopleSeenCalls = <({String beaconId, DateTime? readThroughAt})>[];

  @override
  Future<List<FakeHelpOfferCoordinationRow>> fetchHelpOffersWithCoordination({
    required String beaconId,
  }) {
    fetchCalls++;
    return super.fetchHelpOffersWithCoordination(beaconId: beaconId);
  }

  @override
  Future<DateTime> markBeaconPeopleSeen(String beaconId) async {
    markPeopleSeenCalls.add((beaconId: beaconId, readThroughAt: null));
    return DateTime.utc(2026, 6, 15, 12, 10);
  }
}

/// Pending offer row as the initial help-offer query returns it, before the
/// author has seen it (no `authorSeenAt`; see
/// `help_offer_author_seen_initial_query_test.dart` for the seen variant).
FakeHelpOfferCoordinationRow pendingOfferRow({
  int offerKind = 0,
  Profile offerer = kOfferer,
  DateTime? createdAt,
  DateTime? authorSeenAt,
}) => offerRow(
  offerKind: offerKind,
  offerer: offerer,
  createdAt: createdAt,
  authorSeenAt: authorSeenAt,
);

/// Any help-offer row; defaults describe a pending offer. Non-pending
/// variants: withdrawn (`status: 1`), or decided by the author
/// (`admissionAction` accept/decline).
FakeHelpOfferCoordinationRow offerRow({
  int offerKind = 0,
  Profile offerer = kOfferer,
  DateTime? createdAt,
  int status = 0,
  int? roomAccess,
  int? admissionAction,
  String? lastDeclineReason,
  DateTime? authorSeenAt,
}) => (
  beaconId: kAuthorSeenBeaconId,
  userId: offerer.id,
  user: offerer,
  message: 'I can help',
  helpType: null,
  roleLabel: null,
  status: status,
  withdrawReason: null,
  createdAt: createdAt ?? kOfferCreatedAt,
  updatedAt: createdAt ?? kOfferCreatedAt,
  responseType: null,
  responseUpdatedAt: null,
  responseAuthorUserId: null,
  roomAccess: roomAccess,
  admissionAction: admissionAction,
  lastDeclineReason: lastDeclineReason,
  lastRemoveReason: null,
  stakeState: 0,
  offerKind: offerKind,
  isDirectAuthorForward: false,
  authorSeenAt: authorSeenAt?.toUtc().toIso8601String(),
);

Map<String, dynamic> peopleSeenFrame({
  required String lastSeenAt,
  String beaconId = kAuthorSeenBeaconId,
}) => {
  'type': 'subscription',
  'path': 'entity_changes',
  'payload': {
    'entity': 'people_seen',
    'id': beaconId,
    'event': 'update',
    'actor_user_id': kAuthor.id,
    'last_seen_at': lastSeenAt,
  },
};

Beacon authorSeenBeacon() => Beacon(
  id: kAuthorSeenBeaconId,
  title: 'Needs help',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  author: kAuthor,
);

/// Offerer-side stack: raw WS frames → [InvalidationService] →
/// [RealtimeSyncCase] → real [BeaconViewCubit].
class AuthorSeenHarness {
  AuthorSeenHarness({
    int offerKind = 0,
    List<FakeHelpOfferCoordinationRow>? rows,
    this.viewer = kOfferer,
    List<BeaconParticipant> participants = const [],
  }) {
    coordination = CountingCoordinationRepository(
      rows: rows ?? [pendingOfferRow(offerKind: offerKind)],
    );
    beaconRepo = TrackingBeaconRepository()
      ..fetchByIdHandler = (_) async => authorSeenBeacon();
    invalidation = InvalidationService.forTesting(ws.stream);
    cubit = BeaconViewCubit(
      id: kAuthorSeenBeaconId,
      myProfile: viewer,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        coordinationRepo: coordination,
        roomRepo: FakeBeaconViewRoomRepository(participants: participants),
        realtimeSyncCase: RealtimeSyncCase(invalidation),
      ),
      effects: FakeUiEffectPort(),
    );
  }

  final Profile viewer;
  final ws = StreamController<Map<String, dynamic>>.broadcast();
  late final CountingCoordinationRepository coordination;
  late final TrackingBeaconRepository beaconRepo;
  late final InvalidationService invalidation;
  late final BeaconViewCubit cubit;

  Future<void> load() => waitFor(
    () => cubit.state.beaconContextLoaded && cubit.state.helpOffers.isNotEmpty,
  );

  /// Sends a frame and lets the 100 ms realtime batch window flush.
  Future<void> send(Map<String, dynamic> frame) async {
    ws.add(frame);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<void> dispose() async {
    await cubit.close();
    await invalidation.dispose();
    await ws.close();
    await beaconRepo.dispose();
  }
}

Future<void> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

BeaconParticipant stewardParticipant() => BeaconParticipant(
  id: 'Pstewardrow01',
  beaconId: kAuthorSeenBeaconId,
  userId: kSteward.id,
  role: BeaconParticipantRoleBits.steward,
  status: 0,
  roomAccess: RoomAccessBits.admitted,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

/// Opens the People surface (what the screen mounts for the People tab)
/// against the harness's real [BeaconViewCubit], rebuilt from the cubit's
/// state stream the way `BeaconViewScreen` does, so later state changes
/// (e.g. a realtime patch) update the already-visible surface.
Future<void> openPeopleSurface(WidgetTester tester, AuthorSeenHarness h) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<ProfileCubit>.value(
            value: AuthorSeenProfileCubitStub(h.viewer),
          ),
          BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
          BlocProvider<BeaconViewCubit>.value(value: h.cubit),
        ],
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: BlocBuilder<BeaconViewCubit, BeaconViewState>(
              bloc: h.cubit,
              builder: (context, state) => BeaconPeopleSurface(
                beaconViewCubit: h.cubit,
                beaconState: state,
                focusUserId: null,
                peopleTabAttentionActive: false,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump();
}

Future<void> pumpPeople(
  WidgetTester tester,
  BeaconViewState state, {
  Profile viewer = kOfferer,
  Locale locale = const Locale('en'),
}) async {
  final cubit = FrozenBeaconViewCubit(state);
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      home: MultiBlocProvider(
        providers: [
          BlocProvider<ProfileCubit>.value(
            value: AuthorSeenProfileCubitStub(viewer),
          ),
          BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
          BlocProvider<BeaconViewCubit>.value(value: cubit),
        ],
        child: Scaffold(
          body: BeaconPeopleTabBody(
            state: state,
            beaconViewCubit: cubit,
            l10n: lookupL10n(locale),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
