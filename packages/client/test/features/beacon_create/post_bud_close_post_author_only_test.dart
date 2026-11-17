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
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/context/domain/entity/context_entity.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
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
    ..registerSingleton<ContextRepository>(_ContextRepositoryFake());
  addTearDown(GetIt.I.reset);

  final h = BudHarness(
    parent: budPost(authorId: postAuthorId),
    profiles: _profiles,
  );
  h.port.candidates = candidates;
  await registerBudInvitePicker(tester, h);
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

/// Goes to the invite step, which is the shared Forward recipient picker.
Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('PostBud.NextButton')));
  await settleBud(tester);
  expect(find.byType(ForwardRecipientPicker), findsOneWidget);
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('PostBud.SubmitButton')));
  await settleBud(tester);
}

final _closePostLabel = lookupL10n(const Locale('en')).postBudClosePost;

Finder _closePostBox() => find.widgetWithText(
  CheckboxListTile,
  _closePostLabel,
  skipOffstage: false,
);

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

        expect(
          find.byWidgetPredicate(
            (w) => w is ForwardRecipientRow && w.candidate.id == 'author',
          ),
          findsOne,
        );
        expect(_closePostBox(), findsNothing);
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
          _closePostBox(),
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
          _closePostBox(),
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
          _closePostBox(),
        );
        expect(box.value, isFalse);

        await _submit(tester);
        expect(opened.h.port.calls.single.closePost, isFalse);
      },
    );
  });
}
