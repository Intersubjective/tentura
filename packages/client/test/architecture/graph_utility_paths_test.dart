@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _client = 'packages/client';
const _graph = '$_client/lib/features/graph';
const _legacyFolder = 'utils';
const _oldReference = 'graph/ui/$_legacyFolder';
const _newReference = 'graph/ui/util';
const _oldRelative = '../$_legacyFolder/';
const _newRelative = '../util/';
const _oldDirectory = '$_graph/ui/$_legacyFolder';
const _newDirectory = '$_graph/ui/util';
const _constellationUi = '$_client/lib/features/constellation/ui';
const _constellationUtilities = '$_constellationUi/utils';
const _constellationScene =
    '$_constellationUtilities/constellation_graph_scene.dart';
const _testPath = '$_client/test/architecture/graph_utility_paths_test.dart';
// Pre-move digests let a depth-one checkout check the original bytes.
const _originalDigests = {
  'animated_highlighted_edge_painter.dart':
      '0ec6d7929548907e4c9f19a0daf8b263c04ff8fcec4aef842da08a37d5858fa6',
  'ease_in_out_reynolds.dart':
      '140caa77beeb258ed6679a31687f07b5ef2ed0ca46af7b63c2a08a67e50a7c7f',
  'graph_edge_stroke.dart':
      'd2b118c9767782b82bdbf6963a77541b964e7da0472705e231340bd9d8a2045e',
  'graph_edge_style.dart':
      '8d97b99190c077725397d88eade4939100da64961450edc60e8bd5dde04c097c',
  'graph_scene_ids.dart':
      '4cd03247ed4563d8e8a30076f56bf55cdf62ebdb45a7f0f493a211dbe00aabdb',
  'tentura_layout_algorithms.dart':
      '5b77a9fd00b22eff978eb1f908c5cec4dd475d3d846e7d65302c6f22238eeb27',
};
final _files = _originalDigests.keys;
const _packageUtil = 'package:tentura/features/$_newReference';
const _relativeUtil = '../../../$_newReference';
const _sceneIds = 'graph_scene_ids.dart';
const _layoutAlgorithms = 'tentura_layout_algorithms.dart';
const _expectedImports = {
  '$_graph/ui/bloc/graph_cubit.dart': {
    '${_newRelative}graph_edge_style.dart',
    '$_newRelative$_sceneIds',
  },
  '$_graph/ui/widget/graph_body.dart': {
    '${_newRelative}animated_highlighted_edge_painter.dart',
    '${_newRelative}ease_in_out_reynolds.dart',
    '$_newRelative$_layoutAlgorithms',
  },
  '$_graph/ui/widget/graph_legend_content.dart': {
    '${_newRelative}graph_edge_style.dart',
  },
  '$_graph/ui/widget/graph_legend_edge_swatch.dart': {
    '${_newRelative}graph_edge_stroke.dart',
    '${_newRelative}graph_edge_style.dart',
  },
  '$_constellationUi/bloc/constellation_cubit.dart': {
    '$_relativeUtil/$_sceneIds',
    '$_relativeUtil/$_layoutAlgorithms',
  },
  '$_constellationUi/scene/constellation_interaction_controller.dart': {
    '$_relativeUtil/$_sceneIds',
  },
  '$_constellationUi/scene/constellation_magnet_layout.dart': {
    '$_packageUtil/$_sceneIds',
  },
  '$_constellationUi/scene/constellation_scene_controller.dart': {
    '$_relativeUtil/$_sceneIds',
    '$_relativeUtil/$_layoutAlgorithms',
  },
  _constellationScene: {'$_relativeUtil/$_sceneIds'},
  '$_constellationUi/widget/constellation_viewport_overlay.dart': {
    '$_packageUtil/$_sceneIds',
  },
};

final _repository = Directory.current.parent.parent;

Future<String> _git(
  List<String> args, {
  Map<String, String>? environment,
  bool allowNoMatches = false,
}) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: _repository.path,
    stdoutEncoding: latin1,
    environment: environment,
  );
  expect(
    result.exitCode,
    allowNoMatches ? anyOf(0, 1) : 0,
    reason: 'git ${args.join(' ')}\n${result.stderr}',
  );
  return result.stdout as String;
}

