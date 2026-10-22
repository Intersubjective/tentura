import 'dart:ui' show Tristate;

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

import '../../support/web_default_shortcuts.dart';

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
  GraphNodeWidget child, {
  Map<ShortcutActivator, Intent>? shortcuts,
}) async {
  final cubit = _BadgeTestGraphCubit();
  addTearDown(cubit.close);
  await tester.pumpWidget(
    MaterialApp(
      shortcuts: shortcuts,
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

/// Whether the primary focus sits on (or inside) the pumped [GraphNodeWidget].
bool _nodeHasFocus(WidgetTester tester) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  final node = tester.element(find.byType(GraphNodeWidget));
  var inside = focused == node;
  focused.visitAncestorElements((e) {
    if (e == node) inside = true;
    return !inside;
  });
  return inside;
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

    testWidgets('selected node announces its connection to the viewer', (
      tester,
    ) async {
      const profile = Profile(id: 'U-peer', displayName: 'Olga');
      await _pumpGraphNode(
        tester,
        GraphNodeWidget(
          nodeDetails: GenealogyUserNode(nodeKey: 'G-peer', user: profile),
          isFocused: true,
          connectionSemantics: 'Olga → you, trust, mutual',
          onTap: () {},
        ),
      );

      await _withSemantics(tester, () async {
        final semantics = _nodeSemantics(tester);
        expect(semantics.label, 'Olga');
        expect(semantics.value, 'Olga → you, trust, mutual');
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
            (widget) => widget is Semantics && widget.properties.button == true,
          ),
        ),
        findsNothing,
      );
    });
  });

  // #391 / #615: Graph view nodes were buttons without keyboard focus.
  group('GraphNodeWidget keyboard', () {
    const peer = GenealogyUserNode(
      nodeKey: 'G-peer',
      user: Profile(id: 'U-peer', displayName: 'Peer'),
    );

    testWidgets('an interactive node is reachable with Tab', (tester) async {
      await _pumpGraphNode(
        tester,
        GraphNodeWidget(nodeDetails: peer, onTap: () {}),
      );
      expect(_nodeHasFocus(tester), isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(_nodeHasFocus(tester), isTrue);
    });

    testWidgets('an interactive node is one focusable button with tap', (
      tester,
    ) async {
      await _withSemantics(tester, () async {
        await _pumpGraphNode(
          tester,
          GraphNodeWidget(nodeDetails: peer, onTap: () {}),
        );
        final data = _nodeSemantics(tester).getSemanticsData();
        final flags = data.flagsCollection;
        expect(flags.isButton, isTrue);
        // isFocusable == "has a focused state" (not Tristate.none).
        expect(flags.isFocused, isNot(Tristate.none));
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(data.label, 'Peer');
      });
    });

    for (final (name, shortcuts) in [
      ('default', null),
      ('web', webDefaultShortcuts),
    ]) {
      for (final key in [
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.numpadEnter,
        LogicalKeyboardKey.space,
      ]) {
        testWidgets(
          '$name shortcuts: ${key.keyLabel} activates a focused node',
          (tester) async {
            var taps = 0;
            final node = GraphNodeWidget(
              nodeDetails: peer,
              onTap: () => taps++,
            );
            await _pumpGraphNode(
              tester,
              node,
              shortcuts: shortcuts,
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
            expect(_nodeHasFocus(tester), isTrue);

            await tester.sendKeyEvent(key);
            await tester.pump();

            expect(taps, 1);
          },
        );
      }
    }

    testWidgets('a non-interactive node takes no focus', (tester) async {
      await _pumpGraphNode(tester, const GraphNodeWidget(nodeDetails: peer));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(_nodeHasFocus(tester), isFalse);
    });
  });
}

final _epoch = DateTime.utc(2024, 1, 1);
