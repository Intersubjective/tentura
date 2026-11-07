// #252 (ichorid 2026-11-02): a member with no contacts writes a new Post and
// reaches «Получатели»: the picker said «Пока некому отправить» with the
// trust hint but offered no invite, so the member was stuck with a written
// message, and the «Пока не видели 0 / Уже в цепочке 0» tab row was noise.
// Now the embedded new-Post picker's empty state offers «Пригласить
// знакомого», which opens the invite-link dialog over the composer (the draft
// stays), and the tab row is hidden while there is no one at all. The
// Request forward picker keeps its empty state and «Invite new person» chip;
// with some contacts the tabs still show.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/post_create_screen.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/screen/forward_beacon_screen.dart';
import 'package:tentura/features/forward/ui/widget/forward_invite_bar.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/forward/ui/widget/forward_scope_links.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_create/fake_beacon_ports.dart';

const _viewer = Profile(id: 'Uviewer', displayName: 'Зоя');
const _draft = 'Ищу, с кем пойти на концерт в субботу';

const _sizes = {'375x667': Size(375, 667), 'desktop': Size(1280, 800)};
const _locales = [Locale('ru'), Locale('en')];

class _ProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _viewer);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);

  @override
  bool get isClosed => false;

  @override
  Future<void> close() async {}
}

class _PresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream => const Stream.empty();
}

class _NoClipboard extends Fake implements ClipboardImageRepository {}

class _FakeInvitationRepository extends Fake implements InvitationRepository {
  final created = <String?>[];
  final deleted = <String>[];

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<InvitationsFetchResult> fetchMine({
    int pendingOffset = 0,
    int pendingLimit = 0,
    int acceptedOffset = 0,
    int acceptedLimit = 0,
  }) async => (
    pending: <InvitationEntity>[],
    accepted: <InvitationEntity>[],
    pendingCount: 0,
  );

  @override
  Future<int> fetchTtlHours() async => 48;

  @override
  Future<InvitationFetchByIdResult?> fetchById(String id) async => null;

  @override
  Future<InvitationEntity> create({
    required String addresseeName,
    String? beaconId,
  }) async {
    created.add(beaconId);
    return InvitationEntity(
      id: 'Iabc123def456',
      beaconId: beaconId,
      createdAt: DateTime.utc(2026, 11, 2),
      updatedAt: DateTime.utc(2026, 11, 2),
    );
  }

  @override
  Future<void> deleteById(String id) async => deleted.add(id);

  @override
  Future<void> dispose() async {}
}

/// Records router calls: the invite must not navigate away from the composer.
class _NavRouter extends Fake implements StackRouter {
  late BuildContext host;
  final calls = <String>[];

  @override
  String get currentUrl => kPathPostNew;

  @override
  void markUrlStateForReplace() {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add('${invocation.memberName}');
    return Future<dynamic>.value();
  }

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => true;

  @override
  Future<bool> maybePop<T extends Object?>([T? result]) async =>
      Navigator.of(host).maybePop(result);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _useSize(WidgetTester tester, Size size) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const _clara = ForwardCandidate(
  profile: Profile(id: 'Uclara', displayName: 'Clara', rScore: 1, score: 70),
);

/// The new-Post composer, opened over a home route, on its recipients step
/// with [_draft] written.
Future<({_FakeInvitationRepository invitations, _NavRouter router})>
_pumpPostRecipients(
  WidgetTester tester, {
  required Locale locale,
  required Size size,
  List<ForwardCandidate> candidates = const [],
}) async {
  _useSize(tester, size);
  final effects = FakeUiEffectPort();
  final invitations = _FakeInvitationRepository();
  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);
  getIt
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<ProfileCubit>(_ProfileCubit())
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(_NoClipboard())
    ..registerSingleton<InvitationRepository>(invitations);

  final cubit = BeaconCreateCubit(
    kind: BeaconKind.post,
    beaconCreateCase: fakeBeaconCreateCase(),
    effects: effects,
  );
  addTearDown(cubit.close);
  final forward = ForwardCubit(
    beaconId: '',
    embedded: true,
    effects: effects,
    debugSkipInitialLoad: true,
    debugInitialState: ForwardState(
      candidates: candidates,
      candidatesLoad: candidates.isEmpty
          ? const ForwardCandidatesEmpty()
          : const ForwardCandidatesReady(),
    ),
  );
  addTearDown(forward.close);

