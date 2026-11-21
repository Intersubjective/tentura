@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _legacyFolder = 'utils';
const _oldDirectory = 'lib/ui/$_legacyFolder';
const _utilityDirectory = 'lib/ui/util';
const _tenturaPackage = 'package:tentura/';
const _clientPath = 'packages/client/';
const _oldPackagePath = '${_tenturaPackage}ui/$_legacyFolder/';
const _verificationTest =
    '${_clientPath}test/architecture/shared_ui_utility_paths_test.dart';
const _preMoveRevision = '145afa4ad0bc5a142b672041c08b1e7e2e26dbc0';
const _hudFile = 'beacon_hud_now_display.dart';
const _utilityFiles = {
  'app_reload.dart',
  'app_reload_stub.dart',
  'app_reload_web.dart',
  'availability_line.dart',
  'beacon_activity_event_presenter.dart',
  'beacon_card_deadline.dart',
  'beacon_location_actions.dart',
  'beacon_schedule_presenter.dart',
  'beacon_you_presentation.dart',
  'calendar_day_display.dart',
  'capability_tag_presenter.dart',
  'code_unit_length_formatter.dart',
  'copy_text_to_clipboard.dart',
  'duration_format.dart',
  'frame_slice_scheduler.dart',
  'plain_text_preview.dart',
  'post_expiry_clock.dart',
  'profile_member_since.dart',
  'profile_presence_line.dart',
  'rearrange_preview_scheduler.dart',
  'relative_time.dart',
  'schedule_date_format.dart',
  'snack_bar_clearance.dart',
  'string_input_validator.dart',
  'tentura_id_input_formatter.dart',
  'ui_utils.dart',
  'withdraw_reason_label.dart',
  _hudFile,
};

final _generatedDartFile = RegExp(r'\.(g|freezed|gr|config|schema)\.dart$');
final _bareOldPath = RegExp(
  r'(?<![\w./-])ui/'
  '$_legacyFolder'
  r'\b',
);
final _oldDirectoryMention = RegExp(
  '$_oldDirectory'
  r'\b',
);

Iterable<File> _dartSources(String directory) => Directory(directory)
    .listSync(recursive: true, followLinks: false)
    .whereType<File>()
    .where(
      (file) =>
          file.path.endsWith('.dart') &&
          !_generatedDartFile.hasMatch(file.path) &&
          !file.uri.pathSegments.contains('_g'),
    );

Iterable<StringLiteral> _uriLiterals(Directive directive) sync* {
  if (directive case UriBasedDirective(:final uri)) {
    yield uri;
  }
  if (directive case PartOfDirective(:final StringLiteral uri)) {
    yield uri;
  }
  if (directive case NamespaceDirective(:final configurations)) {
    for (final configuration in configurations) {
      yield configuration.uri;
    }
  }
}

Iterable<String> _directiveUris(Directive directive) =>
    _uriLiterals(directive).map((uri) => uri.stringValue).nonNulls;

String _rewritePathMentions(String text) => text
    .replaceAll(_oldDirectoryMention, _utilityDirectory)
    .replaceAll(_oldPackagePath, '${_tenturaPackage}ui/util/')
    .replaceAll(_bareOldPath, 'ui/util');

String _rewriteDirectiveUri(String uri, String sourcePath) {
  final reference = Uri.parse(uri);
  if (uri.startsWith(_oldPackagePath)) {
    return uri.replaceFirst(_oldPackagePath, '${_tenturaPackage}ui/util/');
  }
  if (reference.hasScheme) return uri;
  final target = Uri(path: '/$sourcePath').resolveUri(reference);
  if (!target.path.startsWith('/$_clientPath$_oldDirectory/')) return uri;
  return uri.replaceFirst(
    RegExp(
      '(^|(?<=/))'
      '$_legacyFolder'
      r'/(?=[^/]+$)',
    ),
    'util/',
  );
}

// Compare Dart tokens and comments so line wrapping by dart format is allowed,
// while declarations, expressions, strings and unrelated comments stay intact.
List<String> _dartContents(
  String source,
  String path, {
  bool rewrite = false,
  bool moved = false,
}) {
  final unit = parseString(
    content: source,
    path: path,
    throwIfDiagnostics: false,
  ).unit;
  final uriReplacements = <int, String>{};
  if (rewrite) {
    for (final literal in unit.directives.expand(_uriLiterals)) {
      final uri = literal.stringValue;
      if (uri == null) continue;
      final replacement = _rewriteDirectiveUri(uri, path);
      uriReplacements[literal.offset] = literal.beginToken.lexeme.replaceFirst(
        uri,
        replacement,
      );
    }
  }

  final contents = <String>[];
  for (var token = unit.beginToken; ; token = token.next!) {
    for (
      Token? comment = token.precedingComments;
      comment != null;
      comment = comment.next
    ) {
      contents.add(
        rewrite && !moved
            ? _rewritePathMentions(comment.lexeme)
            : comment.lexeme,
      );
    }
    if (token.isEof) return contents;
    contents.add(
      uriReplacements[token.offset] ??
          (rewrite && !moved && token.type == TokenType.STRING
              ? _rewritePathMentions(token.lexeme)
              : token.lexeme),
    );
  }
}

