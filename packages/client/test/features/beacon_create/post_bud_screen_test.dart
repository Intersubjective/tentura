// The Request form in bud mode (plan D1): the Post parent turns the second
// step into «Кого позвать», hosted by the shared Forward recipient picker —
// members in the server's order (writers first), ineligible members hidden,
// «через X», a warning above five ticked, a note per invitee, «Закрыть
// пост…» — and the form step warns about discoverability and forwarding.
// With `kPostBuddingEnabled` off none of it shows.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/post_bud_invite_outcome.dart';
import 'package:tentura/domain/entity/post_bud_result.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/context/domain/entity/context_entity.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_row.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'post_bud_fakes.dart';

class _ContextRepositoryFake extends Fake implements ContextRepository {
  @override
  Stream<RepositoryEvent<ContextEntity>> get changes =>
      const Stream<RepositoryEvent<ContextEntity>>.empty();

  @override
  Future<Iterable<String>> fetch({bool fromCache = true}) async => [];
}

class _Router extends Mock implements StackRouter {
  final opened = <PageRouteInfo>[];

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => true;

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    opened.add(route);
    return null;
  }
}

const _profiles = [
  Profile(id: 'quiet', displayName: 'Quiet Quinn'),
  Profile(id: 'writer', displayName: 'Writer Wanda'),
  Profile(id: 'silent', displayName: 'Silent Sam'),
  Profile(id: 'blocked', displayName: 'Blocked Bob'),
  Profile(id: 'via', displayName: 'Vika'),
];