  final router = _NavRouter();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: Builder(
        builder: (homeContext) => TextButton(
          onPressed: () => Navigator.of(homeContext).push<void>(
            MaterialPageRoute<void>(
              builder: (routeContext) {
                router.host = routeContext;
                return RouterScope(
                  controller: router,
                  stateHash: 0,
                  inheritableObserversBuilder: () => const [],
                  child: StackRouterScope(
                    controller: router,
                    stateHash: 0,
                    child: TenturaResponsiveScope(
                      child: MultiBlocProvider(
                        providers: [
                          BlocProvider<ProfileCubit>.value(
                            value: GetIt.I<ProfileCubit>(),
                          ),
                          BlocProvider<PresenceCubit>.value(
                            value: _PresenceCubit(),
                          ),
                          BlocProvider<ScreenCubit>(
                            create: (_) => ScreenCubit(effects),
                          ),
                          BlocProvider<BeaconCreateCubit>.value(value: cubit),
                          BlocProvider<ForwardCubit>.value(value: forward),
                        ],
                        child: const PostCreateScreen(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          child: const Text('open-post-create'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open-post-create'));
  await _settle(tester);

  await tester.enterText(find.byKey(PostCreateScreen.textFieldKey), _draft);
  await _settle(tester);
  await tester.tap(find.byKey(PostCreateScreen.nextButtonKey));
  await _settle(tester);
  expect(find.byType(ForwardRecipientPicker), findsOneWidget);
  return (invitations: invitations, router: router);
}

Finder _invite(L10n l10n) => find.text(l10n.emptyInviteSomeoneAction);

void main() {
  for (final locale in _locales) {
    final l10n = lookupL10n(locale);
    for (final size in _sizes.entries) {
      final tag = '${locale.languageCode} ${size.key}';

      testWidgets('$tag: no contacts, the new-Post picker shows the empty '
          'state with the trust hint and «${l10n.emptyInviteSomeoneAction}», '
          'and no tab row', (tester) async {
        await _pumpPostRecipients(tester, locale: locale, size: size.value);

        expect(find.text(l10n.forwardEmptyNoContactsTitle), findsOneWidget);
        expect(find.text(l10n.trustWidensReachHint), findsOneWidget);
        expect(_invite(l10n), findsOneWidget);
        expect(find.byType(ForwardScopeLinks), findsNothing);
        expect(find.text(l10n.forwardScopeUnseenShort), findsNothing);
        expect(find.text(l10n.forwardScopeInvolvedShort), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$tag: the invite opens the invite link over the composer; '
          'back returns to it with the draft unchanged', (tester) async {
        final h = await _pumpPostRecipients(
          tester,
          locale: locale,
          size: size.value,
        );

        await tester.ensureVisible(_invite(l10n));
        await tester.tap(_invite(l10n));
        await tester.pumpAndSettle();

        // The existing invite-link dialog, a plain invite (no request).
        expect(find.byType(ShareCodeDialog), findsOneWidget);
        expect(find.text(l10n.labelInvitationCode), findsOneWidget);
        expect(h.invitations.created, [null]);
        // Over the composer: nothing navigated, the composer is mounted.
        expect(h.router.calls, isEmpty);
        expect(find.byType(PostCreateScreen, skipOffstage: false), findsOne);

        // Back closes the dialog only.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(ShareCodeDialog), findsNothing);
        expect(find.byType(ForwardRecipientPicker), findsOneWidget);
        expect(find.text(l10n.forwardEmptyNoContactsTitle), findsOneWidget);
        expect(h.router.calls, isEmpty);

        // The Post step still holds the text as written.
        await tester.tap(
          find.descendant(
            of: find.byType(TenturaTopBar),
            matching: find.byIcon(Icons.arrow_back),
          ),
        );
        await _settle(tester);
        expect(
          tester
              .widget<TextField>(find.byKey(PostCreateScreen.textFieldKey))
              .controller!
              .text,
          _draft,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('$tag: with some contacts the tab row still shows', (
        tester,
      ) async {
        await _pumpPostRecipients(
          tester,
          locale: locale,
          size: size.value,
          candidates: const [_clara],
        );
        expect(find.byType(ForwardScopeLinks), findsOneWidget);
        expect(find.text('Clara'), findsWidgets);
        expect(find.text(l10n.forwardEmptyNoContactsTitle), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('${locale.languageCode} 375x667: the Request forward picker '
        'keeps its empty state and «${l10n.forwardInviteNewPerson}» chip', (
      tester,
    ) async {
      _useSize(tester, const Size(375, 667));
      final effects = FakeUiEffectPort();
      GetIt.I
        ..registerSingleton<InvitationRepository>(_FakeInvitationRepository())
        ..registerSingleton<UiEffectPort>(effects);
      addTearDown(GetIt.I.reset);
      final cubit = ForwardCubit(
        beaconId: 'b1',
        debugSkipInitialLoad: true,
        effects: effects,
      );
      addTearDown(cubit.close);
      cubit.emit(
        ForwardState(
          beaconId: 'b1',
          beacon: Beacon.empty.copyWith(
            id: 'aaaaaaaa-bbbb-cccc-dddd-1234567890ab',
            title: 'Test beacon',
            context: 'General',
            viewerCanForward: true,
            startAt: DateTime.utc(2025, 5, 12),
            endAt: DateTime.utc(2025, 5, 19),
          ),
          candidatesLoad: const ForwardCandidatesEmpty(),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => TenturaResponsiveScope(child: child!),
          locale: locale,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: TenturaTheme.light(),
          home: MultiBlocProvider(
            providers: [
              BlocProvider<ForwardCubit>.value(value: cubit),
              BlocProvider<ProfileCubit>.value(value: _ProfileCubit()),
            ],
            child: const ForwardBeaconPage(beaconId: 'b1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(TestIds.key(TestIds.forwardInviteNewPerson)),
        findsOneWidget,
      );
      expect(find.byType(ForwardInviteBar), findsOneWidget);
      expect(find.text(l10n.forwardEmptyNoContactsTitle), findsOneWidget);
      expect(find.text(l10n.trustWidensReachHint), findsOneWidget);
      expect(_invite(l10n), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
