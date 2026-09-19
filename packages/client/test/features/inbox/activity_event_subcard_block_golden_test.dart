import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/widget/activity_event_subcard_block.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _anna = Profile(id: 'u1', displayName: 'Anna');
const _gleb = Profile(id: 'u2', displayName: 'Глеб');

AttentionReceipt _event({
  required String id,
  String? actorUserId,
  String title = 'Offered help',
  String body = 'Body',
  bool obligation = false,
}) => AttentionReceipt(
  id: id,
  category: 'requestProgress',
  kind: 'helpOfferSubmitted',
  priority: 'normal',
  title: title,
  body: body,
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 6, 19, 16, 40),
  collapsedCount: 1,
  presentationKey: 'help_offer_submitted',
  presentationPayloadJson: '{}',
  surface: AttentionSurface.activity,
  actorUserId: actorUserId,
  requiresAction: obligation,
);

final _events = [
  _event(id: 'e1', actorUserId: 'u1', title: 'Anna', body: 'I can help'),
  _event(
    id: 'e2',
    actorUserId: 'u2',
    title: 'Глеб',
    body: 'Могу дать прицеп',
    obligation: true,
  ),
  _event(id: 'e3', title: 'Request updated'),
];

Widget _host({
  required double width,
  required Locale locale,
  required ThemeData theme,
  double textScale = 1,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: locale,
  theme: theme,
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: MediaQuery(
    data: MediaQueryData(
      size: Size(width, 400),
      textScaler: TextScaler.linear(textScale),
    ),
    child: TenturaResponsiveScope(
      child: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: RepaintBoundary(
            key: const Key('golden'),
            child: SizedBox(
              width: width,
              child: ActivityEventSubcardBlock(
                eventTotal: 12,
                eventsPreview: _events,
                beaconId: 'b1',
                actors: const {'u1': _anna, 'u2': _gleb},
                onClearEvent: (_) {},
                onOpenTimeline: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _pumpGolden(
  WidgetTester tester, {
  required String name,
  required double width,
  required Locale locale,
  required ThemeData theme,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _host(width: width, locale: locale, theme: theme, textScale: textScale),
  );
  await tester.pumpAndSettle();
  await expectLater(
    find.byKey(const Key('golden')),
    matchesGoldenFile('goldens/$name'),
  );
}

void main() {
  for (final width in [360.0, 390.0]) {
    for (final brightness in ['light', 'dark']) {
      for (final lang in ['en', 'ru']) {
        testWidgets('event block $brightness $lang $width', (tester) async {
          await _pumpGolden(
            tester,
            name: 'activity_event_block_${brightness}_${lang}_$width.png',
            width: width,
            locale: Locale(lang),
            theme: brightness == 'light'
                ? TenturaTheme.light()
                : TenturaTheme.dark(),
          );
        });
      }
    }
  }

  testWidgets('event block light ru 360 at 1.3x', (tester) async {
    await _pumpGolden(
      tester,
      name: 'activity_event_block_light_ru_360.0_s1_3.png',
      width: 360,
      locale: const Locale('ru'),
      theme: TenturaTheme.light(),
      textScale: 1.3,
    );
  });

  testWidgets('height does not depend on how many events the server has', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<double> heightFor(int eventTotal) async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(1.3),
            ),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    key: const Key('measured'),
                    width: 360,
                    child: ActivityEventSubcardBlock(
                      eventTotal: eventTotal,
                      eventsPreview: _events,
                      beaconId: 'b1',
                      actors: const {'u1': _anna, 'u2': _gleb},
                      onClearEvent: (_) {},
                      onOpenTimeline: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byKey(const Key('measured'))).height;
    }

    final few = await heightFor(4);
    final many = await heightFor(4000);
    // §9: the ceiling is by construction — «ещё N» leaves for the Timeline,
    // so a Request with 4000 live events is exactly as tall as one with 4.
    expect(many, few);
    expect(many, lessThanOrEqualTo(224));
    // Compact window class shows one mini-card, whatever the total.
    expect(find.byType(AttentionMiniCard), findsOneWidget);
  });
}
