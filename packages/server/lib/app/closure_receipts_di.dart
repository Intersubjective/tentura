import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/closure_receipts_port.dart';

/// Injectable `as:` target; inherits no-op [NoopClosureReceipts] behaviour.
@Singleton(as: ClosureReceiptsPort, order: -999)
final class RegisteredNoopClosureReceipts extends NoopClosureReceipts {}
