// #483: "Edit message" opened without the caret in the field, offered only
// Save (also for unchanged or empty text), and had no Cancel.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'support/room_body_harness.dart';

void main() {
  const me = Profile(id: 'me', displayName: 'Me');
  final message = RoomMessage(
    id: 'm1',
    beaconId: 'b1',
    authorId: me.id,
    author: me,
    body: 'Hello room',
    createdAt: DateTime.utc(2026, 6, 30, 12),
  );

  Future<Finder> openEditSheet(WidgetTester tester) async {
    final l10n = lookupL10n(const Locale('en'));
    await pumpBeaconRoomBody(
      tester,
      roomState: roomBodyState(messages: [message]),
      height: 900,
    );
    await tester.pumpAndSettle();
    await tester.longPressAt(
      tester.getTopLeft(find.byType(RoomMessageTextBody)) + const Offset(8, 8),
    );
    await tester.pumpAndSettle();
    final edit = find.text(l10n.beaconRoomActionEditMessage);
    await tester.ensureVisible(edit);
    await tester.pumpAndSettle();
    await tester.tap(edit);
    await tester.pumpAndSettle();
    final sheetField = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(EditableText),
    );
    expect(sheetField, findsOneWidget);
    return sheetField;
  }

  FilledButton saveButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Save'),
  );

  testWidgets('opens focused, with the caret after the text', (tester) async {
    final field = await openEditSheet(tester);
    final editable = tester.widget<EditableText>(field);

    expect(editable.focusNode.hasFocus, isTrue);
    expect(
      editable.controller.selection,
      const TextSelection.collapsed(offset: 'Hello room'.length),
    );
  });

  testWidgets('Save waits for a changed, non-empty text', (tester) async {
    final field = await openEditSheet(tester);
    expect(saveButton(tester).onPressed, isNull);

    await tester.enterText(field, 'Hello room!');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNotNull);

    await tester.enterText(field, '   ');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNull);
  });

  testWidgets('Cancel closes the unchanged sheet', (tester) async {
    await openEditSheet(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
  });
}
