import 'dart:async';

import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

Builder outputsRefreshBuilder(BuilderOptions options) =>
    const OutputsRefreshBuilder();

/// Output-less builder that makes a `--build-filter` on a `.graphql` source
/// build that operation's generated files.
///
/// build_runner matches filters against a step's declared outputs, so a filter
/// on the source alone skips `graphql_builder` and leaves the outputs stale
/// after a schema-only change. This builder has no outputs, so the filter
/// matches its primary input instead; it then reads every generated sibling
/// of the source, which makes build_runner build them.
class OutputsRefreshBuilder implements Builder {
  const OutputsRefreshBuilder();

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.graphql': <String>[],
      };

  @override
  FutureOr<void> build(BuildStep buildStep) async {
    final input = buildStep.inputId;
    final name = p.basenameWithoutExtension(input.path);
    final outputs = buildStep.findAssets(
      Glob('${p.dirname(input.path)}/*/$name.*.dart'),
    );
    await for (final id in outputs) {
      await buildStep.canRead(id);
    }
  }
}
