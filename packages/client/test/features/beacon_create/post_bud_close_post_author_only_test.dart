// Only the Post's author may close it when budding a Request (#666). The
// invite step shows «Close the post…» to the author with today's default and
// never to anyone else; a member who is not the author submits closePost=false
// even with every member ticked.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/post_bud_invite_candidate.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/context/domain/entity/context_entity.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
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
  Profile(id: 'author', displayName: 'Author Ann'),
  Profile(id: 'other', displayName: 'Other Olga'),
  Profile(id: 'third', displayName: 'Third Tom'),
];

Future<({BudHarness h, BeaconCreateCubit cubit, _Router router})> _pump(
  WidgetTester tester, {
  required String postAuthorId,
  required List<PostBudInviteCandidate> candidates,
}) async {
  final effects = FakeUiEffectPort();
  GetIt.I
    ..registerSingleton<Env>(const Env())
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<AuthCase>(
      buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote()),
    )
    ..registerSingleton<ContextRepository>(_ContextRepositoryFake());
  addTearDown(GetIt.I.reset);

  final h = BudHarness(
    parent: budPost(authorId: postAuthorId),
    profiles: _profiles,
  );
  h.port.candidates = candidates;
  final cubit = h.cubit(effects: effects);
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
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return (h: h, cubit: cubit, router: router);
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('PostBud.NextButton')));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('PostBud.SubmitButton')));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

const _closePostLabel = 'Close the post and continue in the request';

void main() {
  group('invite step «Close the post» belongs to the Post author', () {
    testWidgets(
      'a member who is not the author sees no checkbox and sends closePost=false',
      (tester) async {
        final opened = await _pump(
          tester,
          postAuthorId: 'author',
          candidates: [
            budCandidate('author', pretick: true),
            budCandidate('other', pretick: true),
            budCandidate('third', pretick: true),
          ],
        );
        await _next(tester);

        expect(find.byKey(const Key('PostBud.InviteStep')), findsOneWidget);
        expect(find.byKey(const ValueKey('PostBud.Invitee.author')), findsOne);
        expect(find.byKey(const Key('PostBud.ClosePost')), findsNothing);
        expect(find.text(_closePostLabel), findsNothing);

        await _submit(tester);
        expect(opened.h.port.calls, hasLength(1));
        expect(opened.h.port.calls.single.closePost, isFalse);
      },
    );

    testWidgets(
      'the author sees the checkbox ticked by default once every member is '
      'ticked, and sends closePost=true',
      (tester) async {
        final opened = await _pump(
          tester,
          postAuthorId: 'me',
          candidates: [
            budCandidate('other', pretick: true),
            budCandidate('third', pretick: true),
          ],
        );
        await _next(tester);

        expect(find.text(_closePostLabel), findsOneWidget);
        final box = tester.widget<CheckboxListTile>(
          find.byKey(const Key('PostBud.ClosePost')),
        );
        expect(box.value, isTrue);

        await _submit(tester);
        expect(opened.h.port.calls.single.closePost, isTrue);
      },
    );

    testWidgets(
      'the author of a two-member Post gets the checkbox ticked even when the '
      'only invitee is not ticked',
      (tester) async {
        final opened = await _pump(
          tester,
          postAuthorId: 'me',
          candidates: [budCandidate('other')],
        );
        await _next(tester);

        final box = tester.widget<CheckboxListTile>(
          find.byKey(const Key('PostBud.ClosePost')),
        );
        expect(box.value, isTrue);

        await _submit(tester);
        expect(opened.h.port.calls.single.closePost, isTrue);
      },
    );

    testWidgets(
      'the author gets the checkbox unticked while a member is left out',
      (tester) async {
        final opened = await _pump(
          tester,
          postAuthorId: 'me',
          candidates: [
            budCandidate('other', pretick: true),
            budCandidate('third'),
            budCandidate('author'),
          ],
        );
        await _next(tester);

        final box = tester.widget<CheckboxListTile>(
          find.byKey(const Key('PostBud.ClosePost')),
        );
        expect(box.value, isFalse);

        await _submit(tester);
        expect(opened.h.port.calls.single.closePost, isFalse);
      },
    );
  });
}
