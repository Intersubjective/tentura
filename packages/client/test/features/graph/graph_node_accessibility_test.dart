import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _viewer = Profile(
  id: 'Uviewer',
  displayName: 'Viewer',
  score: 3,
  rScore: 3,
);

class _BadgeTestGraphCubit extends Cubit<GraphState> implements GraphCubit {
  _BadgeTestGraphCubit() : super(const GraphState(me: _viewer, focus: ''));

  @override
  String get originNodeId => 'Gviewer';

  @override
  bool canPageMore(String id) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<void> _pumpGraphNode(
  WidgetTester tester,
  GraphNodeWidget child,
) async {
  final cubit = _BadgeTestGraphCubit();
  addTearDown(cubit.close);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: BlocProvider<GraphCubit>.value(
        value: cubit,
        child: child,
      ),
    ),
  );
  await tester.pump();
}

SemanticsNode _nodeSemantics(WidgetTester tester) {
  return tester.getSemantics(find.byType(GraphNodeWidget));
}

Future<void> _withSemantics(
  WidgetTester tester,
  Future<void> Function() run,
) async {
  final handle = tester.ensureSemantics();
  try {
    await run();
  } finally {
    handle.dispose();
  }
}

void main() {
  group('GraphNodeWidget accessibility', () {
    testWidgets('focused live user announces button, selected, and name', (
      tester,
    ) async {
      const profile = Profile(id: 'U-peer', displayName: 'Ada Lovelace');
      await _pumpGraphNode(
        tester,
        GraphNodeWidget(
          nodeDetails: GenealogyUserNode(nodeKey: 'G-peer', user: profile),
          isFocused: true,
          onTap: () {},
        ),
      );

      await _withSemantics(tester, () async {
        final semantics = _nodeSemantics(tester);
        expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);
        expect(semantics.hasFlag(SemanticsFlag.isSelected), isTrue);
        expect(semantics.label, 'Ada Lovelace');
        expect(semantics.label, isNot(contains('U-peer')));
      });
    });

    testWidgets(
      'unfocused interactive user announces button without selected',
      (
        tester,
      ) async {
        const profile = Profile(id: 'U-peer', displayName: 'Ada Lovelace');
        await _pumpGraphNode(
          tester,
          GraphNodeWidget(
            nodeDetails: GenealogyUserNode(nodeKey: 'G-peer', user: profile),
            onTap: () {},
          ),
        );

        await _withSemantics(tester, () async {
          final semantics = _nodeSemantics(tester);
          expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);
          expect(semantics.hasFlag(SemanticsFlag.isSelected), isFalse);
          expect(semantics.label, 'Ada Lovelace');
        });
      },
    );

    testWidgets('genealogy user uses displayLabel not node key', (
      tester,
    ) async {
      const profile = Profile(id: 'U-hidden', displayName: 'Gene Person');
      await _pumpGraphNode(
        tester,
        GraphNodeWidget(
          nodeDetails: GenealogyUserNode(nodeKey: 'Gopaque-key', user: profile),
          onTap: () {},
        ),
      );

      await _withSemantics(tester, () async {
        final semantics = _nodeSemantics(tester);
        expect(semantics.label, 'Gene Person');
        expect(semantics.label, isNot(contains('Gopaque-key')));
        expect(semantics.label, isNot(contains('U-hidden')));
      });
    });

    testWidgets('beacon announces localized request label and title', (
      tester,
    ) async {
      final l10n = lookupL10n(const Locale('en'));
      final beacon = Beacon(
        id: 'B123',
        title: 'Weekend ride',
        createdAt: _epoch,
        updatedAt: _epoch,
        author: Profile(id: 'U-author', displayName: 'Author'),
      );
      await _pumpGraphNode(
        tester,
        GraphNodeWidget(
          nodeDetails: BeaconNode(beacon: beacon),
          onTap: () {},
        ),
      );

      await _withSemantics(tester, () async {
        final semantics = _nodeSemantics(tester);
        expect(semantics.label, '${l10n.beaconViewTitle}: Weekend ride');
        expect(semantics.label, isNot(contains('B123')));
      });
    });

    testWidgets('deleted genealogy node uses anonymized human label', (
      tester,
    ) async {
      await _pumpGraphNode(
        tester,
        GraphNodeWidget(
          nodeDetails: const GenealogyDeletedNode(
            nodeKey: 'Gdeleted',
            label: 'Former member',
          ),
          onTap: () {},
        ),
      );

      await _withSemantics(tester, () async {
        final semantics = _nodeSemantics(tester);
        expect(semantics.label, 'Former member');
        expect(semantics.label, isNot(contains('Gdeleted')));
      });
    });

    testWidgets('interactive nodes expose click hover cursor', (tester) async {
      await _pumpGraphNode(
        tester,
        GraphNodeWidget(
          nodeDetails: const GenealogyUserNode(
            nodeKey: 'G-peer',
            user: Profile(id: 'U-peer', displayName: 'Peer'),
          ),
          onTap: () {},
        ),
      );

      final mouseRegion = tester.widget<MouseRegion>(
        find.descendant(
          of: find.byType(GraphNodeWidget),
          matching: find.byType(MouseRegion),
        ),
      );
      expect(mouseRegion.cursor, SystemMouseCursors.click);
    });

    testWidgets('non-interactive nodes omit button semantics and hover', (
      tester,
    ) async {
      await _pumpGraphNode(
        tester,
        const GraphNodeWidget(
          nodeDetails: GenealogyUserNode(
            nodeKey: 'G-peer',
            user: Profile(id: 'U-peer', displayName: 'Peer'),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(GraphNodeWidget),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is MouseRegion &&
                widget.cursor == SystemMouseCursors.click,
          ),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(GraphNodeWidget),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.button == true,
          ),
        ),
        findsNothing,
      );
    });
  });
}

final _epoch = DateTime.utc(2024, 1, 1);
