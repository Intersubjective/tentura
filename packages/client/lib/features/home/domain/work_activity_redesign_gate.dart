import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

/// Named injectable key for the Work / Activity redesign activation gate.
///
/// Default `true` as of UNIT 20; tests may override via GetIt registration.
const workActivityRedesignGate = 'workActivityRedesignGate';

@module
abstract class WorkActivityRedesignGateModule {
  @Named(workActivityRedesignGate)
  bool get enabled => true;
}

/// Whether the Work / Activity redesign UI is mounted (UNIT 09 gate).
bool readWorkActivityRedesignGateEnabled() {
  if (!GetIt.I.isRegistered<bool>(instanceName: workActivityRedesignGate)) {
    return true;
  }
  return GetIt.I.get<bool>(instanceName: workActivityRedesignGate);
}
