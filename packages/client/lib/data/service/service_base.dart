import 'package:logging/logging.dart';

import 'package:tentura/env.dart';

abstract class ServiceBase {
  const ServiceBase({
    required this.env,
    required this.logger,
  });

  final Env env;

  final Logger logger;
}
