import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'semantics_identifier.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('hasSemanticsIdentifier', () {
    testWidgets('matches the node that carries the identifier', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          Semantics(
            identifier: 'probe.ok',
            label: 'Probe',
            button: true,
            onTap: () {},
            excludeSemantics: true,
            child: const SizedBox(width: 48, height: 48),
          ),
        ),
      );
      final node = find.semantics.byLabel('Probe').evaluate().single;
      expect(node, hasSemanticsIdentifier('probe.ok'));
      expect(node.getSemanticsData(), hasSemanticsIdentifier('probe.ok'));
      handle.dispose();
    });

    testWidgets('rejects a different identifier', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          Semantics(
            identifier: 'probe.ok',
            label: 'Probe',
            excludeSemantics: true,
            child: const SizedBox(width: 48, height: 48),
          ),
        ),
      );
      final node = find.semantics.byLabel('Probe').evaluate().single;
      expect(node, isNot(hasSemanticsIdentifier('probe.other')));
      handle.dispose();
    });

    // The #390 shape: an identifier-only Semantics around a Material button
    // forms its own (unnamed) node, so the named, tappable button node under
    // it has no identifier. The matcher must say so.
    testWidgets('rejects a button whose identifier sits on a wrapper node', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          Semantics(
            identifier: 'probe.wrapper',
            child: TextButton(onPressed: () {}, child: const Text('Probe')),
          ),
        ),
      );
      final button = find.semantics.byLabel('Probe').evaluate().single;
      expect(button, isNot(hasSemanticsIdentifier('probe.wrapper')));
      expect(
        find.semantics.byPredicate((n) => n.identifier == 'probe.wrapper'),
        findsOne,
        reason: 'the identifier is on its own wrapper node',
      );
      handle.dispose();
    });

    test('rejects values that are not semantics', () {
      expect('probe.ok', isNot(hasSemanticsIdentifier('probe.ok')));
    });
  });

  // Canary for why the helper exists: flutter_test ignores `identifier:` in
  // isSemantics. If this starts failing, the SDK now checks it and callers
  // may go back to plain isSemantics(identifier: ...).
  testWidgets('flutter_test isSemantics still ignores identifier', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _wrap(
        Semantics(
          identifier: 'probe.ok',
          label: 'Probe',
          excludeSemantics: true,
          child: const SizedBox(width: 48, height: 48),
        ),
      ),
    );
    expect(
      find.semantics.byLabel('Probe').evaluate().single,
      isSemantics(label: 'Probe', identifier: 'probe.not-this-one'),
    );
    handle.dispose();
  });
}
