// B028 / B041: the wrap-up review is reachable as a page, and a Request that
// was reopened once can still be closed through it: record the outcomes, then
// Close now. The page leaves once the review is over.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/closure/domain/entity/closure_member.dart';
import 'package:tentura/features/closure/domain/entity/closure_outcome.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/features/closure/domain/use_case/closure_case.dart';
import 'package:tentura/features/closure/ui/bloc/closure_author_cubit.dart';
import 'package:tentura/features/closure/ui/bloc/closure_helper_cubit.dart';
import 'package:tentura/features/closure/ui/screen/closure_author_screen.dart';
import 'package:tentura/features/closure/ui/screen/closure_helper_screen.dart';
import 'package:tentura/features/closure/ui/screen/closure_review_page.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import '../../support/people_tags_widget_harness.dart';

const _beaconId = 'Breopened0001';

/// Epoch 2: the first round was cancelled by the one allowed Reopen.
const _secondEpoch = 2;

/// Mirrors the server for a two-member episode: Close now once every member
/// has an outcome (`ClosureCase.canCloseNow`, ≤ 2 members); Reopen spent.
final class _SecondRoundRepository implements ClosureRepository {
  _SecondRoundRepository({this.role = ClosureRole.author});

  final ClosureRole role;
  final members = const [
    ClosureMember(id: 'u1', displayName: 'Ann'),
    ClosureMember(id: 'u2', displayName: 'Bob'),
  ];
  final outcomes = <String, ClosureOutcome>{};
  int status = 0;
  final closeNowEpochs = <int>[];

  @override
  Future<ClosureState> fetchState(String beaconId) async => ClosureState(
    epoch: _secondEpoch,
    status: status,
    role: role,
    members: members,
    closesAt: DateTime.utc(2030, 1, 10, 12),
    outcomes: role == ClosureRole.author ? Map.of(outcomes) : null,
    earlyCloseAt: DateTime.utc(2030, 1, 5, 12),
    canCloseNow:
        status == 0 && members.every((m) => outcomes.containsKey(m.id)),
  );

  @override
  Future<void> saveOutcome({
    required String beaconId,
    required int expectedEpoch,
    required String helperId,
    required ClosureOutcome? outcome,
  }) async {
    expect(expectedEpoch, _secondEpoch);
    if (outcome == null) {
      outcomes.remove(helperId);
    } else {
      outcomes[helperId] = outcome;
    }
  }

