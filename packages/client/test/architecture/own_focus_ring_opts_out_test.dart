@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #499 / #619: the app-level `TenturaFocusRing` outlines whichever control
/// holds keyboard focus. A control that draws its own keyboard ring must opt
/// out with `TenturaFocusRing.exclude`, or keyboard users see two rings.
///
/// "Draws its own keyboard ring": the file strokes with the shared ring width
/// (`TenturaSpacing.focusRing`) and reads keyboard focus state. Rings drawn
/// for hover or selection (no focus read) are not keyboard rings.
const _ringOwner = 'lib/design_system/components/tentura_focus_ring.dart';

final _ringStroke = RegExp(r'TenturaSpacing\.focusRing\b');
final _focusRead = RegExp(
  r'\b(hasPrimaryFocus|hasFocus|onShowFocusHighlight|onFocusChange)\b',
);
final _optOut = RegExp(r'TenturaFocusRing\.exclude\s*\(');

/// Source with whole-line `//` comments dropped, so a comment that names the
/// ring neither triggers nor satisfies the rule.
String _code(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

/// Paths in [sources] (path → file text) that draw their own keyboard focus
/// ring without opting out of the app-level one.
List<String> ownRingWithoutOptOut(Map<String, String> sources) => [
  for (final MapEntry(key: path, value: source) in sources.entries)
    if (path != _ringOwner)
      if (_code(source) case final code
          when _ringStroke.hasMatch(code) &&
              _focusRead.hasMatch(code) &&
              !_optOut.hasMatch(code))
        path,
];

Directory _libRoot() => Directory('lib').existsSync()
    ? Directory('lib')
    : Directory('packages/client/lib');

void main() {
  test('every own keyboard focus ring opts out of the app-level ring', () {
    final root = _libRoot();
    final prefix = root.path.substring(0, root.path.length - 'lib'.length);
    final sources = {
      for (final entity in root.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          entity.path.substring(prefix.length): entity.readAsStringSync(),
    };
    expect(
      ownRingWithoutOptOut(sources),
      isEmpty,
      reason:
          'a control that draws its own keyboard focus ring must wrap itself '
          'in TenturaFocusRing.exclude(child: ...)',
    );
  });

  group('the own-ring rule itself', () {
    const ring = '''
final ring = node.hasPrimaryFocus
    ? Border.all(width: TenturaSpacing.focusRing)
    : null;
''';

    test('flags a focus-driven ring with no opt-out', () {
      expect(ownRingWithoutOptOut({'a.dart': ring}), ['a.dart']);
    });

    test('passes once the control opts out', () {
      expect(
        ownRingWithoutOptOut({
          'a.dart': '$ring\nTenturaFocusRing.exclude(child: child);',
        }),
        isEmpty,
      );
    });

    test('ignores a ring drawn for hover or selection, not focus', () {
      expect(
        ownRingWithoutOptOut({
          'a.dart': 'Border.all(width: TenturaSpacing.focusRing);',
        }),
        isEmpty,
      );
    });

    test('a commented-out opt-out does not count', () {
      expect(
        ownRingWithoutOptOut({
          'a.dart': '$ring\n// TenturaFocusRing.exclude(child: child);',
        }),
        ['a.dart'],
      );
    });
  });
}
