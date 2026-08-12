import 'package:mockito/annotations.dart';

import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/invite_seed_prompt_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';

@GenerateMocks([
  InviteSeedPromptPort,
  InviteGenealogyRepositoryPort,
  MutatingUnitOfWorkPort,
])
void main() {}
