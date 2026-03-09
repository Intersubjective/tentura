import 'package:logging/logging.dart';

import 'package:tentura/env.dart';

base class UseCaseBase {
  UseCaseBase({
    required this.env,
    required this.logger,
  });

  final Env env;

  final Logger logger;
}
