@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/evaluation_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/capability/capability_consts.dart';
import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';
import 'package:tentura_server/domain/entity/review_finalization_result.dart';
import 'package:tentura_server/domain/use_case/evaluation/review_finalization_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/review_finalization_test_support.dart';

const _beaconId = 'Bcapc2bcn001';
const _author = 'Ucapc2author1';
const _committer1 = 'Ucapc2comit01';
const _committer2 = 'Ucapc2comit02';
const _former = 'Ucapc2formr01';
const _forwarder = 'Ucapc2forwd01';
const _subject = 'Ucapc2subj001';
const _kOut = kCapKOut;

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('ReviewFinalizationCase outcome evidence (C2)', () {
    late Connection writer;
    late TenturaDb database;
    late EvaluationRepository evalRepo;
    late CapabilityEvidenceRepository capEvidenceRepo;
    late MutatingUnitOfWork unitOfWork;
    late ReviewFinalizationCase finalizationCase;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);

      database = TenturaDb(target.databaseEnv);
      evalRepo = EvaluationRepository(database);
      capEvidenceRepo = CapabilityEvidenceRepository(database);
      unitOfWork = MutatingUnitOfWork(database);
      finalizationCase = ReviewFinalizationCase(
        unitOfWork,
        evalRepo,
        FakeForwardEdges(),
        FakeAttribution(),
        FakeHelpOffers(),
        RecordingTrustEvidence(),
        capEvidenceRepo,
        env: target.databaseEnv,
        logger: Logger('ReviewFinalizationOutcomeEvidencePgTest'),
      );
    });

    setUp(() async {
      await writer.execute(r'''
DELETE FROM public.person_capability_event
WHERE observer_user_id LIKE 'Ucapc2%'
   OR subject_user_id LIKE 'Ucapc2%'
''');
      await writer.execute(r'''
DELETE FROM public.capability_evidence_edge
WHERE observer_user_id LIKE 'Ucapc2%'
   OR subject_user_id LIKE 'Ucapc2%'
''');
      await writer.execute(r'''
DELETE FROM public.capability_evidence_generation
WHERE observer_user_id LIKE 'Ucapc2%'
   OR subject_user_id LIKE 'Ucapc2%'
''');
      await writer.execute(r'''
DELETE FROM public.beacon_evaluation_ack_tag
WHERE beacon_id = 'Bcapc2bcn001'
''');
      await writer.execute(r'''
DELETE FROM public.beacon_evaluation
WHERE beacon_id = 'Bcapc2bcn001'
''');
      await writer.execute(r'''
UPDATE public.beacon
SET status = 5
WHERE id = 'Bcapc2bcn001'
''');
      await writer.execute(r'''
UPDATE public.beacon_review_window
SET status = 0,
    closes_at = now() + interval '7 days'
WHERE beacon_id = 'Bcapc2bcn001'
''');
      await _seedFixture(writer);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });

    Future<ReviewFinalizationResult> closeBeacon() =>
        finalizationCase.closeAndFinalize(
          _beaconId,
          reason: 'test',
          actorUserId: _author,
        );

    test(
      'non-positive finalized values emit no outcome evidence',
      () async {
        await evalRepo.submitEvaluationAtomic(
          beaconId: _beaconId,
          evaluatorId: _author,
          evaluatedUserId: _subject,
          value: BeaconEvaluationValue.zero,
          reasonTags: const ['quality'],
          note: 'zero',
          ackTags: const ['transport'],
        );
        await evalRepo.submitEvaluationAtomic(
          beaconId: _beaconId,
          evaluatorId: _committer1,
          evaluatedUserId: _subject,
          value: BeaconEvaluationValue.neg1,
          reasonTags: const ['quality'],
          note: 'neg',
          ackTags: const ['pets'],
        );
        await evalRepo.submitEvaluationAtomic(
          beaconId: _beaconId,
          evaluatorId: _former,
          evaluatedUserId: _subject,
          value: BeaconEvaluationValue.noBasis,
          reasonTags: const [],
          note: 'no basis',
          ackTags: const ['manual_labour'],
        );

        await closeBeacon();

        expect(await _outcomeLedgerCount(writer, _subject), 0);
        expect(
          await _cellCountForSubject(writer, _subject),
          0,
        );
      },
      skip: skipReason,
    );

    test(
      'forwarder evaluations are excluded from outcome emission',
      () async {
        await writer.execute(r'''
INSERT INTO public.beacon_evaluation (
  beacon_id, evaluator_id, evaluated_user_id, value, reason_tags, note, status
) VALUES (
  'Bcapc2bcn001',
  'Ucapc2forwd01',
  'Ucapc2subj001',
  4,
  'quality',
  'forwarder ack',
  1
)
ON CONFLICT (beacon_id, evaluator_id, evaluated_user_id) DO UPDATE SET
  value = EXCLUDED.value,
  status = EXCLUDED.status
''');
        await writer.execute(r'''
INSERT INTO public.beacon_evaluation_ack_tag (
  beacon_id, evaluator_id, subject_id, tag_slug
) VALUES (
  'Bcapc2bcn001',
  'Ucapc2forwd01',
  'Ucapc2subj001',
  'transport'
)
ON CONFLICT DO NOTHING
''');

        await closeBeacon();

        expect(await _outcomeLedgerCount(writer, _subject), 0);
      },
      skip: skipReason,
    );

    test(
      'three co-acknowledgers emit three ledger rows with per-observer cell strength 1/3',
      () async {
        for (final evaluator in [_author, _committer1, _former]) {
          await evalRepo.submitEvaluationAtomic(
            beaconId: _beaconId,
            evaluatorId: evaluator,
            evaluatedUserId: _subject,
            value: BeaconEvaluationValue.pos1,
            reasonTags: const ['quality'],
            note: 'thanks',
            ackTags: const ['transport'],
          );
        }

        await closeBeacon();

        expect(
          await _outcomeLedgerCount(writer, _subject, tag: 'transport'),
          3,
        );

        for (final observer in [_author, _committer1, _former]) {
          expect(
            await _effectiveOutStrength(writer, observer, _subject, 'transport'),
            closeTo(1 / (kCapKOut + 1), 1e-4),
          );
        }
      },
      skip: skipReason,
    );

    test(
      'beacon-wide tag cap keeps top corroborated tags per subject',
      () async {
        await evalRepo.submitEvaluationAtomic(
          beaconId: _beaconId,
          evaluatorId: _author,
          evaluatedUserId: _subject,
          value: BeaconEvaluationValue.pos2,
          reasonTags: const ['quality'],
          note: 'a',
          ackTags: const ['transport', 'pets', 'manual_labour'],
        );
        await evalRepo.submitEvaluationAtomic(
          beaconId: _beaconId,
          evaluatorId: _committer1,
          evaluatedUserId: _subject,
          value: BeaconEvaluationValue.pos1,
          reasonTags: const ['quality'],
          note: 'b',
          ackTags: const ['transport', 'pets'],
        );
        await evalRepo.submitEvaluationAtomic(
          beaconId: _beaconId,
          evaluatorId: _former,
          evaluatedUserId: _subject,
          value: BeaconEvaluationValue.pos1,
          reasonTags: const ['quality'],
          note: 'c',
          ackTags: const ['transport'],
        );
        await evalRepo.submitEvaluationAtomic(
          beaconId: _beaconId,
          evaluatorId: _committer2,
          evaluatedUserId: _subject,
          value: BeaconEvaluationValue.pos1,
          reasonTags: const ['quality'],
          note: 'd',
          ackTags: const ['cooking'],
        );

        await closeBeacon();

        final tags = await _outcomeTagsForSubject(writer, _subject);
        expect(tags, ['cooking', 'pets', 'transport']);
        expect(tags, isNot(contains('manual_labour')));
      },
      skip: skipReason,
    );

    test(
      're-running finalization is idempotent for outcome evidence',
      () async {
        await evalRepo.submitEvaluationAtomic(
          beaconId: _beaconId,
          evaluatorId: _author,
          evaluatedUserId: _subject,
          value: BeaconEvaluationValue.pos1,
          reasonTags: const ['quality'],
          note: 'once',
          ackTags: const ['transport'],
        );

        final first = await closeBeacon();
        expect(first.didClose, isTrue);
        final ledgerAfterFirst = await _outcomeLedgerCount(writer, _subject);

        final second = await closeBeacon();
        expect(second.didClose, isFalse);
        expect(
          await _outcomeLedgerCount(writer, _subject),
          ledgerAfterFirst,
        );
      },
      skip: skipReason,
    );

    test(
      'three distinct observers in one finalization do not nest mutating users',
      () async {
        for (final evaluator in [_author, _committer1, _former]) {
          await evalRepo.submitEvaluationAtomic(
            beaconId: _beaconId,
            evaluatorId: evaluator,
            evaluatedUserId: _subject,
            value: BeaconEvaluationValue.pos2,
            reasonTags: const ['quality'],
            note: 'multi',
            ackTags: const ['transport'],
          );
        }

        await expectLater(closeBeacon(), completes);
        expect(await _outcomeLedgerCount(writer, _subject), 3);
      },
      skip: skipReason,
    );
  });
}

