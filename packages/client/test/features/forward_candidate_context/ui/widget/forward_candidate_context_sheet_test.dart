import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_state.dart';
import 'package:tentura/features/forward_candidate_context/domain/entity/candidate_connection_context.dart';
import 'package:tentura/features/forward_candidate_context/domain/port/forward_candidate_context_repository_port.dart';
import 'package:tentura/features/forward_candidate_context/domain/use_case/load_forward_candidate_context_case.dart';
import 'package:tentura/features/forward_candidate_context/ui/widget/forward_candidate_context_sheet.dart';
import 'package:tentura/ui/effect/ui_effect_bus.dart';
import 'package:tentura/ui/l10n/l10n.dart';

final class _Repository implements ForwardCandidateContextRepositoryPort {
  final responses = <Future<CandidateConnectionContext> Function()>[];
  int calls = 0;

  @override
  Future<CandidateConnectionContext> load({
    required String candidateId,
    required String context,
  }) {
    final response = responses[calls];
    calls++;
    return response();
  }
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Repository repository;
  late ForwardCubit forwardCubit;

  setUp(() {
    repository = _Repository();
  });

  tearDown(() async {
    if (!forwardCubit.isClosed) await forwardCubit.close();
    await GetIt.I.reset();
  });

  ForwardCandidate candidate({
    bool direct = false,
    String description = 'Builds bridges between teams.',
    List<String> capabilities = const ['general'],
  }) => ForwardCandidate(
    profile: Profile(
      id: 'U2',
      displayName: 'Alice',
      description: description,
      myVote: direct ? 1 : 0,
      subjectExplicitlyTrustsViewer: direct,
      score: direct ? 0 : 1,
      rScore: direct ? 0 : 1,
    ),
    topCapabilities: capabilities,
  );

  Future<void> pumpHost(
    WidgetTester tester,
    ForwardCandidate value, {
    ThemeData? theme,
    Size size = const Size(390, 844),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    GetIt.I.registerSingleton<LoadForwardCandidateContextCase>(
      LoadForwardCandidateContextCase(
        repository,
        env: const Env(),
        logger: Logger('ForwardCandidateContextSheetTest'),
      ),
    );
    forwardCubit = _MutableForwardCubit(
      initialState: ForwardState(
        beaconId: 'B1',
        context: 'personal',
        candidates: [value],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? TenturaTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: BlocProvider.value(
          value: forwardCubit,
          child: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => unawaited(
                  showForwardCandidateContextSheet(
                    sourceContext: context,
                    forwardCubit: forwardCubit,
                    candidate: value,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
  }

  testWidgets('direct contact shows direct state without repository call', (
    tester,
  ) async {
    await pumpHost(tester, candidate(direct: true));
    await tester.pumpAndSettle();

    expect(find.text('Direct connection'), findsOneWidget);
    expect(find.text('Select'), findsOneWidget);
    expect(find.text('View full profile'), findsOneWidget);
    expect(repository.calls, 0);
  });

  testWidgets('loading does not block selection', (tester) async {
    final pending = Completer<CandidateConnectionContext>();
    repository.responses.add(() => pending.future);
    final value = candidate();
    await pumpHost(tester, value);

    expect(find.text('Finding a path through your network…'), findsOneWidget);
    final select = find.widgetWithText(FilledButton, 'Select');
    expect(tester.widget<FilledButton>(select).onPressed, isNotNull);
    await tester.ensureVisible(select);
    await tester.tap(select);
    await tester.pump();
    expect(forwardCubit.state.selectedIds, {'U2'});

    pending.complete(
      const CandidateConnectionContext(
        status: CandidateConnectionContextStatus.longPath,
      ),
    );
  });

  testWidgets('path collapses, expands, wraps, and hides deleted identity', (
    tester,
  ) async {
    repository.responses.add(
      () async => const CandidateConnectionContext(
        status: CandidateConnectionContextStatus.path,
        nodes: [
          CandidateConnectionNode(
            kind: CandidateConnectionNodeKind.viewer,
            id: 'U1',
          ),
          CandidateConnectionNode(
            kind: CandidateConnectionNodeKind.person,
            id: 'U3',
            displayName: 'Bob',
          ),
          CandidateConnectionNode(
            kind: CandidateConnectionNodeKind.unavailable,
          ),
          CandidateConnectionNode(
            kind: CandidateConnectionNodeKind.person,
            id: 'U4',
            displayName: 'Caroline with a long display name',
          ),
          CandidateConnectionNode(
            kind: CandidateConnectionNodeKind.person,
            id: 'U5',
            displayName: 'Devon',
          ),
          CandidateConnectionNode(
            kind: CandidateConnectionNodeKind.candidate,
            id: 'U2',
            displayName: 'Alice',
          ),
        ],
      ),
    );
    await pumpHost(tester, candidate());
    await tester.pumpAndSettle();

    expect(find.text('One path through your network.'), findsOneWidget);
    expect(find.text('…'), findsOneWidget);
    expect(find.text('Unavailable person'), findsNothing);
    await tester.tap(find.text('Show full path'));
    await tester.pumpAndSettle();
    expect(find.text('Unavailable person'), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('transport failure retries once and actions remain enabled', (
    tester,
  ) async {
    repository.responses
      ..add(() => Future.error(StateError('offline')))
      ..add(
        () async => const CandidateConnectionContext(
          status: CandidateConnectionContextStatus.longPath,
        ),
      );
    await pumpHost(
      tester,
      candidate(description: '', capabilities: const []),
      theme: TenturaTheme.dark(),
      size: const Size(900, 900),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connection details unavailable'), findsOneWidget);
    expect(find.text('View full profile'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(find.text('Long network path'), findsOneWidget);
    expect(find.text('Why they may be relevant'), findsNothing);
  });

  testWidgets('candidate disappearance closes with generic unavailable copy', (
    tester,
  ) async {
    repository.responses.add(
      () async => const CandidateConnectionContext(
        status: CandidateConnectionContextStatus.longPath,
      ),
    );
    await pumpHost(tester, candidate());
    await tester.pumpAndSettle();

    (forwardCubit as _MutableForwardCubit).removeCandidate();
    await tester.pumpAndSettle();

    expect(find.text('View full profile'), findsNothing);
    expect(find.text('This person is no longer available.'), findsOneWidget);
  });
}
