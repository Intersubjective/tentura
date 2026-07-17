import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/ui/widget/inbox_item_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _GoldenProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'viewer', displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

void main() {
  const logicalSize = Size(360, 280);
  final at = DateTime.utc(2026, 6, 20, 12, 34);

  testWidgets('InboxItemTile golden (compact)', (tester) async {
    final beacon = Beacon(
      id: 'b-inbox',
      title: 'Help needed: move a piano',
      author: const Profile(id: 'auth', displayName: 'Alex River'),
      createdAt: at,
      updatedAt: at,
    );
    final item = InboxItem(
      beaconId: beacon.id,
      latestForwardAt: at,
      beacon: beacon,
    );

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
            data: const MediaQueryData(size: logicalSize),
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
                        attentionMarked: true,
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

    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/inbox_item_tile.png'),
    );
  });
}