Future<({BudHarness h, BeaconCreateCubit cubit, _Router router})> _pump(
  WidgetTester tester, {
  bool enabled = true,
  BeaconForwardPolicyValue forwardPolicy = BeaconForwardPolicyValue.open,
  void Function(FakePostBudPort port)? seed,
}) async {
  final effects = FakeUiEffectPort();
  GetIt.I
    ..registerSingleton<Env>(const Env())
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<ContextRepository>(_ContextRepositoryFake());
  addTearDown(GetIt.I.reset);

  final h = BudHarness(
    parent: budPost(forwardPolicy: forwardPolicy),
    profiles: _profiles,
  );
  seed?.call(h.port);
  await registerBudInvitePicker(tester, h);
  final cubit = h.cubit(effects: effects, enabled: enabled);
  addTearDown(cubit.close);

  // Tall: the invite step is a ListView whose rows must all be built.
  const surface = Size(800, 1600);
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = _Router();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: MediaQuery(
        data: const MediaQueryData(size: surface),
        child: TenturaResponsiveScope(
          child: RouterScope(
            controller: router,
            stateHash: 0,
            inheritableObserversBuilder: () => const [],
            child: StackRouterScope(
              controller: router,
              stateHash: 0,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider(create: (_) => ContextCubit()),
                  BlocProvider<ProfileCubit>.value(value: BudProfileCubit()),
                  BlocProvider<BeaconCreateCubit>.value(value: cubit),
                ],
                child: const BeaconCreateScreen(
                  parentBeaconId: kBudPostId,
                  sourceMessageId: kBudSourceMessageId,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await settleBud(tester);
  return (h: h, cubit: cubit, router: router);
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('PostBud.NextButton')));
  await settleBud(tester);
}

Finder _rowOf(String id) => find.byWidgetPredicate(
  (w) => w is ForwardRecipientRow && w.candidate.id == id,
  skipOffstage: false,
);

/// The server's order: writers first, then the rest; `blocked` cannot be
/// invited.
void _seedMembers(FakePostBudPort port) => port.candidates = [
  budCandidate('writer', hasWritten: true, pretick: true),
  budCandidate(
    'blocked',
    hasWritten: true,
    outcome: PostBudInviteOutcome.blocked,
  ),
  budCandidate('silent', pretick: true),
  budCandidate('quiet', viaUserId: 'via'),
];

final _en = lookupL10n(const Locale('en'));

void main() {
  testWidgets('invite step is the Forward picker: server order (writers '
      'first), ineligible hidden, «via X», pre-ticked members ticked', (
    tester,
  ) async {
    await _pump(tester, seed: _seedMembers);
    expect(find.text(_en.postBudAction), findsWidgets);
    await _next(tester);

    expect(find.text(_en.postBudInviteTitle), findsOneWidget);
    expect(find.byType(ForwardRecipientPicker), findsOneWidget);
    final writer = find.descendant(
      of: _rowOf('writer'),
      matching: find.text('Writer Wanda'),
    );
    final silent = find.descendant(
      of: _rowOf('silent'),
      matching: find.text('Silent Sam'),
    );
    expect(writer, findsOneWidget);
    expect(silent, findsOneWidget);
    expect(
      tester.getTopLeft(writer).dy,
      lessThan(tester.getTopLeft(silent).dy),
    );
    expect(_rowOf('blocked'), findsNothing);
    expect(find.text('Blocked Bob', skipOffstage: false), findsNothing);
    expect(
      find.descendant(
        of: _rowOf('quiet'),
        matching: find.textContaining('Vika'),
      ),
      findsOneWidget,
      reason: '«via Vika» on the member Vika brought in',
    );
    // Pre-ticked members are ticked and can get a personal note.
    expect(
      tester.widget<ForwardRecipientRow>(_rowOf('writer')).isSelected,
      isTrue,
    );
    expect(
      tester.widget<ForwardRecipientRow>(_rowOf('silent')).isSelected,
      isTrue,
    );
    expect(
      tester.widget<ForwardRecipientRow>(_rowOf('quiet')).isSelected,
      isFalse,
    );
    expect(
      find.byTooltip(_en.forwardAddPersonalNoteForName('Writer Wanda')),
      findsOneWidget,
    );
    final picked = BlocProvider.of<ForwardCubit>(
      tester.element(find.byType(ForwardRecipientPicker)),
    );
    expect(picked.state.selectedIds, {'writer', 'silent'});
    expect(find.byKey(const Key('PostBud.ManyWarning')), findsNothing);
    expect(
      find.text(_en.postBudClosePost),
      findsOneWidget,
    );
  });

  testWidgets('more than five ticked shows the warning', (tester) async {
    await _pump(
      tester,
      seed: (port) => port.candidates = [
        for (var i = 0; i < 6; i++) budCandidate('u$i', pretick: true),
      ],
    );
    await _next(tester);
    expect(find.byType(ForwardRecipientPicker), findsOneWidget);
    expect(find.byKey(const Key('PostBud.ManyWarning')), findsOneWidget);
    expect(
      find.text(_en.postBudInviteManyWarning(6)),
      findsOneWidget,
    );
  });

  testWidgets('form step: no cover, forwarding and discoverable warnings', (
    tester,
  ) async {
    final opened = await _pump(
      tester,
      forwardPolicy: BeaconForwardPolicyValue.closed,
    );
    expect(find.byKey(const Key('BeaconCreate.CoverRow')), findsNothing);
    expect(find.byKey(const Key('PostBud.ForwardingWarning')), findsOneWidget);
    expect(find.byKey(const Key('PostBud.DiscoverableWarning')), findsNothing);

    opened.cubit.setDiscoverable(true);
    await settleBud(tester, rounds: 2);
    expect(
      find.byKey(const Key('PostBud.DiscoverableWarning')),
      findsOneWidget,
    );
  });

  testWidgets('submit buds once, opens the child, names who was skipped', (
    tester,
  ) async {
    final opened = await _pump(
      tester,
      seed: (port) {
        _seedMembers(port);
        port.result = const PostBudResult(
          outcome: PostBudOutcome.created,
          childBeaconId: 'child-9',
          invitees: [
            PostBudInviteeResult(
              userId: 'writer',
              outcome: PostBudInviteOutcome.invited,
            ),
            PostBudInviteeResult(
              userId: 'silent',
              outcome: PostBudInviteOutcome.recipientPaused,
            ),
          ],
        );
      },
    );
    await _next(tester);
    expect(find.byType(ForwardRecipientPicker), findsOneWidget);
    await tester.tap(find.byKey(const Key('PostBud.SubmitButton')));
    await settleBud(tester);

    expect(opened.h.port.calls, hasLength(1));
    expect(opened.router.opened, hasLength(1));
    final args = opened.router.opened.single.args! as BeaconViewRouteArgs;
    expect(args.id, 'child-9');
    expect(
      find.text(_en.postBudNotInvitedSnack('Silent Sam'), findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('gate off: the Post parent gets no bud form', (tester) async {
    await _pump(tester, enabled: false, seed: _seedMembers);
    expect(find.byKey(const Key('PostBud.NextButton')), findsNothing);
    expect(find.byKey(const Key('PostBud.InviteStep')), findsNothing);
    expect(find.text(_en.postBudAction), findsNothing);
  });
}
