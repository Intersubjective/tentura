import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/lazy_write_timeout_notice.dart';

// The overdue-acknowledgement notice is a non-blocking design-system snackbar
// shown whenever the notice stream emits. It is chrome: it never interrupts a
// drag under it. Pinned API shape: `LazyWriteTimeoutNotice({notices, child})`
// and the value type `LazyWriteNotice`.

Map<String, dynamic> _en = {};

Future<void> _pump(
  WidgetTester tester,
  Stream<LazyWriteNotice> notices,
  Widget child,
) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('en'),
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: LazyWriteTimeoutNotice(notices: notices, child: child),
    ),
  ),
);

void main() {
  setUpAll(() {
    _en =
        jsonDecode(File('l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
  });

  testWidgets('a notice shows the overdue snackbar copy', (tester) async {
    final notices = StreamController<LazyWriteNotice>.broadcast();
    addTearDown(notices.close);
    await _pump(tester, notices.stream, const SizedBox.expand());
    expect(find.byType(SnackBar), findsNothing);

    notices.add(const LazyWriteNotice());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(_en['lazyWriteAckOverdue'] as String), findsOneWidget);
  });

  test(
    'the overdue copy exists in both locales with the same placeholders',
    () {
      final ru =
          jsonDecode(File('l10n/app_ru.arb').readAsStringSync())
              as Map<String, dynamic>;
      final placeholders = RegExp(r'\{(\w+)\}');
      Set<String> names(String text) =>
          placeholders.allMatches(text).map((m) => m.group(1)!).toSet();
      final en = _en['lazyWriteAckOverdue'] as String?;
      final ruText = ru['lazyWriteAckOverdue'] as String?;

      expect(en, isNotNull);
      expect(en, isNotEmpty);
      expect(ruText, isNotNull);
      expect(ruText, isNotEmpty);
      expect(names(ruText!), names(en!));
    },
  );

  testWidgets('the notice shows the Russian copy under the Russian locale', (
    tester,
  ) async {
    final notices = StreamController<LazyWriteNotice>.broadcast();
    addTearDown(notices.close);
    final ru =
        jsonDecode(File('l10n/app_ru.arb').readAsStringSync())
            as Map<String, dynamic>;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: LazyWriteTimeoutNotice(
            notices: notices.stream,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    notices.add(const LazyWriteNotice());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(ru['lazyWriteAckOverdue'] as String), findsOneWidget);
  });

  testWidgets('a notice during a drag leaves the drag uninterrupted', (
    tester,
  ) async {
    final notices = StreamController<LazyWriteNotice>.broadcast();
    addTearDown(notices.close);
    var moved = Offset.zero;
    var started = 0;
    var ended = 0;
    var cancelled = 0;
    await _pump(
      tester,
      notices.stream,
      GestureDetector(
        key: const Key('node'),
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => started++,
        onPanUpdate: (d) => moved += d.delta,
        onPanEnd: (_) => ended++,
        onPanCancel: () => cancelled++,
        child: const SizedBox.expand(),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('node'))),
    );
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    final beforeNotice = moved;

    notices.add(const LazyWriteNotice());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(moved, beforeNotice, reason: 'the notice moves nothing');

    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(started, 1);
    expect(cancelled, 0);
    expect(ended, 1);
    expect(moved.dx, closeTo(30, 1));
    expect(moved.dy, closeTo(40, 1));
  });
}
