// A21: the (i) diagram of the helper screen. Contract:
//  - `ShareFlowDiagram(memberCount: int, avatars: List<Profile>)` in
//    `features/closure/ui/widget/share_flow_diagram.dart` — its
//    constructor(s) take ONLY these two inputs (plus `key`), never a share,
//    percent or author decision (U20). `const`-ness is not pinned.
//  - one `TenturaAvatar` per entry of `avatars`; the flows are drawn by a
//    `CustomPaint` painter with `drawLine` / `drawPath` (not by avatars) and
//    the painter draws no text (labels are `Text` widgets, «пример» among
//    them); the picture itself is hidden from semantics.
//  - the example flows are EQUAL (one paint: same colour, style, width) and
//    GREY (near-zero chroma); the painted output depends only on the member
//    count and the number of avatars, never on who the avatars are.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/closure/ui/widget/share_flow_diagram.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _file = 'lib/features/closure/ui/widget/share_flow_diagram.dart';

// Digit-free ids and names, so any digit the diagram prints is its own.
String _letters(int i) => String.fromCharCodes([
  97 + i ~/ 26,
  97 + i % 26,
]);

List<Profile> _profiles(int n, {String prefix = 'u'}) => [
  for (var i = 0; i < n; i++)
    Profile(id: '$prefix${_letters(i)}', displayName: '$prefix ${_letters(i)}'),
];

Future<void> _pump(
  WidgetTester tester, {
  required int memberCount,
  required List<Profile> avatars,
}) async {
  tester.view
    ..physicalSize = const Size(360, 1200)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      locale: const Locale('ru'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ShareFlowDiagram(memberCount: memberCount, avatars: avatars),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Iterable<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(ShareFlowDiagram),
        matching: find.byType(Text),
      ),
    )
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '');

bool _insideAvatar(Element e) {
  var inside = false;
  e.visitAncestorElements((a) {
    if (a.widget is TenturaAvatar) inside = true;
    return !inside;
  });
  return inside;
}

/// Everything the diagram's own painters (not the avatars') draw.
List<RecordedInvocation> _painted(WidgetTester tester) {
  final canvas = TestRecordingCanvas();
  final elements = find
      .descendant(
        of: find.byType(ShareFlowDiagram),
        matching: find.byType(CustomPaint),
      )
      .evaluate()
      .where((e) => !_insideAvatar(e));
  for (final e in elements) {
    final cp = e.widget as CustomPaint;
    final size = (e.renderObject! as RenderBox).size;
    cp.painter?.paint(canvas, size);
    cp.foregroundPainter?.paint(canvas, size);
  }
  return canvas.invocations;
}

bool _isFlow(RecordedInvocation r) =>
    r.invocation.memberName == #drawLine ||
    r.invocation.memberName == #drawPath;

Paint _paintOf(RecordedInvocation r) =>
    r.invocation.positionalArguments.whereType<Paint>().single;

String _paintKey(Paint p) =>
    '${p.color.toARGB32()}|${p.style}|${p.strokeWidth}';

/// Geometry + paint of every draw call, independent of object identity.
List<String> _signature(List<RecordedInvocation> ops) => [
  for (final r in ops)
    [
      r.invocation.memberName,
      for (final a in r.invocation.positionalArguments)
        switch (a) {
          final Paint p => _paintKey(p),
          final ui.Path p => p.getBounds().toString(),
          final Offset o => o.toString(),
          final Rect rect => rect.toString(),
          _ => a.runtimeType.toString(),
        },
    ].join(','),
];

