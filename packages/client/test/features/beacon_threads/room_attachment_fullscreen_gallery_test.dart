import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart'
    show BeaconRoomMessageAttachmentKind;
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_attachment_widgets.dart';

RoomMessageAttachment _image() => const RoomMessageAttachment(
      id: 'a1',
      kind: BeaconRoomMessageAttachmentKind.image,
      position: 0,
      mime: 'image/jpeg',
      sizeBytes: 1,
      imageId: 'img-1',
      imageAuthorId: 'auth',
    );

Future<void> _pumpGallery(WidgetTester tester, ThemeData theme) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: RoomAttachmentFullscreenGallery(
        attachments: [_image()],
        initialIndex: 0,
      ),
    ),
  );
}

void main() {
  testWidgets('gallery scaffold uses theme bg in light mode', (tester) async {
    await _pumpGallery(tester, TenturaTheme.light());

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, TenturaPalette.bg);
  });

  testWidgets('gallery scaffold uses theme bg in dark mode', (tester) async {
    await _pumpGallery(tester, TenturaTheme.dark());

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, TenturaPalette.bgDark);
  });
}
