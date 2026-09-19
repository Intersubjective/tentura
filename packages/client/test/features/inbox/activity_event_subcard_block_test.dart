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
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

AttentionReceipt _event({
  required String id,
  String? actorUserId,
  String title = 'Offered help',
  String body = 'Body',
  bool obligation = false,
  DateTime? createdAt,
}) => AttentionReceipt(
  id: id,
  category: 'requestProgress',
  kind: 'helpOfferSubmitted',
  priority: 'normal',
  title: title,
  body: body,
  actionUrl: '/#/',
  createdAt: createdAt ?? DateTime.utc(2026, 1, 2),
  collapsedCount: 1,
  presentationKey: 'help_offer_submitted',
  presentationPayloadJson: '{}',
  surface: AttentionSurface.activity,
  actorUserId: actorUserId,
  requiresAction: obligation,
);

Future<FakeUiEffectPort> _pump(
  WidgetTester tester, {
  required List<AttentionReceipt> events,
  Map<String, Profile> actors = const {},
  required List<String> marked,
  int? eventTotal,
  Size size = const Size(800, 600),
}) async {
  final effects = FakeUiEffectPort();
  final screen = ScreenCubit.local(effects);
  await tester.binding.setSurfaceSize(size);
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
          data: MediaQueryData(size: size),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: ActivityEventSubcardBlock(
                eventTotal: eventTotal ?? events.length,
                eventsPreview: events,
                actors: actors,
                overflowPolicy: AttentionBlockOverflowPolicy.paginate,
                onEventTap: (receipt) => marked.add(receipt.id),
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

List<String> _renderedIds(WidgetTester tester) => tester
    .widgetList<AttentionMiniCard>(find.byType(AttentionMiniCard))
    .map((c) => c.receipt.id)
    .toList(growable: false);

void main() {
  testWidgets('renders every row as the shared mini-card', (tester) async {
    final marked = <String>[];
    await _pump(
      tester,
      events: [_event(id: 'e1', actorUserId: 'u1', title: 'Offered help')],
      actors: const {'u1': Profile(id: 'u1', displayName: 'Anna')},
      marked: marked,
    );

    expect(find.byType(AttentionMiniCard), findsOneWidget);
    expect(find.byType(TenturaAvatar), findsOneWidget);
    expect(find.textContaining('Anna'), findsOneWidget);
    expect(find.textContaining('Offered help'), findsOneWidget);
  });

  testWidgets('avatar tap opens the profile, never the row action', (
    tester,
  ) async {
    final marked = <String>[];
    final effects = await _pump(
      tester,
      events: [_event(id: 'e1', actorUserId: 'u1')],
      actors: const {'u1': Profile(id: 'u1', displayName: 'Anna')},
      marked: marked,
    );

    await tester.tap(find.byType(TenturaAvatar));
    await tester.pump();
    expect(
      effects.emitted.whereType<NavigatePush>().map((e) => e.path),
      ['$kPathProfileView/u1'],
    );
    expect(marked, isEmpty);
  });

  testWidgets('keeps glyph when actor missing', (tester) async {
    final marked = <String>[];
    await _pump(tester, events: [_event(id: 'e1')], marked: marked);

    expect(find.byType(TenturaAvatar), findsNothing);
    expect(find.byType(AttentionMiniCard), findsOneWidget);
  });

  testWidgets('shows offer note when headline is actor name', (tester) async {
    final marked = <String>[];
    await _pump(
      tester,
      events: [
        _event(
          id: 'e1',
          actorUserId: 'u1',
          title: 'Vadim',
          body: 'I can sew the costume',
        ),
      ],
      actors: const {'u1': Profile(id: 'u1', displayName: 'Vadim')},
      marked: marked,
    );

    expect(find.textContaining('Vadim'), findsOneWidget);
    expect(find.textContaining('I can sew the costume'), findsOneWidget);
  });

  testWidgets('collapsed preview puts obligations first (D10)', (tester) async {
    final marked = <String>[];
    await _pump(
      tester,
      // Newest first, and the only obligation is last in time order.
      events: [
        _event(id: 'optional-1', createdAt: DateTime.utc(2026, 1, 5)),
        _event(id: 'optional-2', createdAt: DateTime.utc(2026, 1, 4)),
        _event(id: 'optional-3', createdAt: DateTime.utc(2026, 1, 3)),
        _event(
          id: 'obligation-1',
          obligation: true,
          createdAt: DateTime.utc(2026, 1, 2),
        ),
      ],
      marked: marked,
    );

    // visibleCap is 3 outside compact: the obligation must be in the preview.
    expect(_renderedIds(tester), [
      'obligation-1',
      'optional-1',
      'optional-2',
    ]);
  });

  testWidgets('expands and collapses again', (tester) async {
    final marked = <String>[];
    await _pump(
      tester,
      events: [
        for (var i = 1; i <= 5; i++) _event(id: 'e$i'),
      ],
      marked: marked,
    );

    expect(_renderedIds(tester), hasLength(3));

    await tester.tap(find.byType(TenturaTextAction));
    await tester.pumpAndSettle();
    expect(_renderedIds(tester), hasLength(5));

    // The collapse control is the affordance the old block never had.
    await tester.tap(find.text('Collapse'));
    await tester.pumpAndSettle();
    expect(_renderedIds(tester), hasLength(3));
  });
}
