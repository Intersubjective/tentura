import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/design_system/tentura_theme.dart';
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
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: MyWorkLastEventRow(
          beacon: beacon,
          viewModel: viewModel,
          currentUserId: currentUserId,
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

    final authorId = 'author1';
    final beacon = Beacon.empty.copyWith(
      id: 'b2',
      author: Profile(id: authorId, displayName: 'Alice Author'),
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
      actor: Profile(id: authorId, displayName: 'Alice Author'),
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
    expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);
    expect(find.textContaining('ago'), findsOneWidget);
  });

  testWidgets('renders avatar and first name for another actor', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));

    final authorId = 'author1';
    final beacon = Beacon.empty.copyWith(
      id: 'b4',
      author: Profile(id: authorId, displayName: 'Alice Author'),
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
      actor: Profile(id: authorId, displayName: 'Alice Author'),
    );

    await _pumpRow(
      tester,
      beacon: beacon,
      viewModel: _vm(beacon: beacon, lastActivityEvent: last),
      currentUserId: 'viewer',
    );

    expect(find.textContaining(l10n.beaconActivityBeaconPublished), findsOneWidget);
    expect(find.textContaining('Alice'), findsOneWidget);
    expect(find.textContaining(l10n.myWorkLastEventYou), findsNothing);
    expect(find.byType(TenturaAvatar), findsOneWidget);
    expect(find.byType(ProfileAuthorStarBadge), findsOneWidget);
  });
}
