import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

AttentionReceipt _receipt({
  String? actorUserId,
  String title = 'Offered help',
}) =>
    AttentionReceipt(
      id: 'r1',
      category: 'requestProgress',
      kind: 'helpOfferSubmitted',
      priority: 'normal',
      title: title,
      body: 'Garden cleanup',
      actionUrl: '/#/view?id=b1',
      createdAt: DateTime.utc(2026, 6, 19, 16, 40),
      collapsedCount: 1,
      presentationKey: 'help_offer_submitted',
      presentationPayloadJson: '{}',
      surface: AttentionSurface.activity,
      actorUserId: actorUserId,
      beaconId: 'b1',
      itemKind: AttentionItemKind.requestActivity,
    );

Future<FakeUiEffectPort> _pump(
  WidgetTester tester, {
  required Profile? actor,
  required List<String> opens,
}) async {
  final effects = FakeUiEffectPort();
  final screen = ScreenCubit.local(effects);
  await tester.binding.setSurfaceSize(const Size(360, 200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    BlocProvider<ScreenCubit>.value(
      value: screen,
      child: MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 200)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: UpdatesFeedTile(
                receipt: _receipt(actorUserId: actor?.id),
                actor: actor,
                onTap: () => opens.add('request'),
                onMarkSeen: () {},
                onMarkUnseen: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return effects;
}

void main() {
  testWidgets('avatar tap opens profile without opening request', (tester) async {
    final opens = <String>[];
    final effects = await _pump(
      tester,
      actor: const Profile(id: 'u1', displayName: 'Anna'),
      opens: opens,
    );

    expect(find.byType(TenturaAvatar), findsOneWidget);
    expect(find.textContaining('Anna'), findsOneWidget);

    await tester.tap(find.byType(TenturaAvatar));
    await tester.pump();

    expect(
      effects.emitted.whereType<NavigatePush>().map((e) => e.path),
      ['$kPathProfileView/u1'],
    );
    expect(opens, isEmpty);
  });

  testWidgets('body tap opens request without profile navigate', (tester) async {
    final opens = <String>[];
    final effects = await _pump(
      tester,
      actor: const Profile(id: 'u1', displayName: 'Anna'),
      opens: opens,
    );

    // Tap the headline text (inside the row interaction, not the avatar).
    await tester.tap(find.textContaining('Offered help'));
    await tester.pump();

    expect(opens, ['request']);
    expect(effects.emitted.whereType<NavigatePush>(), isEmpty);
  });

  testWidgets('person stream row golden light en 360', (tester) async {
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
                    child: UpdatesFeedTile(
                      receipt: _receipt(actorUserId: 'u1'),
                      actor: const Profile(id: 'u1', displayName: 'Anna'),
                      onTap: () {},
                      onMarkSeen: () {},
                      onMarkUnseen: () {},
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
      matchesGoldenFile('goldens/updates_feed_tile_with_actor_light_en_360.png'),
    );
  },
    tags: 'golden',
  );
}
