import 'dart:async';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:injectable/injectable.dart';
import 'package:blurhash_dart/blurhash_dart.dart';

import 'package:tentura_server/data/repository/image_repository.dart';
import 'package:tentura_server/data/repository/tasks_repository.dart';
import 'package:tentura_server/env.dart';

import '../entity/task_entity.dart';

@LazySingleton()
class TaskWorkerCase {
  @FactoryMethod()
  static Future<TaskWorkerCase> create(
    Env env,
    ImageRepository imageRepository,
    TaskRepository tasksRepository,
  ) => Future.value(
    TaskWorkerCase(
      env,
      imageRepository,
      tasksRepository,
    ),
  );

  TaskWorkerCase(
    this._env,
    this._imageRepository,
    this._tasksRepository,
  );

  final Env _env;

  final ImageRepository _imageRepository;

  final TaskRepository _tasksRepository;

  final _runnerCompleter = Completer<void>();

  late final _tasks = <Future<void> Function()>[
    // Calculate Image Hash
    () async {
      final task = await _tasksRepository
          .acquire<TaskEntity<TaskCalculateImageHashDetails>>();
      if (task == null) return;
      try {
        final imageBytes = await _imageRepository.get(
          id: task.details.imageId,
        );
        final (:hash, :height, :width) = processImage(imageBytes);

        await _imageRepository.update(
          id: task.details.imageId,
          blurHash: hash,
          height: height,
          width: width,
        );
        await _tasksRepository.complete(task.id);
      } catch (e) {
        await _tasksRepository.fail(task.id);
        rethrow;
      }
    },
  ];

  bool _canRun = true;

  Future<void> dispose() {
    _canRun = false;
    return _runnerCompleter.future;
  }

  Future<void> run() async {
    while (_canRun) {
      await Future<void>.delayed(_env.taskOnEmptyDelay);
      for (final task in _tasks) {
        try {
          if (_canRun) await task();
        } catch (e) {
          if (_env.isDebugModeOn) print(e);
        }
      }
    }
    _runnerCompleter.complete();
  }

  static ({String hash, int height, int width}) processImage(
    Uint8List imageBytes, [
    int kMaxNumCompX = 8,
    int kMinNumCompX = 6,
  ]) {
    final image =
        img.decodeImage(imageBytes) ??
        (throw const FormatException('Cant decode image'));
    final numComp = image.height == image.width
        ? (x: kMaxNumCompX, y: kMaxNumCompX)
        : image.height > image.width
        ? (x: kMinNumCompX, y: kMaxNumCompX)
        : (x: kMaxNumCompX, y: kMinNumCompX);
    return (
      hash: BlurHash.encode(
        image,
        numCompX: numComp.x,
        numCompY: numComp.y,
      ).hash,
      height: image.height,
      width: image.width,
    );
  }
}
