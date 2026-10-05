// «Who'll take it?» baton, client side for everyone except the message author:
//  - `RoomBatonCard` shows an asked person a private card (prompt, Can help /
//    Can't help, availability note) that leaks no other names, tier or counts;
//  - once the baton is final it shows the outcome copy (you / someoneElse /
//    closed); anyone else only ever sees a «{name} took it.» chip;
//  - `RoomMessageTile` renders that card under a message that carries a baton,
//    and renders the marker-12 system line without any list of refusals;
//  - `RoomCubit.batonRespond` updates the answer optimistically (poll-vote
//    pattern) and rolls it back when the request fails;
//  - end to end, tapping Can help on a tile backed by a real `RoomCubit`
//    reaches the repository with `canHelp: true` and shows the answered copy
//    before the server replies.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_baton_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

const _viewer = Profile(id: 'u-viewer', displayName: 'Viewer');
const _batonAuthor = Profile(id: 'u-anna', displayName: 'Anna Author');

const _waiting = RoomBatonCandidateData(
  id: 'baton-1',
  status: RoomBatonStatus.collecting,
  myResponse: RoomBatonResponse.waiting,
);

RoomBatonCandidateData _answered(RoomBatonResponse response) =>
    RoomBatonCandidateData(
      id: 'baton-1',
      status: RoomBatonStatus.collecting,
      myResponse: response,
    );

RoomBatonCandidateData _outcome(
  RoomBatonOutcome outcome, {
  RoomBatonStatus status = RoomBatonStatus.taken,
  RoomBatonResponse? myResponse,
}) => RoomBatonCandidateData(
  id: 'baton-1',
  status: status,
  myResponse: myResponse,
  outcome: outcome,
);

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _viewer);

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
  void Function(bool canHelp)? onRespond,
}) => _localized(RoomBatonCard(baton: baton, onRespond: onRespond));

Widget _tileHarness(
  RoomMessage message, {
  List<BeaconParticipant> participants = const [],
  Locale locale = const Locale('en'),
  void Function(String batonId, bool canHelp)? onBatonRespond,
}) => MultiBlocProvider(
  providers: [
    BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
    BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
    BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
  ],
  child: _localized(
    RoomMessageTile(
      message: message,
      myProfile: _viewer,
      participants: participants,
      onToggleReaction: (_, _) async {},
      onBatonRespond: onBatonRespond,
    ),
    locale: locale,
  ),
);

RoomMessage _messageWithBaton(RoomBatonData? baton) => RoomMessage(
  id: 'msg-1',
  beaconId: 'b-baton',
  authorId: _batonAuthor.id,
  author: _batonAuthor,
  body: 'Can somebody drive the van on Saturday?',
  createdAt: DateTime.utc(2026, 10, 3, 12),
  baton: baton,
);

BeaconParticipant _participant(String userId, String title) =>
    BeaconParticipant(
      id: 'p-$userId',
      beaconId: 'b-baton',
      userId: userId,
      role: 0,
      status: 0,
      roomAccess: 1,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      userTitle: title,
    );

RoomMessage _tookItMessage() => RoomMessage(
  id: 'sys-1',
  beaconId: 'b-baton',
  authorId: _batonAuthor.id,
  author: _batonAuthor,
  body: '',
  createdAt: DateTime.utc(2026, 10, 3, 13),
  semanticMarker: BeaconRoomSemanticMarker.batonTaken,
  systemPayloadJson:
      '{"batonId":"baton-1","sourceMessageId":"msg-1",'
      '"takerUserId":"u-boris"}',
);

const _batonStringLeaks = [
  'priority',
  'tier',
  'rank',
  'приоритет',
  'ранг',
];

/// Icons that spell out a number or a count; a tier could hide in one.
const _numberedIcons = <IconData>[
  Icons.looks_one,
  Icons.looks_two,
  Icons.looks_3,
  Icons.looks_4,
  Icons.looks_5,
  Icons.looks_6,
  Icons.filter_1,
  Icons.filter_2,
  Icons.filter_3,
  Icons.exposure_plus_1,
  Icons.numbers,
];

/// Every string a user, a screen reader or a tooltip could read in [scope]:
/// text, rich text, tooltips, semantics labels and icon labels.
List<String> _allStringsIn(WidgetTester tester, Finder scope) {
  final out = <String>[];
  for (final w in tester.widgetList(
    find.descendant(of: scope, matching: find.byWidgetPredicate((_) => true)),
  )) {
    switch (w) {
      case Text(:final data, :final textSpan, :final semanticsLabel):
        out.addAll([?data, ?textSpan?.toPlainText(), ?semanticsLabel]);
      case RichText(:final text):
        out.add(text.toPlainText());
      case Tooltip(:final message, :final richMessage):
        out.addAll([?message, ?richMessage?.toPlainText()]);
      case Semantics(:final properties):
        out.addAll([?properties.label, ?properties.value, ?properties.hint]);
      case Icon(:final semanticLabel):
        out.addAll([?semanticLabel]);
    }
  }
  return out;
}

