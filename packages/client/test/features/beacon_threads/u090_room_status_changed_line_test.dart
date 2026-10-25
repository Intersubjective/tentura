// U090: a status change posts a `statusChanged` system line (kind 7) with
// payload `{version: 1, fromStatus, toStatus, reason}` (smallint statuses).
// The room must show who changed the status and from what to what, as a
// centered system line, not an empty chat bubble.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _viewer = Profile(id: 'viewer', displayName: 'Viewer');
const _author = Profile(id: 'u-author', displayName: 'Tab QA');

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

// Smallint statuses: 0 open, 5 reviewOpen (Final check), 6 closed,
// 8 enoughHelp.
RoomMessage _statusLine({
  required int from,
  required int to,
  String reason = 'enoughHelp',
  // No author on the line: a system change or a deleted account.
  bool authorless = false,
  Profile author = _author,
}) => RoomMessage(
  id: 'R-status',
  beaconId: 'B1',
  authorId: authorless ? '' : author.id,
  author: authorless ? const Profile() : author,
  body: '',
  createdAt: DateTime.utc(2026, 10, 14, 9),
  systemMessageKind: BeaconRoomSystemMessageKind.statusChanged,
  systemPayloadJson:
      '{"version":1,"fromStatus":$from,"toStatus":$to,"reason":"$reason"}',
);

Widget _harness(RoomMessage message, {Locale locale = const Locale('en')}) =>
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
      ],
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: locale,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 900)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: SingleChildScrollView(
                child: RoomMessageTile(
                  message: message,
                  myProfile: _viewer,
                  onToggleReaction: (_, _) async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('shows who changed the status, from and to', (tester) async {
    await tester.pumpWidget(_harness(_statusLine(from: 0, to: 8)));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Tab QA changed the status: Open → Enough help',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('an automatic change has no actor', (tester) async {
    await tester.pumpWidget(
      _harness(
        _statusLine(from: 5, to: 6, reason: 'closureExpired', authorless: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Status changed: Final check → Closed',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('a change by a since-deleted account names a former member', (
    tester,
  ) async {
    // author_id is ON DELETE SET NULL: the line loses its actor, but the
    // reason says a person made it, so it must not read as automatic.
    await tester.pumpWidget(
      _harness(_statusLine(from: 1, to: 3, authorless: true)),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'A former member changed the status:',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Status changed:', findRichText: true),
      findsNothing,
    );

    await tester.pumpWidget(
      _harness(
        _statusLine(from: 1, to: 3, authorless: true),
        locale: const Locale('ru'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Бывший участник изменил статус:',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('an unreadable payload renders nothing', (tester) async {
    await tester.pumpWidget(
      _harness(
        RoomMessage(
          id: 'R-bad',
          beaconId: 'B1',
          authorId: _author.id,
          author: _author,
          body: '',
          createdAt: DateTime.utc(2026, 10, 14, 9),
          systemMessageKind: BeaconRoomSystemMessageKind.statusChanged,
          systemPayloadJson: '{"version":2}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('status', findRichText: true), findsNothing);
    expect(find.textContaining('Tab QA', findRichText: true), findsNothing);
  });

  testWidgets('is localized (ru)', (tester) async {
    await tester.pumpWidget(
      _harness(_statusLine(from: 0, to: 5), locale: const Locale('ru')),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Tab QA изменил(а) статус', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('own change reads «Вы изменили» in ru, "You changed" in en', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        _statusLine(from: 0, to: 5, author: _viewer),
        locale: const Locale('ru'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Вы изменили статус', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('изменил(а)', findRichText: true), findsNothing);

    await tester.pumpWidget(
      _harness(_statusLine(from: 0, to: 5, author: _viewer)),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('You changed the status', findRichText: true),
      findsOneWidget,
    );
  });
  testWidgets('the line is announced once to a screen reader', (tester) async {
    // #702: the Semantics label and the Text both carried the line, so the
    // merged node read it twice.
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_harness(_statusLine(from: 0, to: 8)));
    await tester.pumpAndSettle();

    const line = 'Tab QA changed the status: Open → Enough help';
    final node = tester.getSemantics(
      find.textContaining(line, findRichText: true),
    );
    expect(node.label, contains(line));
    expect(line.allMatches(node.label).length, 1);
    handle.dispose();
  });
}
