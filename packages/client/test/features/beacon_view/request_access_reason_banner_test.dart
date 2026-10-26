import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/widget/request_access_reason_banner.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _bannerText =
    'You can see this request because you take part in a related request.';

Beacon _beacon({
  required BeaconAccessLevel? accessLevel,
  int accessReasons = 0,
  String? lineageParentBeaconId,
}) => Beacon(
  id: 'B1',
  title: 't',
  author: const Profile(id: 'U1', displayName: 'a'),
  createdAt: DateTime.utc(2026, 6, 20),
  updatedAt: DateTime.utc(2026, 6, 20),
  accessLevel: accessLevel,
  accessReasons: accessReasons,
  lineageParentBeaconId: lineageParentBeaconId,
);

Beacon _parent({
  BeaconKind kind = BeaconKind.post,
  String title = 'GQ1024: planning a weekend',
}) => Beacon(
  id: 'P1',
  title: title,
  kind: kind,
  author: const Profile(id: 'U1', displayName: 'a'),
  createdAt: DateTime.utc(2026, 6, 19),
  updatedAt: DateTime.utc(2026, 6, 19),
);

const _postBannerText =
    "You can see this request because you're in the post "
    '«GQ1024: planning a weekend» it grew from.';

Future<void> _pumpBanner(
  WidgetTester tester,
  Beacon beacon, {
  Beacon? parent,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: SizedBox(
            width: 400,
            child: RequestAccessReasonBanner(beacon: beacon, parent: parent),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shown for context-child observer', (tester) async {
    await _pumpBanner(
      tester,
      _beacon(accessLevel: BeaconAccessLevel.observer, accessReasons: 64),
    );
    expect(find.text(_bannerText), findsOneWidget);
  });

  testWidgets('shown for context-ancestor observer', (tester) async {
    await _pumpBanner(
      tester,
      _beacon(accessLevel: BeaconAccessLevel.observer, accessReasons: 128),
    );
    expect(find.text(_bannerText), findsOneWidget);
  });

  testWidgets('hidden for member even with a context bit', (tester) async {
    await _pumpBanner(
      tester,
      _beacon(accessLevel: BeaconAccessLevel.member, accessReasons: 64),
    );
    expect(find.text(_bannerText), findsNothing);
  });

  testWidgets('hidden for author', (tester) async {
    await _pumpBanner(tester, _beacon(accessLevel: BeaconAccessLevel.author));
    expect(find.text(_bannerText), findsNothing);
  });

  testWidgets('hidden without a server access level', (tester) async {
    await _pumpBanner(tester, _beacon(accessLevel: null, accessReasons: 64));
    expect(find.text(_bannerText), findsNothing);
  });

  testWidgets('hidden for forwarded-only observer', (tester) async {
    await _pumpBanner(
      tester,
      _beacon(accessLevel: BeaconAccessLevel.observer, accessReasons: 8),
    );
    expect(find.text(_bannerText), findsNothing);
  });

  testWidgets('applied takes priority over context', (tester) async {
    await _pumpBanner(
      tester,
      _beacon(accessLevel: BeaconAccessLevel.observer, accessReasons: 16 | 64),
    );
    expect(find.text(_bannerText), findsNothing);
  });

  testWidgets('context takes priority over discovered', (tester) async {
    await _pumpBanner(
      tester,
      _beacon(accessLevel: BeaconAccessLevel.observer, accessReasons: 32 | 64),
    );
    expect(find.text(_bannerText), findsOneWidget);
  });

  group('a Request budded from a Post (#724)', () {
    final budded = _beacon(
      accessLevel: BeaconAccessLevel.observer,
      accessReasons: 64,
      lineageParentBeaconId: 'P1',
    );

    testWidgets('a post member is told it grew from that post', (
      tester,
    ) async {
      await _pumpBanner(tester, budded, parent: _parent());
      expect(find.text(_postBannerText), findsOneWidget);
      expect(find.text(_bannerText), findsNothing);
      expect(
        find.byKey(RequestAccessReasonBanner.openParentKey),
        findsOneWidget,
      );
    });

    testWidgets('a declined post member also sees the post reason', (
      tester,
    ) async {
      // Eve: her offer was declined, so only the bud snapshot remains.
      await _pumpBanner(
        tester,
        _beacon(
          accessLevel: BeaconAccessLevel.observer,
          accessReasons: 32 | 64,
          lineageParentBeaconId: 'P1',
        ),
        parent: _parent(),
      );
      expect(find.text(_postBannerText), findsOneWidget);
    });

    testWidgets('real data: a bud has no lineage parent, the post is named', (
      tester,
    ) async {
      // QA on dev: a budded Request's Post is its hierarchy parent; the
      // Request itself carries no lineage parent.
      await _pumpBanner(
        tester,
        _beacon(
          accessLevel: BeaconAccessLevel.observer,
          accessReasons: 32 | 64,
        ),
        parent: _parent(),
      );
      expect(find.text(_postBannerText), findsOneWidget);
      expect(find.text(_bannerText), findsNothing);
      expect(
        find.byKey(RequestAccessReasonBanner.openParentKey),
        findsOneWidget,
      );
    });

    testWidgets('guard: a Request parent keeps the related-request line', (
      tester,
    ) async {
      await _pumpBanner(
        tester,
        budded,
        parent: _parent(kind: BeaconKind.request),
      );
      expect(find.text(_bannerText), findsOneWidget);
      expect(find.byKey(RequestAccessReasonBanner.openParentKey), findsNothing);
    });

    testWidgets('guard: until the parent is read, the general line stays', (
      tester,
    ) async {
      await _pumpBanner(tester, budded);
      expect(find.text(_bannerText), findsOneWidget);
    });

    testWidgets('guard: access through a child Request is not the post', (
      tester,
    ) async {
      await _pumpBanner(
        tester,
        _beacon(
          accessLevel: BeaconAccessLevel.observer,
          accessReasons: 128,
          lineageParentBeaconId: 'P1',
        ),
        parent: _parent(),
      );
      expect(find.text(_bannerText), findsOneWidget);
      expect(find.text(_postBannerText), findsNothing);
    });

    testWidgets('Russian names the post too', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: Scaffold(
              body: SizedBox(
                width: 400,
                child: RequestAccessReasonBanner(
                  beacon: budded,
                  parent: _parent(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Вы видите этот запрос, потому что участвуете в посте '
          '«GQ1024: planning a weekend», из которого он вырос.',
        ),
        findsOneWidget,
      );
    });
  });
}
