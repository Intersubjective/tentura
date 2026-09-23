import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_presenter.dart';
import 'package:tentura/ui/widget/beacon_request_preview_identity.dart';
import 'package:tentura/ui/widget/overlapping_people_avatars.dart';

Widget _harness(Widget child) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: child,
    ),
  ),
);

BeaconRequestPreviewData _data({
  List<Profile> helpers = const [],
  int helperCount = 0,
  String? description,
}) => BeaconRequestPreviewData(
  beaconId: 'child-1',
  title: 'Need a ladder',
  author: const Profile(id: 'author-1', displayName: 'Alice'),
  admittedHelpers: helpers,
  admittedHelperCount: helperCount,
  status: BeaconStatus.open,
  phaseStatus: const BeaconPhaseStatusPresentation(
    slot1: 'Open',
    slot1Tone: TenturaTone.neutral,
  ),
  description: description,
  coverSource: BeaconCoverSource.photo,
  needs: const {},
);

void main() {
  testWidgets('names author and shows helper line when helpers exist', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        BeaconRequestPreviewIdentity(
          data: _data(
            helpers: const [
              Profile(id: 'helper-1', displayName: 'Bob'),
            ],
            helperCount: 1,
            description: 'Two line description body that should appear',
          ),
          currentUserId: 'viewer',
          showDescription: true,
        ),
      ),
    );

    expect(find.text('Need a ladder'), findsOneWidget);
    expect(find.text('By Alice'), findsOneWidget);
    expect(find.text('With Bob'), findsOneWidget);
    expect(
      find.text('Two line description body that should appear'),
      findsOneWidget,
    );
    expect(find.byType(OverlappingPeopleAvatars), findsOneWidget);
  });

  testWidgets('zero helpers omits helper name line', (tester) async {
    await tester.pumpWidget(
      _harness(
        BeaconRequestPreviewIdentity(
          data: _data(),
          currentUserId: 'viewer',
        ),
      ),
    );

    expect(find.text('By Alice'), findsOneWidget);
    expect(find.textContaining('With '), findsNothing);
  });

  testWidgets('desk and child share the same identity widget type', (
    tester,
  ) async {
    // Regression guard: both surfaces must compose BeaconRequestPreviewIdentity
    // rather than diverging private card subclasses.
    await tester.pumpWidget(
      _harness(
        Column(
          children: [
            BeaconRequestPreviewIdentity(
              data: _data(),
              currentUserId: 'viewer',
              trailing: const Icon(Icons.more_vert),
            ),
            BeaconRequestPreviewIdentity(
              data: _data(description: 'Snippet'),
              currentUserId: 'viewer',
              showDescription: true,
            ),
          ],
        ),
      ),
    );

    expect(find.byType(BeaconRequestPreviewIdentity), findsNWidgets(2));
    expect(find.text('Need a ladder'), findsNWidgets(2));
  });
}
