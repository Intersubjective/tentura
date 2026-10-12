@Timeout(Duration(minutes: 2))
library;

// Request plan lines in the discussion (#220 §5.10): system_message_kind 5
// with markers 13 (revised), 14 (ticks), 15 («Не успеваю»), 16 (copied).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_room_line.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_plan_line.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../beacon_plan/beacon_plan_test_support.dart';

const _kBeaconId = 'B1';
const _viewer = Profile(id: 'viewer', displayName: 'Viewer');
const _olga = Profile(id: 'u-olga', displayName: 'Olga');

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
  _participant('u-olga', 'Olga'),
  _participant('u-ivan', 'Ivan'),
  _participant('u-maria', 'Maria'),
];

RoomMessage _planMessage(int marker, Object? payload) => RoomMessage(
  id: 'plan-$marker',
  beaconId: _kBeaconId,
  authorId: _olga.id,
  author: _olga,
  body: '',
  createdAt: DateTime.utc(2026, 10, 12, 10, 10),
  semanticMarker: marker,
  systemMessageKind: BeaconRoomSystemMessageKind.plan,
  systemPayloadJson: payload is String ? payload : jsonEncode(payload),
);

Widget _harness(Widget child, {PlanCubit? planCubit}) {
  final body = planCubit == null
      ? child
      : BlocProvider<PlanCubit>.value(value: planCubit, child: child);
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
      home: TenturaResponsiveScope(child: Scaffold(body: body)),
    ),
  );
}

Widget _tile(RoomMessage message) => RoomMessageTile(
  message: message,
  myProfile: _viewer,
  onToggleReaction: (_, _) async {},
  participants: _participants,
);

Map<String, Object?> _change(
  String op,
  String title, [
  Map<String, Object?>? extra,
]) => {
  'op': op,
  'stepId': 'PS-$title',
  'title': title,
  ...?extra,
};

TextStyle? _styleOf(WidgetTester tester, String text) {
  final rich = tester.widget<RichText>(
    find
        .byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains(text),
        )
        .first,
  );
  TextStyle? found;
  rich.text.visitChildren((s) {
    if (s is TextSpan && (s.text ?? '').contains(text)) {
      found = s.style;
      return false;
    }
    return true;
  });
  return found;
}