void main() {
  for (final n in [3, 5, 12]) {
    testWidgets('$n members: an avatar each, «пример», no layout error', (
      tester,
    ) async {
      final avatars = _profiles(n + 1); // author + members
      await _pump(tester, memberCount: n, avatars: avatars);
      expect(
        find.descendant(
          of: find.byType(ShareFlowDiagram),
          matching: find.byType(TenturaAvatar),
        ),
        findsNWidgets(avatars.length),
      );
      expect(find.text('пример'), findsWidgets);
      expect(_painted(tester).where(_isFlow), isNotEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('never prints a percent, decimal or share', (tester) async {
    await _pump(tester, memberCount: 7, avatars: _profiles(8));
    for (final t in _texts(tester)) {
      expect(
        t,
        isNot(
          matches(RegExp(r'%|\d[.,]\d|процент|percent', caseSensitive: false)),
        ),
        reason: t,
      );
    }
  });

  testWidgets('the painter draws no text, so no number hides in the picture', (
    tester,
  ) async {
    await _pump(tester, memberCount: 7, avatars: _profiles(8));
    final names = _painted(tester).map((r) => r.invocation.memberName).toSet();
    expect(names, isNotEmpty);
    expect(names, isNot(contains(#drawParagraph)));
  });

  for (final n in [3, 5, 12]) {
    testWidgets('$n members: example flows are equal and grey', (tester) async {
      await _pump(tester, memberCount: n, avatars: _profiles(n + 1));
      final flows = _painted(tester).where(_isFlow).toList();
      final groups = <String, List<Paint>>{};
      for (final r in flows) {
        final p = _paintOf(r);
        groups.putIfAbsent(_paintKey(p), () => []).add(p);
      }
      expect(flows, isNotEmpty);
      final biggest = groups.values.reduce(
        (a, b) => a.length >= b.length ? a : b,
      );
      // One flow per colleague at least, all drawn with one and the same
      // paint: equal colour, style and width.
      expect(biggest.length, greaterThanOrEqualTo(n - 1));
      final c = biggest.first.color;
      final channels = [c.r, c.g, c.b];
      final spread =
          channels.reduce((a, b) => a > b ? a : b) -
          channels.reduce((a, b) => a < b ? a : b);
      expect(spread, lessThanOrEqualTo(0.1), reason: 'grey, got $c');
      expect(c.a, greaterThan(0));
      if (biggest.first.style == PaintingStyle.stroke) {
        expect(biggest.first.strokeWidth, greaterThan(0));
      }
    });
  }

  testWidgets('painted output ignores who the avatars are', (tester) async {
    await _pump(tester, memberCount: 5, avatars: _profiles(6));
    final a = _signature(_painted(tester));
    await _pump(
      tester,
      memberCount: 5,
      avatars: _profiles(6, prefix: 'other'),
    );
    final b = _signature(_painted(tester));
    expect(a, isNotEmpty);
    expect(b, a);
  });

  testWidgets('the picture is excluded from semantics', (tester) async {
    await _pump(tester, memberCount: 4, avatars: _profiles(5));
    expect(
      find.descendant(
        of: find.byType(ShareFlowDiagram),
        matching: find.byType(ExcludeSemantics),
      ),
      findsWidgets,
    );
  });

  test('every constructor takes only memberCount, avatars and key', () {
    final src = File(_file).readAsStringSync();
    expect(src, contains('class ShareFlowDiagram '));
    final starts = RegExp(
      r'^[ \t]*(?:const[ \t]+|factory[ \t]+)?ShareFlowDiagram(?:\.\w+)?[ \t]*\(',
      multiLine: true,
    ).allMatches(src).toList();
    expect(starts, isNotEmpty, reason: 'a constructor is declared');
    final names = <String>{};
    for (final m in starts) {
      var depth = 1;
      var i = m.end;
      while (depth > 0 && i < src.length) {
        final ch = src[i++];
        if (ch == '(') depth++;
        if (ch == ')') depth--;
      }
      final params = src.substring(m.end, i - 1);
      names.addAll(
        params
            .replaceAll(RegExp(r'[{}\[\]]'), '')
            .split(',')
            .map((s) => s.split('=').first.trim())
            .where((s) => s.isNotEmpty)
            .map((s) => s.split(RegExp(r'[\s.]')).last),
      );
    }
    expect(names, containsAll(['memberCount', 'avatars']));
    expect(names.difference({'memberCount', 'avatars', 'key'}), isEmpty);
  });
}
