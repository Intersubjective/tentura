// Prints the contact-resolution sweep settings Env derives from the process
// environment; run as a subprocess by the contact resolution drain test.
import 'package:injectable/injectable.dart' show Environment;
import 'package:tentura_server/env.dart';

void main() {
  final env = Env(environment: Environment.test, printEnv: false);
  print(
    'batch=${env.contactResolutionBatchSize} '
    'rows=${env.contactResolutionRunRowBudget} '
    'timeSeconds=${env.contactResolutionRunTimeBudget.inSeconds} '
    'intervalMinutes=${env.contactResolutionSweepInterval.inMinutes}',
  );
}
