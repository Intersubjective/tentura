import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_last_event.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_last_event_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';

MyWorkCardViewModel _vm({
  required Beacon beacon,
  MyWorkLastEvent? lastActivityEvent,
}) =>
    MyWorkCardViewModel(
      beaconId: beacon.id,
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredActive,
      beacon: beacon,
      lastActivityEvent: lastActivityEvent,
    );

Future<void> _pumpRow(
  WidgetTester tester, {
  required Beacon beacon,
  required MyWorkCardViewModel viewModel,
  String currentUserId = 'viewer',
  bool muted = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: MyWorkLastEventBody(
          beacon: beacon,
          viewModel: viewModel,
          currentUserId: currentUserId,
          muted: muted,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows updated placeholder until last event loads', (
    tester,
  ) async {
    final beacon = Beacon.empty.copyWith(
      id: 'b1',
      createdAt: DateTime(2026, 6, 10, 9),
      updatedAt: DateTime(2026, 6, 10, 12),
    );

    await _pumpRow(
      tester,
      beacon: beacon,
      viewModel: _vm(beacon: beacon),
    );

    expect(find.textContaining('updated'), findsOneWidget);
    expect(find.byIcon(Icons.campaign_outlined), findsNothing);
  });

  testWidgets('renders event label and inline you without avatar for self', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));

    const authorId = 'author1';
    final beacon = Beacon.empty.copyWith(
      id: 'b2',
      author: const Profile(id: authorId, displayName: 'Alice Author'),
    );
    final last = MyWorkLastEvent(
      event: BeaconActivityEvent(
        id: 'e1',
        beaconId: 'b2',
        visibility: 0,
        type: BeaconActivityEventTypeBits.beaconPublished,
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        actorId: authorId,
      ),
      actor: const Profile(id: authorId, displayName: 'Alice Author'),
    );

    await _pumpRow(
      tester,
      beacon: beacon,
      viewModel: _vm(beacon: beacon, lastActivityEvent: last),
      currentUserId: authorId,
    );

    expect(find.textContaining(l10n.beaconActivityBeaconPublished), findsOneWidget);
    expect(find.textContaining(l10n.myWorkLastEventYou), findsOneWidget);
    expect(find.textContaining(l10n.labelYou), findsNothing);
    expect(find.byType(TenturaAvatar), findsNothing);
    expect(find.byType(ProfileAuthorStarBadge), findsNothing);
    expect(find.byIcon(Icons.star_rounded), findsNothing);
    expect(find.byIcon(Icons.campaign_outlined), findsNothing);
    expect(find.byIcon(Icons.history_outlined), findsNothing);
    expect(find.textContaining('ago'), findsOneWidget);
  });

  testWidgets('renders avatar and first name for another actor', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));

    const authorId = 'author1';
    final beacon = Beacon.empty.copyWith(
      id: 'b4',
      author: const Profile(id: authorId, displayName: 'Alice Author'),
    );
    final last = MyWorkLastEvent(
      event: BeaconActivityEvent(
        id: 'e2',
        beaconId: 'b4',
        visibility: 0,
        type: BeaconActivityEventTypeBits.beaconPublished,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        actorId: authorId,
      ),
      actor: const Profile(id: authorId, displayName: 'Alice Author'),
    );

    await _pumpRow(
      tester,
      beacon: beacon,
      viewModel: _vm(beacon: beacon, lastActivityEvent: last),
    );

    expect(find.textContaining(l10n.beaconActivityBeaconPublished), findsOneWidget);
    expect(find.textContaining('Alice'), findsOneWidget);
    expect(find.textContaining(l10n.myWorkLastEventYou), findsNothing);
    expect(find.byType(TenturaAvatar), findsOneWidget);
    expect(find.byType(ProfileAuthorStarBadge), findsOneWidget);
  });

  testWidgets('reviewExpired system event omits by-actor clause', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));

    final beacon = Beacon.empty.copyWith(id: 'b5');
    final last = MyWorkLastEvent(
      event: BeaconActivityEvent(
        id: 'e3',
        beaconId: 'b5',
        visibility: 0,
        type: BeaconActivityEventTypeBits.beaconLifecycleChanged,
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        diffJson:
            '{"fromState":5,"toState":6,"reason":"${BeaconLifecycleChangeReason.reviewExpired}"}',
      ),
      actor: const Profile(),
    );

    await _pumpRow(
      tester,
      beacon: beacon,
      viewModel: _vm(beacon: beacon, lastActivityEvent: last),
    );

    expect(
      find.textContaining(l10n.beaconActivityLifecycleReviewExpired),
      findsOneWidget,
    );
    expect(find.textContaining(l10n.myWorkLastEventBy), findsNothing);
    expect(find.textContaining('ago'), findsOneWidget);
  });

  group('muted line keeps AA contrast (#413)', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    // Every coloured span in the row: opaque and ≥ 4.5:1 on the card surface.
    // On the base branch the muted line drew textMuted at alpha 0.72 (and the
    // age at 0.72 × 0.85), which fails both checks.
    void expectReadable(WidgetTester tester) {
      final surface = TenturaColorPalette.light.surface;
      // Avatar initials and icons are not the line's ink; skip them.
      final skipped = <RichText>{
        for (final type in [TenturaAvatar, ProfileAuthorStarBadge, Icon])
          ...tester.widgetList<RichText>(
            find.descendant(
              of: find.byType(type),
              matching: find.byType(RichText),
            ),
          ),
      };
      final colors = <Color>[];
      for (final rich in tester.widgetList<RichText>(
        find.descendant(
          of: find.byType(MyWorkLastEventBody),
          matching: find.byType(RichText),
        ),
      )) {
        if (skipped.contains(rich)) continue;
        rich.text.visitChildren((span) {
          final color = span.style?.color;
          if (color != null) colors.add(color);
          return true;
        });
      }
      expect(colors, isNotEmpty);
      for (final color in colors) {
        expect(color.a, 1.0, reason: '$color is translucent');
        expect(
          contrast(color, surface),
          greaterThanOrEqualTo(4.5),
          reason: '$color on $surface',
        );
      }
    }

    testWidgets('placeholder line', (tester) async {
      final beacon = Beacon.empty.copyWith(
        id: 'm1',
        createdAt: DateTime(2026, 6, 10, 9),
        updatedAt: DateTime(2026, 6, 10, 12),
      );
      await _pumpRow(
        tester,
        beacon: beacon,
        viewModel: _vm(beacon: beacon),
        muted: true,
      );
      expectReadable(tester);
    });

    testWidgets('event line with actor and age', (tester) async {
      const authorId = 'author1';
      final beacon = Beacon.empty.copyWith(
        id: 'm2',
        author: const Profile(id: authorId, displayName: 'Alice Author'),
      );
      final last = MyWorkLastEvent(
        event: BeaconActivityEvent(
          id: 'e-m2',
          beaconId: 'm2',
          visibility: 0,
          type: BeaconActivityEventTypeBits.beaconPublished,
          createdAt: DateTime.now().subtract(const Duration(hours: 1)),
          actorId: authorId,
        ),
        actor: const Profile(id: authorId, displayName: 'Alice Author'),
      );
      await _pumpRow(
        tester,
        beacon: beacon,
        viewModel: _vm(beacon: beacon, lastActivityEvent: last),
        muted: true,
      );
      expectReadable(tester);
    });
  });
}
