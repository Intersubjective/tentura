// Issue #667: a Post whose only message is the root showed that text twice in
// the Posts list (the root excerpt line and the last-message line). The row
// names it once and keeps the age; a later reply still shows under the root.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/ui/widget/post_conversation_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';

const _root = 'Who wants to help me move a sofa on Sunday? Pizza included';
const _reply = 'I can, what time?';

void main() {
  final now = DateTime.utc(2030, 1, 1, 12);
  final l10n = lookupL10n(const Locale('en'));

  Future<void> pumpRow(
    WidgetTester tester, {
    String? lastMessage,
    bool lastMessageIsRoot = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: TenturaResponsiveScope(
            child: PostConversationRow(
              post: PostSummary(
                id: 'P1',
                authorId: 'U1',
                authorName: 'Theo',
                rootExcerpt: _root,
                lastMessageExcerpt: lastMessage,
                lastMessageIsRoot: lastMessageIsRoot,
                lastActivityAt: now.subtract(const Duration(minutes: 5)),
              ),
              now: now,
              onOpen: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() => RelativeTimestampTicker.debugClock = () => now);
  tearDown(() => RelativeTimestampTicker.debugClock = null);

  /// The row's own Semantics label (what a screen reader reads for it).
  String rowLabel(WidgetTester tester) => tester
      .widget<Semantics>(
        find.descendant(
          of: find.byType(PostConversationRow),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                (w.properties.label?.contains(_root) ?? false),
          ),
        ),
      )
      .properties
      .label!;

  Finder age() => find.text(l10n.relativeTimeCompactMinutes(5));

  group('#667 Posts list row', () {
    testWidgets('a root-only Post shows its text once and keeps the age', (
      tester,
    ) async {
      await pumpRow(tester, lastMessage: _root, lastMessageIsRoot: true);

      expect(find.text(_root), findsOneWidget);
      expect(age(), findsOneWidget);
      expect(
        RegExp(RegExp.escape(_root)).allMatches(rowLabel(tester)).length,
        1,
      );
    });

    testWidgets('a root with a different excerpt is hidden by identity', (
      tester,
    ) async {
      await pumpRow(tester, lastMessage: _reply, lastMessageIsRoot: true);

      expect(find.text(_root), findsOneWidget);
      expect(find.text(_reply), findsNothing);
      expect(age(), findsOneWidget);
    });

    testWidgets('a reply equal to the root is still shown', (tester) async {
      await pumpRow(tester, lastMessage: _root);

      expect(find.text(_root), findsNWidgets(2));
      expect(age(), findsOneWidget);
      expect(
        RegExp(RegExp.escape(_root)).allMatches(rowLabel(tester)).length,
        2,
      );
    });

    testWidgets('a Post with a reply shows the root and the reply', (
      tester,
    ) async {
      await pumpRow(tester, lastMessage: _reply);

      expect(find.text(_root), findsOneWidget);
      expect(find.text(_reply), findsOneWidget);
      expect(age(), findsOneWidget);
      expect(rowLabel(tester), contains(_reply));
      expect(
        rowLabel(tester),
        contains(l10n.postConversationAddressed('Theo')),
      );
    });
  });
}