void main() {
  testWidgets('13: actor, up to three changes, «N more», comment, History', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        _tile(
          _planMessage(BeaconRoomSemanticMarker.planRevised, {
            'actorId': 'u-olga',
            'revisionSeq': 5,
            'revisionKind': 1,
            'changeCount': 4,
            'changes': [
              _change('retitled', 'Build frame', {'fromTitle': 'Frame'}),
              _change('added', 'Water beds', {'toAssigneeId': 'u-olga'}),
              _change('removed', 'Buy paint'),
              _change('moved', 'Lunch'),
            ],
            'comment': 'rain',
          }),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.text('Olga changed the plan', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('~ Frame → Build frame', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('+ Water beds (Olga)', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('– Buy paint', findRichText: true), findsOneWidget);
    expect(find.textContaining('Lunch', findRichText: true), findsNothing);
    expect(find.text('1 more', findRichText: true), findsOneWidget);
    expect(find.text('«rain»', findRichText: true), findsOneWidget);
    expect(find.byKey(RoomPlanLine.historyKey), findsOneWidget);
    // Not a chat bubble.
    expect(find.text('System'), findsNothing);
  });

  testWidgets('13: History opens the history at that revision', (
    tester,
  ) async {
    final opened = <int>[];
    await tester.pumpWidget(
      _harness(
        RoomPlanLine(
          message: _planMessage(BeaconRoomSemanticMarker.planRevised, {
            'revisionSeq': 7,
            'revisionKind': 2,
            'restoredFromSeq': 3,
            'changeCount': 0,
            'changes': <Object>[],
            'comment': '',
          }),
          actorName: 'Olga',
          nameOf: (id) => id ?? '',
          onOpenHistory: (_, seq) => opened.add(seq),
        ),
      ),
    );
    expect(
      find.text('Olga restored version 3', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.byKey(RoomPlanLine.historyKey));
    expect(opened, [7]);
  });

  testWidgets('14: own tick and a tick for someone else', (tester) async {
    await tester.pumpWidget(
      _harness(
        Column(
          children: [
            _tile(
              _planMessage(BeaconRoomSemanticMarker.planStepsDone, {
                'ticks': [
                  {
                    'stepId': 'PS1',
                    'title': 'Bring boards',
                    'assigneeId': 'u-ivan',
                    'actorId': 'u-ivan',
                    'at': '2026-10-12T10:31:00.000Z',
                  },
                ],
              }),
            ),
            _tile(
              _planMessage(BeaconRoomSemanticMarker.planStepsDone, {
                'ticks': [
                  {
                    'stepId': 'PS2',
                    'title': 'Open storage',
                    'assigneeId': 'u-ivan',
                    'actorId': 'u-olga',
                    'at': '2026-10-12T10:31:00.000Z',
                  },
                ],
              }),
            ),
          ],
        ),
      ),
    );
    expect(
      find.text('✓ Ivan: Bring boards', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('✓ Olga for Ivan: Open storage', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('14: coalesced ticks; an undone entry is struck through', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        _tile(
          _planMessage(BeaconRoomSemanticMarker.planStepsDone, {
            'ticks': [
              {
                'stepId': 'PS1',
                'title': 'Bring boards',
                'assigneeId': 'u-ivan',
                'actorId': 'u-ivan',
                'at': '2026-10-12T10:31:00.000Z',
              },
              {
                'stepId': 'PS2',
                'title': 'Buy screws',
                'assigneeId': 'u-maria',
                'actorId': 'u-maria',
                'at': '2026-10-12T10:32:00.000Z',
                'undoneAt': '2026-10-12T10:40:00.000Z',
                'undoneById': 'u-maria',
              },
            ],
          }),
        ),
      ),
    );
    expect(find.text('✓ 2 steps done', findRichText: true), findsOneWidget);
    expect(find.textContaining('unmarked', findRichText: true), findsOneWidget);
    expect(
      _styleOf(tester, '✓ Maria: Buy screws')?.decoration,
      TextDecoration.lineThrough,
    );
    expect(
      _styleOf(tester, '✓ Ivan: Bring boards')?.decoration,
      isNot(TextDecoration.lineThrough),
    );
  });

  testWidgets('15: moved by +Δ and handed to someone', (tester) async {
    await tester.pumpWidget(
      _harness(
        Column(
          children: [
            _tile(
              _planMessage(BeaconRoomSemanticMarker.planCantMake, {
                'actorId': 'u-ivan',
                'stepId': 'PS3',
                'title': 'Build frame',
                'option': 'reschedule',
                'revisionSeq': 6,
                'fromStartAt': '2026-10-12T11:00:00.000Z',
                'toStartAt': '2026-10-12T12:00:00.000Z',
              }),
            ),
            _tile(
              _planMessage(BeaconRoomSemanticMarker.planCantMake, {
                'actorId': 'u-ivan',
                'stepId': 'PS4',
                'title': 'Lunch',
                'option': 'handover',
                'revisionSeq': 7,
                'toUserId': 'u-maria',
              }),
            ),
          ],
        ),
      ),
    );
    expect(
      find.text(
        "⏰ Ivan can't make it: Build frame → moved by +1h 0m",
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        "⏰ Ivan can't make it: Lunch → handed to Maria",
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('16: source title only when the viewer can read it', (
    tester,
  ) async {
    final message = _planMessage(BeaconRoomSemanticMarker.planCopied, {
      'sourceBeaconId': 'SRC',
      'stepCount': 9,
      'revisionSeq': 1,
    });
    await tester.pumpWidget(_harness(_tile(message)));
    expect(
      find.text('Plan copied from another request', findRichText: true),
      findsOneWidget,
    );

    final repo = FakeBeaconPlanRepository(
      const BeaconPlan(
        beaconId: _kBeaconId,
        copiedFromBeaconId: 'SRC',
        copiedFromTitle: 'Garden beds',
      ),
    );
    final cubit = PlanCubit(
      beaconId: _kBeaconId,
      viewerId: _viewer.id,
      planCase: planCaseFor(repo),
    );
    await tester.runAsync(cubit.load);
    await tester.pumpWidget(_harness(_tile(message), planCubit: cubit));
    await tester.pump();
    expect(
      find.text('Plan copied from «Garden beds»', findRichText: true),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(cubit.close);
  });

  testWidgets('a broken payload falls back to «Plan changed»', (tester) async {
    await tester.pumpWidget(
      _harness(
        _tile(_planMessage(BeaconRoomSemanticMarker.planRevised, '{oops')),
      ),
    );
    expect(find.byKey(RoomPlanLine.fallbackKey), findsOneWidget);
    expect(find.text('Plan changed', findRichText: true), findsOneWidget);
  });

  test('payload parsing is lenient', () {
    expect(
      PlanRoomLine.tryParse(
        marker: BeaconRoomSemanticMarker.planStepsDone,
        payloadJson: jsonEncode({'ticks': <Object>[]}),
      ),
      isNull,
    );
    final line = PlanRoomLine.tryParse(
      marker: BeaconRoomSemanticMarker.planCantMake,
      payloadJson: jsonEncode({
        'option': 'reschedule',
        'title': 'X',
        'fromEndAt': '2026-10-12T11:00:00.000Z',
        'toEndAt': '2026-10-12T10:30:00.000Z',
      }),
    );
    expect(line, isA<PlanCantMakeLine>());
    expect((line! as PlanCantMakeLine).shift, const Duration(minutes: -30));
  });
}
