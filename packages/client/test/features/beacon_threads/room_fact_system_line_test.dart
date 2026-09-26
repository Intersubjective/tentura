// tentura-617.33: room system lines for fact edit / unpin (issue #181 plan
// §6). Server emits room messages with semanticMarker 10
// (BeaconRoomSemanticMarker.factEdited) / 11 (factUnpinned), an empty body
// and a system_payload `{factCardId, pinnedBy, factText, revisionSeq?}`;
// `message.authorId` is the actor who edited / unpinned.
//
// RoomMessageTile must render these as centered timeline lines:
// - someone else's fact: "Boris edited Anna's fact" + excerpt of factText;
// - own fact (actor == pinnedBy): "Anna edited a fact";
// - marker 11: unpinned copy naming the actor;
// - edit line with revisionSeq > 1: tappable "What changed" that opens the
//   fact history sheet (FactHistorySheet).
//
// Today markers 10/11 fall through to the generic chat row, so these fail.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_fact_history_entry.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_history_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/enums.dart';

const _kBeaconId = 'b-fact-line';
const _kFactCardId = 'fact-line-1';
const _kAnnaId = 'u-anna';
const _kBorisId = 'u-boris';
const _kViewerId = 'viewer';
/// Opening words of the fact; the excerpt must start with these.
const _kFactOpening = 'Meet at the north gate at nine';

/// Long enough (well over two lines at 400 px) that a real excerpt has to
/// clip it, so the full text can never be what the system line shows.
const _kFactText =
    '$_kFactOpening sharp, bring the spare keys for the storage room, two '
    'flashlights, the printed route map, water for everyone in the group, '
    'and the signed permit from the council office — without the permit '
    'the guards will not let the van through the side entrance at all, '
    'so double-check it is in the folder before leaving home tomorrow.';

const _kSurfaceWidth = 400.0;

const _viewer = Profile(id: _kViewerId, displayName: 'Viewer');
const _anna = Profile(id: _kAnnaId, displayName: 'Anna');
const _boris = Profile(id: _kBorisId, displayName: 'Boris');

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

class _FakeFactCardRepository extends Fake
    implements BeaconFactCardRepository {
  final List<({String beaconId, String factCardId})> revisionCalls = [];

  @override
  Future<BeaconFactHistoryPage> revisions({
    required String beaconId,
    required String factCardId,
    String? before,
  }) async {
    revisionCalls.add((beaconId: beaconId, factCardId: factCardId));
    return (
      entries: <BeaconFactTimelineEntry>[
        BeaconFactHistoryEdited(
          id: 'rev-2',
          factCardId: factCardId,
          seq: 2,
          factText: _kFactText,
          actorId: _kBorisId,
          actorTitle: 'Boris',
          createdAt: DateTime.utc(2026, 1, 2),
        ),
      ],
      nextCursor: null,
    );
  }
}

BeaconParticipant _participant(String userId, String title) =>
    BeaconParticipant(
      id: 'p-$userId',
      beaconId: _kBeaconId,
      userId: userId,
      role: BeaconParticipantRoleBits.helper,
      status: 0,
      roomAccess: RoomAccessBits.admitted,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      userTitle: title,
    );

final _participants = [
  _participant(_kAnnaId, 'Anna'),
  _participant(_kBorisId, 'Boris'),
];

RoomMessage _factSystemMessage({
  required int marker,
  required Profile actor,
  required String pinnedBy,
  int? revisionSeq,
}) => RoomMessage(
  id: 'sys-${actor.id}-$marker',
  beaconId: _kBeaconId,
  authorId: actor.id,
  author: actor,
  body: '',
  createdAt: DateTime.utc(2026, 1, 3),
  semanticMarker: marker,
  systemPayloadJson: jsonEncode({
    'factCardId': _kFactCardId,
    'pinnedBy': pinnedBy,
    'factText': _kFactText,
    'revisionSeq': ?revisionSeq,
  }),
);

