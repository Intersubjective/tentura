import 'package:hooks/hooks.dart';

import 'build/version_update.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    versionUpdate();
  });
}
