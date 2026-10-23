// #668 review: on pushed screens the back button was announced twice
// ("Back\nBack"): a Semantics label wrapped an IconButton whose tooltip says
// the same word. Spec: the back (or close) control is ONE button node that
// says its name once and can be tapped.

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';

class _Router extends Mock implements StackRouter {
  _Router({required this.poppable});

  final bool poppable;

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => poppable;
}

Future<void> _pump(
  WidgetTester tester, {
  required bool poppable,
  bool closeWhenCanPop = false,
  VoidCallback? onPressed,
}) async {
  final router = _Router(poppable: poppable);
  await tester.pumpWidget(
    MaterialApp(
      home: RouterScope(
        controller: router,
        stateHash: 0,
        inheritableObserversBuilder: () => const [],
        child: StackRouterScope(
          controller: router,
          stateHash: 0,
          child: Scaffold(
            appBar: AppBar(
              leading: AutoLeadingWithFallback(
                fallbackPath: '/home',
                closeWhenCanPop: closeWhenCanPop,
                onPressed: onPressed,
                onFallback: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// What a screen reader says for [data]: its label, then its tooltip.
String _spoken(SemanticsData data) =>
    [data.label, data.tooltip].where((s) => s.isNotEmpty).join('\n');

/// Engine-visible nodes that say [word].
List<SemanticsData> _nodesSaying(String word) => find.semantics
    .byPredicate(
      (node) =>
          !node.isMergedIntoParent &&
          _spoken(node.getSemanticsData()).contains(word),
    )
    .evaluate()
    .map((node) => node.getSemanticsData())
    .toList();

void _expectOneButton(String word) {
  final nodes = _nodesSaying(word);
  expect(nodes, hasLength(1), reason: 'one node says "$word"');
  final node = nodes.single;
  expect(_spoken(node), word, reason: 'said once');
  expect(node.flagsCollection.isButton, isTrue);
  expect(node.hasAction(SemanticsAction.tap), isTrue);
}

void main() {
  testWidgets('back with a custom action on a poppable stack says Back once', (
    tester,
  ) async {
    await _pump(tester, poppable: true, onPressed: () {});
    _expectOneButton('Back');
  });

  testWidgets('close on a poppable stack says Close once', (tester) async {
    await _pump(tester, poppable: true, closeWhenCanPop: true);
    _expectOneButton('Close');
  });

  testWidgets('fallback back after a web refresh says Back once', (
    tester,
  ) async {
    await _pump(tester, poppable: false);
    _expectOneButton('Back');
  });
}
