import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

/// Named injectable key for the My Work obligations activation gate.
///
/// Default `true` since UNIT 09; tests may override via GetIt registration.
const myWorkObligationsGate = 'myWorkObligationsGate';

@module
abstract class MyWorkObligationsGateModule {
  @Named(myWorkObligationsGate)
  bool get enabled => true;
}

/// Whether the My Work obligations feed is mounted (UNIT 04 gate, flipped in UNIT 09).
bool readMyWorkObligationsGateEnabled() {
  if (!GetIt.I.isRegistered<bool>(instanceName: myWorkObligationsGate)) {
    return false;
  }
  return GetIt.I.get<bool>(instanceName: myWorkObligationsGate);
}
