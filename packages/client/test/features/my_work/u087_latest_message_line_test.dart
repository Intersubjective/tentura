// U087 — each Request card on the Requests list shows one "latest" line: who
// wrote last, what, how long ago, and how many messages are unread
// ("Nina: Parking sorted? · 1m · 2 new"). Before, the card showed only a small
// blue dot, so the author had to open every Request to see what changed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_latest_message_line.dart';
import 'package:tentura/ui/l10n/l10n.dart';

final _now = DateTime.utc(2026, 10, 14, 12);

MyWorkCardViewModel _vm({
  String text = 'Parking sorted? I also bring blankets.',
  String authorId = 'u-nina',
  String authorName = 'Nina',
  int unread = 2,
}) => MyWorkCardViewModel(
  beaconId: 'B1',
  role: MyWorkCardRole.authored,
  kind: MyWorkCardKind.authoredActive,
  beacon: Beacon.empty.copyWith(id: 'B1', title: 'Moving day'),
  roomLatestMessageText: text,
  roomLatestMessageAuthorId: authorId,
  roomLatestMessageAuthorName: authorName,
  roomLatestMessageAt: _now.subtract(const Duration(minutes: 1)),
  roomUnreadCount: unread,
);

Widget _harness(MyWorkCardViewModel vm, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: MyWorkLatestMessageLine(
            vm: vm,
            currentUserId: 'u-me',
            now: _now.toLocal(),
          ),
        ),
      ),
    );

void main() {
  testWidgets('shows who wrote last, what, when and the unread count', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_vm()));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Nina: Parking sorted? I also bring blankets.'),
      findsOneWidget,
    );
    expect(find.textContaining('1m'), findsOneWidget);
    expect(find.text('2 new'), findsOneWidget);
  });

  testWidgets('own message reads "You", no count when nothing is unread', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(_vm(authorId: 'u-me', authorName: 'Tab QA', unread: 0)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('You: Parking sorted?'), findsOneWidget);
    expect(find.textContaining('new'), findsNothing);
  });

  testWidgets('nothing at all without a message', (tester) async {
    await tester.pumpWidget(_harness(_vm(text: '')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nina'), findsNothing);
  });

  testWidgets('ru', (tester) async {
    await tester.pumpWidget(_harness(_vm(), locale: const Locale('ru')));
    await tester.pumpAndSettle();
    expect(find.text('2 новых'), findsOneWidget);
  });
}
