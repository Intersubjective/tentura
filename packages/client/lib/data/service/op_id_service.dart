import 'package:injectable/injectable.dart';
import 'package:tentura/domain/port/op_id_port.dart';
import 'package:uuid/uuid.dart';

@LazySingleton(as: OpIdPort, env: [Environment.dev, Environment.prod])
final class OpIdService implements OpIdPort {
  final _uuid = const Uuid();

  @override
  String newOpId() => _uuid.v4();
}