Finder _countOrTierWidgetsIn(Finder scope) => find.descendant(
  of: scope,
  matching: find.byWidgetPredicate(
    (w) =>
        w is Badge ||
        w is Slider ||
        w is ProgressIndicator ||
        (w is Icon && _numberedIcons.contains(w.icon)),
  ),
);

/// Serves one message carrying a baton and lets a test hold the answer back.
class _BatonRespondRepository extends FakeBeaconThreadsRepository {
  _BatonRespondRepository({required super.userId});

  final calls = <({String batonId, bool canHelp})>[];
  Completer<void>? gate;
  Exception? error;

  /// Message that carries the baton; refetches serve its updated projection.
  String batonMessageId = 'msg-1';

  @override
  Future<RoomBatonData?> batonRespond({
    required String batonId,
    required bool canHelp,
  }) async {
    calls.add((batonId: batonId, canHelp: canHelp));
    final held = gate;
    if (held != null) await held.future;
    final failure = error;
    if (failure != null) throw failure;
    final updated = _answered(
      canHelp ? RoomBatonResponse.canHelp : RoomBatonResponse.cantHelp,
    );
    messages = [
      for (final m in messages)
        if (m.id == batonMessageId) m.copyWith(baton: updated) else m,
    ];
    return updated;
  }
}

