// #664: an invited Post member who opens the budded Request itself sees
// the author's invitation there — «‹inviter› invites you to help», the note,
// and Accept / Can't make it above Offer help — not only in Activity.

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/domain/attention/attention_actor_profiles_case.dart';
import 'package:tentura/domain/entity/author_invite.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/author_invite_case.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_my_invite_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_my_invite_banner.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_showcase_surface.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/domain/use_case/inbox_case.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../inbox/author_invite_test_support.dart';
import '../inbox/inbox_case_test.dart'
    show FakeInboxRepository, buildTestBeaconThreadsCase, buildTestInboxCase;
import 'beacon_view_screen_harness.dart';

const _mira = Profile(id: 'Umira', displayName: 'Mira');
final _t = DateTime.utc(2026, 10, 23);

PendingAuthorInvite _invite(String id, String beaconId, {String? note}) =>
    PendingAuthorInvite(
      id: id,
      beaconId: beaconId,
      beaconTitle: 'Move on Saturday',
      inviterId: _mira.id,
      createdAt: _t,
      note: note,
    );

void main() {
  group('BeaconMyInviteCubit', () {
    late FakeAuthorInvitePort port;
    late FakeUiEffectPort effects;
    late FakeInboxRepository inbox;
    late int answered;
    bool? lastAccepted;

    BeaconMyInviteCubit build(String beaconId) => BeaconMyInviteCubit(
      beaconId: beaconId,
      authorInviteCase: buildAuthorInviteCase(port),
      actorProfiles: buildActorProfiles(const [_mira]),
      inboxCase: buildTestInboxCase(inbox, buildTestBeaconThreadsCase()),
      effects: effects,
      onAnswered: ({accepted = false}) async {
        answered++;
        lastAccepted = accepted;
      },
    );

    setUp(() {
      port = FakeAuthorInvitePort()
        ..pending = [
          _invite('I-other', 'B-other'),
          _invite('I1', 'B1', note: 'You know the van'),
        ];
      effects = FakeUiEffectPort();
      inbox = FakeInboxRepository();
      answered = 0;
      lastAccepted = null;
    });

    test(
      'keeps the pending invite on this Request, with its inviter',
      () async {
        final cubit = build('B1');
        addTearDown(cubit.close);
        await cubit.load();
        expect(cubit.state.invite?.id, 'I1');
        expect(cubit.state.invite?.note, 'You know the van');
        expect(cubit.state.inviter?.displayName, 'Mira');
      },
    );

    group('InboxCase injection', () {
      tearDown(() async {
        if (GetIt.I.isRegistered<InboxCase>()) {
          await GetIt.I.unregister<InboxCase>();
        }
      });

      test('without an InboxCase anywhere the cubit fails loudly', () async {
        if (GetIt.I.isRegistered<InboxCase>()) {
          await GetIt.I.unregister<InboxCase>();
        }
        // No silent drop of the decline note: the wiring is a bug to see.
        expect(
          () => BeaconMyInviteCubit(
            beaconId: 'B1',
            authorInviteCase: buildAuthorInviteCase(port),
            actorProfiles: buildActorProfiles(const [_mira]),
            effects: effects,
          ),
          throwsA(anything),
        );
      });

      test('the registered InboxCase records the decline note', () async {
        GetIt.I.registerSingleton<InboxCase>(
          buildTestInboxCase(inbox, buildTestBeaconThreadsCase()),
        );
        final cubit = BeaconMyInviteCubit(
          beaconId: 'B1',
          authorInviteCase: buildAuthorInviteCase(port),
          actorProfiles: buildActorProfiles(const [_mira]),
          effects: effects,
        );
        addTearDown(cubit.close);
        await cubit.load();
        await cubit.decline(message: 'Away that weekend');
        expect(inbox.lastSetStatus, (
          beaconId: 'B1',
          status: InboxItemStatus.rejected,
          rejectionMessage: 'Away that weekend',
        ));
      });
    });

    test('no invite on this Request: nothing to show', () async {
      final cubit = build('B-none');
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state.invite, isNull);
    });

    test('accept answers the invite, clears it and reloads the page', () async {
      final cubit = build('B1');
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.accept();
      expect(port.accepted, ['I1']);
      expect(port.declined, isEmpty);
      expect(cubit.state.invite, isNull);
      expect(cubit.state.busy, isFalse);
      expect(answered, 1);
      expect(lastAccepted, isTrue);
    });

    test('decline answers the invite and records the note', () async {
      final cubit = build('B1');
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.decline(message: 'Away that weekend');
      expect(port.declined, ['I1']);
      expect(cubit.state.invite, isNull);
      expect(lastAccepted, isFalse);
      // The same note write as the Activity invite card: on the inbox row.
      expect(inbox.lastSetStatus, (
        beaconId: 'B1',
        status: InboxItemStatus.rejected,
        rejectionMessage: 'Away that weekend',
      ));
      expect(answered, 1);
    });

    test('decline with no note sends only the invite decline', () async {
      final cubit = build('B1');
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.decline();
      expect(port.declined, ['I1']);
      expect(inbox.lastSetStatus, isNull);
      expect(answered, 1);
    });

    test('a failed note write still counts the decline', () async {
      inbox.setStatusError = Exception('offline');
      final cubit = build('B1');
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.decline(message: 'Away that weekend');
      expect(port.declined, ['I1']);
      expect(cubit.state.invite, isNull);
      expect(effects.emitted.whereType<ShowError>(), isEmpty);
      expect(answered, 1);
    });

    test('a refused decline records no note', () async {
      final cubit = build('B1');
      addTearDown(cubit.close);
      await cubit.load();
      port.error = Exception('withdrawn');
      await cubit.decline(message: 'Away that weekend');
      expect(cubit.state.invite?.id, 'I1');
      expect(inbox.lastSetStatus, isNull);
      expect(answered, 0);
    });

    test('a refused accept keeps the invite and shows the error', () async {
      final cubit = build('B1');
      addTearDown(cubit.close);
      await cubit.load();
      port.error = Exception('expired');
      await cubit.accept();
      expect(port.accepted, ['I1']);
      expect(cubit.state.invite?.id, 'I1');
      expect(cubit.state.busy, isFalse);
      expect(effects.emitted.whereType<ShowError>(), hasLength(1));
      expect(answered, 0);
    });
  });

  group('Request showcase', () {
    const invitee = 'invitee';

    tearDown(unregisterBeaconViewHarnessGetIt);

    Future<void> pumpShowcase(
      WidgetTester tester, {
      required List<PendingAuthorInvite> pending,
    }) async {
      final author = beaconViewHarnessAuthorState();
      await pumpBeaconViewHarness(
        tester,
        size: kBeaconViewHarnessCompact,
        beaconState: author.copyWith(
          beacon: author.beacon.copyWith(
            accessLevel: BeaconAccessLevel.observer,
            viewerCanForward: true,
          ),
          myProfile: const Profile(id: invitee, displayName: 'Theo'),
          roomParticipants: const [],
        ),
        threadsState: beaconViewHarnessThreadsState(),
        afterGetItRegistered: () {
          // Swap the harness's empty invites for these; its InboxCase stays,
          // the banner's decline note needs one.
          GetIt.I
            ..unregister<AuthorInviteCase>()
            ..unregister<AttentionActorProfilesCase>()
            ..registerSingleton<AuthorInviteCase>(
              buildAuthorInviteCase(FakeAuthorInvitePort()..pending = pending),
            )
            ..registerSingleton<AttentionActorProfilesCase>(
              buildActorProfiles(const [_mira]),
            );
        },
      );
      await tester.pumpAndSettle();
      expect(find.byType(BeaconShowcaseSurface), findsOneWidget);
    }

    testWidgets('an invited member sees the invitation above Offer help', (
      tester,
    ) async {
      await pumpShowcase(
        tester,
        pending: [
          _invite('I1', kBeaconViewHarnessBeaconId, note: 'You know the van'),
        ],
      );
      expect(find.text('Mira invites you to help'), findsOneWidget);
      expect(find.text('You know the van'), findsOneWidget);
      final accept = find.byKey(BeaconMyInviteBanner.acceptKey);
      final decline = find.byKey(BeaconMyInviteBanner.declineKey);
      expect(accept, findsOneWidget);
      expect(decline, findsOneWidget);
      expect(
        find.descendant(of: accept, matching: find.text('Accept')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: decline, matching: find.text("Can't make it")),
        findsOneWidget,
      );
      final offerHelp = find.text('Offer help');
      expect(offerHelp, findsOneWidget);
      expect(
        tester.getTopLeft(accept).dy,
        lessThan(tester.getTopLeft(offerHelp).dy),
      );
    });

    testWidgets('no invite on this Request: the plain showcase', (
      tester,
    ) async {
      await pumpShowcase(tester, pending: [_invite('I2', 'another-request')]);
      expect(find.byKey(BeaconMyInviteBanner.acceptKey), findsNothing);
      expect(find.byKey(BeaconMyInviteBanner.declineKey), findsNothing);
      expect(find.text('Mira invites you to help'), findsNothing);
      expect(find.text('Offer help'), findsOneWidget);
    });
  });
}
