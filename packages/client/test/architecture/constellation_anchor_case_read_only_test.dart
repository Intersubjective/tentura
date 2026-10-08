import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Placement writes belong to `ConstellationPlacementCase`; the anchor case is
/// reduced to the confirmed-projection cache and its catch-up reads.
void main() {
  final packageRoot = Directory('lib/features').existsSync()
      ? ''
      : 'packages/client/';
  final anchorCaseFile = File(
    '${packageRoot}lib/features/constellation/domain/use_case/'
    'constellation_anchor_case.dart',
  );
  final cubitFile = File(
    '${packageRoot}lib/features/constellation/ui/bloc/'
    'constellation_cubit.dart',
  );

  const writeMethods = [
    'upsert',
    'upsertAll',
    'deleteAnchor',
    'delete',
    'place',
    'unpin',
  ];
  final writeAlternation = writeMethods.join('|');

  String withoutComments(String source) => source
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'//.*'), '');

  List<File> dartFiles(String relativeDir) =>
      Directory('$packageRoot$relativeDir')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) => !file.path.endsWith('.g.dart'))
          .where((file) => !file.path.endsWith('.freezed.dart'))
          .toList();

  /// Every identifier a source file binds to a `ConstellationAnchorCase`.
  Set<String> anchorCaseNames(String source) {
    final names = <String>{};
    for (final pattern in [
      // Fields, parameters, locals and `late` declarations with that type.
      RegExp(r'ConstellationAnchorCase\??\s+([A-Za-z_]\w*)'),
      // Locals initialised by the constructor or by any lookup expression
      // (`getIt<T>()`, `GetIt.I.get<T>()`, `context.read<T>()`, ...).
      RegExp(
        r'([A-Za-z_]\w*)\s*=\s*(?:await\s+)?'
        r'(?:ConstellationAnchorCase\s*\(|'
        r'[^;=]*?<\s*ConstellationAnchorCase\s*>\s*\()',
      ),
      // Any identifier that names itself an anchor case.
      RegExp(r'(?<!\w)(\w*[aA]nchorCase\w*)(?=\s*[!?.,;:)=])'),
    ]) {
      for (final match in pattern.allMatches(source)) {
        names.add(match.group(1)!);
      }
    }
    return names;
  }

  /// `receiver.write(` calls where the receiver is typed as an anchor case.
  List<String> anchorCaseWriteCallsIn(String rawSource, String path) {
    final source = withoutComments(rawSource);
    if (!source.contains('AnchorCase') && !source.contains('anchorCase')) {
      return const [];
    }
    final names = anchorCaseNames(source);
    final receivers = [
      ...names.map((name) => '(?<!\\w)${RegExp.escape(name)}'),
      r'<\s*ConstellationAnchorCase\s*>\s*\(\s*\)',
    ].join('|');
    final call = RegExp(
      '(?:$receivers)\\s*[!?]?\\s*\\??\\.\\.?\\s*'
      '($writeAlternation)\\s*(?:<[^>(]*>)?\\s*\\(',
    );
    final lines = source.split('\n');
    final offenders = <String>[];
    // Calls may wrap after the receiver, so match on the whole text and map
    // the offset back to a line number.
    for (final match in call.allMatches(source)) {
      final line = '\n'.allMatches(source.substring(0, match.start)).length;
      offenders.add('$path:${line + 1}: ${lines[line].trim()}');
    }
    return offenders;
  }

  List<String> anchorCaseWriteCalls(File file) =>
      anchorCaseWriteCallsIn(file.readAsStringSync(), file.path);

  group('ConstellationAnchorCase has no placement write API', () {
    test('declares no upsert, delete or place member of any signature', () {
      final source = withoutComments(anchorCaseFile.readAsStringSync());
      // Name only, so a void, synchronous or nested-generic return type cannot
      // slip past; a private `_upsert(` counts as a write member too, while
      // the cache-maintenance helpers (_upsertConfirmedAnchor) carry other
      // names.
      final member = RegExp(
        '(?<![\\w.])_?($writeAlternation)\\s*(?:<[^>(]*>)?\\s*\\(',
      );
      expect(member.allMatches(source).map((m) => m.group(1)), isEmpty);
    });

    test('does not forward a write to the anchor repository either', () {
      final source = withoutComments(anchorCaseFile.readAsStringSync());
      final forwarded = RegExp(
        '\\.\\s*($writeAlternation)\\s*(?:<[^>(]*>)?\\s*\\(',
      );
      expect(forwarded.allMatches(source).map((m) => m.group(1)), isEmpty);
    });

    test('no client production code calls a write method on it', () {
      final offenders = [
        for (final file in dartFiles('lib')) ...anchorCaseWriteCalls(file),
      ];
      expect(offenders, isEmpty);
    });

    test('no test calls a write method on it', () {
      final offenders = [
        for (final file
            in Directory('${packageRoot}test')
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.endsWith('.dart'))
                .where(
                  (f) => !f.path.endsWith(
                    'constellation_anchor_case_read_only_test.dart',
                  ),
                ))
          ...anchorCaseWriteCalls(file),
      ];
      expect(
        offenders,
        isEmpty,
        reason:
            'Tests that only covered the removed write half are deleted, or '
            'migrated to ConstellationPlacementCase tests',
      );
    });

    test('the detector flags the call shapes it must recognise', () {
      const probe = '''
final ConstellationAnchorCase? _anchors;
Future<void> f(ConstellationAnchorCase anchorCase) async {
  await anchorCase.upsert(target: t);
  await _anchors!.deleteAnchor(target: t);
  _anchors?.place(parent: t);
  GetIt.I<ConstellationAnchorCase>().upsertAll(parentTarget: t);
  final c = ConstellationAnchorCase(a, b);
  c
    .delete(target: t);
  final d = getIt.get<ConstellationAnchorCase>();
  d.unpin(t);
  final placement = getIt.get<ConstellationPlacementCase>();
  placement.place(parent: t);
  anchorCase.confirmedProjection;
}
''';
      expect(anchorCaseWriteCallsIn(probe, 'probe.dart'), hasLength(6));
    });
  });

  group(
    'ConstellationCubit writes placements through ConstellationPlacementCase',
    () {
      late String source;
      late String placementReceiver;

      setUp(() {
        source = withoutComments(cubitFile.readAsStringSync());
        final declared = RegExp(
          r'ConstellationPlacementCase\??\s+(_?\w+)',
        ).firstMatch(source);
        placementReceiver = declared?.group(1) ?? '';
      });

      test('holds a ConstellationPlacementCase dependency', () {
        expect(
          placementReceiver,
          isNotEmpty,
          reason:
              'cubit needs a field or parameter typed ConstellationPlacementCase',
        );
      });

      test('moves a cluster through its place method', () {
        expect(placementReceiver, isNotEmpty);
        expect(
          RegExp(
            '(?<!\\w)${RegExp.escape(placementReceiver)}\\s*[!?]?\\.\\s*place\\s*\\(',
          ).hasMatch(source),
          isTrue,
        );
      });

      test('removes a pin through its unpin method', () {
        expect(placementReceiver, isNotEmpty);
        expect(
          RegExp(
            '(?<!\\w)${RegExp.escape(placementReceiver)}\\s*[!?]?\\.\\s*unpin\\s*\\(',
          ).hasMatch(source),
          isTrue,
        );
      });

      test('issues no upsert or delete on any receiver', () {
        final legacy = RegExp(
          r'\.\s*(upsert|upsertAll|deleteAnchor|delete)\s*(?:<[^>(]*>)?\s*\(',
        );
        expect(legacy.allMatches(source).map((m) => m.group(1)), isEmpty);
      });
    },
  );

  group('Constellation screen supplies the placement case', () {
    test('resolves ConstellationPlacementCase from the service locator', () {
      final screen = File(
        '${packageRoot}lib/features/constellation/ui/screen/'
        'constellation_screen.dart',
      );
      expect(
        RegExp(
          r'<\s*ConstellationPlacementCase\s*>\s*\(',
        ).hasMatch(withoutComments(screen.readAsStringSync())),
        isTrue,
        reason: 'any lookup form is fine, as long as the screen resolves it',
      );
    });
  });

  group('Placement case tests carry the migrated write behaviour', () {
    final placementCaseTests = File(
      '${packageRoot}test/features/constellation/'
      'constellation_placement_case_test.dart',
    ).readAsStringSync();

    test('cover placing a whole cluster in one write', () {
      expect(
        placementCaseTests,
        contains("'one place applies its entire cluster"),
      );
    });

    test('cover unpinning a target as a delete', () {
      expect(
        placementCaseTests,
        contains("'unpin settles a delete through apply"),
      );
    });
  });
}
