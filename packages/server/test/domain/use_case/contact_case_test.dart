import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/contact_case.dart';

import 'contact_case_mocks.mocks.dart';

void main() {
  late MockUserContactRepositoryPort contactRepo;
  late ContactCase case_;

  setUp(() {
    contactRepo = MockUserContactRepositoryPort();
    case_ = ContactCase(
      contactRepo,
      env: Env(environment: Environment.test),
      logger: Logger('ContactCaseTest'),
    );
    when(
      contactRepo.upsert(
        viewerId: anyNamed('viewerId'),
        subjectId: anyNamed('subjectId'),
        contactName: anyNamed('contactName'),
      ),
    ).thenAnswer((_) async {});
  });

  group('ContactCase.set', () {
    test('trims the name and upserts', () async {
      await case_.set(
        viewerId: 'Ualice',
        subjectId: 'Ubob',
        contactName: '  Bob2000  ',
      );
      verify(
        contactRepo.upsert(
          viewerId: 'Ualice',
          subjectId: 'Ubob',
          contactName: 'Bob2000',
        ),
      ).called(1);
    });

    test('rejects self-rename', () async {
      await expectLater(
        case_.set(
          viewerId: 'Ualice',
          subjectId: 'Ualice',
          contactName: 'Me Myself',
        ),
        throwsA(isA<IdWrongException>()),
      );
      verifyNever(
        contactRepo.upsert(
          viewerId: anyNamed('viewerId'),
          subjectId: anyNamed('subjectId'),
          contactName: anyNamed('contactName'),
        ),
      );
    });

    test('rejects a too-short name (after trim)', () async {
      await expectLater(
        case_.set(viewerId: 'Ualice', subjectId: 'Ubob', contactName: ' B '),
        throwsA(isA<IdWrongException>()),
      );
    });

    test('rejects a too-long name', () async {
      await expectLater(
        case_.set(
          viewerId: 'Ualice',
          subjectId: 'Ubob',
          contactName: 'x' * 33,
        ),
        throwsA(isA<IdWrongException>()),
      );
    });
  });

  group('ContactCase.delete', () {
    test('delegates and reports whether an entry existed', () async {
      when(
        contactRepo.delete(
          viewerId: anyNamed('viewerId'),
          subjectId: anyNamed('subjectId'),
        ),
      ).thenAnswer((_) async => true);
      expect(
        await case_.delete(viewerId: 'Ualice', subjectId: 'Ubob'),
        isTrue,
      );
      verify(contactRepo.delete(viewerId: 'Ualice', subjectId: 'Ubob'))
          .called(1);
    });
  });
}
