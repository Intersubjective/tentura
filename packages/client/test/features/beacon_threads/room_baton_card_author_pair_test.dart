// «Who'll take it?» baton together, author side: a confirmed pair is ONE row
// «A and X — can help together» (two avatars), never two solo rows; «Choose
// now» counts it; the choose sheet lists it once under its tier and tapping it
// picks the pair's taker; `RoomMessageTile` forwards that pick with the baton
// id. Pending pairs (A named X, X silent) stay a plain «waiting» row.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_baton_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _author = Profile(id: 'u-anna', displayName: 'Anna Author');
const _a = 'Boris Driver';
const _x = 'Xenia Partner';

RoomBatonCandidate _candidate(
  String id,
  String title,
  RoomBatonResponse response, {
  int tier = 1,
  RoomBatonTaker? partner,
}) => RoomBatonCandidate(
  userId: id,
  title: title,
  tier: tier,
  response: response,
  partner: partner,
);

const _xAsPartner = RoomBatonTaker(id: 'u-xenia', title: _x);
const _aAsPartner = RoomBatonTaker(id: 'u-boris', title: _a);

RoomBatonAuthorData _collecting(
  List<RoomBatonCandidate> candidates, {
  List<RoomBatonConfirmedPair> pairs = const [],
}) => RoomBatonAuthorData(
  id: 'baton-1',
  status: RoomBatonStatus.collecting,
  candidates: candidates,
  allAnswered: false,
  eligibleCount: pairs.length,
  pairs: pairs,
);

const _pairAX = RoomBatonConfirmedPair(
  takerId: 'u-boris',
  partnerId: 'u-xenia',
  tier: 1,
);

/// A can help with X (accepted), B waits.
final _pairAndWaiting = _collecting(
  [
    _candidate(
      'u-boris',
      _a,
      RoomBatonResponse.canHelp,
      partner: _xAsPartner,
    ),
    _candidate('u-clara', 'Clara Pending', RoomBatonResponse.waiting),
  ],
  pairs: const [_pairAX],
);

/// A and X both asked, each can help naming the other.
final _mutualPair = _collecting(
  [
    _candidate(
      'u-boris',
      _a,
      RoomBatonResponse.canHelp,
      partner: _xAsPartner,
    ),
    _candidate(
      'u-xenia',
      _x,
      RoomBatonResponse.canHelp,
      partner: _aAsPartner,
    ),
  ],
  pairs: const [_pairAX],
);

/// A named X, X has not answered: projected as plain waiting.
final _pendingPair = _collecting([
  _candidate('u-boris', _a, RoomBatonResponse.waiting),
  _candidate('u-clara', 'Clara Pending', RoomBatonResponse.waiting),
]);

final _pairOnlyChoosable = _collecting(
  [
    _candidate(
      'u-boris',
      _a,
      RoomBatonResponse.canHelp,
      partner: _xAsPartner,
    ),
    _candidate('u-clara', 'Clara Pending', RoomBatonResponse.waiting),
    _candidate('u-dmitri', 'Dmitri Busy', RoomBatonResponse.cantHelp),
  ],
  pairs: const [_pairAX],
);

final _pairAndSolo = _collecting(
  [
    _candidate(
      'u-boris',
      _a,
      RoomBatonResponse.canHelp,
      partner: _xAsPartner,
    ),
    _candidate('u-eva', 'Eva Helper', RoomBatonResponse.canHelp),
  ],
  pairs: const [_pairAX],
);

final _pairTier1SoloTier2 = _collecting(
  [
    _candidate(
      'u-boris',
      _a,
      RoomBatonResponse.canHelp,
      partner: _xAsPartner,
    ),
    _candidate('u-eva', 'Eva Helper', RoomBatonResponse.canHelp, tier: 2),
  ],
  pairs: const [_pairAX],
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
  Locale locale = const Locale('en'),
}) => _localized(
  RoomBatonCard(baton: baton, onSelect: onSelect, onCancel: () {}),
  locale: locale,
);

Widget _tileHarness(
  RoomBatonData baton, {
  void Function(String batonId, String? userId)? onBatonSelect,
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
      onToggleReaction: (_, _) async {},
      onBatonSelect: onBatonSelect,
      onBatonCancel: (_) {},
    ),
  ),
);

/// The nearest Row that holds both [name] and [status].
Finder _rowOf(Finder name, String status) {
  for (final row
      in find.ancestor(of: name, matching: find.byType(Row)).evaluate()) {
    final own = find.byElementPredicate((e) => identical(e, row));
    if (find
        .descendant(of: own, matching: find.text(status))
        .evaluate()
        .isNotEmpty) {
      return own;
    }
  }
  return find.byType(SizedBox).hitTestable(); // none: callers' expects fail
}

/// The content of the open choose sheet.
Finder _sheetContent(WidgetTester tester) {
  final pick = find.text('Pick for me');
  expect(pick, findsOneWidget, reason: 'the choose sheet is open');
  var sheet = tester.element(pick);
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

Future<void> _openChooseSheet(WidgetTester tester) async {
  await tester.tap(find.text('Choose now'));
  await tester.pump(kDoubleTapTimeout);
  await tester.pumpAndSettle();
}

ButtonStyleButton _buttonLabelled(String label) =>
    find
            .ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            )
            .evaluate()
            .first
            .widget
        as ButtonStyleButton;

