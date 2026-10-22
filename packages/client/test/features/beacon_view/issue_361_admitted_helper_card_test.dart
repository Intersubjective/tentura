// #361 — right after the author accepts a help offer, the helper card read
// "Helper · Help offered · marked useful · Just now · edited": nothing was
// marked useful (Accept stores the `useful` response as part of admission)
// and nothing was edited (the accept path bumps `beacon_help_offer.updated_at`
// through the stake_state write and the BEFORE UPDATE trigger). The card must
// say what happened: the offer was accepted (the footer already reads
// "Admitted").
//
// "edited": a timing heuristic that ignored updates near the author's
// response hid real edits (owner review on PR #610), so the server now keeps
// `beacon_help_offer.edited_at`, set only when the helper changes the text
// or help types of an active offer (m0258). The card and the activity
// timeline read it; `updated_at` (bumped by every accept write) no longer
// decides anything. An edit made seconds after the author's response is
// still an edit.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/timeline_help_offer_mapping.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_people_labels.dart';
import 'package:tentura/features/beacon_view/ui/widget/help_offer_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _FakePlatformRepository implements PlatformRepositoryPort {
  @override
  Future<String> getAppVersion() async => 'test';

  @override
  Future<String> getStringFromClipboard() async => '';

  @override
  Future<void> launchUri(Uri uri) async {}

  @override
  Future<void> launchUrl(String uri) async {}

  @override
  Future<void> launchUserLink(Uri uri) async {}
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'me', displayName: 'Me'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
      ],
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

const _helper = Profile(id: 'h1', displayName: 'Helper One');

/// Offer created at [createdAt]; the author's response (Accept writes
/// `useful`) at [responseAt]; the row's `updated_at` at [updatedAt]; the
/// helper's last edit at [editedAt].
TimelineHelpOffer _offer({
  required DateTime createdAt,
  required DateTime updatedAt,
  DateTime? editedAt,
  DateTime? responseAt,
  CoordinationResponseType? response,
  HelpOfferAdmissionAction? admissionAction,
  int? roomAccess,
  CommitmentStakeState stakeState = CommitmentStakeState.none,
  bool isWithdrawn = false,
}) => TimelineHelpOffer(
  user: _helper,
  message: 'I have a van',
  createdAt: createdAt,
  updatedAt: updatedAt,
  editedAt: editedAt,
  isWithdrawn: isWithdrawn,
  coordinationResponse: response,
  coordinationResponseAt: responseAt,
  admissionAction: admissionAction,
  roomAccess: roomAccess,
  stakeState: stakeState,
);

/// The state the author's Accept leaves behind: response `useful` at the
/// accept moment, admitted, acknowledged, and `updated_at` bumped by the same
/// accept (the trigger fires a moment after the coordination write).
TimelineHelpOffer _justAccepted(DateTime createdAt) {
  final acceptedAt = createdAt.add(const Duration(seconds: 30));
  return _offer(
    createdAt: createdAt,
    updatedAt: acceptedAt.add(const Duration(milliseconds: 500)),
    responseAt: acceptedAt,
    response: CoordinationResponseType.useful,
    admissionAction: HelpOfferAdmissionAction.accept,
    roomAccess: RoomAccessBits.admitted,
    stakeState: CommitmentStakeState.acknowledged,
  );
}

BeaconParticipant _participant(DateTime at) => BeaconParticipant(
  id: 'p1',
  beaconId: 'B1',
  userId: _helper.id,
  role: BeaconParticipantRoleBits.helper,
  status: BeaconParticipantStatusBits.committed,
  roomAccess: RoomAccessBits.admitted,
  createdAt: at,
  updatedAt: at,
);

Widget _authorTile(TimelineHelpOffer offer, BeaconParticipant participant) =>
    HelpOfferTile(
      helpOffer: offer,
      beaconId: 'B1',
      beaconAuthor: const Profile(id: 'me', displayName: 'Me'),
      beaconAuthorId: 'me',
      isAuthorView: true,
      participant: participant,
      showBackupHint: false,
    );

