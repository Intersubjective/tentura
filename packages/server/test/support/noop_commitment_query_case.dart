import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/env.dart';

import 'recording_commitment_repository.dart';

class _FakeHelpOfferRepo extends Fake implements HelpOfferRepositoryPort {}

CommitmentQueryCase noopCommitmentQueryCase({Logger? logger}) =>
    CommitmentQueryCase(
      NoOpCommitmentRepository(),
      _FakeHelpOfferRepo(),
      env: Env(environment: Environment.test),
      logger: logger ?? Logger('noopCommitmentQueryCase'),
    );