Future<void> _seedFixture(Connection writer) async {
  await writer.execute(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  ('Ucapc2author1', 'Author', 'pk-a'),
  ('Ucapc2comit01', 'Committer 1', 'pk-c1'),
  ('Ucapc2comit02', 'Committer 2', 'pk-c2'),
  ('Ucapc2formr01', 'Former committer', 'pk-f'),
  ('Ucapc2forwd01', 'Forwarder', 'pk-fw'),
  ('Ucapc2subj001', 'Subject', 'pk-s')
ON CONFLICT DO NOTHING
''');

  await writer.execute(r'''
INSERT INTO public.beacon (
  id, user_id, title, description, needs, primary_need_slug
) VALUES (
  'Bcapc2bcn001',
  'Ucapc2author1',
  'Outcome evidence beacon',
  'd',
  'transport,pets,manual_labour,cooking',
  'transport'
)
ON CONFLICT DO NOTHING
''');

  await writer.execute(r'''
INSERT INTO public.beacon_review_window (
  beacon_id, opened_at, closes_at, status
) VALUES (
  'Bcapc2bcn001',
  now() - interval '1 day',
  now() + interval '7 days',
  0
)
ON CONFLICT (beacon_id) DO UPDATE SET
  opened_at = EXCLUDED.opened_at,
  closes_at = EXCLUDED.closes_at,
  status = EXCLUDED.status
''');

  await writer.execute('''
INSERT INTO public.beacon_evaluation_participant (
  beacon_id, user_id, role, contribution_summary, causal_hint
) VALUES
  (
    'Bcapc2bcn001',
    'Ucapc2author1',
    ${EvaluationParticipantRole.author.dbValue},
    'authored',
    'hint'
  ),
  (
    'Bcapc2bcn001',
    'Ucapc2comit01',
    ${EvaluationParticipantRole.committer.dbValue},
    'helped',
    'hint'
  ),
  (
    'Bcapc2bcn001',
    'Ucapc2comit02',
    ${EvaluationParticipantRole.committer.dbValue},
    'helped',
    'hint'
  ),
  (
    'Bcapc2bcn001',
    'Ucapc2formr01',
    ${EvaluationParticipantRole.formerCommitter.dbValue},
    'helped before',
    'hint'
  ),
  (
    'Bcapc2bcn001',
    'Ucapc2forwd01',
    ${EvaluationParticipantRole.forwarder.dbValue},
    'forwarded',
    'hint'
  ),
  (
    'Bcapc2bcn001',
    'Ucapc2subj001',
    ${EvaluationParticipantRole.committer.dbValue},
    'helped too',
    'hint'
  )
ON CONFLICT DO NOTHING
''');

  for (final evaluator in [
    _author,
    _committer1,
    _committer2,
    _former,
    _forwarder,
  ]) {
    await writer.execute('''
INSERT INTO public.beacon_evaluation_visibility (
  beacon_id, evaluator_id, participant_id
) VALUES (
  'Bcapc2bcn001',
  '$evaluator',
  'Ucapc2subj001'
)
ON CONFLICT DO NOTHING
''');
    await writer.execute('''
INSERT INTO public.beacon_review_status (beacon_id, user_id, status)
VALUES ('Bcapc2bcn001', '$evaluator', 0)
ON CONFLICT DO NOTHING
''');
  }
}

Future<int> _outcomeLedgerCount(
  Connection writer,
  String subjectId, {
  String? tag,
}) async {
  final tagFilter = tag == null ? '' : " AND tag_slug = '$tag'";
  final rows = await writer.execute(
    "SELECT count(*)::int FROM public.person_capability_event "
    "WHERE subject_user_id = '$subjectId' "
    "AND source_type = 3 "
    "AND deleted_at IS NULL$tagFilter",
  );
  return rows.single.single! as int;
}

Future<int> _cellCountForSubject(Connection writer, String subjectId) async {
  final rows = await writer.execute(
    "SELECT count(*)::int FROM public.capability_evidence_edge "
    "WHERE subject_user_id = '$subjectId'",
  );
  return rows.single.single! as int;
}

Future<List<String>> _outcomeTagsForSubject(
  Connection writer,
  String subjectId,
) async {
  final rows = await writer.execute(
    "SELECT DISTINCT tag_slug FROM public.person_capability_event "
    "WHERE subject_user_id = '$subjectId' "
    "AND source_type = 3 "
    "AND deleted_at IS NULL "
    "ORDER BY tag_slug",
  );
  return rows.map((r) => r[0]! as String).toList();
}

Future<double> _effectiveOutStrength(
  Connection writer,
  String observer,
  String subject,
  String tag,
) async {
  final row = await writer.execute(
    "SELECT public.cap_strength(s_out, $_kOut, anchor_at, "
    "${kCapHalfLifeOutSeconds.toDouble()}) "
    "FROM public.capability_evidence_edge "
    "WHERE observer_user_id = '$observer' "
    "AND subject_user_id = '$subject' "
    "AND tag_slug = '$tag'",
  );
  return (row.single.single as num).toDouble();
}

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

class _DisposablePgTarget {
  const _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_REVIEW_OUTCOME_TEST_DB'] ??
        'tentura_test_review_outcome_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_REVIEW_OUTCOME_TEST_DB',
        'must match tentura_test_[a-z0-9_]+ and be at most 63 characters',
      );
    }

    Env envFor(String database) => Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgDatabase: database,
      pgUsername: username,
      pgPassword: password,
      printEnv: false,
      isDebugModeOn: false,
    );

    return _DisposablePgTarget(
      adminEnv: envFor(adminDatabase),
      databaseEnv: envFor(databaseName),
      databaseName: databaseName,
    );
  }

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  Future<void> recreate() async {
    final admin = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await admin.execute(
        'SELECT pg_terminate_backend(pid) FROM pg_stat_activity '
        "WHERE datname = '$databaseName' AND pid <> pg_backend_pid()",
      );
      await admin.execute('DROP DATABASE IF EXISTS "$databaseName"');
      await admin.execute('CREATE DATABASE "$databaseName"');
    } finally {
      await admin.close();
    }
  }

  Future<void> drop() async {
    final admin = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await admin.execute(
        'SELECT pg_terminate_backend(pid) FROM pg_stat_activity '
        "WHERE datname = '$databaseName' AND pid <> pg_backend_pid()",
      );
      await admin.execute('DROP DATABASE IF EXISTS "$databaseName"');
    } finally {
      await admin.close();
    }
  }
}
