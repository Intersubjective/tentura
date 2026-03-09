import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

@module
abstract class RegisterModule {
  @singleton
  Logger get logger => Logger.root;
}