Iterable<String> _fields(String output) =>
    output.split('\u0000').where((field) => field.isNotEmpty);

File _file(String path) => File.fromUri(_repository.uri.resolve(path));

Future<Set<String>> _references(
  String text, {
  String? revision,
  List<String> roots = const [],
}) async {
  // An empty pathspec searches all tracked files from the repository root.
  final output = await _git([
    'grep',
    '-l',
    '-z',
    '-F',
    '-e',
    text,
    ?revision,
    '--',
    ...roots,
  ], allowNoMatches: true);
  return {
    for (final field in _fields(output))
      if (revision == null) field else field.substring(revision.length + 1),
  };
}

Iterable<String> _importUris(String path) sync* {
  final imports = parseString(
    content: _file(path).readAsStringSync(),
    path: path,
  ).unit.directives.whereType<ImportDirective>();
  for (final directive in imports) {
    for (final literal in [
      directive.uri,
      ...directive.configurations.map((c) => c.uri),
    ]) {
      final uri = literal.stringValue;
      if (uri != null) yield uri;
    }
  }
}

String? _graphUtilityTarget(String importer, String uri) {
  const package = 'package:tentura/';
  final reference = Uri.parse(uri);
  final target = uri.startsWith(package)
      ? '/$_client/lib/${uri.substring(package.length)}'
      : Uri(path: '/$importer').resolveUri(reference).path;
  if (target.startsWith('/$_newDirectory/') ||
      target.startsWith('/$_oldDirectory/')) {
    return target.substring(1);
  }
  return null;
}

Future<List<String>> _graphUriDiagnostics(Set<String> importers) async {
  final packageConfig =
      jsonDecode(
            _file('.dart_tool/package_config.json').readAsStringSync(),
          )
          as Map<String, Object?>;
  final flutterRoot = Uri.parse(packageConfig['flutterRoot']! as String);
  final collection = AnalysisContextCollection(
    includedPaths: [_file(_client).path],
    sdkPath: '${flutterRoot.toFilePath()}/bin/cache/dart-sdk',
  );
  try {
    final problems = <String>[];
    for (final importer in importers) {
      final path = _file(importer).path;
      final result = await collection
          .contextFor(path)
          .currentSession
          .getErrors(path);
      expect(result, isA<ErrorsResult>(), reason: importer);
      for (final diagnostic in (result as ErrorsResult).diagnostics) {
        final message = diagnostic.message;
        if (diagnostic.diagnosticCode.lowerCaseName == 'uri_does_not_exist' &&
            (message.contains(_oldReference) ||
                message.contains(_newReference) ||
                (importer.startsWith('$_graph/') &&
                    (message.contains(_oldRelative) ||
                        message.contains(_newRelative))))) {
          problems.add('$importer: $message');
        }
      }
    }
    return problems;
  } finally {
    await collection.dispose();
  }
}

