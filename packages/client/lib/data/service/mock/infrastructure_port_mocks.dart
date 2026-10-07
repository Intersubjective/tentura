import 'package:injectable/injectable.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura/domain/port/clock_port.dart';
import 'package:tentura/domain/port/op_id_port.dart';
import 'package:tentura/domain/port/wake_up_port.dart';

@Injectable(as: ClockPort, env: [Environment.test], order: 1)
class ClockPortMock extends Mock implements ClockPort {}

@Injectable(as: OpIdPort, env: [Environment.test], order: 1)
class OpIdPortMock extends Mock implements OpIdPort {}

@Injectable(as: WakeUpPort, env: [Environment.test], order: 1)
class WakeUpPortMock extends Mock implements WakeUpPort {}
