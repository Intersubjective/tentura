import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/widget/activity_event_subcard_block.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

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
      createdAt: DateTime.utc(2026, 1, 2),
      collapsedCount: 1,
      presentationKey: 'help_offer_submitted',
      presentationPayloadJson: '{}',
      surface: AttentionSurface.activity,
      actorUserId: actorUserId,
    );

Future<FakeUiEffectPort> _pump(
  WidgetTester tester, {
  required List<AttentionReceipt> events,
  Map<String, Profile> actors = const {},
  required List<String> marked,
}) async {
  final effects = FakeUiEffectPort();
  final screen = ScreenCubit.local(effects);
  await tester.binding.setSurfaceSize(const Size(800, 600));
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
          data: const MediaQueryData(size: Size(800, 600)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: ActivityEventSubcardBlock(
                eventTotal: events.length,
                eventsPreview: events,
                actors: actors,
                onMarkSeen: marked.add,
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
  testWidgets('shows avatar and name when actor present', (tester) async {
    final marked = <String>[];
    final effects = await _pump(
      tester,
      events: [_event(id: 'e1', actorUserId: 'u1', title: 'Offered help')],
      actors: const {'u1': Profile(id: 'u1', displayName: 'Anna')},
      marked: marked,
    );

    expect(find.byType(TenturaAvatar), findsOneWidget);
    expect(find.textContaining('Anna'), findsOneWidget);
    expect(find.textContaining('Offered help'), findsOneWidget);

    await tester.tap(find.byType(TenturaAvatar));
    await tester.pump();
    expect(
      effects.emitted.whereType<NavigatePush>().map((e) => e.path),
      ['$kPathProfileView/u1'],
    );
    expect(marked, isEmpty);
  });

  testWidgets('body tap marks seen without opening profile', (tester) async {
    final marked = <String>[];
    final effects = await _pump(
      tester,
      events: [_event(id: 'e1', actorUserId: 'u1')],
      actors: const {'u1': Profile(id: 'u1', displayName: 'Anna')},
      marked: marked,
    );

    await tester.tap(find.byType(TenturaTechCardStatic));
    await tester.pump();
    expect(marked, ['e1']);
    expect(effects.emitted.whereType<NavigatePush>(), isEmpty);
  });

  testWidgets('keeps glyph when actor missing', (tester) async {
    final marked = <String>[];
    await _pump(
      tester,
      events: [_event(id: 'e1')],
      marked: marked,
    );

    expect(find.byType(TenturaAvatar), findsNothing);
    expect(find.byType(TenturaTechCardStatic), findsOneWidget);
  });

  testWidgets('does not duplicate name when headline is actor name', (tester) async {
    final marked = <String>[];
    await _pump(
      tester,
      events: [_event(id: 'e1', actorUserId: 'u1', title: 'Anna')],
      actors: const {'u1': Profile(id: 'u1', displayName: 'Anna')},
      marked: marked,
    );

    expect(find.textContaining('Anna'), findsOneWidget);
  });
}
