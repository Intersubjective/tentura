// «Who'll take it?» baton, client side for the message author:
//  - `RoomBatonCard` lists every asked person with their answer (can help /
//    waiting / can't help) and shows a priority label only when more than one
//    priority tier is in use;
//  - «Choose now» is disabled («Nobody can help yet.») until somebody said
//    «Can help», and stays enabled while others are still waiting;
//  - once everyone answered the card prompts the author to choose;
//  - «Choose now» opens a sheet that lists only people who can help, grouped by
//    priority, with «Pick for me» (no user id) and a tap on a name (that id);
//  - «Cancel» asks for confirmation before it reports a cancel;
//  - after the pick the card collapses to «{name} took it.» and shows nobody
//    else;
//  - `RoomMessageTile` forwards select / cancel with the baton id.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_baton_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _author = Profile(id: 'u-anna', displayName: 'Anna Author');

RoomBatonCandidate _candidate(
  String id,
  String title,
  RoomBatonResponse response, {
  int tier = 1,
}) => RoomBatonCandidate(
  userId: id,
  title: title,
  tier: tier,
  response: response,
);

RoomBatonAuthorData _collecting(
  List<RoomBatonCandidate> candidates, {
  bool allAnswered = false,
}) => RoomBatonAuthorData(
  id: 'baton-1',
  status: RoomBatonStatus.collecting,
  candidates: candidates,
  allAnswered: allAnswered,
  eligibleCount: candidates
      .where((c) => c.response == RoomBatonResponse.canHelp)
      .length,
);

/// The four example states: can help, waiting, can't help, and a second
/// person who can help.
final _mixedAnswers = _collecting([
  _candidate('u-boris', 'Boris Driver', RoomBatonResponse.canHelp),
  _candidate('u-clara', 'Clara Pending', RoomBatonResponse.waiting),
  _candidate('u-dmitri', 'Dmitri Busy', RoomBatonResponse.cantHelp),
  _candidate('u-eva', 'Eva Helper', RoomBatonResponse.canHelp),
]);

final _nobodyCanHelp = _collecting([
  _candidate('u-boris', 'Boris Driver', RoomBatonResponse.cantHelp),
  _candidate('u-clara', 'Clara Pending', RoomBatonResponse.waiting),
]);

final _oneCanHelpOthersWaiting = _collecting([
  _candidate('u-boris', 'Boris Driver', RoomBatonResponse.canHelp),
  _candidate('u-clara', 'Clara Pending', RoomBatonResponse.waiting),
  _candidate('u-dmitri', 'Dmitri Busy', RoomBatonResponse.cantHelp),
]);

final _tiered = _collecting([
  _candidate('u-boris', 'Boris Driver', RoomBatonResponse.canHelp, tier: 2),
  _candidate('u-clara', 'Clara Pending', RoomBatonResponse.waiting, tier: 1),
  _candidate('u-dmitri', 'Dmitri Busy', RoomBatonResponse.cantHelp, tier: 3),
  _candidate('u-eva', 'Eva Helper', RoomBatonResponse.canHelp, tier: 1),
  _candidate('u-fedor', 'Fedor Spare', RoomBatonResponse.canHelp, tier: 2),
]);

final _taken = RoomBatonAuthorData(
  id: 'baton-1',
  status: RoomBatonStatus.taken,
  candidates: [
    _candidate('u-boris', 'Boris Driver', RoomBatonResponse.canHelp),
    _candidate('u-clara', 'Clara Pending', RoomBatonResponse.waiting),
    _candidate('u-dmitri', 'Dmitri Busy', RoomBatonResponse.cantHelp),
  ],
  allAnswered: false,
  eligibleCount: 1,
  taker: const RoomBatonTaker(id: 'u-boris', title: 'Boris Driver'),
  selectionMode: RoomBatonSelectionMode.manual,
);

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _author);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _MockPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

