import 'dart:io';

import 'package:tentura_server/app/app.dart';
import 'package:tentura_server/env.dart';

Future<void> main(List<String> args) async {
  await App().run(Env.dev());
  exit(0);
}
