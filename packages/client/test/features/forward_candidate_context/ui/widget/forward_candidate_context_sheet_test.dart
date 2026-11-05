import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/entity/forward_reach.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward_candidate_context/domain/entity/candidate_connection_context.dart';
import 'package:tentura/features/forward_candidate_context/domain/port/forward_candidate_context_repository_port.dart';
import 'package:tentura/features/forward_candidate_context/domain/use_case/load_forward_candidate_context_case.dart';
import 'package:tentura/features/forward_candidate_context/ui/widget/forward_candidate_context_sheet.dart';
import 'package:tentura/ui/effect/ui_effect_bus.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../../../support/phone_surface.dart';

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
    List<String> capabilities = const ['transport', 'food'],
    ForwardReach? reach,
    DateTime? joinedAt,
  }) => ForwardCandidate(
    profile: Profile(
      id: 'U2',
      displayName: 'Alice',
      description: description,
      myVote: direct ? 1 : 0,
      subjectExplicitlyTrustsViewer: direct,
      score: direct ? 50 : 1,
      rScore: direct ? 0 : 1,
      joinedAt: joinedAt,
    ),
    reach: reach,
    topCapabilities: capabilities,
  );

  Future<void> pumpHost(
    WidgetTester tester,
    ForwardCandidate value, {
    ThemeData? theme,
    Size size = const Size(390, 844),
    bool viewerIsAuthor = false,
    Locale locale = const Locale('en'),
    Set<String> needs = const {'transport', 'food'},
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
        beacon: Beacon.empty.copyWith(id: 'B1', needs: needs),
        candidates: [value],
        viewerIsAuthor: viewerIsAuthor,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? TenturaTheme.light(),
        locale: locale,
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

  testWidgets('header paints MeritRank rating arcs', (tester) async {
    await pumpHost(tester, candidate(direct: true));
    await tester.pumpAndSettle();
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('joined 20 days ago shows Joined relative copy', (tester) async {
    final now = DateTime(2026, 6, 1, 12);
    await withClock(Clock.fixed(now), () async {
      await pumpHost(
        tester,
        candidate(
          direct: true,
          joinedAt: now.subtract(const Duration(days: 20)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Joined 20 days'), findsOneWidget);
    });
  });

  testWidgets('older join shows Member since month year', (tester) async {
    final now = DateTime(2026, 6, 1, 12);
    await withClock(Clock.fixed(now), () async {
      repository.responses.add(
        () async => CandidateConnectionContext(
          status: CandidateConnectionContextStatus.longPath,
          candidateJoinedAt: DateTime.utc(2025, 3, 4),
        ),
      );
      await pumpHost(
        tester,
        candidate(reach: const ForwardReach(kind: ForwardReachKind.wider)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Member since Mar 2025'), findsOneWidget);
    });
  });

  testWidgets('via_connection vouch copy appears before fetch completes', (
    tester,
  ) async {
    final pending = Completer<CandidateConnectionContext>();
    repository.responses.add(() => pending.future);
    await pumpHost(
      tester,
      candidate(
        reach: ForwardReach(
          kind: ForwardReachKind.viaConnection,
          via: [const Profile(id: 'V1', displayName: 'A')],
          viaCount: 1,
        ),
      ),
    );
    expect(find.text('Vouched for by A'), findsOneWidget);
    pending.complete(
      const CandidateConnectionContext(
        status: CandidateConnectionContextStatus.unavailable,
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('shared_request shows both-in title line', (tester) async {
    repository.responses.add(
      () async => const CandidateConnectionContext(
        status: CandidateConnectionContextStatus.unavailable,
      ),
    );
    await pumpHost(
      tester,
      candidate(
        reach: const ForwardReach(
          kind: ForwardReachKind.sharedRequest,
          sharedRequest: (id: 'R1', title: 'Moving boxes'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Both in "Moving boxes"'), findsOneWidget);
  });

  testWidgets('wider five-node path collapses to four slots then expands', (
    tester,
  ) async {
    repository.responses.add(
      () async => const CandidateConnectionContext(
        status: CandidateConnectionContextStatus.path,
        nodes: [
          CandidateConnectionNode(
            kind: CandidateConnectionNodeKind.viewer,
            id: 'U1',
            displayName: 'You',
          ),
          CandidateConnectionNode(
            kind: CandidateConnectionNodeKind.person,
            id: 'U3',
            displayName: 'B',
          ),
          CandidateConnectionNode(
            kind: CandidateConnectionNodeKind.person,
            id: 'U4',
            displayName: 'C',
          ),
          CandidateConnectionNode(
            kind: CandidateConnectionNodeKind.person,
            id: 'U5',
            displayName: 'D',
          ),
          CandidateConnectionNode(
            kind: CandidateConnectionNodeKind.candidate,
            id: 'U2',
            displayName: 'Alice',
          ),
        ],
      ),
    );
    await pumpHost(
      tester,
      candidate(reach: const ForwardReach(kind: ForwardReachKind.wider)),
    );
    await tester.pumpAndSettle();

    expect(find.text('…'), findsOneWidget);
    expect(find.byType(TenturaAvatar), findsNWidgets(4));
    await tester.tap(find.text('Show full path'));
    await tester.pumpAndSettle();
    expect(find.byType(TenturaAvatar), findsAtLeastNWidgets(6));
  });

  testWidgets('legacy path copy strings never render', (tester) async {
    repository.responses.add(
      () async => const CandidateConnectionContext(
        status: CandidateConnectionContextStatus.path,
        nodes: [
          CandidateConnectionNode(kind: CandidateConnectionNodeKind.viewer),
          CandidateConnectionNode(
            kind: CandidateConnectionNodeKind.candidate,
            id: 'U2',
          ),
        ],
      ),
    );
    await pumpHost(
      tester,
      candidate(reach: const ForwardReach(kind: ForwardReachKind.wider)),
    );
    await tester.pumpAndSettle();
    expect(find.text('One path through your network.'), findsNothing);
    expect(find.textContaining('network snapshot'), findsNothing);
  });

  testWidgets('section order: how, why, about, then actions', (tester) async {
    repository.responses.add(
      () async => const CandidateConnectionContext(
        status: CandidateConnectionContextStatus.unavailable,
      ),
    );
    await pumpHost(tester, candidate());
    await tester.pumpAndSettle();

    double top(Finder f) => tester.getTopLeft(f).dy;
    expect(
      top(find.text('How you know them')),
      lessThan(top(find.text('Why for this request'))),
    );
    expect(
      top(find.text('Why for this request')),
      lessThan(top(find.text('About'))),
    );
    expect(
      top(find.text('About')),
      lessThan(top(find.widgetWithText(FilledButton, 'Select'))),
    );
    expect(find.textContaining('Matches:'), findsOneWidget);
  });

  testWidgets('375x667 RU sheet headings', (tester) async {
    await usePhoneSurface(tester);
    repository.responses.add(
      () async => const CandidateConnectionContext(
        status: CandidateConnectionContextStatus.unavailable,
      ),
    );
    await pumpHost(
      tester,
      candidate(direct: true, capabilities: const []),
      locale: const Locale('ru'),
      needs: const {},
    );
    await tester.pumpAndSettle();
    expect(find.text('Как вы их знаете'), findsOneWidget);
    expect(find.text('Почему для этого запроса'), findsNothing);
  });

  testWidgets('direct contact shows trust without repository call', (
    tester,
  ) async {
    await pumpHost(tester, candidate(direct: true));
    await tester.pumpAndSettle();

    expect(find.text('You trust them'), findsOneWidget);
    expect(repository.calls, 0);
  });

  testWidgets('loading does not block selection', (tester) async {
    final pending = Completer<CandidateConnectionContext>();
    repository.responses.add(() => pending.future);
    await pumpHost(
      tester,
      candidate(reach: const ForwardReach(kind: ForwardReachKind.wider)),
    );

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
    await tester.pumpAndSettle();
    expect(find.text('Distant connection'), findsOneWidget);
  });

  testWidgets('transport failure retries once', (tester) async {
    repository.responses
      ..add(() => Future.error(StateError('offline')))
      ..add(
        () async => const CandidateConnectionContext(
          status: CandidateConnectionContextStatus.longPath,
        ),
      );
    await pumpHost(
      tester,
      candidate(
        description: '',
        capabilities: const [],
        reach: const ForwardReach(kind: ForwardReachKind.wider),
      ),
      theme: TenturaTheme.dark(),
      size: const Size(900, 900),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(find.text('Distant connection'), findsOneWidget);
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

    expect(
      find.text('This person is no longer available.', findRichText: true),
      findsOneWidget,
    );
  });

  group('#730 the author and someone who dismissed the Request', () {
    const hint = 'They dismissed it — use People › Invite';
    const declined = ForwardCandidate(
      profile: Profile(id: 'U2', displayName: 'Carol', score: 1, rScore: 1),
      involvement: CandidateInvolvement.declined,
    );

    void longPath() => repository.responses.add(
      () async => const CandidateConnectionContext(
        status: CandidateConnectionContextStatus.longPath,
      ),
    );

    testWidgets('the sheet shows the People › Invite hint', (tester) async {
      longPath();
      await pumpHost(tester, declined, viewerIsAuthor: true);
      await tester.pumpAndSettle();
      expect(find.text(hint), findsOneWidget);
    });

    testWidgets('Select says to use People › Invite', (tester) async {
      longPath();
      await pumpHost(tester, declined, viewerIsAuthor: true);
      await tester.pumpAndSettle();

      final select = find.widgetWithText(FilledButton, 'Select');
      await tester.ensureVisible(select);
      await tester.tap(select);
      await tester.pumpAndSettle();

      expect(find.text(hint, findRichText: true), findsOneWidget);
    });
  });
}
