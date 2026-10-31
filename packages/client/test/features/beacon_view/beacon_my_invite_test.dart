// #664: an invited Post member who opens the budded Request itself sees
// the author's invitation there — «‹inviter› invites you to help», the note,
// and Accept / Can't make it above Offer help — not only in Activity.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/attention/attention_actor_profiles_case.dart';
import 'package:tentura/domain/entity/author_invite.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/author_invite_case.dart';
import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_my_invite_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_my_invite_banner.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_showcase_surface.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/domain/use_case/inbox_case.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_handler.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';
import 'package:tentura/ui/widget/undo_snack_bar.dart';
import 'package:tentura/ui/message/action_message_base.dart';

import '../../support/phone_surface.dart';
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

/// `dispatchUiEffect` resolves the router up front; ShowMessage never uses it.
class _UnusedRootRouter extends Mock implements RootRouter {}

/// A snack bar line a person reads; its icon glyphs are `RichText`s too.
bool _isCopy(String line) => RegExp(r'\p{L}', unicode: true).hasMatch(line);

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

    // #797: the Request page's «Can't make it» offers the same Undo as the
    // Activity invite card.
    test('a decline the server took offers Undo; pressing it reverts the '
        'decline and the invitation banner comes back', () async {
      final cubit = build('B1');
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.decline(message: 'Away that weekend');
      expect(cubit.state.invite, isNull);

      final offer = effects.emitted
          .whereType<ShowMessage>()
          .map((e) => e.message)
          .whereType<LocalizableActionMessage>()
          .singleOrNull;
      expect(offer, isNotNull, reason: 'the decline offers an Undo');
      expect(offer!.label.toEn, 'Undo');
      expect(offer.label.toRu, 'Отменить');
      expect(port.revertedDeclines, isEmpty);

      offer.onPressed();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(port.revertedDeclines, ['I1']);
      expect(cubit.state.invite?.id, 'I1');
      expect(cubit.state.invite?.note, 'You know the van');
      expect(effects.emitted.whereType<ShowError>(), isEmpty);
    });

    test('a refused decline offers no Undo', () async {
      final cubit = build('B1');
      addTearDown(cubit.close);
      await cubit.load();
      port.error = Exception('withdrawn');

      await cubit.decline(message: 'Away that weekend');

      expect(
        effects.emitted.whereType<ShowMessage>().map((e) => e.message),
        isNot(contains(isA<LocalizableActionMessage>())),
      );
    });

    test('a refused Undo shows the error', () async {
      final cubit = build('B1');
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.decline();
      final offer = effects.emitted
          .whereType<ShowMessage>()
          .map((e) => e.message)
          .whereType<LocalizableActionMessage>()
          .firstOrNull;
      expect(offer, isNotNull, reason: 'the decline offers an Undo');
      const refusal = AuthorInviteRequestNotOpenException();
      port.revertError = refusal;

      offer!.onPressed();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(port.revertedDeclines, ['I1']);
      expect(effects.emitted.whereType<ShowError>().single.error, refusal);
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

  // The Request page's «Can't make it» offers the same Undo bar as the
  // Activity card (#797): the invitation banner is what comes back.
  group("Undo after «Can't make it» on the Request page banner", () {
    late FakeAuthorInvitePort port;
    late FakeUiEffectPort effects;

    setUp(() {
      port = FakeAuthorInvitePort()
        ..pending = [_invite('I1', 'B1', note: 'You know the van')];
      effects = FakeUiEffectPort();
      GetIt.I
        ..registerSingleton<Logger>(Logger('undo-test')) // error bars log
        ..registerSingleton<RootRouter>(_UnusedRootRouter())
        ..registerSingleton<UiEffectPort>(effects)
        ..registerSingleton<AuthorInviteCase>(buildAuthorInviteCase(port))
        ..registerSingleton<AttentionActorProfilesCase>(
          buildActorProfiles(const [_mira]),
        )
        ..registerSingleton<InboxCase>(
          buildTestInboxCase(
            FakeInboxRepository(),
            buildTestBeaconThreadsCase(),
          ),
        );
    });

    tearDown(GetIt.I.reset);

    Future<void> pumpBanner(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
      Size size = const Size(390, 844),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: UiEffectHandler(
            effects: effects,
            child: const Scaffold(
              body: SingleChildScrollView(
                child: BeaconMyInviteBanner(beaconId: 'B1'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    /// «Can't make it» → the dialog → OK, as a person does it.
    Future<void> declineThroughDialog(
      WidgetTester tester, {
      required String ok,
    }) async {
      await tester.tap(find.byKey(BeaconMyInviteBanner.declineKey));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField), 'Away that weekend');
      await tester.tap(find.text(ok));
      // An action snack bar is shown after the next frame; a test with no
      // animation running has to ask for it (the app always has one).
      tester.binding.scheduleFrame();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    final banner = find.byKey(BeaconMyInviteBanner.acceptKey);
    final undo = find.descendant(
      of: find.byType(SnackBar),
      matching: find.byType(SnackBarAction),
    );
    // The bar's message is a RichText; the action label is a Text (a
    // RichText too), so this finds both.
    final snackBarTexts = find.descendant(
      of: find.byType(SnackBar),
      matching: find.byType(RichText),
    );

    testWidgets('the banner is replaced by the shared Undo bar, and Undo '
        'brings the invitation banner back', (tester) async {
      await pumpBanner(tester);
      expect(banner, findsOneWidget);

      await declineThroughDialog(tester, ok: L10nEn().buttonOk);

      expect(port.declined, ['I1']);
      expect(banner, findsNothing);
      expect(undo, findsOneWidget);
      expect(
        find.descendant(of: undo, matching: find.text('Undo')),
        findsOneWidget,
      );
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.duration, kUndoSnackBarDuration);
      expect(bar.persist, isFalse);
      expect(port.revertedDeclines, isEmpty, reason: 'nothing undone yet');

      await tester.tap(undo);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(port.revertedDeclines, ['I1']);
      expect(banner, findsOneWidget);
      expect(find.text('Mira invites you to help'), findsOneWidget);
      expect(find.text('You know the van'), findsOneWidget);
      expect(find.byKey(BeaconMyInviteBanner.declineKey), findsOneWidget);
    });

    testWidgets('a refused Undo tells the person in a plain sentence and '
        'the banner stays gone', (tester) async {
      port.revertError = const AuthorInviteRequestNotOpenException();
      await pumpBanner(tester);
      await declineThroughDialog(tester, ok: L10nEn().buttonOk);
      expect(undo, findsOneWidget);

      await tester.tap(undo);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(port.revertedDeclines, ['I1']);
      expect(banner, findsNothing);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('Undo'),
        ),
        findsNothing,
        reason: 'the Undo bar gave way to the error bar',
      );
      final message = [
        for (final text in tester.widgetList<RichText>(snackBarTexts))
          text.text.toPlainText().trim(),
      ].firstWhere(_isCopy, orElse: () => '');
      expect(message, isNotEmpty, reason: 'the refusal is told');
      expect(message, isNot(matches(RegExp(r'^[a-z]+(?:[A-Z][a-z0-9]*)+$'))));
      for (final raw in ['Exception', 'Instance of', 'AuthorInvite']) {
        expect(message, isNot(contains(raw)));
      }
      expect(message.split(RegExp(r'\s+')).length, greaterThan(2));
      expect(message, endsWith('.'));
    });

    // Fix completeness step 4: QA's phone, in Russian.
    testWidgets('375×667 in Russian: the Undo bar renders in full and '
        'works', (tester) async {
      await usePhoneSurface(tester);
      await pumpBanner(tester, locale: const Locale('ru'), size: kPhoneSurface);
      expect(banner, findsOneWidget);

      await declineThroughDialog(tester, ok: L10nRu().buttonOk);

      expect(port.declined, ['I1']);
      expect(banner, findsNothing);
      expect(undo, findsOneWidget);
      expect(
        find.descendant(of: undo, matching: find.text('Отменить')),
        findsOneWidget,
      );
      final bar = tester.getRect(find.byType(SnackBar));
      expect(bar.left, greaterThanOrEqualTo(0));
      expect(bar.right, lessThanOrEqualTo(kPhoneSurface.width));
      expect(bar.bottom, lessThanOrEqualTo(kPhoneSurface.height));
      final action = tester.getRect(undo);
      expect(action.left, greaterThanOrEqualTo(bar.left));
      expect(action.right, lessThanOrEqualTo(bar.right));
      // The message beside the action is whole: no ellipsis, in Russian.
      final lines = [
        for (final text in tester.widgetList<RichText>(snackBarTexts))
          text.text.toPlainText().trim(),
      ].where(_isCopy);
      expect(lines.length, greaterThan(1), reason: 'message and action');
      for (final line in lines) {
        expect(line, isNot(endsWith('…')));
        expect(line, matches(RegExp('[А-Яа-я]')));
      }
      expect(tester.takeException(), isNull);

      await tester.tap(undo);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(port.revertedDeclines, ['I1']);
      expect(banner, findsOneWidget);
      expect(find.text('Принять'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