Future<String> _git(
  Directory repository,
  List<String> args, {
  Map<String, String>? environment,
}) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: repository.path,
    environment: environment,
  );
  expect(result.exitCode, 0, reason: 'git ${args.join(' ')}\n${result.stderr}');
  return result.stdout as String;
}

Future<String> _workingTreeRenameDiff(
  Directory repository,
  List<String> diffArgs,
  Iterable<String> destinations,
) async {
  final present = destinations
      .where((path) => File.fromUri(repository.uri.resolve(path)).existsSync())
      .toList();
  if (present.isEmpty) return _git(repository, diffArgs);

  final index = (await _git(repository, [
    'rev-parse',
    '--path-format=absolute',
    '--git-path',
    'index',
  ])).trim();
  final objects = (await _git(repository, [
    'rev-parse',
    '--path-format=absolute',
    '--git-path',
    'objects',
  ])).trim();
  final temporary = await Directory.systemTemp.createTemp(
    'shared-ui-utilities-',
  );
  try {
    final temporaryIndex = File.fromUri(temporary.uri.resolve('index')).path;
    await File(index).copy(temporaryIndex);
    final temporaryObjects = await Directory.fromUri(
      temporary.uri.resolve('objects/'),
    ).create();
    final environment = {
      'GIT_INDEX_FILE': temporaryIndex,
      'GIT_OBJECT_DIRECTORY': temporaryObjects.path,
      'GIT_ALTERNATE_OBJECT_DIRECTORIES': objects,
    };
    // Include the new paths in Git's rename detection before Alloy stages them.
    await _git(
      repository,
      ['add', '--intent-to-add', '--', ...present],
      environment: environment,
    );
    return await _git(repository, diffArgs, environment: environment);
  } finally {
    await temporary.delete(recursive: true);
  }
}

Future<List<String>> _utilityMoveDiff(
  Directory repository, {
  required String base,
  required String landing,
}) async {
  final diffArgs = [
    'diff',
    '-M',
    '--name-status',
    '-z',
    base,
    if (landing.isNotEmpty) landing,
    '--',
  ];
  final expectedMoves = {
    for (final name in _utilityFiles)
      if (name != _hudFile)
        '$_clientPath$_oldDirectory/$name':
            '$_clientPath$_utilityDirectory/$name',
  };
  final diff = landing.isEmpty
      ? await _workingTreeRenameDiff(repository, diffArgs, expectedMoves.values)
      : await _git(repository, diffArgs);
  final fields = diff.split('\u0000');
  final problems = <String>[];
  for (var i = 0; i < fields.length - 1;) {
    final status = fields[i++];
    final before = fields[i++];
    final isRename = status.startsWith('R');
    final after = isRename ? fields[i++] : before;
    if (!isRename && status == 'A' && after == _verificationTest) continue;
    if (isRename) {
      if (expectedMoves[before] != after) {
        problems.add('Unexpected rename $before → $after');
        continue;
      }
      expectedMoves.remove(before);
    } else if (status != 'M' ||
        !(after.startsWith(_clientPath) ||
            after == 'AGENTS.md' ||
            after.startsWith('.cursor/rules/') ||
            after.startsWith('docs/') ||
            after.startsWith('scripts/'))) {
      problems.add('Unexpected Git change $status $after');
      continue;
    }
    final isDart = before.startsWith(_clientPath) && before.endsWith('.dart');
    if (isDart &&
        (_generatedDartFile.hasMatch(before) ||
            before.split('/').contains('_g'))) {
      problems.add('Unexpected generated source change $after');
      continue;
    }
    final original = await _git(repository, ['show', '$base:$before']);
    final current = landing.isEmpty
        ? File.fromUri(repository.uri.resolve(after)).readAsStringSync()
        : await _git(repository, ['show', '$landing:$after']);
    final originalContents = isDart
        ? _dartContents(original, before)
        : original;
    final expectedContents = isDart
        ? _dartContents(original, before, rewrite: true, moved: isRename)
        : _rewritePathMentions(original);
    final currentContents = isDart ? _dartContents(current, after) : current;
    const equals = DeepCollectionEquality();
    if (!isRename && equals.equals(originalContents, expectedContents)) {
      problems.add('Changed file has no shared utility path to rewrite $after');
    } else if (!equals.equals(expectedContents, currentContents)) {
      problems.add('Changes exceed shared utility path rewrites in $after');
    }
  }
  for (final MapEntry(key: before, value: after) in expectedMoves.entries) {
    problems.add('Git does not report a rename $before → $after');
  }
  return problems;
}

