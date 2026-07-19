import 'package:tentura_server/domain/port/trust_maintenance_port.dart';

class FakeTrustMaintenancePort implements TrustMaintenancePort {
  int forceRefreshAllCalls = 0;
  int runDueCalls = 0;

  @override
  Future<void> forceRefreshAll() async {
    forceRefreshAllCalls += 1;
  }

  @override
  Future<void> runDue({DateTime? now}) async {
    runDueCalls += 1;
  }
}
