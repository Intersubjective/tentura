import 'dart:io';

import 'package:tentura_server/app/app.dart';

import 'utils/issue_jwt.dart';
import 'utils/convert_images.dart';

Future<void> main(List<String> args) async {
  switch (args.firstOrNull) {
    case null:
      await App().run();

    case 'jwt':
      issueJwt(args);

    case 'convert_images':
      await convertImages();
  }
  exit(0);
}
