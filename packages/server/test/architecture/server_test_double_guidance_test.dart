@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'server test DI guidance is current and release metadata is preserved',
    () {
      final root = Directory.current.parent.parent;
      const advancedPatterns = '.cursor/rules/advanced-patterns.mdc';
      const architecture = '.cursor/rules/architecture.mdc';
      const cleanArchitecture = '.claude/skills/clean-architecture/SKILL.md';
      const mockPath = 'data/repository/mock';
      const clientMockDirectory = 'packages/client/lib/$mockPath';
      const clientMocks = '$clientMockDirectory/client_repository_mocks.dart';
      const serverTestHelper = 'packages/server/test/support/test_di.dart';
      final violations = <String>[];

      for (final file in [
        File('${root.path}/AGENTS.md'),
        ...Directory('${root.path}/.cursor/rules').listSync(recursive: true),
        ...Directory('${root.path}/.claude/skills').listSync(recursive: true),
      ].whereType<File>()) {
        if (file.readAsStringSync().contains(
          'server/lib/$mockPath',
        )) {
          violations.add(
            '${file.path}: points to the former server mock directory',
          );
        }
      }

      const guidanceHeadings = {
        advancedPatterns: {'Test Doubles & Mocks'},
        architecture: {
          'Repository environment scoping & test doubles',
          'Injectable & Dependency Injection',
          'Testing Implications',
        },
        cleanArchitecture: {'DI (Injectable)'},
      };
      final serverTestPath = RegExp(r'\bpackages/server/test(?=/|[^\w-]|$)');
      final formerMockPath = RegExp(
        r'\b(?:lib/)?data/repository/mock(?=/|[^\w-]|$)',
      );
      for (final entry in guidanceHeadings.entries) {
        final path = entry.key;
        final document = File('${root.path}/$path').readAsStringSync();
        final sections = _sections(document, entry.value).toList();
        final helpers = [
          'configureTestDependencies',
          'initTestMocks',
          if (path == advancedPatterns) serverTestHelper,
        ];
        if (!sections.any(
          (section) =>
              serverTestPath.hasMatch(
                section.replaceAll(serverTestHelper, ''),
              ) &&
              helpers.every(section.contains),
        )) {
          violations.add(
            '$path: ${entry.value.join(' or ')} must place server test '
            'doubles under packages/server/test/ and name ${helpers.join(', ')}',
          );
        }
        if (path != advancedPatterns && !document.contains(clientMocks)) {
          violations.add('$path: missing $clientMocks');
        }

        for (final section in sections) {
          // Preserve the explicitly client-owned path and the existing note
          // about the removed client fixtures when checking server guidance.
          final text = section
              .replaceAll(clientMockDirectory, '')
              .replaceAll(
                '(the former `lib/$mockPath/data/` was removed as dead code)',
                '',
              );
          for (final line in text.split('\n').where(formerMockPath.hasMatch)) {
            violations.add(
              '$path: obsolete mock location in guidance: ${line.trim()}',
            );
          }
        }
      }

      // The release comparison belongs to the change under review. CI's regular
      // documentation run has no change-specific base revision.
      final base = Platform.environment['TENTURA_TEST_DI_BASE_REVISION'];
      if (base != null) violations.addAll(_releaseMetadataChanges(root, base));

      expect(violations..sort(), isEmpty);
    },
  );
}

Iterable<String> _sections(String document, Set<String> headings) sync* {
  for (final section
      in document.split(RegExp(r'^## ', multiLine: true)).skip(1)) {
    final title = section
        .split('\n')
        .first
        .trim()
        .replaceFirst(RegExp(r'^\d+\. '), '');
    if (headings.contains(title)) yield section;
  }
}

Iterable<String> _releaseMetadataChanges(Directory root, String base) sync* {
  final versionLine = RegExp(r'^version:[^\r\n]*', multiLine: true);
  for (final path in const [
    'packages/client/pubspec.yaml',
    'packages/server/pubspec.yaml',
    'packages/client/web/index.html',
    'packages/client/web/manifest.json',
  ]) {
    final result = Process.runSync(
      'git',
      ['show', '$base:$path'],
      workingDirectory: root.path,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final committed = result.stdout as String;
    final current = File('${root.path}/$path').readAsStringSync();
    if (path.endsWith('pubspec.yaml')) {
      final baseVersion = versionLine.firstMatch(committed)?.group(0);
      final currentVersion = versionLine.firstMatch(current)?.group(0);
      expect(
        baseVersion,
        isNotNull,
        reason: '$base:$path must declare a version',
      );
      if (currentVersion != baseVersion) {
        yield '$path: expected $baseVersion, found $currentVersion';
      }
    } else if (current != committed) {
      yield '$path: content differs from $base';
    }
  }
}
