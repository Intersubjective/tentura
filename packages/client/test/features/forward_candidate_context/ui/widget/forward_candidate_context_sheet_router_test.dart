import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_state.dart';
import 'package:tentura/features/forward_candidate_context/domain/entity/candidate_connection_context.dart';
import 'package:tentura/features/forward_candidate_context/domain/port/forward_candidate_context_repository_port.dart';
import 'package:tentura/features/forward_candidate_context/domain/use_case/load_forward_candidate_context_case.dart';
import 'package:tentura/features/forward_candidate_context/ui/widget/forward_candidate_context_sheet.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_bus.dart';
import 'package:tentura/ui/l10n/l10n.dart';

final class _Auth extends Fake implements AuthCubit {
  @override
  AuthState get state => AuthState(
    updatedAt: DateTime(2026),
    currentAccountId: 'U1',
  );

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

final class _Settings extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

final class _ContextRepository
    implements ForwardCandidateContextRepositoryPort {
  @override
  Future<CandidateConnectionContext> load({
    required String candidateId,
    required String context,
  }) async => const CandidateConnectionContext(
    status: CandidateConnectionContextStatus.unavailable,
  );
}

final class _MutableForwardCubit extends ForwardCubit {
  _MutableForwardCubit({required ForwardState initialState})
    : super(
        beaconId: initialState.beaconId,
        context: initialState.context,
        debugSkipInitialLoad: true,
        debugInitialState: initialState,
        effects: UiEffectBus(),
      );

  void removeCandidate() {
    emit(state.copyWith(candidates: const []));
  }
}

class _ForwardHost extends StatefulWidget {
  const _ForwardHost({required this.cubit, required this.candidate});

  final ForwardCubit cubit;
  final ForwardCandidate candidate;

  @override
  State<_ForwardHost> createState() => _ForwardHostState();
}

class _ForwardHostState extends State<_ForwardHost> {
  int count = 0;

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: widget.cubit,
    child: Scaffold(
      body: Column(
        children: [
          Text('forward-count:$count'),
          FilledButton(
            onPressed: () => setState(() => count++),
            child: const Text('increment-forward'),
          ),
          FilledButton(
            onPressed: () => unawaited(
              showForwardCandidateContextSheet(
                sourceContext: context,
                forwardCubit: widget.cubit,
                candidate: widget.candidate,
              ),
            ),
            child: const Text('open-candidate'),
          ),
        ],
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RootRouter router;
  late ForwardCubit forwardCubit;
  late PageInfo forwardPage;
  late PageInfo profilePage;
  late ForwardCandidate candidate;

  setUpAll(() {
    forwardPage = ForwardBeaconRoute.page;
    profilePage = ProfileViewRoute.page;
  });

  tearDownAll(() {
    ForwardBeaconRoute.page = forwardPage;
    ProfileViewRoute.page = profilePage;
  });

  setUp(() {
    candidate = const ForwardCandidate(
      profile: Profile(
        id: 'U2',
        displayName: 'Alice',
        description: 'Helps with product research.',
        myVote: 1,
      ),
      topCapabilities: ['general'],
    );
    forwardCubit = _MutableForwardCubit(
      initialState: ForwardState(
        beaconId: 'B1',
        context: 'personal',
        candidates: [candidate],
      ),
    );
    GetIt.I.registerSingleton<LoadForwardCandidateContextCase>(
      LoadForwardCandidateContextCase(
        _ContextRepository(),
        env: const Env(),
        logger: Logger('ForwardCandidateContextSheetRouterTest'),
      ),
    );
    ForwardBeaconRoute.page = PageInfo(
      ForwardBeaconRoute.name,
      builder: (_) => _ForwardHost(cubit: forwardCubit, candidate: candidate),
    );
    ProfileViewRoute.page = PageInfo(
      ProfileViewRoute.name,
      builder: (data) => Scaffold(
        body: Text(
          'full-profile:${data.inheritedPathParams.getString('id', '')}',
        ),
      ),
    );
    router = RootRouter(
      Logger('ForwardCandidateContextSheetRouterTest'),
      _Auth(),
      _Settings(),
      PostJoinNavigationCubit(),
    );
  });

  tearDown(() async {
    router.dispose();
    await forwardCubit.close();
    await GetIt.I.reset();
  });

  Future<void> pump(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/forward/B1';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        routerConfig: router.config(
          deepLinkBuilder: router.deepLinkBuilder,
          deepLinkTransformer: router.deepLinkTransformer,
          reevaluateListenable: router.reevaluateListenable,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final entry in [
    ('compact', const Size(390, 844)),
    ('regular', const Size(900, 900)),
  ]) {
    testWidgets('${entry.$1} sheet keeps Forward mounted below Profile', (
      tester,
    ) async {
      await pump(tester, entry.$2);
      await tester.tap(find.text('increment-forward'));
      await tester.tap(find.text('open-candidate'));
      await tester.pumpAndSettle();

      expect(find.text('Direct connection'), findsOneWidget);
      expect(router.stackData.map((data) => data.name), [
        ForwardBeaconRoute.name,
      ]);

      await tester.tap(find.text('View full profile'));
      await tester.pumpAndSettle();

      expect(find.text('full-profile:U2'), findsOneWidget);
      expect(router.stackData.map((data) => data.name), [
        ForwardBeaconRoute.name,
        ProfileViewRoute.name,
      ]);

      await router.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Direct connection'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('forward-count:1'), findsOneWidget);
      expect(router.stackData.map((data) => data.name), [
        ForwardBeaconRoute.name,
      ]);
    });
  }

  testWidgets('candidate disappearance under Profile closes the sheet', (
    tester,
  ) async {
    await pump(tester, const Size(390, 844));
    await tester.tap(find.text('open-candidate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View full profile'));
    await tester.pumpAndSettle();

    (forwardCubit as _MutableForwardCubit).removeCandidate();
    await tester.pumpAndSettle();
    expect(find.text('full-profile:U2'), findsOneWidget);

    await router.maybePop();
    await tester.pumpAndSettle();

    expect(find.text('Direct connection'), findsNothing);
    expect(find.text('This person is no longer available.'), findsOneWidget);
    expect(router.stackData.map((data) => data.name), [
      ForwardBeaconRoute.name,
    ]);
  });
}
