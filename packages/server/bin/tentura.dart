import 'dart:io';

import 'package:tentura_server/app/app.dart';
import 'package:tentura_server/app/sentry/sentry_init.dart';
import 'package:tentura_server/env.dart';

import 'utils/issue_jwt.dart';
import 'utils/convert_images.dart';

Future<void> main(List<String> args) async {
  switch (args.firstOrNull) {
    case null:
      final env = Env.prod();
      await initSentry(
        env: env,
        appRunner: () => App().run(env),
      );

    case 'jwt':
      issueJwt(args);

    case 'convert_images':
      await convertImages();
  }
  exit(0);
}
