import 'package:injectable/injectable.dart';

/// Named injectable key for the My Work obligations activation gate.
///
/// Default `false` until UNIT 09 flips it. Units 04–08 read this value.
const myWorkObligationsGate = 'myWorkObligationsGate';

@module
abstract class MyWorkObligationsGateModule {
  @Named(myWorkObligationsGate)
  bool get enabled => false;
}
