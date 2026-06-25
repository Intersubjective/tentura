import 'dart:async';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/service/email/email_link_builder.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/notification_outbox_repository_port.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';
import 'package:tentura_server/domain/use_case/email_digest_case.dart';
import 'package:tentura_server/domain/use_case/task_worker_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_access_guard.dart';

Uint8List _png(int width, int height) =>
    Uint8List.fromList(img.encodePng(img.Image(width: width, height: height)));

Env _testEnv({Duration? taskOnEmptyDelay}) => Env(
      environment: Environment.test,
      publicOrigin: 'https://t.example',
      unsubscribeSigningSecret: 'secret',
      taskOnEmptyDelay: taskOnEmptyDelay ?? Duration.zero,
    );

class _FakeTaskRepo implements TaskRepositoryPort {
  _FakeTaskRepo({this.pending});

  TaskEntity<TaskCalculateImageHashDetails>? pending;
  final completed = <String>[];
  final failed = <String>[];

  @override
  Future<T?> acquire<T extends TaskEntity>() async {
    final task = pending;
    pending = null;
    return task as T?;
  }

  @override
  Future<void> complete(String id) async => completed.add(id);

  @override
  Future<void> fail(String id) async => failed.add(id);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeImageRepo implements ImageRepositoryPort {
  Uint8List bytes = _png(8, 8);
  String? updatedId;
  String? updatedBlurHash;
  int? updatedHeight;
  int? updatedWidth;

  @override
  Future<Uint8List> get({required String id}) async => bytes;

  @override
  Future<void> update({
    required String id,
    required String blurHash,
    required int height,
    required int width,
  }) async {
    updatedId = id;
    updatedBlurHash = blurHash;
    updatedHeight = height;
    updatedWidth = width;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _CountingOutbox implements NotificationOutboxRepositoryPort {
  int accountsWithPendingCalls = 0;
  int deleteSettledCalls = 0;

  @override
  Future<List<String>> accountsWithPendingEmail() async {
    accountsWithPendingCalls++;
    return const [];
  }

  @override
  Future<int> deleteSettledOlderThan(Duration age) async {
    deleteSettledCalls++;
    return 0;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _NoopPrefs implements NotificationPreferenceRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _NoopContacts implements VerifiedContactRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _NoopEmail implements EmailSenderPort {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

EmailDigestCase _digestCase(_CountingOutbox outbox) => EmailDigestCase(
      _NoopPrefs(),
      outbox,
      _NoopContacts(),
      _NoopEmail(),
      EmailLinkBuilder(_testEnv()),
      _testEnv(),
      Logger('test'),
      FakeBeaconAccessGuard(),
    );

TaskWorkerCase _worker({
  required TaskRepositoryPort tasks,
  required ImageRepositoryPort images,
  required EmailDigestCase digest,
  required NotificationOutboxRepositoryPort outbox,
  Env? env,
}) =>
    TaskWorkerCase(
      images,
      tasks,
      digest,
      outbox,
      env: env ?? _testEnv(),
      logger: Logger('test'),
    );

Future<void> _runBriefly(TaskWorkerCase worker) async {
  unawaited(worker.run());
  await Future<void>.delayed(const Duration(milliseconds: 30));
  await worker.dispose();
}

void main() {
  group('TaskWorkerCase.processImage', () {
    test('square image uses max components on both axes', () {
      final result = TaskWorkerCase.processImage(_png(10, 10));
      expect(result.width, 10);
      expect(result.height, 10);
      expect(result.hash, isNotEmpty);
    });

    test('portrait image uses min x and max y components', () {
      final square = TaskWorkerCase.processImage(_png(10, 10));
      final portrait = TaskWorkerCase.processImage(_png(6, 12));
      expect(portrait.width, 6);
      expect(portrait.height, 12);
      expect(portrait.hash, isNot(isEmpty));
      expect(portrait.hash, isNot(square.hash));
    });

    test('landscape image uses max x and min y components', () {
      final square = TaskWorkerCase.processImage(_png(10, 10));
      final landscape = TaskWorkerCase.processImage(_png(12, 6));
      expect(landscape.width, 12);
      expect(landscape.height, 6);
      expect(landscape.hash, isNot(square.hash));
    });

    test('invalid bytes throw when image cannot be decoded', () {
      expect(
        () => TaskWorkerCase.processImage(Uint8List(64)),
        throwsA(isA<Object>()),
      );
    });
  });

  group('TaskWorkerCase.run smoke', () {
    test('processes calculate-image-hash task and updates image metadata', () async {
      final tasks = _FakeTaskRepo(
        pending: const TaskEntity<TaskCalculateImageHashDetails>(
          id: 'task-1',
          details: TaskCalculateImageHashDetails(imageId: 'img-1'),
        ),
      );
      final images = _FakeImageRepo();
      final outbox = _CountingOutbox();
      final worker = _worker(
        tasks: tasks,
        images: images,
        digest: _digestCase(outbox),
        outbox: outbox,
      );

      await _runBriefly(worker);

      expect(tasks.completed, ['task-1']);
      expect(tasks.failed, isEmpty);
      expect(images.updatedId, 'img-1');
      expect(images.updatedBlurHash, isNotEmpty);
      expect(images.updatedHeight, 8);
      expect(images.updatedWidth, 8);
    });

    test('marks task failed when image bytes cannot be decoded', () async {
      final tasks = _FakeTaskRepo(
        pending: const TaskEntity<TaskCalculateImageHashDetails>(
          id: 'task-bad',
          details: TaskCalculateImageHashDetails(imageId: 'img-bad'),
        ),
      );
      final images = _FakeImageRepo()..bytes = Uint8List.fromList([0, 1, 2]);
      final outbox = _CountingOutbox();
      final worker = _worker(
        tasks: tasks,
        images: images,
        digest: _digestCase(outbox),
        outbox: outbox,
      );

      await _runBriefly(worker);

      expect(tasks.failed, ['task-bad']);
      expect(tasks.completed, isEmpty);
      expect(images.updatedId, isNull);
    });

    test('throttles digest and retention sweeps within their windows', () async {
      final outbox = _CountingOutbox();
      final worker = _worker(
        tasks: _FakeTaskRepo(),
        images: _FakeImageRepo(),
        digest: _digestCase(outbox),
        outbox: outbox,
      );

      await _runBriefly(worker);

      expect(outbox.accountsWithPendingCalls, 1);
      expect(outbox.deleteSettledCalls, 1);
    });

    test('dispose stops the worker loop', () async {
      final worker = _worker(
        tasks: _FakeTaskRepo(),
        images: _FakeImageRepo(),
        digest: _digestCase(_CountingOutbox()),
        outbox: _CountingOutbox(),
      );

      final runFuture = worker.run();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await worker.dispose();
      await expectLater(runFuture, completes);
    });
  });
}
