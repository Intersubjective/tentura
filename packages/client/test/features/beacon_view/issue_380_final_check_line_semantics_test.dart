// #380 (#634): the "Final check ends … · Extensions: X of 2" line under the
// status-sheet row is its own semantics node carrying the whole line, so a
// screen reader reaches it. Before, the plain Text had no node of its own and
// was folded into whatever text sat above it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/beacon_view/domain/beacon_status_menu.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_status_bottom_sheet.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _sheetHeader = 'Request status';

const _reviewRow = BeaconStatusMenuRow(
  id: BeaconStatusMenuRowId.wrappingUp,
  action: BeaconStatusMenuAction.openReview,
  isSelected: true,
  isEnabled: true,
  disabledReason: BeaconStatusMenuDisabledReason.none,
);

final _closesAt = DateTime.utc(2026, 6, 27, 12, 30);

ClosureState _closure({required int extensionsUsed}) => ClosureState(
  epoch: 1,
  status: BeaconStatus.reviewOpen.smallintValue,
  role: ClosureRole.author,
  members: const [],
  closesAt: _closesAt,
  extensionsUsed: extensionsUsed,
);

/// The tile under a header text inside one semantics container, the way the
/// status sheet stacks its title and hint above the rows.
Widget _host(Widget tile) => MaterialApp(
  locale: const Locale('en'),
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: TenturaResponsiveScope(
    child: Scaffold(
      body: Semantics(
        container: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [const Text(_sheetHeader), tile],
        ),
      ),
    ),
  ),
);

void main() {
  final l10n = lookupL10n(const Locale('en'));
  // Built inside each test: DateFormat needs locale data first.
  String endsAtLine() => l10n.beaconFinalCheckEndsAt(
    DateFormat.MMMd('en').add_Hm().format(_closesAt.toLocal()),
  );

  setUpAll(() => initializeDateFormatting('en'));
  final beacon = Beacon.empty.copyWith(
    id: 'b1',
    status: BeaconStatus.reviewOpen,
  );

  testWidgets(
    'the final check line with extensions is its own semantics node',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          BeaconStatusMenuRowTile(
            row: _reviewRow,
            beacon: beacon,
            isLoading: false,
            onTap: () {},
            onSecondaryTap: () {},
            closure: _closure(extensionsUsed: 1),
            showExtensions: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final endsAt = endsAtLine();
      final line = '$endsAt · ${l10n.beaconFinalCheckExtensionsUsed(1, 2)}';
      expect(find.text(line), findsOneWidget);
      expect(find.bySemanticsLabel(line), findsOneWidget);
      // The header is still announced, and the line is not folded into its
      // node (the container may also carry the row texts, so match loosely).
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(_sheetHeader))),
        findsWidgets,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(
            '${RegExp.escape(_sheetHeader)}[\\s\\S]*${RegExp.escape(endsAt)}',
          ),
        ),
        findsNothing,
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'the final check line without extensions is its own semantics node',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          BeaconStatusMenuRowTile(
            row: _reviewRow,
            beacon: beacon,
            isLoading: false,
            onTap: () {},
            closure: _closure(extensionsUsed: 0),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(endsAtLine()), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('no closure, no final check line (guard)', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        BeaconStatusMenuRowTile(
          row: _reviewRow,
          beacon: beacon,
          isLoading: false,
          onTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(endsAtLine()), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Final check ends')), findsNothing);
    semantics.dispose();
  });
}
