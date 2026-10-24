// Fixture replay uses the workspace's transitive analyzer and test dependencies.

import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:test/test.dart';

/// Last commit before the resumable layout job (U37) touched placement. The
/// oracle replays fixtures against the placement code frozen at this explicit
/// revision, not against whatever main or the working tree currently holds.
/// No deterministic difference from it is approved: geometry must be identical.
const frozenLayoutRevision = '5b8493621d3934eca8059b23197a01029123d952';

const _frozenFixtureDirectory =
    'packages/client/test/features/constellation/fixtures/legacy_layout/'
    '$frozenLayoutRevision';

String _frozenSource(Directory root, String name) => File(
  '${root.path}/$_frozenFixtureDirectory/$name.dart.txt',
).readAsStringSync();

const existingLayoutFixtureFiles = {
  'constellation_layout_test.dart',
  'constellation_layout_positions_pinned_test.dart',
  'constellation_p06_composition_layout_test.dart',
  'constellation_layout_positional_stability_test.dart',
  'constellation_post_projection_test.dart',
  'constellation_field_membership_v2_test.dart',
};

/// Replays the existing fixtures rather than maintaining a second set of inputs.
/// Only temporary copies change: layout calls record their inputs, test/group
/// registration runs fixture bodies, and Flutter's matchers use package:test.
/// All original assertions remain in the copies and in the untouched originals.
({Uri library, Set<String> sites}) writeExistingLayoutFixtureReplay(
  Directory root,
  Directory temporary,
) {
  final fixtureDirectory = Directory(
    '${root.path}/packages/client/test/features/constellation',
  );
  final placedFixtureFiles = {
    for (final file
        in fixtureDirectory.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('_test.dart') &&
          !file.path.endsWith('/constellation_layout_job_test.dart') &&
          RegExp(
            r'\bcomputeConstellationPlacedLayout\s*\(',
          ).hasMatch(file.readAsStringSync()))
        file.uri.pathSegments.last,
  };
  expect(
    existingLayoutFixtureFiles,
    containsAll(placedFixtureFiles),
    reason: 'Every existing placed-layout fixture file must join the oracle.',
  );

  // Checked-in pre-task placement works without Git history in shallow CI
  // checkouts. Imports point at live package files this task did not change.
  final frozenRadial =
      File('${temporary.path}/frozen_radial_hop_positions.dart')
        ..writeAsStringSync(
          _frozenSource(root, 'radial_hop_positions'),
        );
  const constellationDomain = 'package:tentura/features/constellation/domain';
  final frozenLayout = File('${temporary.path}/frozen_constellation_layout.dart')
    ..writeAsStringSync(
      _frozenSource(root, 'constellation_layout')
          .replaceFirst(
            "'package:tentura/features/graph/domain/layout/radial_hop_positions.dart'",
            "'${frozenRadial.uri}'",
          )
          .replaceFirst(
            "'constellation_anchor_composition.dart'",
            "'$constellationDomain/constellation_anchor_composition.dart'",
          )
          .replaceFirst(
            "'constellation_consts.dart'",
            "'$constellationDomain/constellation_consts.dart'",
          )
          .replaceFirst(
            "'layout/layout_geometry.dart'",
            "'$constellationDomain/layout/layout_geometry.dart'",
          ),
    );
  final recorder = File('${temporary.path}/fixture_recorder.dart')
    ..writeAsStringSync(
      _fixtureRecorder.replaceFirst('{{frozenLayout}}', '${frozenLayout.uri}'),
    );
  final imports = <String>[];
  final calls = <String>[];
  final sites = <String>{};
  var index = 0;
  for (final name in existingLayoutFixtureFiles) {
    final file = File('${fixtureDirectory.path}/$name');
    final source = file.readAsStringSync();
    final parsed = parseString(content: source, path: file.path);
    final edits = <_SourceEdit>[];
    for (final directive
        in parsed.unit.directives.whereType<ImportDirective>()) {
      final uri = directive.uri.stringValue!;
      if (uri == 'package:flutter_test/flutter_test.dart') {
        edits.add(
          _SourceEdit(
            directive.offset,
            directive.length,
            "import 'package:test/test.dart' hide expect, group, test;",
          ),
        );
      } else if (name == 'constellation_post_projection_test.dart' &&
          (uri.startsWith('package:ferry/') ||
              uri.startsWith('package:gql_exec/') ||
              uri.startsWith('package:tentura/data/') ||
              uri.startsWith('package:tentura/features/graph/') ||
              uri.contains('/data/'))) {
        edits.add(_SourceEdit(directive.offset, directive.length, ''));
      } else if (!uri.contains(':')) {
        edits.add(
          _SourceEdit(
            directive.uri.offset,
            directive.uri.length,
            "'${file.uri.resolve(uri)}'",
          ),
        );
      }
    }
    if (name == 'constellation_post_projection_test.dart') {
      // The wire-mapping test has no layout input and needs Flutter networking.
      // Keep every composition/layout fixture and its assertions verbatim.
      final fakeLink = parsed.unit.declarations
          .whereType<ClassDeclaration>()
          .singleWhere(
            (declaration) =>
                declaration.namePart.typeName.lexeme == '_FakeLink',
          );
      edits.add(_SourceEdit(fakeLink.offset, fakeLink.length, ''));
      final main = parsed.unit.declarations
          .whereType<FunctionDeclaration>()
          .singleWhere((declaration) => declaration.name.lexeme == 'main');
      final body = main.functionExpression.body as BlockFunctionBody;
      final wireGroup = body.block.statements.first;
      expect(wireGroup.toSource(), startsWith("group('Post wire mapping'"));
      edits.add(_SourceEdit(wireGroup.offset, wireGroup.length, ''));
      // FieldBeaconNode lives in a Flutter-dependent library and only
      // exercises labels and status markers, never layout.
      final nodeGroup = body.block.statements.singleWhere(
        (statement) =>
            statement.toSource().startsWith("group('FieldBeaconNode'"),
      );
      edits.add(_SourceEdit(nodeGroup.offset, nodeGroup.length, ''));
    }
    parsed.unit.accept(
      _LayoutCallRecorder(name, parsed.lineInfo, edits, sites),
    );
    edits.sort((a, b) => b.offset.compareTo(a.offset));
    var rewritten = source;
    for (final edit in edits) {
      rewritten = rewritten.replaceRange(
        edit.offset,
        edit.offset + edit.length,
        edit.replacement,
      );
    }
    // The plain Dart front end crashes on a const value under a null-aware map
    // key; the equivalent conditional entry compiles.
    rewritten = rewritten.replaceAllMapped(
      RegExp(r'^(\s*)\?(\w+):', multiLine: true),
      (match) => '${match[1]}if (${match[2]} != null) ${match[2]}:',
    );
    final copy = File('${temporary.path}/existing_fixture_$index.dart')
      ..writeAsStringSync(
        "import '${recorder.uri}' as recording;\n"
        "import '${recorder.uri}' show Offset, expect, group, test;\n$rewritten",
      );
    imports.add("import '${copy.uri}' as fixture$index;");
    calls.add("recording.sourceFile = '$name'; fixture$index.main();");
    index++;
  }
  final library = File('${temporary.path}/existing_layout_fixtures.dart')
    ..writeAsStringSync('''
import '${recorder.uri}' as recording;
${imports.join('\n')}
void replayExistingLayoutFixtures(recording.LayoutObserver observer) {
  recording.onLayout = observer;
  ${calls.join('\n')}
}
''');
  return (library: library.uri, sites: sites);
}

