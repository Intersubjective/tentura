import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/block/domain/entity/user_block.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';
import 'package:tentura/features/block/ui/sheet/block_user_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  group('BlockUserSheetBody C3', () {
    testWidgets('cascade switch off by default; on reveals radios and re-fetches', (
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
      expect(find.byKey(const Key('block_cascade_mode_sybil')), findsNothing);
      expect(fakeCase.previewCalls, [0]);

      await tester.tap(switchFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
      expect(find.byKey(const Key('block_cascade_mode_sybil')), findsOneWidget);
      expect(find.byKey(const Key('block_cascade_mode_all')), findsOneWidget);
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
          body: BlockUserSheetBody(
            profile: profile,
            blockCase: fakeCase,
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
