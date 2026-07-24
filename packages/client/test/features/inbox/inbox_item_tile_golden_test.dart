import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';
import 'package:tentura/features/inbox/ui/widget/inbox_item_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

class _GoldenProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'viewer', displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

Future<void> _pumpTile(
  WidgetTester tester, {
  required InboxItem item,
  required Size logicalSize,
  bool isSelected = false,
  bool attentionMarked = false,
}) async {
  await tester.pumpWidget(
    BlocProvider<ProfileCubit>.value(
      value: _GoldenProfileCubit(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(size: logicalSize),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: RepaintBoundary(
                  key: const Key('golden'),
                  child: SizedBox(
                    width: logicalSize.width,
                    child: InboxItemTile(
                      item: item,
                      attentionMarked: attentionMarked,
                      isSelected: isSelected,
                      onOpenBeacon: () {},
                      onTap: () {},
                    ),
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
}

void main() {
  const logicalSize = Size(360, 420);
  final at = DateTime.utc(2026, 6, 20, 12, 34);

  testWidgets('InboxItemTile golden (compact)', (tester) async {
    final beacon = Beacon(
      id: 'b-inbox',
      title: 'Help needed: move a piano',
      description:
          'Need two people tomorrow morning to help carry a piano '
          'up three flights. Tools provided.',
      author: const Profile(id: 'auth', displayName: 'Alex River'),
      createdAt: at,
      updatedAt: at,
    );
    final item = InboxItem(
      beaconId: beacon.id,
      latestForwardAt: at,
      beacon: beacon,
      provenance: const InboxProvenance(
        senders: [
          InboxForwardSender(
            id: 'fwd1',
            displayName: 'Sam Forward',
            mr: 1.2,
            notePreview: 'They live near you and are reliable.',
          ),
        ],
        totalDistinctSenders: 1,
        strongestNotePreview: 'They live near you and are reliable.',
      ),
    );

    await _pumpTile(
      tester,
      item: item,
      logicalSize: logicalSize,
      attentionMarked: true,
    );

    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/inbox_item_tile.png'),
    );
  });

  testWidgets('InboxItemTile golden selected', (tester) async {
    final beacon = Beacon(
      id: 'b-sel',
      title: 'Selected request',
      description: 'Short body for selection chrome.',
      author: const Profile(id: 'auth', displayName: 'Alex River'),
      createdAt: at,
      updatedAt: at,
    );
    final item = InboxItem(
      beaconId: beacon.id,
      latestForwardAt: at,
      beacon: beacon,
    );

    await _pumpTile(
      tester,
      item: item,
      logicalSize: const Size(360, 280),
      isSelected: true,
    );

    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/inbox_item_tile_selected.png'),
    );
  });

  testWidgets('empty description omits ShowMoreText', (tester) async {
    final beacon = Beacon(
      id: 'b-empty',
      title: 'No description',
      author: const Profile(id: 'auth', displayName: 'Alex River'),
      createdAt: at,
      updatedAt: at,
    );
    final item = InboxItem(
      beaconId: beacon.id,
      latestForwardAt: at,
      beacon: beacon,
    );

    await _pumpTile(
      tester,
      item: item,
      logicalSize: const Size(360, 240),
    );

    expect(find.byType(ShowMoreText), findsNothing);
  });

  testWidgets('forward note preview is visible without expanding fold', (
    tester,
  ) async {
    final beacon = Beacon(
      id: 'b-note',
      title: 'With note',
      author: const Profile(id: 'auth', displayName: 'Alex River'),
      createdAt: at,
      updatedAt: at,
    );
    final item = InboxItem(
      beaconId: beacon.id,
      latestForwardAt: at,
      beacon: beacon,
      provenance: const InboxProvenance(
        senders: [
          InboxForwardSender(
            id: 'fwd1',
            displayName: 'Sam Forward',
            mr: 1,
            notePreview: 'Please check this week.',
          ),
        ],
        totalDistinctSenders: 1,
        strongestNotePreview: 'Please check this week.',
      ),
    );

    await _pumpTile(
      tester,
      item: item,
      logicalSize: const Size(360, 320),
    );

    expect(find.textContaining('Please check this week.'), findsOneWidget);
    expect(find.textContaining('Forwarded by'), findsWidgets);
  });
}
