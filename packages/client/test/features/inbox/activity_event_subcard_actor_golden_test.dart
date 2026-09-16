import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/widget/activity_event_subcard_block.dart';
import 'package:tentura/ui/l10n/l10n.dart';

AttentionReceipt _event({
  required String id,
  String? actorUserId,
  String title = 'Offered help',
}) =>
    AttentionReceipt(
      id: id,
      category: 'requestProgress',
      kind: 'helpOfferSubmitted',
      priority: 'normal',
      title: title,
      body: 'Body',
      actionUrl: '/#/',
      createdAt: DateTime.utc(2026, 6, 19, 16, 40),
      collapsedCount: 1,
      presentationKey: 'help_offer_submitted',
      presentationPayloadJson: '{}',
      surface: AttentionSurface.activity,
      actorUserId: actorUserId,
    );

Future<void> _pumpGolden(
  WidgetTester tester, {
  required String goldenName,
  Profile? actor,
}) async {
  const size = Size(360, 120);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: RepaintBoundary(
                key: const Key('golden'),
                child: SizedBox(
                  width: size.width,
                  child: ActivityEventSubcardBlock(
                    eventTotal: 1,
                    eventsPreview: [
                      _event(
                        id: 'e1',
                        actorUserId: actor?.id,
                      ),
                    ],
                    actors: actor == null
                        ? const {}
                        : {actor.id: actor},
                    onMarkSeen: (_) {},
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
  testWidgets('event-subcard-with-actor light en 360', (tester) async {
    await _pumpGolden(
      tester,
      goldenName: 'event_subcard_with_actor_light_en_360.png',
      actor: const Profile(id: 'u1', displayName: 'Anna'),
    );
  });
}