Future<void> _auditMove(
  String base,
  String landing,
  Map<String, String>? environment,
) async {
  final layout = landing.isEmpty
      ? _fields(
          await _git([
            'ls-files',
            '-z',
            '--',
            _oldDirectory,
            _newDirectory,
            _constellationUtilities,
          ], environment: environment),
        ).toSet()
      : _fields(
          await _git([
            'ls-tree',
            '-r',
            '--name-only',
            '-z',
            landing,
            '--',
            _oldDirectory,
            _newDirectory,
            _constellationUtilities,
          ]),
        ).toSet();
  final moves = {
    for (final name in _files) '$_oldDirectory/$name': '$_newDirectory/$name',
  };
  final references = {
    ...await _references(_oldReference, revision: base),
    ...await _references(_oldRelative, revision: base, roots: [_graph]),
  }..removeAll(moves.keys);
  expect(
    references,
    containsAll([
      '$_graph/ui/bloc/graph_cubit.dart',
      '$_graph/ui/widget/graph_body.dart',
      '$_graph/ui/widget/graph_legend_content.dart',
      '$_graph/ui/widget/graph_legend_edge_swatch.dart',
      '$_client/lib/features/constellation/ui/bloc/constellation_cubit.dart',
      '$_client/lib/features/constellation/ui/scene/constellation_interaction_controller.dart',
      '$_client/lib/features/constellation/ui/scene/constellation_magnet_layout.dart',
      '$_client/lib/features/constellation/ui/scene/constellation_scene_controller.dart',
      _constellationScene,
      '$_client/lib/features/constellation/ui/widget/constellation_viewport_overlay.dart',
      '$_client/test/features/graph/graph_edge_style_test.dart',
      '$_client/test/features/constellation/constellation_scene_layout_test.dart',
      '$_client/test/graph_controller_test.dart',
      'scripts/analyze-baseline-inventory.tsv',
    ]),
    reason:
        'The comparison covers graph, Constellation, tests and the analyzer inventory',
  );

  final diff = _fields(
    await _git([
      'diff',
      '-M100%',
      '--name-status',
      '-z',
      if (landing.isEmpty) '--cached',
      base,
      if (landing.isNotEmpty) landing,
      '--',
      '.',
      ':(exclude)$_testPath',
    ], environment: environment),
  ).toList();
  final renames = <String, String>{};
  final modifications = <String>{};
  final otherChanges = <String>[];
  for (var i = 0; i < diff.length;) {
    final status = diff[i++];
    final path = diff[i++];
    if (status == 'R100') {
      renames[path] = diff[i++];
    } else if (status == 'M') {
      modifications.add(path);
    } else {
      otherChanges.add('$status $path');
    }
  }
  expect(renames, moves, reason: 'Git must report all six moves as R100');
  expect(
    otherChanges,
    isEmpty,
    reason: 'Only moves and reference edits belong in the diff',
  );
  expect(
    modifications,
    references,
    reason: 'Only files with obsolete references change',
  );
  expect(layout.where((path) => path.startsWith('$_oldDirectory/')), isEmpty);
  expect(
    layout.where((path) => path.startsWith('$_newDirectory/')),
    unorderedEquals(moves.values),
  );
  expect(
    layout,
    contains(_constellationScene),
    reason: 'The Constellation scene keeps its own utility path',
  );

  final unexpectedContents = <String>[];
  for (final path in references) {
    final original = await _git(['show', '$base:$path']);
    final revised = landing.isEmpty
        ? _file(path).readAsStringSync(encoding: latin1)
        : await _git(['show', '$landing:$path']);
    var expected = original.replaceAll(_oldReference, _newReference);
    if (path.startsWith('$_graph/')) {
      expected = expected.replaceAll(_oldRelative, _newRelative);
    }
    if (revised != expected) unexpectedContents.add(path);
  }
  expect(
    unexpectedContents,
    isEmpty,
    reason: 'Imports, docs and inventory differ only by the graph path',
  );
}

Future<void> _auditWorktree() async {
  final index = (await _git([
    'rev-parse',
    '--path-format=absolute',
    '--git-path',
    'index',
  ])).trim();
  final objects = (await _git([
    'rev-parse',
    '--path-format=absolute',
    '--git-path',
    'objects',
  ])).trim();
  final scratch = await Directory.systemTemp.createTemp('graph-utility-move-');
  try {
    final scratchIndex = '${scratch.path}/index';
    final scratchObjects = await Directory('${scratch.path}/objects').create();
    await File(index).copy(scratchIndex);
    final environment = {
      'GIT_INDEX_FILE': scratchIndex,
      'GIT_OBJECT_DIRECTORY': scratchObjects.path,
      'GIT_ALTERNATE_OBJECT_DIRECTORIES': objects,
    };
    // Refresh tracked files and include untracked graph utility destinations.
    // Other untracked files do not belong to the candidate patch.
    await _git(['add', '-u', '--', '.'], environment: environment);
    final destinations = [
      for (final name in _files)
        if (_file('$_newDirectory/$name').existsSync()) '$_newDirectory/$name',
    ];
    if (destinations.isNotEmpty) {
      await _git(['add', '--', ...destinations], environment: environment);
    }
    await _auditMove('HEAD', '', environment);
  } finally {
    await scratch.delete(recursive: true);
  }
}

