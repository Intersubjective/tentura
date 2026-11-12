import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_presenter.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';
import 'package:tentura/ui/widget/beacon_request_preview_identity.dart';

const _size = kBeaconCardHeaderIconSize;

Widget _harness(Widget child) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: const Locale('en'),
  home: TenturaResponsiveScope(
    child: Scaffold(body: Center(child: child)),
  ),
);

/// The neutral glyph both identity tiles draw: one campaign icon at
/// size * 0.52 in onSurfaceVariant, centred on surfaceContainerHighest.
void _expectNeutralGlyph(WidgetTester tester) {
  final scheme = Theme.of(
    tester.element(find.byType(Scaffold)),
  ).colorScheme;
  final icon = find.byIcon(Icons.campaign_outlined);
  expect(icon, findsOneWidget);
  final widget = tester.widget<Icon>(icon);
  expect(widget.size, _size * 0.52);
  expect(widget.color, scheme.onSurfaceVariant);
  final box = find.ancestor(
    of: icon,
    matching: find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == scheme.surfaceContainerHighest,
    ),
  );
  expect(box, findsOneWidget);
  expect(
    find.ancestor(of: icon, matching: find.byType(Center)),
    findsWidgets,
  );
}

void main() {
  testWidgets('BeaconIdentityTile neutral identity draws the neutral glyph', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        BeaconIdentityTile(
          beacon: Beacon.empty.copyWith(
            id: 'beacon-1',
            title: 'Bring a van on Friday',
            author: const Profile(id: 'author-1'),
          ),
          size: _size,
        ),
      ),
    );
    _expectNeutralGlyph(tester);
  });

  testWidgets(
    'BeaconRequestPreviewIdentity neutral identity draws the neutral glyph',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          const BeaconRequestPreviewIdentity(
            data: BeaconRequestPreviewData(
              beaconId: 'child-1',
              title: 'Need a ladder',
              author: Profile(id: 'author-1', displayName: 'Alice'),
              status: BeaconStatus.open,
              phaseStatus: BeaconPhaseStatusPresentation(
                slot1: 'Open',
                slot1Tone: TenturaTone.neutral,
              ),
              coverSource: BeaconCoverSource.photo,
              needs: {},
            ),
            currentUserId: 'viewer',
          ),
        ),
      );
      _expectNeutralGlyph(tester);
    },
  );
}
