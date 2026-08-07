import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/block/ui/sheet/block_user_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  group('BlockUserSheetBody C3', () {
    testWidgets('cascade switch off by default; on always sends mode 1 and re-fetches', (
      tester,
    ) async {
      final fakeCase = FakeBlockCase()
        ..previewResults = [
          const BlockPreview(),
          const BlockPreview(cascadeCandidateCount: 3),
        ];

      await pumpBlockUserSheet(tester, fakeCase: fakeCase);

      final l10n = lookupL10n(const Locale('en'));
      final switchFinder = find.byKey(const Key('block_cascade_switch'));
      expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);
      expect(fakeCase.previewCalls, [0]);

      await tester.tap(switchFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
      expect(fakeCase.previewCalls, [0, 1]);
      expect(
        find.text(l10n.blockPreviewCascade(3)),
        findsOneWidget,
      );
    });
  });

  group('BlockUserSheetBody C4', () {
    testWidgets('withdrawal notice renders when willWithdrawEdge is true', (
      tester,
    ) async {
      final fakeCase = FakeBlockCase()
        ..previewResults = [
          const BlockPreview(willWithdrawEdge: true),
        ];

      await pumpBlockUserSheet(tester, fakeCase: fakeCase);

      final l10n = lookupL10n(const Locale('en'));
      final noticeFinder = find.text(l10n.blockWithdrawNotice);
      expect(noticeFinder, findsOneWidget);
      expect(find.byKey(const Key('block_withdraw_notice')), findsOneWidget);

      expect(
        find.ancestor(of: noticeFinder, matching: find.byType(InkWell)),
        findsNothing,
      );
      expect(
        find.ancestor(of: noticeFinder, matching: find.byType(SwitchListTile)),
        findsNothing,
      );
      expect(
        find.ancestor(of: noticeFinder, matching: find.byType(Checkbox)),
        findsNothing,
      );
    });

    testWidgets('withdrawal notice absent when willWithdrawEdge is false', (
      tester,
    ) async {
      final fakeCase = FakeBlockCase()
        ..previewResults = [
          const BlockPreview(willWithdrawEdge: false),
        ];

      await pumpBlockUserSheet(tester, fakeCase: fakeCase);

      final l10n = lookupL10n(const Locale('en'));
      expect(find.text(l10n.blockWithdrawNotice), findsNothing);
      expect(find.byKey(const Key('block_withdraw_notice')), findsNothing);
    });
  });

  group('BlockUserSheetBody C5', () {
    testWidgets('open-commitment warning renders when count > 0', (
      tester,
    ) async {
      final fakeCase = FakeBlockCase()
        ..previewResults = [
          const BlockPreview(openCommitmentCount: 2),
        ];

      await pumpBlockUserSheet(tester, fakeCase: fakeCase);

      final l10n = lookupL10n(const Locale('en'));
      expect(find.text(l10n.blockPreviewOpenCommitments), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
      expect(find.byKey(const Key('block_open_commitment_warning')), findsOneWidget);
    });

    testWidgets('open-commitment warning absent when count is 0', (
      tester,
    ) async {
      final fakeCase = FakeBlockCase()
        ..previewResults = [
          const BlockPreview(openCommitmentCount: 0),
        ];

      await pumpBlockUserSheet(tester, fakeCase: fakeCase);

      final l10n = lookupL10n(const Locale('en'));
      expect(find.text(l10n.blockPreviewOpenCommitments), findsNothing);
      expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
    });
  });

  group('BlockUserSheetBody P3.1', () {
    testWidgets('successful block shows confirmation snackbar with manage action', (
      tester,
    ) async {
      final fakeCase = FakeBlockCase()
        ..previewResults = [const BlockPreview()];

      await pumpBlockUserSheet(tester, fakeCase: fakeCase);
      final l10n = lookupL10n(const Locale('en'));

      await tester.tap(find.byKey(const Key('block_confirm_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(l10n.blockManageAction), findsOneWidget);
      expect(fakeCase.blockCalls, [0]);
    });

    testWidgets('manage action navigates to blocked users screen', (tester) async {
      final fakeCase = FakeBlockCase()
        ..previewResults = [const BlockPreview()];
      final recordingRouter = _RecordingRootRouter();
      final getIt = GetIt.instance;
      if (getIt.isRegistered<RootRouter>()) {
        await getIt.unregister<RootRouter>();
      }
      getIt.registerSingleton<RootRouter>(recordingRouter);
      addTearDown(() {
        if (getIt.isRegistered<RootRouter>()) {
          getIt.unregister<RootRouter>();
        }
      });

      await pumpBlockUserSheet(tester, fakeCase: fakeCase);
      final l10n = lookupL10n(const Locale('en'));

      await tester.tap(find.byKey(const Key('block_confirm_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(SnackBar), findsOneWidget);
      await tester.tap(find.text(l10n.blockManageAction));
      await tester.pump();

      expect(recordingRouter.pushedRoutes, hasLength(1));
      expect(recordingRouter.pushedRoutes.single.routeName, BlockedUsersRoute.name);
    });
  });
}

Future<void> pumpBlockUserSheet(
  WidgetTester tester, {
  required FakeBlockCase fakeCase,
  Profile profile = const Profile(
    id: 'user-blocked',
    displayName: 'Bob Blocked',
  ),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => BlockUserSheetBody(
                profile: profile,
                blockCase: fakeCase,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class FakeBlockCase implements BlockCase {
  List<BlockPreview> previewResults = [const BlockPreview()];
  final List<int> previewCalls = [];
  final List<int> blockCalls = [];

  @override
  Future<void> block({
    required String objectId,
    required int cascadeMode,
  }) async {
    blockCalls.add(cascadeMode);
  }

  @override
  Future<BlockPreview> preview({
    required String objectId,
    required int cascadeMode,
  }) async {
    previewCalls.add(cascadeMode);
    final index = previewCalls.length - 1;
    if (index < previewResults.length) {
      return previewResults[index];
    }
    return previewResults.last;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingRootRouter extends Fake implements RootRouter {
  final pushedRoutes = <PageRouteInfo<dynamic>>[];

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo<dynamic> route, {
    OnNavigationFailure? onFailure,
  }) async {
    pushedRoutes.add(route);
    return null;
  }
}
