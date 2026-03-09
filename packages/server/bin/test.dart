import 'dart:io';

import 'package:tentura_server/app/app.dart';

Future<void> main(List<String> args) async {
  await App().runWithTestEnv();
  exit(0);
}