Widget _localized(Widget child, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      home: MediaQuery(
        data: const MediaQueryData(size: Size(400, 900)),
        child: TenturaResponsiveScope(
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );

Widget _cardHarness(
  RoomBatonData baton, {
  void Function(String? userId)? onSelect,
  void Function()? onCancel,
  Locale locale = const Locale('en'),
}) => _localized(
  RoomBatonCard(baton: baton, onSelect: onSelect, onCancel: onCancel),
  locale: locale,
);

Widget _tileHarness(
  RoomBatonData baton, {
  void Function(String batonId, String? userId)? onBatonSelect,
  void Function(String batonId)? onBatonCancel,
}) => MultiBlocProvider(
  providers: [
    BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
    BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
    BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
  ],
  child: _localized(
    RoomMessageTile(
      message: RoomMessage(
        id: 'msg-1',
        beaconId: 'b-baton',
        authorId: _author.id,
        author: _author,
        body: 'Can somebody drive the van on Saturday?',
        createdAt: DateTime.utc(2026, 10, 3, 12),
        baton: baton,
      ),
      myProfile: _author,
      participants: const [],
      onToggleReaction: (_, _) async {},
      onBatonSelect: onBatonSelect,
      onBatonCancel: onBatonCancel,
    ),
  ),
);

const _everyName = [
  'Boris Driver',
  'Clara Pending',
  'Dmitri Busy',
  'Eva Helper',
  'Fedor Spare',
];

/// Every string rendered by `Text` widgets under [root].
List<String> _textsUnder(Finder root) => [
  for (final w in find
      .descendant(of: root, matching: find.byType(Text))
      .evaluate()
      .map((e) => e.widget as Text))
    w.data ?? w.textSpan?.toPlainText() ?? '',
];

/// The visual row of [name]: the widest ancestor of its text that holds no
/// other candidate's name, so a test does not care how the row is built.
List<String> _rowTexts(WidgetTester tester, String name) {
  final nameFinder = find.text(name);
  expect(nameFinder, findsOneWidget, reason: '$name appears exactly once');
  Element row = tester.element(nameFinder);
  tester.element(nameFinder).visitAncestorElements((ancestor) {
    final holdsOther = _everyName
        .where((other) => other != name)
        .any(
          (other) => find
              .descendant(
                of: find.byWidget(ancestor.widget),
                matching: find.text(other),
              )
              .evaluate()
              .isNotEmpty,
        );
    if (holdsOther) return false;
    row = ancestor;
    return true;
  });
  return _textsUnder(find.byWidget(row.widget));
}

/// The content of the open choose sheet: the ancestor of «Pick for me» just
/// below the first one that also holds the card.
Finder _sheetContent(WidgetTester tester) {
  final pick = find.text('Pick for me');
  expect(pick, findsOneWidget, reason: 'the choose sheet is open');
  Element sheet = tester.element(pick);
  tester.element(pick).visitAncestorElements((ancestor) {
    final holdsCard = find
        .descendant(
          of: find.byWidget(ancestor.widget),
          matching: find.byType(RoomBatonCard),
        )
        .evaluate()
        .isNotEmpty;
    if (holdsCard) return false;
    sheet = ancestor;
    return true;
  });
  return find.byWidget(sheet.widget);
}

ButtonStyleButton _buttonLabelled(String label) => find
    .ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    )
    .evaluate()
    .first
    .widget as ButtonStyleButton;

Future<void> _openChooseSheet(WidgetTester tester) async {
  await tester.tap(find.text('Choose now'));
  await tester.pumpAndSettle();
}

void main() {
  group('RoomBatonCard for the author while answers come in', () {
    testWidgets('shows one row per asked person with their answer', (
      tester,
    ) async {
      await tester.pumpWidget(_cardHarness(_mixedAnswers));
      await tester.pumpAndSettle();

      expect(find.text('Who\'ll take it: answers'), findsOneWidget);
      final boris = _rowTexts(tester, 'Boris Driver');
      final clara = _rowTexts(tester, 'Clara Pending');
      final dmitri = _rowTexts(tester, 'Dmitri Busy');
      final eva = _rowTexts(tester, 'Eva Helper');

      expect(boris.join(' '), contains('can help'));
      expect(eva.join(' '), contains('can help'));
      expect(clara.join(' '), contains('waiting'));
      expect(dmitri.join(' '), contains('can\'t help'));

      for (final other in [clara, dmitri]) {
        expect(other.join(' '), isNot(contains('can help')));
      }
      expect(boris.join(' '), isNot(contains('waiting')));
      expect(boris.join(' '), isNot(contains('can\'t help')));
      expect(clara.join(' '), isNot(contains('can\'t help')));
      expect(dmitri.join(' '), isNot(contains('waiting')));
    });

    testWidgets('states the answers in Russian', (tester) async {
      await tester.pumpWidget(
        _cardHarness(_mixedAnswers, locale: const Locale('ru')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Кто возьмётся: ответы'), findsOneWidget);
      expect(
        _rowTexts(tester, 'Boris Driver').join(' '),
        contains('может помочь'),
      );
      expect(
        _rowTexts(tester, 'Clara Pending').join(' '),
        contains('ждём ответа'),
      );
      expect(
        _rowTexts(tester, 'Dmitri Busy').join(' '),
        contains('не может'),
      );
      expect(find.text('Выбрать сейчас'), findsOneWidget);
      expect(find.text('Отменить'), findsOneWidget);
    });

    testWidgets('shows no priority label when everyone has the same '
        'priority', (tester) async {
      await tester.pumpWidget(_cardHarness(_mixedAnswers));
      await tester.pumpAndSettle();

      expect(find.textContaining('Priority'), findsNothing);
    });

    testWidgets('shows each person\'s priority once several priorities are '
        'in use', (tester) async {
      await tester.pumpWidget(_cardHarness(_tiered));
      await tester.pumpAndSettle();

      expect(
        _rowTexts(tester, 'Clara Pending').join(' '),
        contains('Priority 1'),
      );
      expect(
        _rowTexts(tester, 'Eva Helper').join(' '),
        contains('Priority 1'),
      );
      expect(
        _rowTexts(tester, 'Boris Driver').join(' '),
        contains('Priority 2'),
      );
      expect(
        _rowTexts(tester, 'Dmitri Busy').join(' '),
        contains('Priority 3'),
      );
    });

    testWidgets('prompts the author to choose once everyone answered', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardHarness(
          _collecting([
            _candidate('u-boris', 'Boris Driver', RoomBatonResponse.canHelp),
            _candidate('u-dmitri', 'Dmitri Busy', RoomBatonResponse.cantHelp),
          ], allAnswered: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Everyone answered. Choose who takes it.'),
        findsOneWidget,
      );
    });

    testWidgets('does not prompt while somebody is still waiting', (
      tester,
    ) async {
      await tester.pumpWidget(_cardHarness(_mixedAnswers));
      await tester.pumpAndSettle();

      expect(find.textContaining('Everyone answered'), findsNothing);
    });
  });

  group('RoomBatonCard «Choose now»', () {
    testWidgets('is disabled and says nobody can help while nobody has '
        'said can help', (tester) async {
      await tester.pumpWidget(
        _cardHarness(_nobodyCanHelp, onSelect: (_) {}, onCancel: () {}),
      );
      await tester.pumpAndSettle();

      expect(find.text('Choose now'), findsOneWidget);
      expect(_buttonLabelled('Choose now').onPressed, isNull);
      expect(find.text('Nobody can help yet.'), findsOneWidget);

      await tester.tap(find.text('Choose now'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Pick for me'), findsNothing);
    });

    testWidgets('is enabled with one person who can help while others '
        'are still waiting', (tester) async {
      await tester.pumpWidget(
        _cardHarness(
          _oneCanHelpOthersWaiting,
          onSelect: (_) {},
          onCancel: () {},
        ),
      );
      await tester.pumpAndSettle();

      expect(_buttonLabelled('Choose now').onPressed, isNotNull);
      expect(find.text('Nobody can help yet.'), findsNothing);
    });
  });

  group('RoomBatonCard choose sheet', () {
    testWidgets('lists only the people who can help', (tester) async {
      await tester.pumpWidget(
        _cardHarness(_mixedAnswers, onSelect: (_) {}, onCancel: () {}),
      );
      await tester.pumpAndSettle();
      await _openChooseSheet(tester);

      final sheet = _sheetContent(tester);
      expect(
        find.descendant(of: sheet, matching: find.text('Boris Driver')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Eva Helper')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Clara Pending')),
        findsNothing,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Dmitri Busy')),
        findsNothing,
      );
    });

    testWidgets('groups people who can help by priority, highest first', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardHarness(_tiered, onSelect: (_) {}, onCancel: () {}),
      );
      await tester.pumpAndSettle();
      await _openChooseSheet(tester);

      final sheet = _sheetContent(tester);
      double top(String text) => tester.getTopLeft(
        find.descendant(of: sheet, matching: find.text(text)),
      ).dy;

      expect(top('Priority 1'), lessThan(top('Eva Helper')));
      expect(top('Eva Helper'), lessThan(top('Priority 2')));
      expect(top('Priority 2'), lessThan(top('Boris Driver')));
      expect(top('Priority 2'), lessThan(top('Fedor Spare')));
      expect(
        find.descendant(of: sheet, matching: find.text('Priority 3')),
        findsNothing,
        reason: 'nobody in priority 3 can help',
      );
    });

    testWidgets('«Pick for me» lets the server choose', (tester) async {
      final picks = <String?>[];
      await tester.pumpWidget(
        _cardHarness(_mixedAnswers, onSelect: picks.add, onCancel: () {}),
      );
      await tester.pumpAndSettle();
      await _openChooseSheet(tester);

      expect(
        find.text('One person from the highest priority, at random.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Pick for me'));
      await tester.pumpAndSettle();

      expect(picks, [null]);
      expect(find.text('Pick for me'), findsNothing, reason: 'sheet closed');
    });

    testWidgets('tapping a name picks that person', (tester) async {
      final picks = <String?>[];
      await tester.pumpWidget(
        _cardHarness(_mixedAnswers, onSelect: picks.add, onCancel: () {}),
      );
      await tester.pumpAndSettle();
      await _openChooseSheet(tester);

      await tester.tap(
        find.descendant(
          of: _sheetContent(tester),
          matching: find.text('Eva Helper'),
        ),
      );
      await tester.pumpAndSettle();

      expect(picks, ['u-eva']);
      expect(find.text('Pick for me'), findsNothing, reason: 'sheet closed');
    });
  });

  group('RoomBatonCard «Cancel»', () {
    testWidgets('asks for confirmation before reporting a cancel', (
      tester,
    ) async {
      var cancels = 0;
      await tester.pumpWidget(
        _cardHarness(
          _mixedAnswers,
          onSelect: (_) {},
          onCancel: () => cancels++,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(cancels, 0);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();

      expect(cancels, 1);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('keeps the baton when the author dismisses the '
        'confirmation', (tester) async {
      var cancels = 0;
      await tester.pumpWidget(
        _cardHarness(
          _mixedAnswers,
          onSelect: (_) {},
          onCancel: () => cancels++,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextButton),
        ),
      );
      await tester.pumpAndSettle();

      expect(cancels, 0);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('RoomBatonCard for the author once someone took it', () {
    testWidgets('collapses to the taker and nothing else', (tester) async {
      await tester.pumpWidget(
        _cardHarness(_taken, onSelect: (_) {}, onCancel: () {}),
      );
      await tester.pumpAndSettle();

      expect(find.text('Boris Driver took it.'), findsOneWidget);
      for (final name in ['Clara Pending', 'Dmitri Busy']) {
        expect(find.textContaining(name), findsNothing);
      }
      expect(find.text('Who\'ll take it: answers'), findsNothing);
      expect(find.text('Choose now'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
      expect(find.textContaining('can help'), findsNothing);
      expect(find.textContaining('waiting'), findsNothing);
    });

    testWidgets('says who took it in Russian', (tester) async {
      await tester.pumpWidget(
        _cardHarness(_taken, locale: const Locale('ru')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Берёт на себя: Boris Driver'), findsOneWidget);
    });
  });

  group('RoomMessageTile for the author of a baton', () {
    testWidgets('shows the answers card under the message', (tester) async {
      await tester.pumpWidget(_tileHarness(_mixedAnswers));
      await tester.pumpAndSettle();

      expect(find.byType(RoomBatonCard), findsOneWidget);
      expect(find.text('Who\'ll take it: answers'), findsOneWidget);
    });

    testWidgets('forwards a pick with the baton id', (tester) async {
      final picks = <({String batonId, String? userId})>[];
      await tester.pumpWidget(
        _tileHarness(
          _mixedAnswers,
          onBatonSelect: (batonId, userId) =>
              picks.add((batonId: batonId, userId: userId)),
          onBatonCancel: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      await _openChooseSheet(tester);
      await tester.tap(find.text('Pick for me'));
      await tester.pumpAndSettle();

      expect(picks, [(batonId: 'baton-1', userId: null)]);
    });

    testWidgets('forwards a manual pick with the baton id and the chosen '
        'user', (tester) async {
      final picks = <({String batonId, String? userId})>[];
      await tester.pumpWidget(
        _tileHarness(
          _mixedAnswers,
          onBatonSelect: (batonId, userId) =>
              picks.add((batonId: batonId, userId: userId)),
          onBatonCancel: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      await _openChooseSheet(tester);
      await tester.tap(
        find.descendant(
          of: _sheetContent(tester),
          matching: find.text('Eva Helper'),
        ),
      );
      await tester.pumpAndSettle();

      expect(picks, [(batonId: 'baton-1', userId: 'u-eva')]);
    });

    testWidgets('forwards a confirmed cancel with the baton id', (
      tester,
    ) async {
      final cancelled = <String>[];
      await tester.pumpWidget(
        _tileHarness(
          _mixedAnswers,
          onBatonSelect: (_, _) {},
          onBatonCancel: cancelled.add,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();

      expect(cancelled, ['baton-1']);
    });
  });
}
