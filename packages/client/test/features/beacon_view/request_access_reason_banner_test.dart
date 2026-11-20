import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/widget/request_access_reason_banner.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';

const _bannerText =
    'You can see this request because you take part in a related request.';

const _relatedRussian =
    'Вы видите этот запрос, потому что участвуете в связанном запросе.';

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

RenderParagraph _bannerParagraph(WidgetTester tester) =>
    tester.renderObject<RenderParagraph>(
      find.byKey(RequestAccessReasonBanner.bodyTextKey),
    );

Future<void> _pumpBannerPhone(
  WidgetTester tester, {
  required Locale locale,
  required Beacon beacon,
}) async {
  await usePhoneSurface(tester);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: RequestAccessReasonBanner(
            beacon: beacon,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpBanner(
  WidgetTester tester,
  Beacon beacon,
) async {
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
            child: RequestAccessReasonBanner(
              beacon: beacon,
            ),
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

  group('access explanations for Requests budded from Posts', () {
    final budded = _beacon(
      accessLevel: BeaconAccessLevel.observer,
      accessReasons: 64,
      lineageParentBeaconId: 'P1',
    );

    testWidgets('an observer sees the related Request explanation', (
      tester,
    ) async {
      await _pumpBanner(tester, budded);
      expect(find.text(_bannerText), findsOneWidget);
      expect(find.textContaining('it grew from'), findsNothing);
      expect(
        find.byKey(RequestAccessReasonBanner.openParentKey),
        findsNothing,
      );
    });

    testWidgets(
      'discovery alongside parent context keeps the related Request explanation',
      (
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
        );
        expect(find.text(_bannerText), findsOneWidget);
        expect(find.textContaining('it grew from'), findsNothing);
      },
    );

    testWidgets(
      'a bud without a lineage parent shows the related Request explanation',
      (
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
        );
        expect(find.text(_bannerText), findsOneWidget);
        expect(find.textContaining('it grew from'), findsNothing);
        expect(
          find.byKey(RequestAccessReasonBanner.openParentKey),
          findsNothing,
        );
      },
    );

    testWidgets(
      'a bud with a lineage parent uses the generic explanation',
      (
        tester,
      ) async {
        await _pumpBanner(
          tester,
          budded,
        );
        expect(find.text(_bannerText), findsOneWidget);
        expect(find.textContaining('it grew from'), findsNothing);
      },
    );

    testWidgets('a linked Request has no action in its access explanation', (
      tester,
    ) async {
      await _pumpBanner(
        tester,
        budded,
      );
      expect(find.text(_bannerText), findsOneWidget);
      expect(find.byKey(RequestAccessReasonBanner.openParentKey), findsNothing);
    });

    testWidgets(
      'guard: the related Request explanation needs no parent fixture',
      (
        tester,
      ) async {
        await _pumpBanner(tester, budded);
        expect(find.text(_bannerText), findsOneWidget);
      },
    );

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
      );
      expect(find.text(_bannerText), findsOneWidget);
      expect(find.textContaining('it grew from'), findsNothing);
    });

    testWidgets('Russian explains related Request access', (tester) async {
      await _pumpBannerPhone(
        tester,
        locale: const Locale('ru'),
        beacon: budded,
      );
      final paragraph = _bannerParagraph(tester);
      expect(paragraph.didExceedMaxLines, isFalse);
      final plain = paragraph.text.toPlainText();
      expect(plain, _relatedRussian);
      expect(plain, isNot(contains('GQ1024')));
      expect(plain, isNot(contains('…')));
    });

    testWidgets(
      'English phone layout shows the full related Request explanation',
      (
        tester,
      ) async {
        await _pumpBannerPhone(
          tester,
          locale: const Locale('en'),
          beacon: budded,
        );
        final paragraph = _bannerParagraph(tester);
        expect(paragraph.didExceedMaxLines, isFalse);
        final plain = paragraph.text.toPlainText();
        expect(plain, _bannerText);
        expect(plain, isNot(contains('GQ1024')));
        expect(
          find.byKey(RequestAccessReasonBanner.openParentKey),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Russian phone layout shows the full related Request explanation',
      (
        tester,
      ) async {
        await _pumpBannerPhone(
          tester,
          locale: const Locale('ru'),
          beacon: budded,
        );
        final paragraph = _bannerParagraph(tester);
        expect(paragraph.didExceedMaxLines, isFalse);
        final plain = paragraph.text.toPlainText();
        expect(plain, _relatedRussian);
        expect(plain, isNot(contains('GQ1024')));
      },
    );

    testWidgets(
      'desktop layout shows the full related Request explanation',
      (
        tester,
      ) async {
        await _pumpBanner(
          tester,
          budded,
        );
        final paragraph = _bannerParagraph(tester);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.text.toPlainText(), _bannerText);
      },
    );
  });
}
