import 'dart:io';

import 'package:glob/glob.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// build.yaml narrows each code generator to the libraries it can generate
/// for (`generate_for`). A library outside those globs is skipped silently:
/// a freezed / drift / auto_route miss breaks compilation later, but an
/// `@injectable` class outside injectable_builder's globs just never reaches
/// the DI container — a runtime failure only. This test scans `lib/` for the
/// annotations and part directives each generator needs and fails when the
/// library is not matched by that generator's `generate_for`.
void main() {
  // `flutter test` runs from the package root.
  const packageRoot = '';

  final config = _GenerateForConfig.parse(
    File('${packageRoot}build.yaml').readAsStringSync(),
  );

  final sources = Directory('${packageRoot}lib')
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path.substring(packageRoot.length).replaceAll(r'\', '/'))
      .where(_isHandWrittenDart)
      .map(
        (path) =>
            _SourceFile(path, File('$packageRoot$path').readAsStringSync()),
      )
      .toList();

  test("every annotated library is inside its generator's generate_for", () {
    final misses = _findUncovered(config, sources);
    expect(misses, isEmpty, reason: misses.join('\n'));
  });

  test('the scan finds each kind of generator input (not vacuous)', () {
    final counts = {
      for (final rule in _rules)
        rule.builder: sources.where((s) => rule.needs(s.content)).length,
    };
    expect(counts[_injectable], greaterThan(50), reason: '$counts');
    expect(counts[_injectableConfig], 1, reason: '$counts');
    expect(counts[_freezed], greaterThan(50), reason: '$counts');
    expect(counts[_drift], greaterThan(0), reason: '$counts');
    expect(counts[_routePage], greaterThan(10), reason: '$counts');
    expect(counts[_routerConfig], 1, reason: '$counts');
  });

  test('a library outside the globs is reported (negative self-check)', () {
    const widget = 'lib/features/sample/ui/widget/sample_tile.dart';
    const state = 'lib/features/sample/ui/widget/sample_state.dart';
    final misses = _findUncovered(config, const [
      _SourceFile(widget, '@injectable\nclass SampleTile {}\n'),
      _SourceFile(
        state,
        "part 'sample_state.freezed.dart';\n\n@freezed\nclass S {}\n",
      ),
    ]);
    expect(misses, hasLength(2));
    expect(misses[0], allOf(contains(widget), contains(_injectable)));
    expect(misses[1], allOf(contains(state), contains(_freezed)));
  });

  test('a part file is checked through its library', () {
    final misses = _findUncovered(config, const [
      _SourceFile(
        'lib/features/sample/ui/bloc/sample_cubit.dart',
        "part 'sample_state.dart';\npart 'sample_cubit.freezed.dart';\n",
      ),
      _SourceFile(
        'lib/features/sample/ui/sample_part.dart',
        "part of 'bloc/sample_cubit.dart';\n\n@singleton\nclass P {}\n",
      ),
    ]);
    expect(misses, isEmpty, reason: misses.join('\n'));
  });
}

const _injectable = 'injectable_generator:injectable_builder';
const _injectableConfig = 'injectable_generator:injectable_config_builder';
const _freezed = 'freezed';
const _drift = 'drift_dev';
const _routePage = 'auto_route_generator:auto_route_generator';
const _routerConfig = 'auto_route_generator:auto_router_generator';

/// What each generator needs to see. Freezed membership comes from the
/// `part '*.freezed.dart'` directive, not from `@freezed`: a cubit may keep
/// its freezed state in a `part of` file.
final _rules = [
  _Rule(
    _injectable,
    RegExp(
      r'(?<![\w.])@(injectable|singleton|lazySingleton|module|Injectable|'
      r'Singleton|LazySingleton)\b',
    ),
  ),
  _Rule(_injectableConfig, RegExp(r'(?<![\w.])@InjectableInit\b')),
  _Rule(
    _freezed,
    RegExp(
      r'''^\s*part\s+['"][^'"]+\.freezed\.dart['"]\s*;''',
      multiLine: true,
    ),
  ),
  _Rule(
    _drift,
    RegExp(r'(?<![\w.])@Drift(Database|Accessor)\b|\bextends\s+Table\b'),
  ),
  _Rule(_routePage, RegExp(r'(?<![\w.])@RoutePage\b')),
  _Rule(_routerConfig, RegExp(r'(?<![\w.])@AutoRouterConfig\b')),
];

/// One line per (library, generator) pair the generator would skip.
List<String> _findUncovered(
  _GenerateForConfig config,
  List<_SourceFile> sources,
) {
  final misses = <String>[];
  for (final source in sources) {
    final library = source.libraryPath;
    for (final rule in _rules) {
      if (!rule.needs(source.content)) continue;
      if (config.covers(rule.builder, library)) continue;
      final via = library == source.path ? '' : ' (part of $library)';
      misses.add(
        '${source.path}$via needs ${rule.builder}, but the generate_for '
        'of that builder in packages/client/build.yaml does not match '
        '$library. Widen its include globs (or narrow the exclude) so the '
        'file is generated.',
      );
    }
  }
  return misses;
}

bool _isHandWrittenDart(String path) =>
    path.endsWith('.dart') &&
    !path.contains('/_g/') &&
    !path.endsWith('.g.dart') &&
    !path.endsWith('.freezed.dart') &&
    !path.endsWith('.gr.dart') &&
    !path.endsWith('.config.dart');

// A `//` comment: at line start or after whitespace, so `https://` in a
// string survives.
final _lineComment = RegExp(r'(^|\s)//.*', multiLine: true);
final _partOf = RegExp(
  r'''^\s*part\s+of\s+['"]([^'"]+)['"]\s*;''',
  multiLine: true,
);
final _partOfName = RegExp(r'^\s*part\s+of\s+[\w.]+\s*;', multiLine: true);

class _SourceFile {
  const _SourceFile(this.path, this.rawContent);

  /// Package-relative path with `/` separators, e.g. `lib/app/app.dart`.
  final String path;
  final String rawContent;

  /// Source without `//` comments, so documented annotations do not count.
  String get content => rawContent.replaceAll(_lineComment, '');

  /// The library build_runner runs the generator on: the file itself, or
  /// the library named by its `part of '<uri>';` directive.
  String get libraryPath {
    final match = _partOf.firstMatch(content);
    if (match == null) {
      if (_partOfName.hasMatch(content)) {
        throw StateError(
          '$path uses `part of <library name>;` — use `part of '
          "'<uri>';` so its library can be resolved.",
        );
      }
      return path;
    }
    final segments = path.split('/')..removeLast();
    for (final segment in match.group(1)!.split('/')) {
      if (segment == '..') {
        segments.removeLast();
      } else if (segment != '.') {
        segments.add(segment);
      }
    }
    return segments.join('/');
  }
}

class _Rule {
  const _Rule(this.builder, this.pattern);

  final String builder;
  final RegExp pattern;

  bool needs(String content) => pattern.hasMatch(content);
}

class _Globs {
  const _Globs(this.include, this.exclude);

  final List<Glob> include;
  final List<Glob> exclude;
}

/// The `targets.$default.builders.<key>.generate_for` globs of build.yaml.
class _GenerateForConfig {
  _GenerateForConfig(this._byBuilder, this._disabled);

  factory _GenerateForConfig.parse(String buildYaml) {
    final yaml = loadYaml(buildYaml) as YamlMap;
    final builders =
        ((yaml['targets'] as YamlMap)[r'$default'] as YamlMap)['builders']
            as YamlMap;
    final byBuilder = <String, _Globs?>{};
    final disabled = <String>{};
    for (final MapEntry(:key, :value) in builders.entries) {
      final options = value as YamlMap?;
      final generateFor = options?['generate_for'];
      byBuilder[key as String] = switch (generateFor) {
        null => null,
        final YamlList include => _Globs(_globs(include), const []),
        final YamlMap map => _Globs(
          map['include'] == null
              ? [Glob('**')]
              : _globs(map['include'] as YamlList),
          map['exclude'] == null
              ? const []
              : _globs(map['exclude'] as YamlList),
        ),
        _ => throw FormatException('Unexpected generate_for for $key'),
      };
      if (options?['enabled'] == false) disabled.add(key);
    }
    return _GenerateForConfig(byBuilder, disabled);
  }

  final Map<String, _Globs?> _byBuilder;
  final Set<String> _disabled;

  static List<Glob> _globs(YamlList list) => [
    for (final pattern in list) Glob(pattern as String),
  ];

  /// Whether build_runner runs [builder] on [path]. A builder without a
  /// `generate_for` (or not configured at all) runs on every library; a
  /// disabled one on none.
  bool covers(String builder, String path) {
    if (_disabled.contains(builder)) return false;
    final globs = _byBuilder[builder];
    if (globs == null) return true;
    return globs.include.any((g) => g.matches(path)) &&
        !globs.exclude.any((g) => g.matches(path));
  }
}