void main() {
  test('all six graph utilities live in the singular directory', () async {
    final paths = _fields(
      await _git([
        'ls-files',
        '-z',
        '--cached',
        '--others',
        '--exclude-standard',
        '--',
        _oldDirectory,
        _newDirectory,
        _constellationScene,
      ]),
    ).where((path) => _file(path).existsSync()).toSet();
    expect(
      {
        'tracked or pending paths': paths,
        'legacy directory exists': Directory.fromUri(
          _repository.uri.resolve(_oldDirectory),
        ).existsSync(),
      },
      {
        'tracked or pending paths': {
          for (final name in _files) '$_newDirectory/$name',
          _constellationScene,
        },
        'legacy directory exists': false,
      },
    );
    expect(
      _fields(await _git(['ls-files', '-z', '--', _constellationScene])),
      [_constellationScene],
    );
  });

  test(
    'graph utility imports resolve and repository references use the singular path',
    () async {
      final stale = {
        ...await _references(_oldReference),
        ...await _references(_oldRelative, roots: [_graph]),
      };
      final importers = {
        ...stale,
        ...await _references(_newReference),
        ...await _references(_newRelative, roots: [_graph]),
        ..._expectedImports.keys,
      }.where((path) => path.endsWith('.dart') && path != _testPath).toSet();
      final wrongImports = <String>[];
      for (final path in importers) {
        final graphImports = _importUris(
          path,
        ).where((uri) => _graphUtilityTarget(path, uri) != null).toSet();
        final expected = _expectedImports[path];
        if (expected != null && !expected.every(graphImports.contains)) {
          wrongImports.add('$path: expected $expected, found $graphImports');
        }
        if (path.startsWith('$_client/test/')) {
          for (final uri in graphImports.where(
            (uri) => !uri.startsWith('package:tentura/'),
          )) {
            wrongImports.add('$path: expected a package import for $uri');
          }
        }
      }
      final diagnostics = await _graphUriDiagnostics(importers);
      expect(
        {
          'obsolete references': stale.toList(),
          'changed import forms': wrongImports,
          'unresolved imports': diagnostics,
        },
        {
          'obsolete references': isEmpty,
          'changed import forms': isEmpty,
          'unresolved imports': isEmpty,
        },
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'Git records a byte-preserving graph move with only path edits',
    () async {
      final landing = (await _git([
        'log',
        '-1',
        '--format=%H',
        '--diff-filter=D',
        '--no-renames',
        'HEAD',
        '--',
        '$_oldDirectory/${_files.first}',
      ])).trim();
      if (landing.isNotEmpty) {
        await _auditMove('$landing^', landing, null);
      } else {
        final oldFiles = _fields(
          await _git([
            'ls-tree',
            '-r',
            '--name-only',
            '-z',
            'HEAD',
            '--',
            _oldDirectory,
          ]),
        ).toList();
        if (oldFiles.isNotEmpty) {
          expect(
            oldFiles,
            unorderedEquals(_files.map((name) => '$_oldDirectory/$name')),
          );
          await _auditWorktree();
        } else {
          expect(
            (await _git(['rev-parse', '--is-shallow-repository'])).trim(),
            'true',
            reason: 'A full checkout must expose the graph rename commit',
          );
          // A depth-one clone has no parent tree to diff. Check the new
          // files against the original bytes recorded before the move.
          final digests = {
            for (final name in _files)
              if (_file('$_newDirectory/$name').existsSync())
                name: sha256
                    .convert(_file('$_newDirectory/$name').readAsBytesSync())
                    .toString(),
          };
          expect(digests, _originalDigests);
          expect(await _git(['ls-files', '--', _oldDirectory]), isEmpty);
        }
      }
    },
  );
}
