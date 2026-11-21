import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/util/ui_utils.dart';

import '../support/fact_sheet_feedback.dart';
import '../support/phone_surface.dart';

const _message = 'Selection saved';

const _featureSheets = [
  'lib/features/beacon_view/ui/widget/beacon_pinned_facts_sheet.dart',
  'lib/features/post_view/ui/widget/post_info_sheet.dart',
  'lib/features/beacon_threads/ui/widget/fact_picker_sheet.dart',
];

// Inspect tokens so comments and string labels do not count as ownership.
final _localPresentation = RegExp(
  '^(ScaffoldMessenger(State)?|Overlay(State|Entry|Portal(Controller)?)?'
  r'|overlay|([A-Z]\w*)?SnackBar(Host|Widget|Overlay)?)$',
);

List<String> _featureFeedbackHosts() => [
  for (final path in _featureSheets) ..._feedbackHostReferences(path),
];

Iterable<String> _feedbackHostReferences(String path) sync* {
  final parsed = parseString(
    path: path,
    content: File(path).readAsStringSync(),
  );
  final bringPicker = parsed.unit.declarations
      .whereType<FunctionDeclaration>()
      .where(
        (declaration) =>
            declaration.name.lexeme == 'showFactPickFromAvailableSheet',
      )
      .singleOrNull;
  final resultHandler = bringPicker?.functionExpression.body;
  var token = parsed.unit.beginToken;
  while (!token.isEof) {
    final presentsBringResult =
        resultHandler != null &&
        token.offset >= resultHandler.offset &&
        token.offset < resultHandler.end &&
        const {'showSnackBar', 'showSnackBarOn'}.contains(token.lexeme);
    if (_localPresentation.hasMatch(token.lexeme) || presentsBringResult) {
      final line = parsed.lineInfo.getLocation(token.offset).lineNumber;
      yield '$path:$line uses ${token.lexeme}';
    }
    token = token.next!;
  }
}

void main() {
  test('fact sheets delegate pick and copy feedback presentation', () {
    expect(
      _featureFeedbackHosts(),
      isEmpty,
      reason: 'Feature sheets leave successful feedback to the shared host',
    );
  });

  testWidgets(
    'shared adaptive sheets present feedback after a child closes',
    (tester) async {
      await usePhoneSurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (page) => Scaffold(
                body: TextButton(
                  onPressed: () => _openItems(page),
                  child: const Text('Open items'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open items').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose item').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save selection').hitTestable());
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      expect(find.text('Save selection', skipOffstage: false), findsNothing);
      expect(find.text('Choose item').hitTestable(), findsOneWidget);
      expectPhoneFeedback(tester, _message);
    },
  );
}

Future<void> _openItems(BuildContext page) => showTenturaAdaptiveSheet<void>(
  context: page,
  showSnackBars: true,
  builder: (_) => SafeArea(
    child: TextButton(
      onPressed: () => _chooseItem(page),
      child: const Text('Choose item'),
    ),
  ),
);

Future<void> _chooseItem(BuildContext page) async {
  final selection = await showTenturaAdaptiveSheet<String>(
    context: page,
    useRootNavigator: true,
    showSnackBars: true,
    builder: (picker) => SafeArea(
      child: TextButton(
        onPressed: () => Navigator.of(picker).pop(_message),
        child: const Text('Save selection'),
      ),
    ),
  );
  if (page.mounted && selection != null) {
    showSnackBar(page, text: selection);
  }
}