HelpOfferWithCoordinationRow _row({
  required DateTime createdAt,
  required DateTime updatedAt,
  DateTime? editedAt,
  DateTime? responseAt,
  int? responseType,
  int? admissionAction,
}) => (
  beaconId: 'B1',
  userId: _helper.id,
  user: _helper,
  message: 'I have a van',
  helpType: null,
  roleLabel: null,
  status: 0,
  withdrawReason: null,
  createdAt: createdAt,
  updatedAt: updatedAt,
  editedAt: editedAt,
  responseType: responseType,
  responseUpdatedAt: responseAt,
  responseAuthorUserId: responseType == null ? null : 'me',
  roomAccess: admissionAction == null ? null : RoomAccessBits.admitted,
  admissionAction: admissionAction,
  lastDeclineReason: null,
  lastRemoveReason: null,
  stakeState: admissionAction == null
      ? 0
      : CommitmentStakeState.acknowledged.index,
  offerKind: 0,
  isDirectAuthorForward: false,
  authorSeenAt: null,
);

void main() {
  final t0 = DateTime.utc(2026, 10, 14, 12);
  final acceptedAt = t0.add(const Duration(seconds: 30));

  group('beaconPeopleStatusLabel for a committed helper', () {
    final l10n = lookupL10n(const Locale('en'));

    // "Help offered" here rests on one fact: Accept writes the author's
    // `useful` response as part of admission (server acceptHelpOffer and the
    // cubit's optimistic acceptHelpOffer). So `useful` next to an accept is
    // the admission, not the author marking the offer useful. Without an
    // accept, `useful` is a real "marked useful" and must keep its label.
    test('committed + useful + accept says help offered', () {
      expect(
        beaconPeopleStatusLabel(
          l10n,
          BeaconParticipantStatusBits.committed,
          CoordinationResponseType.useful,
          admissionAction: HelpOfferAdmissionAction.accept,
        ),
        l10n.beaconPeopleStatusHelpOffered,
      );
    });

    test('committed + useful without accept keeps the useful label', () {
      expect(
        beaconPeopleStatusLabel(
          l10n,
          BeaconParticipantStatusBits.committed,
          CoordinationResponseType.useful,
        ),
        l10n.beaconPeopleStatusHelpOfferedUseful,
      );
      expect(
        beaconPeopleStatusLabel(
          l10n,
          BeaconParticipantStatusBits.committed,
          CoordinationResponseType.useful,
          admissionAction: HelpOfferAdmissionAction.autoAdmit,
        ),
        l10n.beaconPeopleStatusHelpOfferedUseful,
      );
    });
  });

  // Edited only when the server says the helper edited (`editedAt`).
  group('TimelineHelpOffer.isEdited', () {
    test('an untouched offer is not edited', () {
      expect(_offer(createdAt: t0, updatedAt: t0).isEdited, isFalse);
    });

    test('the accept bumping updated_at is not an edit', () {
      expect(_justAccepted(t0).isEdited, isFalse);
    });

    test('an offer the helper edits after the accept is edited', () {
      final offer = _offer(
        createdAt: t0,
        updatedAt: acceptedAt.add(const Duration(minutes: 10)),
        editedAt: acceptedAt.add(const Duration(minutes: 10)),
        responseAt: acceptedAt,
        response: CoordinationResponseType.useful,
        admissionAction: HelpOfferAdmissionAction.accept,
        roomAccess: RoomAccessBits.admitted,
        stakeState: CommitmentStakeState.acknowledged,
      );
      expect(offer.isEdited, isTrue);
    });

    test('an edit a few seconds after the author response is edited', () {
      final respondedAt = t0.add(const Duration(minutes: 5));
      final offer = _offer(
        createdAt: t0,
        updatedAt: respondedAt.add(const Duration(seconds: 3)),
        editedAt: respondedAt.add(const Duration(seconds: 3)),
        responseAt: respondedAt,
        response: CoordinationResponseType.useful,
      );
      expect(offer.isEdited, isTrue);
    });

    test('a withdrawn offer is not shown as edited', () {
      final offer = _offer(
        createdAt: t0,
        updatedAt: t0.add(const Duration(minutes: 1)),
        editedAt: t0.add(const Duration(seconds: 30)),
        isWithdrawn: true,
      );
      expect(offer.isEdited, isFalse);
    });
  });

  group('activity timeline "updated the offer"', () {
    test('an edit after the accept adds the entry at the edit time', () {
      final editedAt = acceptedAt.add(const Duration(minutes: 10));
      final entries = helpOfferRowsToTimelineEntries(
        beacon: Beacon.empty,
        row: _row(
          createdAt: t0,
          updatedAt: editedAt.add(const Duration(minutes: 1)),
          editedAt: editedAt,
          responseAt: acceptedAt,
          responseType: CoordinationResponseType.useful.smallintValue,
          admissionAction: HelpOfferAdmissionAction.accept.smallintValue,
        ),
      );
      final updated = entries.whereType<TimelineHelpOfferUpdated>().single;
      expect(updated.timestamp, editedAt);
    });

    test('the accept alone adds no entry', () {
      final entries = helpOfferRowsToTimelineEntries(
        beacon: Beacon.empty,
        row: _row(
          createdAt: t0,
          updatedAt: acceptedAt.add(const Duration(milliseconds: 500)),
          responseAt: acceptedAt,
          responseType: CoordinationResponseType.useful.smallintValue,
          admissionAction: HelpOfferAdmissionAction.accept.smallintValue,
        ),
      );
      expect(entries.whereType<TimelineHelpOfferUpdated>(), isEmpty);
    });

    test('an untouched offer adds no entry', () {
      final entries = helpOfferRowsToTimelineEntries(
        beacon: Beacon.empty,
        row: _row(createdAt: t0, updatedAt: t0),
      );
      expect(entries.whereType<TimelineHelpOfferUpdated>(), isEmpty);
    });
  });

  group('helper card right after the author accepts', () {
    final l10n = lookupL10n(const Locale('en'));
    final helpOfferedLine =
        '${l10n.beaconPeopleRoleHelper} · ${l10n.beaconPeopleStatusHelpOffered}';
    final markedUsefulLine =
        '${l10n.beaconPeopleRoleHelper} · '
        '${l10n.beaconPeopleStatusHelpOfferedUseful}';

    setUp(() async {
      await GetIt.I.reset();
      GetIt.I.registerSingleton<PlatformRepositoryPort>(
        _FakePlatformRepository(),
      );
    });

    tearDown(() async {
      await GetIt.I.reset();
    });

    testWidgets('says help offered, not marked useful', (
      tester,
    ) async {
      final createdAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 1),
      );
      await tester.pumpWidget(
        _wrap(_authorTile(_justAccepted(createdAt), _participant(createdAt))),
      );
      await tester.pumpAndSettle();

      expect(find.text(helpOfferedLine), findsOneWidget);
      expect(find.text(markedUsefulLine), findsNothing);
      expect(find.textContaining('marked useful'), findsNothing);
      // The accept's own updated_at bump is not an edit (#361).
      expect(find.textContaining(l10n.labelEdited), findsNothing);
      // The admission itself stays visible on the card.
      expect(find.text(l10n.helpOfferAdmittedLabel), findsOneWidget);
    });

    testWidgets('a real edit still says edited', (tester) async {
      final createdAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 1),
      );
      final accepted = _justAccepted(createdAt);
      final edited = accepted.copyWith(
        editedAt: accepted.updatedAt.add(const Duration(seconds: 5)),
      );
      await tester.pumpWidget(
        _wrap(_authorTile(edited, _participant(createdAt))),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining(l10n.labelEdited), findsOneWidget);
    });

    testWidgets('an offer marked useful without an accept still says so', (
      tester,
    ) async {
      final createdAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 1),
      );
      final offer = _offer(
        createdAt: createdAt,
        updatedAt: createdAt,
        responseAt: createdAt.add(const Duration(seconds: 30)),
        response: CoordinationResponseType.useful,
      );
      await tester.pumpWidget(
        _wrap(_authorTile(offer, _participant(createdAt))),
      );
      await tester.pumpAndSettle();

      expect(find.text(markedUsefulLine), findsOneWidget);
    });
  });
}