  @override
  Future<void> closeNow({
    required String beaconId,
    required int expectedEpoch,
  }) async {
    closeNowEpochs.add(expectedEpoch);
    status = 1; // finalized
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// First round (Return to work still available). [failNextFetch] makes the
/// reload after the next write fail once, like a timeout; after [reopen] the
/// server answers not-found, as it does for a cancelled epoch.
final class _FirstRoundRepository implements ClosureRepository {
  final members = const [
    ClosureMember(id: 'u1', displayName: 'Ann'),
    ClosureMember(id: 'u2', displayName: 'Bob'),
    ClosureMember(id: 'u3', displayName: 'Cy'),
  ];
  final outcomes = <String, ClosureOutcome>{};
  bool failNextFetch = false;
  bool cancelled = false;
  int fetches = 0;
  final reopenEpochs = <int>[];

  @override
  Future<ClosureState> fetchState(String beaconId) async {
    fetches++;
    if (cancelled) throw Exception('Id not found: [$beaconId]');
    if (failNextFetch) {
      failNextFetch = false;
      throw TimeoutException('closureState');
    }
    return ClosureState(
      epoch: 1,
      status: 0,
      role: ClosureRole.author,
      members: members,
      closesAt: DateTime.utc(2030, 1, 10, 12),
      outcomes: Map.of(outcomes),
      earlyCloseAt: DateTime.utc(2030, 1, 5, 12),
      canReopen: true,
    );
  }

  @override
  Future<void> saveOutcome({
    required String beaconId,
    required int expectedEpoch,
    required String helperId,
    required ClosureOutcome? outcome,
  }) async {
    if (outcome == null) {
      outcomes.remove(helperId);
    } else {
      outcomes[helperId] = outcome;
    }
  }

  @override
  Future<void> reopen({
    required String beaconId,
    required int expectedEpoch,
  }) async {
    reopenEpochs.add(expectedEpoch);
    cancelled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ClosureCase _case(ClosureRepository repo) =>
    ClosureCase(repo, env: const Env(), logger: Logger('test'));

Future<void> _pumpHostAndOpen(
  WidgetTester tester,
  Widget Function() page,
) async {
  tester.view
    ..physicalSize = const Size(420, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpPeopleTagsWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => page()),
              ),
              child: const Text('request'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('request'));
  await tester.pumpAndSettle();
}

/// A second of frames: each write refetches, and the pop animates.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('Desktop closure review content', () {
    for (final role in [ClosureRole.author, ClosureRole.voter]) {
      final audience = role == ClosureRole.author ? 'author' : 'helper';
      testWidgets(
        '$audience review body is capped and horizontally centered at 1280 px',
        (tester) async {
          tester.view
            ..physicalSize = const Size(1280, 2400)
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          final repo = _SecondRoundRepository(role: role);
          const author = ClosureMember(id: 'uAuthor', displayName: 'Author');
          final authorCubit = role == ClosureRole.author
              ? ClosureAuthorCubit(_case(repo), beaconId: _beaconId)
              : null;
          final helperCubit = role == ClosureRole.voter
              ? ClosureHelperCubit(
                  _case(repo),
                  beaconId: _beaconId,
                  viewerId: 'u1',
                  author: author,
                )
              : null;
          if (authorCubit != null) addTearDown(authorCubit.close);
          if (helperCubit != null) addTearDown(helperCubit.close);

          await tester.pumpPeopleTagsWidget(
            MaterialApp(
              theme: TenturaTheme.light(),
              locale: const Locale('en'),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              // Match the app: responsive tokens also reach pushed routes.
              builder: (context, child) =>
                  TenturaResponsiveScope(child: child!),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ClosureReviewPage(
                          beaconId: _beaconId,
                          role: role,
                          viewerId: role == ClosureRole.author
                              ? 'uAuthor'
                              : 'u1',
                          author: author,
                          authorCubit: authorCubit,
                          helperCubit: helperCubit,
                        ),
                      ),
                    ),
                    child: const Text('request'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('request'));
          await tester.pumpAndSettle();

          final page = find.byType(ClosureReviewPage);
          final l10n = lookupL10n(const Locale('en'));
          expect(
            find.text(
              role == ClosureRole.author
                  ? l10n.closureAuthorTitle
                  : l10n.closureHelperTitle,
            ),
            findsOneWidget,
          );
          expect(find.text('Bob'), findsOneWidget);
          final body = find.descendant(
            of: page,
            matching: find.byType(ListView),
          );
          expect(body, findsOneWidget);
          final maxWidth = tester.element(body).tt.contentMaxWidth;
          expect(maxWidth, isNotNull);
          final bodyRect = tester.getRect(body);
          final pageRect = tester.getRect(page);
          expect(pageRect.width, 1280);
          expect(bodyRect.width, greaterThan(0));
          expect(bodyRect.width, lessThanOrEqualTo(maxWidth!));
          expect(bodyRect.center.dx, closeTo(pageRect.center.dx, 0.01));
        },
      );
    }
  });

