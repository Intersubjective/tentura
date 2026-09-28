import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/beacon_threads/ui/widget/reaction_quick_picker.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';

Widget _harness(Widget child) => MaterialApp(
  locale: const Locale('en'),
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: TenturaResponsiveScope(
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  final l10n = L10nEn();
  const pray = '\u{1F64F}';

  test('every quick-picker emoji has a meaning', () {
    for (final emoji in BeaconRoomMessageReaction.quickPickerEmojis) {
      expect(reactionEmojiMeaning(l10n, emoji), isNotNull, reason: emoji);
    }
  });

  testWidgets('hover previews meaning, tap picks', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(
      _harness(ReactionQuickPicker(selected: const {}, onPick: picked.add)),
    );
    expect(find.text(l10n.beaconRoomReactionPickerHint), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text(pray)));
    await tester.pump();
    expect(
      find.text('$pray  ${l10n.beaconRoomReactionMeaningThanks}'),
      findsOneWidget,
    );

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(find.text(l10n.beaconRoomReactionPickerHint), findsOneWidget);

    await tester.tap(find.text(pray));
    expect(picked, [pray]);
  });

  testWidgets('long-press previews meaning without picking', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(
      _harness(ReactionQuickPicker(selected: const {}, onPick: picked.add)),
    );
    await tester.longPress(find.text(pray));
    await tester.pump();
    expect(
      find.text('$pray  ${l10n.beaconRoomReactionMeaningThanks}'),
      findsOneWidget,
    );
    expect(picked, isEmpty);
  });

  testWidgets('semantics label is the meaning', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _harness(ReactionQuickPicker(selected: const {}, onPick: (_) {})),
    );
    expect(
      find.bySemanticsLabel(l10n.beaconRoomReactionMeaningThanks),
      findsOneWidget,
    );
    handle.dispose();
  });
}
