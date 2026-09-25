import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_provenance_line.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Any compact relative-time token (`3d`, `2h ago`, `5m`) or "Just now".
final _anyTime = RegExp(r'\d+\s*[mhd]\b|just now', caseSensitive: false);

BeaconFactCard _fact({
  required DateTime createdAt,
  int revisionSeq = 1,
  String? lastEditedBy,
  String lastEditedByTitle = '',
  DateTime? lastEditedAt,
  int otherEditorCount = 0,
  bool historyTruncated = false,
}) => BeaconFactCard(
  id: 'f1',
  beaconId: 'b1',
  factText: 'Gate code is 4821',
  visibility: BeaconFactCardVisibilityBits.public,
  pinnedBy: 'Uanna',
  pinnedByTitle: 'Anna',
  createdAt: createdAt,
  status: revisionSeq > 1 || historyTruncated
      ? BeaconFactCardStatusBits.corrected
      : BeaconFactCardStatusBits.active,
  revisionSeq: revisionSeq,
  lastEditedBy: lastEditedBy,
  lastEditedByTitle: lastEditedByTitle,
  lastEditedAt: lastEditedAt,
  otherEditorCount: otherEditorCount,
  historyTruncated: historyTruncated,
);

Widget _harness(BeaconFactCard fact, {bool compact = false}) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: const Locale('en'),
  home: TenturaResponsiveScope(
    child: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: FactProvenanceLine(fact: fact, compact: compact),
        ),
      ),
    ),
  ),
);

String _lineText(WidgetTester tester) => tester
    .widgetList<RichText>(
      find.descendant(
        of: find.byType(FactProvenanceLine),
        matching: find.byType(RichText),
      ),
    )
    .map((r) => r.text.toPlainText())
    .join(' ');

/// Walks [span] recursively, resolving each text run's effective color
/// through parent-style inheritance.
void _collectLeaves(
  InlineSpan span,
  Color? inherited,
  List<(String, Color?)> out,
) {
  final color = span.style?.color ?? inherited;
  if (span is TextSpan) {
    final text = span.text;
    if (text != null && text.trim().isNotEmpty) out.add((text, color));
    for (final child in span.children ?? const <InlineSpan>[]) {
      _collectLeaves(child, color, out);
    }
  }
}

void main() {
  final now = DateTime.now();
  final threeDaysAgo = now.subtract(const Duration(days: 3));
  final twoHoursAgo = now.subtract(const Duration(hours: 2));

  testWidgets('never edited: pinner name and pin time', (tester) async {
    await tester.pumpWidget(_harness(_fact(createdAt: threeDaysAgo)));
    await tester.pumpAndSettle();

    final text = _lineText(tester);
    expect(text, contains('Anna'));
    expect(text, contains('·'));
    expect(text, contains('3d'));
    expect(text.toLowerCase(), isNot(contains('edited')));
  });

  testWidgets('uses TenturaText.status in onSurfaceVariant', (tester) async {
    await tester.pumpWidget(_harness(_fact(createdAt: threeDaysAgo)));
    await tester.pumpAndSettle();

    final scheme = Theme.of(
      tester.element(find.byType(FactProvenanceLine)),
    ).colorScheme;
    final rendered = tester.widgetList<RichText>(
      find.descendant(
        of: find.byType(FactProvenanceLine),
        matching: find.byType(RichText),
      ),
    );
    final leaves = <(String, Color?)>[];
    for (final r in rendered) {
      _collectLeaves(r.text, null, leaves);
    }
    // Every visible run of the line (names, middots, times, "edited")
    // resolves to onSurfaceVariant after style inheritance.
    expect(leaves, isNotEmpty);
    for (final (text, color) in leaves) {
      expect(color, scheme.onSurfaceVariant, reason: 'span "$text"');
    }
  });

  testWidgets('edited by the pinner: "edited" plus edit time', (tester) async {
    await tester.pumpWidget(
      _harness(
        _fact(
          createdAt: threeDaysAgo,
          revisionSeq: 2,
          lastEditedBy: 'Uanna',
          lastEditedByTitle: 'Anna',
          lastEditedAt: twoHoursAgo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final text = _lineText(tester);
    expect(text, contains('Anna'));
    expect(text.toLowerCase(), contains('edited'));
    expect(text, contains('2h'));
  });

  testWidgets('historyTruncated with no lastEditedAt: "edited", no time', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        _fact(
          createdAt: threeDaysAgo,
          historyTruncated: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final text = _lineText(tester);
    expect(text.toLowerCase(), contains('edited'));
    // The pin time (3d) may still show; no edit time may be invented
    // (e.g. a null lastEditedAt rendered as "Just now").
    final withoutPinTime = text.replaceAll(RegExp('3d( ago)?'), '');
    expect(withoutPinTime, isNot(matches(_anyTime)));
    final afterEdited = text.substring(
      text.toLowerCase().indexOf('edited'),
    );
    expect(afterEdited, isNot(matches(_anyTime)));
  });

  testWidgets('edited by another member: shows the editor name', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        _fact(
          createdAt: threeDaysAgo,
          revisionSeq: 2,
          lastEditedBy: 'Uboris',
          lastEditedByTitle: 'Boris',
          lastEditedAt: twoHoursAgo,
          otherEditorCount: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final text = _lineText(tester);
    expect(text, contains('Boris'));
    expect(text.toLowerCase(), contains('edited'));
    expect(text, isNot(contains('+')));
  });

  testWidgets('otherEditorCount 3: "Boris +2"', (tester) async {
    await tester.pumpWidget(
      _harness(
        _fact(
          createdAt: threeDaysAgo,
          revisionSeq: 5,
          lastEditedBy: 'Uboris',
          lastEditedByTitle: 'Boris',
          lastEditedAt: twoHoursAgo,
          otherEditorCount: 3,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_lineText(tester), contains('Boris +2'));
  });

  testWidgets('compact never-edited omits the time', (tester) async {
    await tester.pumpWidget(
      _harness(_fact(createdAt: threeDaysAgo), compact: true),
    );
    await tester.pumpAndSettle();

    final text = _lineText(tester);
    expect(text, contains('Anna'));
    expect(text, isNot(matches(_anyTime)));
  });

  testWidgets('compact edited omits the time but keeps "edited"', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        _fact(
          createdAt: threeDaysAgo,
          revisionSeq: 2,
          lastEditedBy: 'Uboris',
          lastEditedByTitle: 'Boris',
          lastEditedAt: twoHoursAgo,
          otherEditorCount: 1,
        ),
        compact: true,
      ),
    );
    await tester.pumpAndSettle();

    final text = _lineText(tester);
    expect(text.toLowerCase(), contains('edited'));
    expect(text, isNot(matches(_anyTime)));
  });
}