void main() {
  group('RoomBatonCard for an asked person who has not answered', () {
    testWidgets('shows the prompt, both answer buttons and the availability '
        'note', (tester) async {
      await tester.pumpWidget(_cardHarness(_waiting));
      await tester.pumpAndSettle();

      expect(
        find.text('Can you help? We\'re waiting for your response.'),
        findsOneWidget,
      );
      expect(find.text('Can help'), findsOneWidget);
      expect(find.text('Can\'t help'), findsOneWidget);
      expect(
        find.text(
          '"Can help" means you\'re available, not that you\'ve taken it '
          'yet. If several people can help, one person will be selected.',
        ),
        findsOneWidget,
      );
    });

    for (final locale in const [Locale('en'), Locale('ru')]) {
      for (final (label, baton) in [
        ('before answering', _waiting),
        ('after answering', _answered(RoomBatonResponse.canHelp)),
      ]) {
        testWidgets(
          'exposes no other names, tier or counts $label (${locale.languageCode})',
          (tester) async {
            await tester.pumpWidget(
              _localized(RoomBatonCard(baton: baton), locale: locale),
            );
            await tester.pumpAndSettle();

            final card = find.byType(RoomBatonCard);
            final strings = _allStringsIn(tester, card);
            expect(strings, isNotEmpty);
            for (final text in strings) {
              expect(
                text,
                isNot(matches(RegExp(r'\d'))),
                reason: 'no counts or tier numbers in "$text"',
              );
              for (final leak in _batonStringLeaks) {
                expect(
                  text.toLowerCase(),
                  isNot(contains(leak)),
                  reason: '"$text" must not mention "$leak"',
                );
              }
              expect(text, isNot(contains(_batonAuthor.displayName)));
            }
            expect(
              _countOrTierWidgetsIn(card),
              findsNothing,
              reason: 'no badge, progress or numbered icon in a candidate card',
            );
          },
        );
      }
    }

    testWidgets('tapping Can help reports a positive answer', (tester) async {
      final answers = <bool>[];
      await tester.pumpWidget(
        _cardHarness(
          _waiting,
          onRespond: (canHelp) async => answers.add(canHelp),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Can help'));
      await tester.pump();

      expect(answers, [true]);
    });

    testWidgets('tapping Can\'t help reports a negative answer', (
      tester,
    ) async {
      final answers = <bool>[];
      await tester.pumpWidget(
        _cardHarness(
          _waiting,
          onRespond: (canHelp) async => answers.add(canHelp),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Can\'t help'));
      await tester.pump();

      expect(answers, [false]);
    });
  });

  group('RoomBatonCard for an asked person who already answered', () {
    testWidgets('names a positive answer and says it can be changed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardHarness(_answered(RoomBatonResponse.canHelp)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Your answer: Can help. You can change it.'),
        findsOneWidget,
      );
      expect(
        find.text('Can you help? We\'re waiting for your response.'),
        findsNothing,
      );
    });

    testWidgets('names a negative answer and says it can be changed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardHarness(_answered(RoomBatonResponse.cantHelp)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Your answer: Can\'t help. You can change it.'),
        findsOneWidget,
      );
    });

    testWidgets('lets the person switch to the other answer while collecting', (
      tester,
    ) async {
      final answers = <bool>[];
      await tester.pumpWidget(
        _cardHarness(
          _answered(RoomBatonResponse.canHelp),
          onRespond: (canHelp) async => answers.add(canHelp),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Can\'t help'));
      await tester.pump();

      expect(answers, [false]);
    });
  });

  group('RoomBatonCard once the baton is final for an asked person', () {
    testWidgets('tells the taker "You took it."', (tester) async {
      await tester.pumpWidget(
        _cardHarness(
          _outcome(RoomBatonOutcome.you, myResponse: RoomBatonResponse.canHelp),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('You took it.'), findsOneWidget);
      expect(find.text('Can help'), findsNothing);
      expect(find.text('Can\'t help'), findsNothing);
    });

    testWidgets('tells an unchosen volunteer someone else was selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardHarness(
          _outcome(
            RoomBatonOutcome.someoneElse,
            myResponse: RoomBatonResponse.canHelp,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Someone else was selected. Thanks for offering.'),
        findsOneWidget,
      );
      expect(find.text('Can help'), findsNothing);
    });

    testWidgets('tells a person who declined it is closed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardHarness(
          _outcome(
            RoomBatonOutcome.closed,
            myResponse: RoomBatonResponse.cantHelp,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No longer needed.'), findsOneWidget);
      expect(find.text('Can help'), findsNothing);
      expect(find.text('Can\'t help'), findsNothing);
    });

    for (final response in [RoomBatonResponse.waiting, null]) {
      testWidgets(
        'tells a person who never answered it is closed '
        '(answer: ${response?.name ?? 'absent'})',
        (tester) async {
          await tester.pumpWidget(
            _cardHarness(
              _outcome(RoomBatonOutcome.closed, myResponse: response),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('No longer needed.'), findsOneWidget);
          expect(find.text('Can help'), findsNothing);
          expect(find.text('Can\'t help'), findsNothing);
          expect(
            find.text('Can you help? We\'re waiting for your response.'),
            findsNothing,
          );
        },
      );
    }

    testWidgets('says "No longer needed." when the author cancelled', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardHarness(
          _outcome(RoomBatonOutcome.closed, status: RoomBatonStatus.cancelled),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No longer needed.'), findsOneWidget);
      expect(find.text('Can help'), findsNothing);
    });
  });

  group('RoomBatonCard for everyone else', () {
    testWidgets('shows only a "{name} took it." chip', (tester) async {
      await tester.pumpWidget(
        _cardHarness(
          const RoomBatonObserverData(
            id: 'baton-1',
            status: RoomBatonStatus.taken,
            taker: RoomBatonTaker(id: 'u-boris', title: 'Boris Taker'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Boris Taker took it.'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RoomBatonCard),
          matching: find.byType(Text),
        ),
        findsOneWidget,
      );
      expect(find.text('Can help'), findsNothing);
      expect(find.text('Can\'t help'), findsNothing);
    });
  });

  group('RoomMessageTile with a baton on the message', () {
    testWidgets('renders the candidate card under the message text', (
      tester,
    ) async {
      await tester.pumpWidget(_tileHarness(_messageWithBaton(_waiting)));
      await tester.pumpAndSettle();

      final body = find.textContaining(
        'Can somebody drive the van on Saturday?',
        findRichText: true,
      );
      expect(body, findsOneWidget);
      expect(find.byType(RoomBatonCard), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(RoomBatonCard)).dy,
        greaterThan(tester.getBottomLeft(body).dy - 1),
        reason: 'the card sits under the message it is about',
      );
    });

    testWidgets('forwards the answer with the baton id', (tester) async {
      final answers = <({String batonId, bool canHelp})>[];
      await tester.pumpWidget(
        _tileHarness(
          _messageWithBaton(_waiting),
          onBatonRespond: (batonId, canHelp) async =>
              answers.add((batonId: batonId, canHelp: canHelp)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Can help'));
      await tester.pump();

      expect(answers, [(batonId: 'baton-1', canHelp: true)]);
    });

    testWidgets('renders only the taker chip for an observer', (tester) async {
      await tester.pumpWidget(
        _tileHarness(
          _messageWithBaton(
            const RoomBatonObserverData(
              id: 'baton-1',
              status: RoomBatonStatus.taken,
              taker: RoomBatonTaker(id: 'u-boris', title: 'Boris Taker'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final card = find.byType(RoomBatonCard);
      expect(card, findsOneWidget);
      expect(find.text('Boris Taker took it.'), findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.byType(Text)),
        findsOneWidget,
        reason: 'the chip is the only text the card shows an observer',
      );
      for (final copy in [
        'Can you help? We\'re waiting for your response.',
        'Can help',
        'Can\'t help',
        'You took it.',
        'No longer needed.',
      ]) {
        expect(find.text(copy), findsNothing, reason: copy);
      }
      expect(
        find.descendant(
          of: card,
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
        findsNothing,
      );
      expect(find.textContaining('Your answer:'), findsNothing);
    });

    for (final (label, baton) in [
      ('before answering', _waiting),
      ('after answering', _answered(RoomBatonResponse.canHelp)),
    ]) {
      testWidgets(
        'keeps other people\'s names out of the candidate card $label',
        (tester) async {
          final message = _messageWithBaton(baton).copyWith(
            reactionCounts: const {'👍': 1},
            reactors: const {
              '👍': [Profile(id: 'u-dmitri', displayName: 'Dmitri Reactor')],
            },
          );
          await tester.pumpWidget(
            _tileHarness(
              message,
              participants: [
                _participant('u-boris', 'Boris Taker'),
                _participant('u-clara', 'Clara Declined'),
                _participant('u-dmitri', 'Dmitri Reactor'),
                _participant('u-anna', 'Anna Author'),
              ],
            ),
          );
          await tester.pumpAndSettle();

          final card = find.byType(RoomBatonCard);
          expect(card, findsOneWidget);
          final strings = _allStringsIn(tester, card);
          expect(strings, isNotEmpty);
          for (final text in strings) {
            for (final name in [
              'Boris',
              'Clara',
              'Dmitri',
              'Anna',
              'Viewer',
            ]) {
              expect(
                text,
                isNot(contains(name)),
                reason: 'the card must not show "$name": "$text"',
              );
            }
          }
        },
      );
    }

    testWidgets('renders no baton card on an ordinary message', (tester) async {
      await tester.pumpWidget(_tileHarness(_messageWithBaton(null)));
      await tester.pumpAndSettle();

      expect(find.byType(RoomBatonCard), findsNothing);
      expect(find.text('Can help'), findsNothing);
    });
  });

  group('Room system line for a baton that was taken', () {
    final refusalCopy = RegExp(
      r"declin|refus|can't help|cannot|waiting|unanswered|не могу|отказ|ждём",
      caseSensitive: false,
    );

    testWidgets('names the taker and lists no refusals', (tester) async {
      await tester.pumpWidget(
        _tileHarness(
          _tookItMessage(),
          participants: [
            _participant('u-boris', 'Boris Taker'),
            _participant('u-anna', 'Anna Author'),
            _participant('u-clara', 'Clara Declined'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Boris Taker took it.'), findsOneWidget);
      expect(find.text('Anna Author'), findsNothing);
      expect(find.textContaining('Clara Declined'), findsNothing);
      expect(find.text('Can help'), findsNothing);
      expect(find.text('Can\'t help'), findsNothing);

      final line = find.byType(RoomMessageTile);
      final strings = _allStringsIn(tester, line);
      expect(strings, contains('Boris Taker took it.'));
      for (final text in strings) {
        expect(
          text,
          isNot(matches(refusalCopy)),
          reason: 'the system line must carry no refusal content: "$text"',
        );
      }
      expect(
        find.descendant(of: line, matching: find.byType(ListTile)),
        findsNothing,
      );
      expect(find.byType(RoomBatonCard), findsNothing);
    });

    testWidgets('ignores refusal data even if a payload carries it', (
      tester,
    ) async {
      final message = _tookItMessage().copyWith(
        systemPayloadJson:
            '{"batonId":"baton-1","sourceMessageId":"msg-1",'
            '"takerUserId":"u-boris","refusedUserIds":["u-clara"],'
            '"declinedUserIds":["u-clara"]}',
      );
      await tester.pumpWidget(
        _tileHarness(
          message,
          participants: [
            _participant('u-boris', 'Boris Taker'),
            _participant('u-clara', 'Clara Declined'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Boris Taker took it.'), findsOneWidget);
      expect(find.textContaining('Clara'), findsNothing);
    });

    testWidgets('uses the canonical Russian copy', (tester) async {
      await tester.pumpWidget(
        _tileHarness(
          _tookItMessage(),
          participants: [_participant('u-boris', 'Борис')],
          locale: const Locale('ru'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Берёт на себя: Борис'), findsOneWidget);
    });
  });

  group('RoomCubit.batonRespond', () {
    Future<(_BatonRespondRepository, RoomCubit)> openRoom() async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final repo = _BatonRespondRepository(userId: kRoomCubitFakeMyUserId)
        ..messages = [
          RoomMessage(
            id: 'msg-1',
            beaconId: kRoomCubitFakeBeaconId,
            authorId: 'u-anna',
            body: 'Who can drive?',
            createdAt: DateTime.utc(2026, 10, 3),
            baton: _waiting,
          ),
        ];
      final cubit = roomCubitForTest(repo, effects: FakeUiEffectPort());
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);
      return (repo, cubit);
    }

    RoomBatonResponse? shownResponse(RoomCubit cubit) {
      final baton = cubit.state.messages
          .firstWhere((m) => m.id == 'msg-1')
          .baton;
      return baton is RoomBatonCandidateData ? baton.myResponse : null;
    }

    test('shows the answer before the server has replied', () async {
      final (repo, cubit) = await openRoom();
      repo.gate = Completer<void>();

      final pending = cubit.batonRespond(
        messageId: 'msg-1',
        batonId: 'baton-1',
        canHelp: true,
      );

      expect(shownResponse(cubit), RoomBatonResponse.canHelp);
      repo.gate!.complete();
      await pending;
      expect(repo.calls, [(batonId: 'baton-1', canHelp: true)]);
      expect(shownResponse(cubit), RoomBatonResponse.canHelp);
    });

    test('restores the previous answer when the request fails', () async {
      final (repo, cubit) = await openRoom();
      repo.error = Exception('offline');

      await cubit.batonRespond(
        messageId: 'msg-1',
        batonId: 'baton-1',
        canHelp: false,
      );

      expect(repo.calls, [(batonId: 'baton-1', canHelp: false)]);
      expect(shownResponse(cubit), RoomBatonResponse.waiting);
    });
  });

  group('Answering from a message tile backed by a real RoomCubit', () {
    late _BatonRespondRepository repo;
    late RoomCubit cubit;

    Future<void> openRoomWithTile(WidgetTester tester) async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      repo = _BatonRespondRepository(userId: kRoomCubitFakeMyUserId)
        ..messages = [
          RoomMessage(
            id: 'msg-1',
            beaconId: kRoomCubitFakeBeaconId,
            authorId: 'u-anna',
            author: _batonAuthor,
            body: 'Who can drive?',
            createdAt: DateTime.utc(2026, 10, 3),
            baton: _waiting,
          ),
        ];
      cubit = roomCubitForTest(repo, effects: FakeUiEffectPort());
      addTearDown(cubit.close);

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
            BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
            BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
            BlocProvider<RoomCubit>.value(value: cubit),
          ],
          child: _localized(
            BlocBuilder<RoomCubit, RoomState>(
              builder: (context, state) {
                final message = state.messages
                    .where((m) => m.id == 'msg-1')
                    .firstOrNull;
                if (message == null) return const SizedBox.shrink();
                return RoomMessageTile(
                  message: message,
                  myProfile: _viewer,
                  onToggleReaction: (_, _) async {},
                  onBatonRespond: (batonId, canHelp) => cubit.batonRespond(
                    messageId: message.id,
                    batonId: batonId,
                    canHelp: canHelp,
                  ),
                );
              },
            ),
          ),
        ),
      );
      for (var i = 0; i < 40 && cubit.state.status is StateIsLoading; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    testWidgets('tapping Can help asks the server with canHelp true and shows '
        'the answered copy before it replies', (tester) async {
      await openRoomWithTile(tester);
      expect(
        find.textContaining('Who can drive?', findRichText: true),
        findsOneWidget,
      );
      repo.gate = Completer<void>();

      await tester.tap(find.text('Can help'));
      await tester.pump();

      expect(repo.calls, [(batonId: 'baton-1', canHelp: true)]);
      expect(
        find.text('Your answer: Can help. You can change it.'),
        findsOneWidget,
      );
      expect(
        find.text('Can you help? We\'re waiting for your response.'),
        findsNothing,
      );

      repo.gate!.complete();
      await tester.pumpAndSettle();

      expect(
        find.text('Your answer: Can help. You can change it.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed answer brings the prompt back', (tester) async {
      await openRoomWithTile(tester);
      repo.error = Exception('offline');

      await tester.tap(find.text('Can\'t help'));
      await tester.pumpAndSettle();

      expect(repo.calls, [(batonId: 'baton-1', canHelp: false)]);
      expect(
        find.text('Can you help? We\'re waiting for your response.'),
        findsOneWidget,
      );
      expect(find.textContaining('Your answer:'), findsNothing);
    });
  });
}
