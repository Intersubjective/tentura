import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
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
import 'package:tentura/ui/l10n/l10n.dart';

// #733 / #734: the closure pages of a small Request.
//  - the author's «Close & sum up» uses the standard page: a centred column
//    with the screen padding and card sections (2a);
//  - the preview has a real heading, every row carries its share, and a
//    preview with nothing to show is hidden (2b);
//  - an enabled «Finish now» says it does not wait (2c);
//  - saving the story confirms it inline (734);
//  - a helper with one colleague is told there is nothing to decide (3a).

const _beaconId = 'Bclosure00733';
const _epoch = 2;
const _me = 'me';
final _en = lookupL10n(const Locale('en'));

final class _FakeRepo implements ClosureRepository {
  _FakeRepo(this.state);

  ClosureState state;
  Object? failStory;
  final stories = <String>[];

  /// Holds each save until completed, to tap Save again mid-save.
  Completer<void>? holdStory;

  @override
  Future<ClosureState> fetchState(String beaconId) async => state;

  @override
  Future<void> saveStory({
    required String beaconId,
    required int expectedEpoch,
    required String body,
  }) async {
    stories.add(body);
    final hold = holdStory;
    if (hold != null) await hold.future;
    final e = failStory;
    // ignore: only_throw_errors
    if (e != null) throw e;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ClosureMember _m(String id) => ClosureMember(id: id, displayName: 'Name $id');

ClosureState _authorState({
  List<ClosureMember>? members,
  Map<String, ClosureOutcome> outcomes = const {},
  bool canCloseNow = false,
}) => ClosureState(
  epoch: _epoch,
  status: kClosureStatusEvaluating,
  role: ClosureRole.author,
  members: members ?? [_m('u1'), _m('u2')],
  closesAt: DateTime.utc(2030, 1, 10, 12),
  outcomes: outcomes,
  canCloseNow: canCloseNow,
);

Future<_FakeRepo> _pumpAuthor(
  WidgetTester tester,
  ClosureState state, {
  Size size = const Size(400, 2400),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _FakeRepo(state);
  final cubit = ClosureAuthorCubit(
    ClosureCase(repo, env: const Env(), logger: Logger('test')),
    beaconId: _beaconId,
  );
  addTearDown(cubit.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: BlocProvider<ClosureAuthorCubit>.value(
              value: cubit,
              child: const ClosureAuthorView(peopleTagsEnabled: false),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Future<void> _pumpHelper(
  WidgetTester tester, {
  required List<ClosureMember> members,
  ClosureRole role = ClosureRole.voter,
}) async {
  tester.view
    ..physicalSize = const Size(400, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _FakeRepo(
    ClosureState(
      epoch: _epoch,
      status: kClosureStatusEvaluating,
      role: role,
      members: members,
      closesAt: DateTime.utc(2030, 1, 10, 12),
    ),
  );
  final cubit = ClosureHelperCubit(
    ClosureCase(repo, env: const Env(), logger: Logger('test')),
    beaconId: _beaconId,
    viewerId: _me,
    author: const ClosureMember(id: 'auth', displayName: 'Name auth'),
  );
  addTearDown(cubit.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: BlocProvider<ClosureHelperCubit>.value(
          value: cubit,
          child: const ClosureHelperView(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('author «Close & sum up» page layout (2a)', () {
    testWidgets('wide window: content is a centred column, not full width', (
      tester,
    ) async {
      const size = Size(1280, 1600);
      await _pumpAuthor(tester, _authorState(), size: size);
      final list = tester.getRect(find.byType(ListView));
      expect(list.width, lessThan(size.width * 0.75));
      expect(list.center.dx, closeTo(size.width / 2, 1));
    });

    testWidgets('sections sit in cards inside the screen padding', (
      tester,
    ) async {
      await _pumpAuthor(tester, _authorState());
      final hint = find.text(_en.closureAuthorOutcomeHint);
      expect(
        find.ancestor(of: hint, matching: find.byType(TenturaTechCard)),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.text(_en.closureAuthorCloseNow),
          matching: find.byType(TenturaTechCard),
        ),
        findsOneWidget,
      );
      expect(tester.getTopLeft(hint).dx, greaterThanOrEqualTo(24));
    });
  });

  group('silent preview (2b)', () {
    testWidgets('a capitalised heading and a share on every row', (
      tester,
    ) async {
      await _pumpAuthor(tester, _authorState());
      final title = _en.closureAuthorPreviewTitle;
      expect(find.text(title), findsOneWidget);
      expect(title[0], title[0].toUpperCase());
      expect(find.text('Name u1 — 50%'), findsOneWidget);
      expect(find.text('Name u2 — 50%'), findsOneWidget);
    });

    testWidgets('nobody in the split: the preview is hidden, not bare names', (
      tester,
    ) async {
      await _pumpAuthor(
        tester,
        _authorState(
          outcomes: {
            'u1': ClosureOutcome.notDone,
            'u2': ClosureOutcome.notDone,
          },
        ),
      );
      expect(find.text(_en.closureAuthorPreviewTitle), findsNothing);
      expect(
        find.byKey(const ValueKey('closure.author.preview.u1')),
        findsNothing,
      );
    });

    testWidgets('the two-member note is the reworded one', (tester) async {
      await _pumpAuthor(tester, _authorState());
      expect(find.text(_en.closureAuthorTwoMembers), findsOneWidget);
      expect(
        _en.closureAuthorTwoMembers,
        isNot(
          contains('will understand from their own result how you divided'),
        ),
      );
    });
  });

  group('«Finish now» copy (2c)', () {
    testWidgets('enabled: says it closes without waiting', (tester) async {
      await _pumpAuthor(tester, _authorState(canCloseNow: true));
      expect(find.text(_en.closureAuthorCloseNowNote), findsOneWidget);
    });

    testWidgets('disabled: no such note (guard)', (tester) async {
      await _pumpAuthor(tester, _authorState());
      expect(find.text(_en.closureAuthorCloseNowNote), findsNothing);
    });

    test('the HUD close-now effect no longer says it waits for everyone', () {
      expect(
        _en.beaconHudActEffectCloseNow,
        isNot(contains('when everyone has finished')),
      );
    });
  });

  group('closing story Save (734)', () {
    const saved = ValueKey('closure.author.story.saved');

    testWidgets('a saved story shows «Saved ✓» until it is edited again', (
      tester,
    ) async {
      final repo = await _pumpAuthor(tester, _authorState());
      expect(find.text(_en.closureAuthorStorySaved), findsNothing);

      await tester.enterText(find.byType(TextField), 'Great teamwork');
      await tester.tap(find.byKey(const ValueKey('closure.author.story.save')));
      await tester.pumpAndSettle();
      expect(repo.stories, ['Great teamwork']);
      expect(find.byKey(saved), findsOneWidget);
      expect(find.text('Saved ✓'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Great teamwork!');
      await tester.pump();
      expect(find.byKey(saved), findsNothing);
    });

    // Review r1 nit: the check mark is not read out as «check mark».
    testWidgets('the confirmation reads as «Saved» to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpAuthor(tester, _authorState());
      await tester.enterText(find.byType(TextField), 'Great teamwork');
      await tester.tap(find.byKey(const ValueKey('closure.author.story.save')));
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.byKey(saved));
      expect(node.label, _en.closureAuthorStorySavedLabel);
      expect(node.label, isNot(contains('✓')));
      handle.dispose();
    });

    testWidgets('a second tap while saving does not save again', (
      tester,
    ) async {
      final repo = await _pumpAuthor(tester, _authorState());
      final hold = Completer<void>();
      repo.holdStory = hold;
      await tester.enterText(find.byType(TextField), 'Great teamwork');
      final save = find.byKey(const ValueKey('closure.author.story.save'));

      await tester.tap(save);
      await tester.pump();
      await tester.tap(save);
      await tester.pump();
      expect(repo.stories, ['Great teamwork']);

      hold.complete();
      await tester.pumpAndSettle();
      expect(repo.stories, ['Great teamwork']);
      expect(find.byKey(saved), findsOneWidget);
    });

    testWidgets('a failed save shows no confirmation', (tester) async {
      // The error snackbar logs through GetIt.
      if (!GetIt.I.isRegistered<Logger>()) {
        GetIt.I.registerSingleton<Logger>(Logger('test'));
        addTearDown(() => GetIt.I.unregister<Logger>());
      }
      final repo = await _pumpAuthor(tester, _authorState());
      repo.failStory = Exception('offline');
      await tester.enterText(find.byType(TextField), 'Great teamwork');
      await tester.tap(find.byKey(const ValueKey('closure.author.story.save')));
      await tester.pumpAndSettle();
      expect(find.byKey(saved), findsNothing);
    });

    test('RU has the confirmation too', () {
      final ru = lookupL10n(const Locale('ru'));
      expect(ru.closureAuthorStorySaved, 'Сохранено ✓');
      expect(ru.closureAuthorStorySavedLabel, 'Сохранено');
    });
  });

  group('helper final check with one colleague (3a)', () {
    testWidgets('says there is nothing to decide', (tester) async {
      await _pumpHelper(tester, members: [_m(_me), _m('u2')]);
      expect(find.text(_en.closureHelperNothingToDecide), findsOneWidget);
      expect(find.text(_en.closureHelperDone), findsNothing);
    });

    testWidgets('two colleagues: the vote, no empty state (guard)', (
      tester,
    ) async {
      await _pumpHelper(tester, members: [_m(_me), _m('u2'), _m('u3')]);
      expect(find.text(_en.closureHelperNothingToDecide), findsNothing);
      expect(find.text(_en.closureHelperDone), findsOneWidget);
    });
  });
}