final class _SourceEdit {
  const _SourceEdit(this.offset, this.length, this.replacement);
  final int offset;
  final int length;
  final String replacement;
}

final class _LayoutCallRecorder extends RecursiveAstVisitor<void> {
  _LayoutCallRecorder(this.file, this.lines, this.edits, this.sites);
  final String file;
  final LineInfo lines;
  final List<_SourceEdit> edits;
  final Set<String> sites;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final replacement = switch (node.methodName.name) {
      'computeConstellationPlacedLayout' => 'recording.capturePlaced',
      'computeConstellationLayout' => 'recording.captureLayout',
      _ => null,
    };
    if (replacement != null) {
      final site = '$file:${lines.getLocation(node.offset).lineNumber}';
      sites.add(site);
      edits
        ..add(
          _SourceEdit(
            node.methodName.offset,
            node.methodName.length,
            replacement,
          ),
        )
        ..add(
          _SourceEdit(
            node.argumentList.leftParenthesis.end,
            0,
            "site: '$site', ",
          ),
        );
    }
    super.visitMethodInvocation(node);
  }
}

const _fixtureRecorder = r'''
import 'package:matcher/matcher.dart' show StringDescription, wrapMatcher;
import '{{frozenLayout}}' as frozen;
import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';

typedef LayoutObserver = void Function(String fixture, String site,
    ConstellationPlacedLayoutInput input, ConstellationLayout legacy);
late LayoutObserver onLayout;

// Stand-in for dart:ui's Offset, which the plain Dart VM cannot import.
class Offset {
  const Offset(this.dx, this.dy);
  final double dx;
  final double dy;
}
late String sourceFile;
final _groups = <String>[];
String _testName = '';
int _call = 0;

void group(String description, void Function() body) {
  _groups.add(description);
  try { body(); } finally { _groups.removeLast(); }
}

// package:test's expect needs a running test; fixture bodies run here directly.
void expect(dynamic actual, dynamic matcher, {String? reason}) {
  final wrapped = wrapMatcher(matcher);
  final state = <dynamic, dynamic>{};
  if (wrapped.matches(actual, state)) return;
  final description = StringDescription();
  wrapped.describe(description);
  final mismatch = StringDescription();
  wrapped.describeMismatch(actual, mismatch, state, false);
  throw StateError('Expected: $description Actual: $actual $mismatch '
      '${reason ?? ''} in $_testName');
}

void test(String description, Function body) {
  _testName = '$sourceFile/${[..._groups, description].join('/')}';
  _call = 0;
  final result = Function.apply(body, const []);
  if (result is Future) throw StateError('Layout fixtures must be synchronous');
}

ConstellationLayout capturePlaced({
  required String site,
  required ConstellationPlacedLayoutInput input,
  double ringGap = kConstellationRingUnitPixels,
  double residualRingFactor = 1.6,
  double satelliteOffset = 56,
}) {
  if (ringGap != kConstellationRingUnitPixels || residualRingFactor != 1.6 ||
      satelliteOffset != 56) {
    throw StateError('A fixture needs layout parameters outside LayoutInput: $site');
  }
  final legacy = frozen.computeConstellationPlacedLayout(input: input,
      ringGap: ringGap, residualRingFactor: residualRingFactor,
      satelliteOffset: satelliteOffset);
  onLayout('$_testName/${_call++}', site, input, legacy);
  return legacy;
}

// Identical input adaptation to the production computeConstellationLayout
// convenience function; the placement itself always calls the frozen oracle.
ConstellationLayout captureLayout({
  required String site,
  required String egoId,
  required ConstellationPathResolution paths,
  required Set<String> keptPeerIds,
  required Map<String, List<String>> visibleRequestsByAuthor,
  required Set<String> egoOwnRequestIds,
  int maxHops = 3,
  double ringGap = kConstellationRingUnitPixels,
  double residualRingFactor = 1.6,
  double satelliteOffset = 56,
  Map<String, ConstellationSize> nodeSizes = const {},
  double spacing = 16,
  Set<String> pinnedPersonIds = const {},
  Set<String> pinnedRequestIds = const {},
  Set<String> supportPersonIds = const {},
  Map<String, ConstellationAnchorPosition> anchorByNodeId = const {},
  ConstellationLayoutPriorHints? priorHints,
  ConstellationViewportClass viewportClass = ConstellationViewportClass.expanded,
}) => capturePlaced(site: site, input: (
  egoId: egoId, paths: paths, automaticKeptPeerIds: keptPeerIds,
  pinnedPersonIds: pinnedPersonIds, pinnedRequestIds: pinnedRequestIds,
  supportPersonIds: supportPersonIds, anchorByNodeId: anchorByNodeId,
  priorHints: priorHints, nodeSizes: nodeSizes,
  satelliteRequestIdsByAuthor: visibleRequestsByAuthor,
  requestAuthorById: const {}, egoOwnRequestIds: egoOwnRequestIds,
  spacing: spacing, maxHops: maxHops, viewportClass: viewportClass,
  footprints: const {},
), ringGap: ringGap, residualRingFactor: residualRingFactor,
  satelliteOffset: satelliteOffset);
''';
