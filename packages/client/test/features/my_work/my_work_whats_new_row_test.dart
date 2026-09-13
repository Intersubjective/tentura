import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_last_event.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_whats_new_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';

MyWorkCardViewModel _viewModel({MyWorkLastEvent? lastEvent}) =>
    MyWorkCardViewModel(
      beaconId: 'beacon-1',
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredActive,
      beacon: Beacon.empty.copyWith(
        id: 'beacon-1',
        title: 'Garden cleanup',
        updatedAt: DateTime.utc(2026, 8, 3),
      ),
      lastActivityEvent: lastEvent,
    );

AttentionReceipt _latestUnseen() => AttentionReceipt(
  id: 'unseen-1',
  category: 'coordination',
  kind: 'roomMessagePosted',
  priority: 'normal',
  title: 'Room update',
  body: 'I will bring tools tomorrow',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 8, 4, 9),
  collapsedCount: 1,
  presentationKey: 'room_message_posted',
  presentationPayloadJson: '{"beaconTitle":"Garden cleanup"}',
  surface: AttentionSurface.myWork,
  beaconId: 'beacon-1',
);

Future<void> _pumpWhatsNewGolden(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
  required Brightness brightness,
  required int unseenCount,
  AttentionReceipt? latestUnseen,
  MyWorkLastEvent? lastEvent,
  TextScaler? textScaler,
  required String goldenName,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      theme: brightness == Brightness.light
          ? TenturaTheme.light()
          : TenturaTheme.dark(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: textScaler ?? TextScaler.noScaling,
        ),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: RepaintBoundary(
                key: const Key('golden'),
                child: SizedBox(
                  width: size.width,
                  child: MyWorkWhatsNewRow(
                    beacon: _viewModel(lastEvent: lastEvent).beacon,
                    viewModel: _viewModel(lastEvent: lastEvent),
                    currentUserId: 'viewer-1',
                    unseenCount: unseenCount,
                    latestUnseen: latestUnseen,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await expectLater(
    find.byKey(const Key('golden')),
    matchesGoldenFile('goldens/$goldenName'),
  );
}

void main() {
  const width = 360.0;

  for (final brightness in Brightness.values) {
    for (final locale in const [Locale('en'), Locale('ru')]) {
      testWidgets(
        'whats new emphasis ${brightness.name} ${locale.languageCode}',
        (tester) async {
          await _pumpWhatsNewGolden(
            tester,
            size: const Size(width, 80),
            locale: locale,
            brightness: brightness,
            unseenCount: 3,
            latestUnseen: _latestUnseen(),
            goldenName:
                'my_work_whats_new_emphasis_${brightness.name}_${locale.languageCode}_360.png',
          );
        },
      );

      testWidgets(
        'whats new muted last event ${brightness.name} ${locale.languageCode}',
        (tester) async {
          final last = MyWorkLastEvent(
            actor: const Profile(id: 'actor-1', displayName: 'Anna'),
            event: BeaconActivityEvent(
              id: 'e1',
              beaconId: 'beacon-1',
              visibility: 0,
              type: BeaconActivityEventTypeBits.beaconPublished,
              createdAt: DateTime.utc(2026, 8, 4, 8),
              actorId: 'actor-1',
            ),
          );
          await _pumpWhatsNewGolden(
            tester,
            size: const Size(width, 80),
            locale: locale,
            brightness: brightness,
            unseenCount: 0,
            lastEvent: last,
            goldenName:
                'my_work_whats_new_muted_${brightness.name}_${locale.languageCode}_360.png',
          );
        },
      );
    }
  }

  testWidgets('whats new emphasis text scale 1.3 en', (tester) async {
    await _pumpWhatsNewGolden(
      tester,
      size: const Size(width, 96),
      locale: const Locale('en'),
      brightness: Brightness.light,
      unseenCount: 2,
      latestUnseen: _latestUnseen(),
      textScaler: TextScaler.linear(1.3),
      goldenName: 'my_work_whats_new_emphasis_light_en_360_1p3.png',
    );
  });

}