  testWidgets('second round after a Reopen: outcomes, then Close now closes it '
      'and the page goes back to the Request', (tester) async {
    final semantics = tester.ensureSemantics();
    final repo = _SecondRoundRepository();
    final cubit = ClosureAuthorCubit(_case(repo), beaconId: _beaconId);
    addTearDown(cubit.close);
    await _pumpHostAndOpen(
      tester,
      () => ClosureReviewPage(
        beaconId: _beaconId,
        role: ClosureRole.author,
        viewerId: 'uAuthor',
        author: const ClosureMember(id: 'uAuthor', displayName: 'Author'),
        authorCubit: cubit,
      ),
    );

    expect(
      find.text(lookupL10n(const Locale('en')).closureAuthorTitle),
      findsOneWidget,
    );
    expect(find.byType(ClosureAuthorView), findsOneWidget);
    FilledButton finish() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Finish now'),
    );
    expect(finish().onPressed, isNull);
    // Reopen is spent: no "Return to work" in the second round.
    expect(find.text('Return to work'), findsNothing);

    for (final name in ['Ann', 'Bob']) {
      await tester.tap(find.bySemanticsLabel('$name: Done').first);
      await _settle(tester);
    }
    expect(finish().onPressed, isNotNull);

    await tester.tap(find.text('Finish now'));
    await _settle(tester);

    expect(repo.closeNowEpochs, [_secondEpoch]);
    expect(find.byType(ClosureReviewPage), findsNothing);
    expect(find.text('request'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a member gets their own view, titled for them', (tester) async {
    final repo = _SecondRoundRepository(role: ClosureRole.voter);
    final cubit = ClosureHelperCubit(
      _case(repo),
      beaconId: _beaconId,
      viewerId: 'u1',
      author: const ClosureMember(id: 'uAuthor', displayName: 'Author'),
    );
    addTearDown(cubit.close);
    await _pumpHostAndOpen(
      tester,
      () => ClosureReviewPage(
        beaconId: _beaconId,
        role: ClosureRole.voter,
        viewerId: 'u1',
        author: const ClosureMember(id: 'uAuthor', displayName: 'Author'),
        helperCubit: cubit,
      ),
    );

    expect(find.text('Final check'), findsOneWidget);
    expect(find.byType(ClosureHelperView), findsOneWidget);
    expect(find.byType(ClosureAuthorView), findsNothing);
  });

  testWidgets(
    'the pushed page has a back control that returns to the Request',
    (tester) async {
      final repo = _SecondRoundRepository(role: ClosureRole.voter);
      final cubit = ClosureHelperCubit(
        _case(repo),
        beaconId: _beaconId,
        viewerId: 'u1',
        author: const ClosureMember(id: 'uAuthor', displayName: 'Author'),
      );
      addTearDown(cubit.close);
      await _pumpHostAndOpen(
        tester,
        () => ClosureReviewPage(
          beaconId: _beaconId,
          role: ClosureRole.voter,
          viewerId: 'u1',
          author: const ClosureMember(id: 'uAuthor', displayName: 'Author'),
          helperCubit: cubit,
        ),
      );

      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(ClosureReviewPage), findsNothing);
      expect(find.text('request'), findsOneWidget);
    },
  );

  testWidgets('a failed reload after a write keeps the author on the review', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repo = _FirstRoundRepository();
    final cubit = ClosureAuthorCubit(_case(repo), beaconId: _beaconId);
    addTearDown(cubit.close);
    await _pumpHostAndOpen(
      tester,
      () => ClosureReviewPage(
        beaconId: _beaconId,
        role: ClosureRole.author,
        viewerId: 'uAuthor',
        author: const ClosureMember(id: 'uAuthor', displayName: 'Author'),
        authorCubit: cubit,
      ),
    );
    expect(find.byType(ClosureAuthorView), findsOneWidget);

    repo.failNextFetch = true;
    await tester.tap(find.bySemanticsLabel('Ann: Done').first);
    await _settle(tester);

    expect(repo.outcomes, {'u1': ClosureOutcome.done});
    expect(cubit.state.loadError, isA<TimeoutException>());
    expect(find.byType(ClosureReviewPage), findsOneWidget);
    expect(find.byType(ClosureAuthorView), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('Return to work ends the review and the page goes back', (
    tester,
  ) async {
    final repo = _FirstRoundRepository();
    final cubit = ClosureAuthorCubit(_case(repo), beaconId: _beaconId);
    addTearDown(cubit.close);
    await _pumpHostAndOpen(
      tester,
      () => ClosureReviewPage(
        beaconId: _beaconId,
        role: ClosureRole.author,
        viewerId: 'uAuthor',
        author: const ClosureMember(id: 'uAuthor', displayName: 'Author'),
        authorCubit: cubit,
      ),
    );
    final fetchesBefore = repo.fetches;

    await tester.tap(find.text('Return to work'));
    await _settle(tester);

    expect(repo.reopenEpochs, [1]);
    expect(cubit.state.ended, isTrue);
    // Nothing to reload for a cancelled epoch.
    expect(repo.fetches, fetchesBefore);
    expect(find.byType(ClosureReviewPage), findsNothing);
    expect(find.text('request'), findsOneWidget);
  });
}
