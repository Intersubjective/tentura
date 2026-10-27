// #723: the composer's Emoji button sat inside a second «button» node, the
// wrapper that carries its e2e identifier, so the accessibility tree showed
// `button "Emoji" > button "Emoji"` (QA 7.56.5, Request and Post chats). One
// node now carries the name, the tap and the identifier, as Send and Paste do.

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/emoji/ui/widget/emoji_picker_button.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/semantics_identifier.dart';

Future<void> _pumpButton(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  bool enabled = true,
}) async {
  const size = Size(1400, 720);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: EmojiPickerButton(
                controller: TextEditingController(),
                enabled: enabled,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

List<SemanticsNode> _nodes(bool Function(SemanticsNode node) test) =>
    find.semantics.byPredicate(test).evaluate().toList();

bool _isButton(SemanticsNode node) =>
    node.getSemanticsData().flagsCollection.isButton;

List<SemanticsNode> _buttonsInside(SemanticsNode node) {
  final out = <SemanticsNode>[];
  bool visit(SemanticsNode child) {
    if (_isButton(child)) out.add(child);
    child.visitChildren(visit);
    return true;
  }

  node.visitChildren(visit);
  return out;
}

SemanticsNode _emojiNode() {
  final withId = _nodes(
    (n) => n.getSemanticsData().identifier == TestIds.roomEmojiButton,
  );
  expect(withId, hasLength(1));
  return withId.single;
}

void _expectOneEmojiNode(String name) {
  final node = _emojiNode();
  expect(
    node,
    allOf(
      isSemantics(label: name, isButton: true, hasTapAction: true),
      hasSemanticsIdentifier(TestIds.roomEmojiButton),
    ),
  );
  expect(_buttonsInside(node), isEmpty, reason: 'a button inside $name');
  final named = _nodes((n) {
    final d = n.getSemanticsData();
    return _isButton(n) && (d.label == name || d.tooltip == name);
  });
  expect(named, hasLength(1), reason: 'buttons named $name');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Emoji is a single named button node', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpButton(tester);

    _expectOneEmojiNode('Emoji');
    handle.dispose();
  });

  testWidgets('Russian: «Эмодзи» is a single named button node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpButton(tester, locale: const Locale('ru'));

    _expectOneEmojiNode('Эмодзи');
    handle.dispose();
  });

  testWidgets('the screen-reader tap opens and closes the picker', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpButton(tester);
    final emoji = find.semantics.byPredicate(
      (n) => n.getSemanticsData().identifier == TestIds.roomEmojiButton,
    );

    tester.semantics.tap(emoji);
    await tester.pumpAndSettle();
    expect(find.byType(EmojiPicker), findsOneWidget);

    tester.semantics.tap(emoji);
    await tester.pumpAndSettle();
    expect(find.byType(EmojiPicker), findsNothing);
    handle.dispose();
  });

  // The one node keeps the open/closed state that the IconButton's own
  // `isSelected` carried before its semantics were excluded.
  testWidgets('the Emoji node says whether the picker is open', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpButton(tester);
    final emoji = find.semantics.byPredicate(
      (n) => n.getSemanticsData().identifier == TestIds.roomEmojiButton,
    );

    expect(
      _emojiNode(),
      isSemantics(hasExpandedState: true, isExpanded: false),
    );

    tester.semantics.tap(emoji);
    await tester.pumpAndSettle();
    expect(
      _emojiNode(),
      isSemantics(hasExpandedState: true, isExpanded: true),
    );

    tester.semantics.tap(emoji);
    await tester.pumpAndSettle();
    expect(
      _emojiNode(),
      isSemantics(hasExpandedState: true, isExpanded: false),
    );
    handle.dispose();
  });

  // Guard: a locked composer keeps the button, says it is off and opens
  // nothing.
  testWidgets('a disabled Emoji button is one node that does nothing', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpButton(tester, enabled: false);

    final node = _emojiNode();
    expect(node, isSemantics(isButton: true, isEnabled: false));
    expect(_buttonsInside(node), isEmpty);
    await tester.tap(find.byKey(TestIds.key(TestIds.roomEmojiButton)));
    await tester.pumpAndSettle();
    expect(find.byType(EmojiPicker), findsNothing);
    handle.dispose();
  });
}
