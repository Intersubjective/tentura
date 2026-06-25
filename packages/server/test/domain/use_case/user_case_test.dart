import 'dart:async';
import 'dart:typed_data';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/image_entity.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/user_case.dart';
import 'package:tentura_server/env.dart';

import 'user_case_mocks.mocks.dart';

void main() {
  late MockUserRepositoryPort userRepo;
  late MockImageRepositoryPort imageRepo;
  late MockTaskRepositoryPort taskRepo;
  late UserCase case_;

  final createdAt = DateTime.utc(2026, 6, 25);
  const userId = 'Ualice';

  UserEntity user({
    String? displayName,
    String? description,
    String? handle,
    ImageEntity? image,
  }) =>
      UserEntity(
        id: userId,
        displayName: displayName ?? 'Alice',
        description: description ?? '',
        handle: handle ?? '',
        image: image,
      );

  ImageEntity sampleImage({String id = 'Iold'}) => ImageEntity(
        id: id,
        authorId: userId,
        createdAt: createdAt,
      );

  void stubGetById(UserEntity entity) {
    when(userRepo.getById(userId)).thenAnswer((_) async => entity);
  }

  void stubUpdate() {
    when(
      userRepo.update(
        id: anyNamed('id'),
        displayName: anyNamed('displayName'),
        description: anyNamed('description'),
        imageId: anyNamed('imageId'),
        dropImage: anyNamed('dropImage'),
        setHandle: anyNamed('setHandle'),
        handle: anyNamed('handle'),
      ),
    ).thenAnswer((_) async {});
  }

  setUp(() {
    userRepo = MockUserRepositoryPort();
    imageRepo = MockImageRepositoryPort();
    taskRepo = MockTaskRepositoryPort();
    case_ = UserCase(
      imageRepo,
      userRepo,
      taskRepo,
      env: Env(environment: Environment.test),
      logger: Logger('UserCaseTest'),
    );
    stubUpdate();
    when(
      imageRepo.delete(
        authorId: anyNamed('authorId'),
        imageId: anyNamed('imageId'),
      ),
    ).thenAnswer((_) async {});
    when(imageRepo.deleteAllOf(userId: anyNamed('userId')))
        .thenAnswer((_) async {});
    when(
      imageRepo.put(
        authorId: anyNamed('authorId'),
        bytes: anyNamed('bytes'),
      ),
    ).thenAnswer((_) async => 'Inew');
    when(taskRepo.schedule(any)).thenAnswer((_) async => 'T1');
    when(userRepo.deleteById(id: anyNamed('id'))).thenAnswer((_) async {});
  });

  group('UserCase.getProfile', () {
    test('delegates to the user repository', () async {
      final entity = user(displayName: 'Ada Lovelace');
      when(userRepo.getById(userId)).thenAnswer((_) async => entity);

      expect(await case_.getProfile(id: userId), entity);
      verify(userRepo.getById(userId)).called(1);
    });
  });

  group('UserCase.updateProfile', () {
    test('forwards displayName and description to the repository', () async {
      final refreshed = user(
        displayName: 'Ada L.',
        description: 'Mathematician',
      );
      stubGetById(refreshed);

      final result = await case_.updateProfile(
        id: userId,
        displayName: 'Ada L.',
        description: 'Mathematician',
      );

      expect(result, refreshed);
      verify(
        userRepo.update(
          id: userId,
          displayName: 'Ada L.',
          description: 'Mathematician',
          imageId: null,
          dropImage: false,
          setHandle: false,
          handle: null,
        ),
      ).called(1);
      verify(userRepo.getById(userId)).called(1);
    });

    group('handle validation', () {
      test('rejects an invalid handle when setHandle is true', () async {
        await expectLater(
          case_.updateProfile(
            id: userId,
            setHandle: true,
            handle: 'Bad-Handle',
          ),
          throwsA(
            isA<IdWrongException>().having(
              (e) => e.description,
              'description',
              contains('lowercase letters, digits, underscore'),
            ),
          ),
        );
        verifyNever(
          userRepo.update(
            id: anyNamed('id'),
            displayName: anyNamed('displayName'),
            description: anyNamed('description'),
            imageId: anyNamed('imageId'),
            dropImage: anyNamed('dropImage'),
            setHandle: anyNamed('setHandle'),
            handle: anyNamed('handle'),
          ),
        );
      });

      test('rejects a too-short handle after trim', () async {
        await expectLater(
          case_.updateProfile(
            id: userId,
            setHandle: true,
            handle: '  ab  ',
          ),
          throwsA(isA<IdWrongException>()),
        );
      });

      test('accepts a valid handle and forwards setHandle to the repository',
          () async {
        final refreshed = user(handle: 'alice_smith');
        stubGetById(refreshed);

        await case_.updateProfile(
          id: userId,
          setHandle: true,
          handle: '  Alice_Smith  ',
        );

        verify(
          userRepo.update(
            id: userId,
            displayName: null,
            description: null,
            imageId: null,
            dropImage: false,
            setHandle: true,
            handle: '  Alice_Smith  ',
          ),
        ).called(1);
      });

      test('skips validation when setHandle is false', () async {
        stubGetById(user());

        await case_.updateProfile(
          id: userId,
          setHandle: false,
          handle: 'INVALID',
        );

        verify(
          userRepo.update(
            id: userId,
            displayName: null,
            description: null,
            imageId: null,
            dropImage: false,
            setHandle: false,
            handle: 'INVALID',
          ),
        ).called(1);
      });

      test('skips validation when handle is empty after trim', () async {
        stubGetById(user());

        await case_.updateProfile(
          id: userId,
          setHandle: true,
          handle: '   ',
        );

        verify(
          userRepo.update(
            id: userId,
            displayName: null,
            description: null,
            imageId: null,
            dropImage: false,
            setHandle: true,
            handle: '   ',
          ),
        ).called(1);
      });
    });

    group('image updates', () {
      test('deletes the existing image when dropImage is true', () async {
        stubGetById(user(image: sampleImage()));

        await case_.updateProfile(id: userId, dropImage: true);

        verify(
          imageRepo.delete(authorId: userId, imageId: 'Iold'),
        ).called(1);
        verify(
          userRepo.update(
            id: userId,
            displayName: null,
            description: null,
            imageId: null,
            dropImage: true,
            setHandle: false,
            handle: null,
          ),
        ).called(1);
        verifyNever(
          imageRepo.put(
            authorId: anyNamed('authorId'),
            bytes: anyNamed('bytes'),
          ),
        );
      });

      test('does not delete when the user has no image and dropImage is false',
          () async {
        stubGetById(user());

        await case_.updateProfile(id: userId, displayName: 'Alice');

        verifyNever(
          imageRepo.delete(
            authorId: anyNamed('authorId'),
            imageId: anyNamed('imageId'),
          ),
        );
      });

      test('uploads bytes, schedules hash task, and passes imageId', () async {
        stubGetById(user());
        final bytes = Stream<Uint8List>.value(Uint8List.fromList([1, 2, 3]));

        await case_.updateProfile(id: userId, imageBytes: bytes);

        final captured = verify(
          imageRepo.put(authorId: userId, bytes: captureAnyNamed('bytes')),
        ).captured.single as Stream<Uint8List>;
        expect(await captured.toList(), [Uint8List.fromList([1, 2, 3])]);

        verify(
          taskRepo.schedule(
            argThat(
              predicate<TaskEntity>(
                (task) =>
                    task.details is TaskCalculateImageHashDetails &&
                    (task.details! as TaskCalculateImageHashDetails).imageId ==
                        'Inew',
              ),
            ),
          ),
        ).called(1);
        verify(
          userRepo.update(
            id: userId,
            displayName: null,
            description: null,
            imageId: 'Inew',
            dropImage: false,
            setHandle: false,
            handle: null,
          ),
        ).called(1);
      });

      test('replaces an existing image by deleting old bytes first', () async {
        stubGetById(user(image: sampleImage()));
        final bytes = Stream<Uint8List>.value(Uint8List.fromList([9]));

        await case_.updateProfile(id: userId, imageBytes: bytes);

        verify(imageRepo.delete(authorId: userId, imageId: 'Iold')).called(1);
        verify(
          imageRepo.put(authorId: userId, bytes: anyNamed('bytes')),
        ).called(1);
      });
    });

    test('returns the refreshed user from the repository', () async {
      final refreshed = user(displayName: 'Updated');
      stubGetById(refreshed);

      expect(
        await case_.updateProfile(id: userId, displayName: 'Updated'),
        refreshed,
      );
      verify(userRepo.getById(userId)).called(1);
    });
  });

  group('UserCase.deleteById', () {
    test('deletes the user and all of their images', () async {
      expect(await case_.deleteById(id: userId), isTrue);
      verify(userRepo.deleteById(id: userId)).called(1);
      verify(imageRepo.deleteAllOf(userId: userId)).called(1);
    });
  });
}