Widget _harness(RoomMessage message) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
      BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
      BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
    ],
    child: MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(_kSurfaceWidth, 900)),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: RoomMessageTile(
              message: message,
              myProfile: _viewer,
              onToggleReaction: (_, _) async {},
              participants: _participants,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The single text widget showing the fact excerpt: it starts with the fact's
/// opening words and is visibly an excerpt — either its string is shorter
/// than the full fact, or it is clamped (`maxLines` ≤ 3 + ellipsis).
Finder _excerptFinder() => find.byWidgetPredicate((w) {
  if (w is! Text) return false;
  final shown = w.data ?? w.textSpan?.toPlainText() ?? '';
  return shown.contains(_kFactOpening);
}, description: 'Text containing the fact excerpt');

void _expectExcerpt(WidgetTester tester) {
  final finder = _excerptFinder();
  expect(finder, findsOneWidget);
  final text = tester.widget<Text>(finder);
  final shown = text.data ?? text.textSpan?.toPlainText() ?? '';
  final clipped = shown.length < _kFactText.length;
  final clamped =
      text.maxLines != null &&
      text.maxLines! <= 3 &&
      text.overflow == TextOverflow.ellipsis;
  expect(
    clipped || clamped,
    isTrue,
    reason:
        'fact text must be shown as an excerpt (shortened or clamped to '
        '≤ 3 lines with ellipsis), got maxLines=${text.maxLines} '
        'overflow=${text.overflow} length=${shown.length}',
  );
  // The full-length fact must not be rendered as ordinary chat body text.
  expect(find.text(_kFactText), findsNothing);
}

/// Centered system line: [finder] is horizontally centered in the tile
/// (not a left-aligned chat bubble) and there is no generic chat chrome —
/// no 'System' sender label and no standalone author name header.
void _expectCenteredSystemLine(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final dx = tester.getCenter(finder).dx;
  // Measure against the tile itself: most tests run on the default 800 px
  // test surface (only the MediaQuery reports _kSurfaceWidth).
  final tileCenterDx = tester.getCenter(find.byType(RoomMessageTile)).dx;
  expect(
    (dx - tileCenterDx).abs(),
    lessThan(24),
    reason: 'system line must be centered, center dx=$dx',
  );
  expect(find.text('System'), findsNothing);
  expect(find.text('Boris'), findsNothing);
  expect(find.text('Anna'), findsNothing);
}

void main() {
  late _FakeFactCardRepository repo;

  setUp(() async {
    repo = _FakeFactCardRepository();
    final getIt = GetIt.instance;
    if (getIt.isRegistered<BeaconFactCardRepository>()) {
      await getIt.unregister<BeaconFactCardRepository>();
    }
    getIt.registerSingleton<BeaconFactCardRepository>(repo);
  });

  tearDown(() async {
    final getIt = GetIt.instance;
    if (getIt.isRegistered<BeaconFactCardRepository>()) {
      await getIt.unregister<BeaconFactCardRepository>();
    }
  });

  group('RoomMessageTile fact system lines (tentura-617.33)', () {
    testWidgets(
      "marker 10 by another user on Anna's fact shows "
      "'Boris edited Anna's fact' plus the excerpt",
      (tester) async {
        await tester.pumpWidget(
          _harness(
            _factSystemMessage(
              marker: BeaconRoomSemanticMarker.factEdited,
              actor: _boris,
              pinnedBy: _kAnnaId,
              revisionSeq: 2,
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectCenteredSystemLine(
          tester,
          find.textContaining("Boris edited Anna's fact"),
        );
        _expectExcerpt(tester);
        _expectCenteredSystemLine(tester, _excerptFinder());
        expect(find.textContaining('unpinned'), findsNothing);
      },
    );

    testWidgets("marker 10 on own fact shows 'Anna edited a fact'", (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _factSystemMessage(
            marker: BeaconRoomSemanticMarker.factEdited,
            actor: _anna,
            pinnedBy: _kAnnaId,
            revisionSeq: 2,
          ),
        ),
      );
      await tester.pumpAndSettle();

      _expectCenteredSystemLine(
        tester,
        find.textContaining('Anna edited a fact'),
      );
      expect(find.textContaining("Anna's fact"), findsNothing);
      _expectExcerpt(tester);
      _expectCenteredSystemLine(tester, _excerptFinder());
    });

    testWidgets(
      "marker 11 by another user shows 'Boris unpinned Anna's fact' "
      'plus the excerpt',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            _factSystemMessage(
              marker: BeaconRoomSemanticMarker.factUnpinned,
              actor: _boris,
              pinnedBy: _kAnnaId,
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectCenteredSystemLine(
          tester,
          find.textContaining("Boris unpinned Anna's fact"),
        );
        _expectExcerpt(tester);
        _expectCenteredSystemLine(tester, _excerptFinder());
        expect(find.textContaining('edited'), findsNothing);
        expect(find.textContaining('What changed'), findsNothing);
      },
    );

    testWidgets(
      "marker 11 on own fact shows 'Anna unpinned a fact' plus the excerpt",
      (tester) async {
        await tester.pumpWidget(
          _harness(
            _factSystemMessage(
              marker: BeaconRoomSemanticMarker.factUnpinned,
              actor: _anna,
              pinnedBy: _kAnnaId,
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectCenteredSystemLine(
          tester,
          find.textContaining('Anna unpinned a fact'),
        );
        expect(find.textContaining("Anna's fact"), findsNothing);
        expect(find.textContaining('edited'), findsNothing);
        _expectExcerpt(tester);
        _expectCenteredSystemLine(tester, _excerptFinder());
      },
    );

    // 'What changed' needs a prior revision to diff against: the first
    // revision (seq 1) or a payload without revisionSeq gets no link, but
    // the edit line itself must still render.
    for (final (label, seq) in [('revisionSeq 1', 1), ('no revisionSeq', null)]) {
      testWidgets("edit line with $label shows no 'What changed' link", (
        tester,
      ) async {
        await tester.pumpWidget(
          _harness(
            _factSystemMessage(
              marker: BeaconRoomSemanticMarker.factEdited,
              actor: _boris,
              pinnedBy: _kAnnaId,
              revisionSeq: seq,
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectCenteredSystemLine(
          tester,
          find.textContaining("Boris edited Anna's fact"),
        );
        _expectExcerpt(tester);
        expect(find.textContaining('What changed'), findsNothing);
      });
    }

    testWidgets("'What changed' on an edit line opens the fact history sheet", (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(_kSurfaceWidth, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _harness(
          _factSystemMessage(
            marker: BeaconRoomSemanticMarker.factEdited,
            actor: _boris,
            pinnedBy: _kAnnaId,
            revisionSeq: 3,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final link = find.textContaining('What changed');
      expect(link, findsOneWidget);
      expect(find.byType(FactHistorySheet), findsNothing);

      await tester.tap(link);
      await tester.pumpAndSettle();

      expect(find.byType(FactHistorySheet), findsOneWidget);
      final sheet = tester.widget<FactHistorySheet>(
        find.byType(FactHistorySheet),
      );
      expect(sheet.beaconId, _kBeaconId);
      expect(sheet.factCardId, _kFactCardId);
      expect(sheet.baseRevisionSeq, 3);
      expect(repo.revisionCalls, isNotEmpty);
      expect(repo.revisionCalls.first.factCardId, _kFactCardId);
    });
  });
}