void main() {
  group('RoomBatonCard author view of a confirmed pair', () {
    testWidgets('shows one row with both avatars, both names and «can help '
        'together»; the partner has no solo row', (tester) async {
      await tester.pumpWidget(_cardHarness(_pairAndWaiting));
      await tester.pumpAndSettle();

      const names = '$_a and $_x';
      expect(find.text(names), findsOneWidget);
      expect(find.text('can help together'), findsOneWidget);
      final row = _rowOf(find.text(names), 'can help together');
      expect(row, findsOneWidget, reason: 'names and status share one row');
      expect(
        find.descendant(of: row, matching: find.byType(TenturaAvatar)),
        findsNWidgets(2),
      );
      expect(find.text(_a), findsNothing, reason: 'no separate solo row');
      expect(find.text(_x), findsNothing);
      expect(find.text('can help'), findsNothing);

      expect(find.text('Clara Pending'), findsOneWidget);
      expect(find.text('waiting'), findsOneWidget);
    });

    testWidgets('states the pair in Russian', (tester) async {
      await tester.pumpWidget(
        _cardHarness(_pairAndWaiting, locale: const Locale('ru')),
      );
      await tester.pumpAndSettle();

      expect(find.text('$_a и $_x'), findsOneWidget);
      expect(find.text('могут вместе'), findsOneWidget);
    });

    testWidgets('a mutual pair is one row, not one per person', (tester) async {
      await tester.pumpWidget(_cardHarness(_mutualPair));
      await tester.pumpAndSettle();

      expect(find.text('$_a and $_x'), findsOneWidget);
      expect(find.text('can help together'), findsOneWidget);
      expect(find.text(_a), findsNothing);
      expect(find.text(_x), findsNothing);
      expect(find.text('can help'), findsNothing);
    });

    testWidgets('a pending pair stays a plain «waiting» row and does not '
        'name the partner', (tester) async {
      await tester.pumpWidget(_cardHarness(_pendingPair));
      await tester.pumpAndSettle();

      expect(find.text(_a), findsOneWidget);
      expect(find.textContaining('Xenia'), findsNothing);
      expect(find.text('can help together'), findsNothing);
      expect(find.text('waiting'), findsNWidgets(2));
    });
  });

  group('RoomBatonCard «Choose now» with a pair', () {
    testWidgets('is enabled with only a pair who can help', (tester) async {
      await tester.pumpWidget(
        _cardHarness(_pairOnlyChoosable, onSelect: (_) {}),
      );
      await tester.pumpAndSettle();

      expect(_buttonLabelled('Choose now').onPressed, isNotNull);
      expect(find.text('Nobody can help yet.'), findsNothing);
    });
  });

  group('RoomBatonCard choose sheet with a pair', () {
    testWidgets('lists the pair once, «together», next to solo helpers', (
      tester,
    ) async {
      await tester.pumpWidget(_cardHarness(_pairAndSolo, onSelect: (_) {}));
      await tester.pumpAndSettle();
      await _openChooseSheet(tester);

      final sheet = _sheetContent(tester);
      Finder inSheet(String t) =>
          find.descendant(of: sheet, matching: find.text(t));
      expect(inSheet('Pick for me'), findsOneWidget);
      expect(inSheet('$_a and $_x'), findsOneWidget);
      expect(inSheet('together'), findsOneWidget);
      expect(inSheet('Eva Helper'), findsOneWidget);
      expect(inSheet(_a), findsNothing);
      expect(inSheet(_x), findsNothing);
    });

    testWidgets('lists a mutual pair exactly once', (tester) async {
      await tester.pumpWidget(_cardHarness(_mutualPair, onSelect: (_) {}));
      await tester.pumpAndSettle();
      await _openChooseSheet(tester);

      final sheet = _sheetContent(tester);
      expect(
        find.descendant(of: sheet, matching: find.text('$_a and $_x')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text(_x)),
        findsNothing,
      );
    });

    testWidgets('puts the pair under its own priority, before lower ones', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardHarness(_pairTier1SoloTier2, onSelect: (_) {}),
      );
      await tester.pumpAndSettle();
      await _openChooseSheet(tester);

      final sheet = _sheetContent(tester);
      double top(String text) => tester
          .getTopLeft(find.descendant(of: sheet, matching: find.text(text)))
          .dy;
      expect(top('Priority 1'), lessThan(top('$_a and $_x')));
      expect(top('$_a and $_x'), lessThan(top('Priority 2')));
      expect(top('Priority 2'), lessThan(top('Eva Helper')));
      expect(
        top('together'),
        inInclusiveRange(top('$_a and $_x'), top('Priority 2')),
        reason: 'the «together» subtitle sits on the pair entry in tier 1',
      );
    });

    testWidgets("tapping the pair picks the pair's taker, not the partner", (
      tester,
    ) async {
      final picks = <String?>[];
      await tester.pumpWidget(_cardHarness(_pairAndSolo, onSelect: picks.add));
      await tester.pumpAndSettle();
      await _openChooseSheet(tester);

      await tester.tap(
        find.descendant(
          of: _sheetContent(tester),
          matching: find.text('$_a and $_x'),
        ),
      );
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      expect(picks, ['u-boris']);
      expect(find.text('Pick for me'), findsNothing, reason: 'sheet closed');
    });
  });

  group('RoomMessageTile forwards a pair pick', () {
    testWidgets('batonSelect gets the baton id and the pair taker', (
      tester,
    ) async {
      final calls = <(String, String?)>[];
      await tester.pumpWidget(
        _tileHarness(
          _pairAndSolo,
          onBatonSelect: (batonId, userId) => calls.add((batonId, userId)),
        ),
      );
      await tester.pumpAndSettle();
      await _openChooseSheet(tester);

      await tester.tap(
        find.descendant(
          of: _sheetContent(tester),
          matching: find.text('$_a and $_x'),
        ),
      );
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();

      expect(calls, [('baton-1', 'u-boris')]);
    });
  });
}
