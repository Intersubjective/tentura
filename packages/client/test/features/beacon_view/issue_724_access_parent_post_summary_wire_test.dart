import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/widget/request_access_reason_banner.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';

void main() {
  const requestId = 'Bea026c489fab';
  const postId = 'B797e767f5da1';
  Beacon request({int accessReasons = 32 | 64}) => Beacon(
    id: requestId,
    title: 'GQ1024 Garden cleanup Saturday',
    createdAt: DateTime.utc(2026, 10, 24, 1),
    updatedAt: DateTime.utc(2026, 10, 24, 1),
    lineageParentBeaconId: postId,
    accessLevel: BeaconAccessLevel.observer,
    accessReasons: accessReasons,
    author: const Profile(id: 'Ualice', displayName: 'Alice'),
  );

  testWidgets(
    'Russian phone explains observer access for a Request linked to a Post',
    (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: Scaffold(
              body: RequestAccessReasonBanner(
                beacon: request(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Вы видите этот запрос, потому что участвуете в связанном запросе.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('из которого он вырос'), findsNothing);
      expect(find.byKey(RequestAccessReasonBanner.openParentKey), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Russian phone explains observer access without a lineage link',
    (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: Scaffold(
              body: RequestAccessReasonBanner(
                beacon: request().copyWith(lineageParentBeaconId: null),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Вы видите этот запрос, потому что участвуете в связанном запросе.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('из которого он вырос'), findsNothing);
      expect(find.byKey(RequestAccessReasonBanner.openParentKey), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
