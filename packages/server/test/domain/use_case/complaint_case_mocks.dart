import 'package:mockito/annotations.dart';

import 'package:tentura_server/domain/port/complaint_repository_port.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';

@GenerateMocks([
  ComplaintRepositoryPort,
  EmailSenderPort,
])
void main() {}
