import 'dart:io';
import 'package:args/args.dart';

import 'package:tentura_server/app.dart';

import 'utils/issue_jwt.dart';
import 'utils/calculate_blur_hashes.dart';

const kBlurKeyName = 'blur';
const kJwtKeyName = 'jwt';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    await App().run();
  } else {
    ArgParser()
      ..addCommand(kBlurKeyName)
      ..addCommand(
        kJwtKeyName,
        ArgParser()..addOption('sub', callback: issueJwt),
      )
      ..parse(args);

    if (args.contains(kBlurKeyName)) {
      await const BlurHashCalculator().calculateBlurHashes();
    }

    exit(0);
  }
}