CompilationUnit _parseSourceFile(String path) =>
    parseString(path: path, content: File(path).readAsStringSync()).unit;

class _SentryHelperRead extends RecursiveAstVisitor<void> {
  final paths = <String>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target case MethodInvocation(
      methodName: SimpleIdentifier(name: 'File'),
      argumentList: ArgumentList(:final arguments),
    ) when node.methodName.name == 'readAsStringSync') {
      if (arguments.singleOrNull case StringLiteral(:final stringValue?)) {
        if (stringValue.endsWith('/ui_utils.dart')) paths.add(stringValue);
      }
    }
    super.visitMethodInvocation(node);
  }
}

void main() {
  test(
    'Git records every shared utility rename and only shared path edits',
    () async {
      final repository = Directory.current.parent.parent;
      final history = await Process.run(
        'git',
        ['rev-parse', '--verify', '--quiet', '$_preMoveRevision^{commit}'],
        workingDirectory: repository.path,
      );
      if (history.exitCode == 1) {
        expect(
          (await _git(repository, [
            'rev-parse',
            '--is-shallow-repository',
          ])).trim(),
          'true',
          reason: 'The pre-move revision is required in a full checkout',
        );
        markTestSkipped(
          'The pre-move revision is outside the shallow checkout',
        );
        return;
      }
      expect(history.exitCode, 0, reason: history.stderr as String);

      // Inspect the landing commit after it exists, so later worktree edits
      // and commits do not enter the one-time rename comparison.
      final landing = (await _git(repository, [
        'log',
        '-1',
        '--format=%H',
        '--diff-filter=D',
        '--no-renames',
        '$_preMoveRevision..HEAD',
        '--',
        '$_clientPath$_oldDirectory/app_reload.dart',
      ])).trim();
      expect(
        await _utilityMoveDiff(
          repository,
          base: _preMoveRevision,
          landing: landing,
        ),
        isEmpty,
      );
    },
  );

  test(
    'shared UI utilities live together and preserve the existing HUD helper',
    () {
      final hud = File('$_utilityDirectory/$_hudFile');
      expect(hud.existsSync(), isTrue, reason: hud.path);
      expect(
        sha256.convert(hud.readAsBytesSync()).toString(),
        '416ab1e9d9f5701977cf44fa86aad8f084792bd9045c5b3d66513d3fe386e4c9',
        reason: 'The existing HUD helper has identical bytes after the move',
      );
      for (final importer in [
        'lib/features/beacon_threads/ui/widget/beacon_room_body.dart',
        'lib/features/beacon_view/ui/util/beacon_hud_derivation.dart',
        'lib/ui/widget/beacon_hud_metadata_composer.dart',
        'test/features/my_work/issue487_residuals_test.dart',
      ]) {
        final imports = parseString(
          content: File(importer).readAsStringSync(),
          path: importer,
        ).unit.directives.whereType<ImportDirective>();
        expect(
          imports.map((directive) => directive.uri.stringValue),
          contains('${_tenturaPackage}ui/util/$_hudFile'),
          reason: importer,
        );
      }

      final files = Directory(_utilityDirectory).listSync().whereType<File>();
      expect(
        {
          for (final file in files)
            if (file.path.endsWith('.dart')) file.uri.pathSegments.last,
        },
        unorderedEquals(_utilityFiles),
        reason: 'All shared helpers must be present under $_utilityDirectory',
      );
      expect(
        FileSystemEntity.typeSync(_oldDirectory),
        FileSystemEntityType.notFound,
      );
    },
  );

  test(
    'Dart directives resolve shared utility URIs under the singular path',
    () {
      final lib = Directory('lib').absolute.uri;
      final oldPath = Directory(_oldDirectory).absolute.uri.path;
      final newPath = Directory(_utilityDirectory).absolute.uri.path;
      final unresolved = <String>[];
      for (final directory in ['lib', 'test', 'integration_test']) {
        for (final file in _dartSources(directory)) {
          final source = file.readAsStringSync();
          if (!source.contains('utils/') && !source.contains('util/')) continue;
          final directives = parseString(
            content: source,
            path: file.path,
            throwIfDiagnostics: false,
          ).unit.directives;
          for (final uri in directives.expand(_directiveUris)) {
            final reference = Uri.parse(uri);
            final target = switch (reference) {
              Uri(scheme: 'package', :final path)
                  when path.startsWith('tentura/') =>
                lib.resolve(path.substring('tentura/'.length)),
              Uri(scheme: '') => file.absolute.uri.resolveUri(reference),
              _ => null,
            };
            if (target == null) continue;
            if (target.path.startsWith(oldPath) ||
                (target.path.startsWith(newPath) &&
                    !File.fromUri(target).existsSync())) {
              unresolved.add('${file.path}: $uri');
            }
          }
        }
      }
      expect(
        unresolved,
        isEmpty,
        reason: 'Shared utility targets use $newPath',
      );
    },
  );

  test(
    'app reload exports platform implementations from its own directory',
    () {
      final entry = File('$_utilityDirectory/app_reload.dart');
      expect(entry.existsSync(), isTrue, reason: entry.path);
      final exports = parseString(
        content: entry.readAsStringSync(),
      ).unit.directives.whereType<ExportDirective>();
      expect(exports, hasLength(1));
      final export = exports.single;
      expect(export.uri.stringValue, 'app_reload_stub.dart');
      expect(export.configurations, hasLength(1));
      final web = export.configurations.single;
      expect(web.name.toSource(), 'dart.library.js_interop');
      expect(web.uri.stringValue, 'app_reload_web.dart');
      for (final uri in _directiveUris(export)) {
        expect(
          File.fromUri(entry.uri.resolve(uri)).existsSync(),
          isTrue,
          reason: uri,
        );
      }
    },
  );

  test('source-reading tests point to the live snackbar helper', () {
    final snackbar = _parseSourceFile(
      'test/architecture/snack_bars_replace_not_queue_test.dart',
    );
    final helperPaths = snackbar.declarations
        .whereType<TopLevelVariableDeclaration>()
        .expand((declaration) => declaration.variables.variables)
        .where((variable) => variable.name.lexeme == '_helper')
        .map((variable) => variable.initializer)
        .whereType<StringLiteral>()
        .map((literal) => literal.stringValue)
        .toList();
    final sentryRead = _SentryHelperRead();
    _parseSourceFile(
      'test/app/sentry_observability_contract_test.dart',
    ).accept(sentryRead);
    const helper = '$_utilityDirectory/ui_utils.dart';

    expect(
      {
        'snackbar exclusion': helperPaths,
        'Sentry source read': sentryRead.paths,
      },
      equals({
        'snackbar exclusion': [helper],
        'Sentry source read': [helper],
      }),
    );
    expect(File(helper).existsSync(), isTrue, reason: helper);
    expect(
      _parseSourceFile(
        helper,
      ).declarations.whereType<FunctionDeclaration>().map(
        (declaration) => declaration.name.lexeme,
      ),
      containsAll(['showSnackBar', 'showSnackBarOn']),
    );
  });

  test(
    'repository documentation and client sources name the shared utility path',
    () async {
      final repository = Directory.current.parent.parent;
      final files = await _git(
        repository,
        [
          'ls-files',
          '-z',
          '--cached',
          '--others',
          '--exclude-standard',
          '--',
          'AGENTS.md',
          '.cursor/rules',
          'docs',
          'scripts',
        ],
      );
      const oldPackageDirectory = '${_tenturaPackage}ui/$_legacyFolder';
      final stalePaths = <String>[];
      for (final path in files.split('\u0000')) {
        if (path.isEmpty) continue;
        final file = File.fromUri(repository.uri.resolve(path));
        if (!file.existsSync()) continue;
        final source = file.readAsStringSync(encoding: latin1);
        if (source.contains(_oldDirectory) ||
            source.contains(oldPackageDirectory)) {
          stalePaths.add(path);
        }
      }
      for (final directory in ['lib', 'test', 'integration_test']) {
        for (final file in Directory(
          directory,
        ).listSync(recursive: true, followLinks: false).whereType<File>()) {
          if (_generatedDartFile.hasMatch(file.path) ||
              file.uri.pathSegments.contains('_g')) {
            continue;
          }
          final source = file.readAsStringSync(encoding: latin1);
          if (source.contains(_oldDirectory) ||
              source.contains(_oldPackagePath) ||
              _bareOldPath.hasMatch(source)) {
            stalePaths.add(file.path);
          }
        }
      }
      expect(stalePaths, isEmpty, reason: 'Shared utility paths use ui/util');
    },
  );
}
