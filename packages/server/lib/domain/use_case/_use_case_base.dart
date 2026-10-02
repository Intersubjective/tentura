import 'package:logging/logging.dart';

import 'package:tentura_server/env.dart';

class UseCaseBase {
  UseCaseBase({
    required this.env,
    required this.logger,
  });

  final Env env;

  final Logger logger;
}
