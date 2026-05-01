import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/use_case/capability_case.dart';

import 'capability_case_mocks.mocks.dart';

void main() {
  late MockPersonCapabilityEventRepositoryPort repo;
  late CapabilityCase case_;

  setUp(() {
    repo = MockPersonCapabilityEventRepositoryPort();
    case_ = CapabilityCase(
      repo,
      env: Env(environment: Environment.test),
      logger: Logger('CapabilityCaseTest'),
    );
    when(repo.upsertPrivateLabels(
      observerId: anyNamed('observerId'),
      subjectId: anyNamed('subjectId'),
      slugs: anyNamed('slugs'),
    )).thenAnswer((_) async {});
    when(repo.insertForwardReasons(
      observerId: anyNamed('observerId'),
      subjectId: anyNamed('subjectId'),
      beaconId: anyNamed('beaconId'),
      slugs: anyNamed('slugs'),
      note: anyNamed('note'),
    )).thenAnswer((_) async {});
  });

  group('upsertPrivateLabel', () {
    test('rejects self-labelling', () async {
      await expectLater(
        case_.upsertPrivateLabel(
          observerId: 'U1',
          subjectId: 'U1',
          slugs: ['transport'],
        ),
        throwsA(
          isA<ExceptionBase>().having(
            (e) => (e.code as CapabilityExceptionCodes).exceptionCode,
            'code',
            CapabilityExceptionCode.selfLabelForbidden,
          ),
        ),
      );
      verifyZeroInteractions(repo);
    });

    test('rejects unknown slug', () async {
      await expectLater(
        case_.upsertPrivateLabel(
          observerId: 'U1',
          subjectId: 'U2',
          slugs: ['not_a_real_slug'],
        ),
        throwsA(
          isA<ExceptionBase>().having(
            (e) => (e.code as CapabilityExceptionCodes).exceptionCode,
            'code',
            CapabilityExceptionCode.invalidSlug,
          ),
        ),
      );
      verifyZeroInteractions(repo);
    });

    test('delegates valid slugs to repository', () async {
      await case_.upsertPrivateLabel(
        observerId: 'U1',
        subjectId: 'U2',
        slugs: ['transport', 'pets'],
      );
      verify(
        repo.upsertPrivateLabels(
          observerId: 'U1',
          subjectId: 'U2',
          slugs: ['transport', 'pets'],
        ),
      ).called(1);
    });

    test('empty slug list clears labels', () async {
      await case_.upsertPrivateLabel(
        observerId: 'U1',
        subjectId: 'U2',
        slugs: [],
      );
      verify(
        repo.upsertPrivateLabels(
          observerId: 'U1',
          subjectId: 'U2',
          slugs: [],
        ),
      ).called(1);
    });
  });

  group('recordForwardReasons', () {
    test('empty slugs is a no-op', () async {
      await case_.recordForwardReasons(
        observerId: 'U1',
        subjectId: 'U2',
        beaconId: 'B1',
        slugs: [],
      );
      verifyZeroInteractions(repo);
    });

    test('rejects unknown slug', () async {
      await expectLater(
        case_.recordForwardReasons(
          observerId: 'U1',
          subjectId: 'U2',
          beaconId: 'B1',
          slugs: ['bad_slug'],
        ),
        throwsA(
          isA<ExceptionBase>().having(
            (e) => (e.code as CapabilityExceptionCodes).exceptionCode,
            'code',
            CapabilityExceptionCode.invalidSlug,
          ),
        ),
      );
      verifyZeroInteractions(repo);
    });

    test('valid slugs delegate to repository', () async {
      await case_.recordForwardReasons(
        observerId: 'U1',
        subjectId: 'U2',
        beaconId: 'B1',
        slugs: ['transport', 'calls'],
      );
      verify(
        repo.insertForwardReasons(
          observerId: 'U1',
          subjectId: 'U2',
          beaconId: 'B1',
          slugs: ['transport', 'calls'],
        ),
      ).called(1);
    });

    test('passes note to repository', () async {
      await case_.recordForwardReasons(
        observerId: 'U1',
        subjectId: 'U2',
        beaconId: 'B1',
        slugs: ['tools'],
        note: 'has a van',
      );
      verify(
        repo.insertForwardReasons(
          observerId: 'U1',
          subjectId: 'U2',
          beaconId: 'B1',
          slugs: ['tools'],
          note: 'has a van',
        ),
      ).called(1);
    });
  });
}
