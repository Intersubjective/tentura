@Tags(['pg'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:http/http.dart' as http;
// MultipartFile exposes the media type from http's dependency.
// ignore: depend_on_referenced_packages
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as image;
import 'package:minio/minio.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_plus/shelf_plus.dart' show Request, Response;
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura_server/api/root_router.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/person_subject.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/private_avatar_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/phantom_case.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_server/utils/id.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/session_database_di_harness.dart';

const _dailyCap = 11 * 1024 * 1024;
const _quotaError = RateLimitedException(
  description: 'Daily upload limit reached, try again tomorrow',
);
const _avatarMutation = 'personPrivateAvatarUpload';
const _avatarPath = '/api/v2/private-avatars';
const _minioOptIn = 'TENTURA_PRIVATE_AVATAR_TEST_MINIO';

const _aclVariable = 'S3_OBJECT_ACL';
const _aclChild = 'TENTURA_AVATAR_ACL_TEST_CHILD';
const _aclRequestTest = 'private and ordinary uploads send their expected ACLs';
const _aclCases = <String?, ({String? ordinary, String? avatar})>{
  null: (ordinary: 'public-read', avatar: 'private'),
  'omit': (ordinary: null, avatar: null),
  'none': (ordinary: null, avatar: null),
  'false': (ordinary: null, avatar: null),
  'public-read': (ordinary: 'public-read', avatar: 'private'),
  'authenticated-read': (ordinary: 'authenticated-read', avatar: 'private'),
};

typedef _Subject = ({String? userId, String? phantomId});

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PRIVATE_AVATAR_API_TEST_DB',
    defaultNamePrefix: 'tentura_test_private_avatar_api',
    useDevBindings: true,
  );
  final skip = await pgSkipReason(target);

  if (Platform.environment[_aclChild] == '1') {
    late _S3Recorder storage;
    late _Fixture fixture;
    setUpAll(() async {
      storage = await _S3Recorder.start();
      fixture = await _Fixture.startWithDisposableDatabase(
        target,
        endpoint: storage.endpoint,
        bucket: _S3Recorder.bucket,
        accessKey: 'test-access-key',
        secretKey: 'test-secret-key',
      );
    });

    test(_aclRequestTest, () async {
      final configuredAcl = Platform.environment[_aclVariable];
      final expected = _aclCases[configuredAcl]!;
      final owner = await fixture.user();
      final subject = (userId: await fixture.user(), phantomId: null);
      final ordinaryId = await fixture.ordinaryUpload(owner, _jpeg());
      final avatarJpeg = image.encodeJpg(image.Image(width: 512, height: 512));
      await fixture.upload(owner, subject, avatarJpeg);
      final avatarKey = await fixture.avatarKey(owner, subject);
      final avatar = (await fixture.avatarRows(owner)).single.toColumnMap();
      expect(avatar['width'], 512);
      expect(avatar['height'], 512);
      expect(avatar['blurhash'], allOf(isA<String>(), isNotEmpty));
      expect(avatarKey, _avatarKeyPattern(owner));
      expect(storage.objects[avatarKey], avatarJpeg);

      expect(storage.puts, [
        (
          key: 'images/$owner/$ordinaryId.jpg',
          acl: expected.ordinary,
          contentType: 'image/jpeg',
        ),
        (
          key: avatarKey,
          acl: expected.avatar,
          contentType: 'image/jpeg',
        ),
      ], reason: 'S3_OBJECT_ACL=$configuredAcl');
    }, skip: skip);
    return;
  }

  group('S3 upload ACL policy', () {
    for (final configuredAcl in _aclCases.keys) {
      test(
        'sends the expected PUT headers with $_aclVariable ${configuredAcl ?? 'unset'}',
        () async {
          // Env reads Platform.environment, so each configuration needs a fresh VM.
          final output = await _runDart(
            [
              'test',
              '--reporter=expanded',
              '--plain-name=$_aclRequestTest',
              'test/api/controllers/private_avatar_upload_pg_test.dart',
            ],
            environment: {
              for (final entry in Platform.environment.entries)
                if (entry.key != _aclVariable) entry.key: entry.value,
              _aclChild: '1',
              _aclVariable: ?configuredAcl,
            },
            timeout: const Duration(seconds: 45),
          );
          expect(output.code, 0, reason: output.diagnostics);
          expect(
            output.stdout,
            contains('All tests passed!'),
            reason: output.diagnostics,
          );
        },
      );
    }
  }, skip: skip);

  group('Private avatar API', () {
    late _S3Recorder storage;
    late _Fixture fixture;
    late String owner;
    late _Subject subject;
    final jpeg = _jpeg();

    setUpAll(() async {
      storage = await _S3Recorder.start();
      fixture = await _Fixture.startWithDisposableDatabase(
        target,
        endpoint: storage.endpoint,
        bucket: _S3Recorder.bucket,
        accessKey: 'test-access-key',
        secretKey: 'test-secret-key',
      );
    });

    setUp(() async {
      storage.reset();
      owner = await fixture.user();
      subject = (userId: await fixture.user(), phantomId: null);
    });

    group('Private avatar JPEG validation', () {
      Future<void> put(Uint8List bytes, {String? asOwner}) =>
          getIt<PrivateAvatarRepositoryPort>().put(
            ownerId: asOwner ?? owner,
            subject: PersonSubject.user(subject.userId!),
            bytes: Stream.value(bytes),
          );

      for (final (label, marker) in [
        ('baseline', 0xc0),
        ('progressive', 0xc2),
      ]) {
        for (final (completeScan, scanDescription) in [
          (false, 'with a tiny scan'),
          (true, 'with a complete scan'),
        ]) {
          test(
            'rejects oversized $label JPEGs $scanDescription before writing anything',
            () async {
              await expectLater(
                put(image.encodePng(image.Image(width: 8, height: 8))),
                throwsA(
                  isA<IdWrongException>().having(
                    (error) => error.description,
                    'description',
                    'Invalid JPEG image',
                  ),
                ),
              );
              final jpeg = _oversizedJpeg(marker, completeScan: completeScan);
              await _expectRejectionWithinHeapLimit(jpeg);

              await expectLater(
                put(jpeg),
                throwsA(
                  isA<IdWrongException>().having(
                    (error) => error.description,
                    'description',
                    _dimensionError,
                  ),
                ),
              );

              expect(await fixture.avatarRows(owner), isEmpty);
              expect(await fixture.usedBytes(owner), 0);
              expect(storage.puts, isEmpty);
            },
          );
        }
      }

      test('decodes at the pixel cap and rejects one column over it', () async {
        final (width, height) = _jpegDimensionsAt(kMaxPrivateAvatarPixels);
        final accepted = _flatJpeg(0xc0, width: width, height: height);
        await put(accepted);

        final row = (await fixture.avatarRows(owner)).single.toColumnMap();
        expect(row['width'], width);
        expect(row['height'], height);
        expect(row['blurhash'], allOf(isA<String>(), isNotEmpty));
        expect(row['object_key'], _avatarKeyPattern(owner));
        expect(storage.puts.single.key, row['object_key']);
        expect(storage.objects[storage.puts.single.key], accepted);

        final otherOwner = await fixture.user();
        await expectLater(
          put(
            _flatJpeg(0xc0, width: width + 1, height: height),
            asOwner: otherOwner,
          ),
          throwsA(
            isA<IdWrongException>().having(
              (error) => error.description,
              'description',
              _dimensionError,
            ),
          ),
        );
        expect(await fixture.avatarRows(otherOwner), isEmpty);
        expect(await fixture.usedBytes(otherOwner), 0);
        expect(storage.puts, hasLength(1));
      });
    });

    for (final onAccount in [true, false]) {
      test(
        onAccount
            ? 'stores the JPEG on a Tentura account with a private ACL'
            : 'stores the JPEG on someone not on Tentura yet with a private ACL',
        () async {
          final person = onAccount
              ? subject
              : (
                  userId: null,
                  phantomId: await getIt<PhantomCase>().create(
                    ownerId: owner,
                    name: 'Anna',
                  ),
                );

          final ordinaryId = await fixture.ordinaryUpload(owner, jpeg);
          final ordinaryKey = 'images/$owner/$ordinaryId.jpg';
          final ordinaryPut = storage.puts.single;
          expect(ordinaryPut.key, ordinaryKey);
          expect(ordinaryPut.acl, 'public-read');
          expect(ordinaryPut.contentType, 'image/jpeg');

          await fixture.upload(owner, person, jpeg);

          final key = await fixture.avatarKey(owner, person);
          expect(key, _avatarKeyPattern(owner));
          expect(storage.puts.map((put) => put.key), [ordinaryKey, key]);
          final privatePut = storage.puts.last;
          expect(privatePut.acl, 'private');
          expect(privatePut.contentType, 'image/jpeg');
          expect(storage.objects[key], jpeg);
        },
      );
    }

    for (final (caller, status) in [
      ('the avatar subject', HttpStatus.forbidden),
      ('another signed-in account', HttpStatus.forbidden),
      ('a caller without a bearer token', HttpStatus.unauthorized),
    ]) {
      test('does not serve the JPEG to $caller', () async {
        final key = await fixture.seedAvatar(owner, subject, jpeg);
        final viewer = switch (caller) {
          'the avatar subject' => subject.userId,
          'another signed-in account' => await fixture.user(),
          _ => null,
        };

        final reply = await fixture.download(key, viewer: viewer);

        _expectNoImage(
          status: reply.statusCode,
          expectedStatus: status,
          contentType: reply.headers['content-type'],
          body: reply.bodyBytes,
        );
      });
    }

    test('serves the original JPEG to its owner', () async {
      final key = await fixture.seedAvatar(owner, subject, jpeg);

      await _expectOwnerDownload(fixture, key: key, owner: owner, jpeg: jpeg);
    });

    test(
      'rejects a JPEG one byte over the limit before using storage or quota',
      () async {
        final reply = await fixture.uploadReply(
          owner,
          subject,
          _jpeg(length: kMaxImageUploadBytes + 1),
        );

        _expectUploadError(reply, const PayloadTooLargeException());
        expect(await fixture.avatarRows(owner), isEmpty);
        expect(storage.puts, isEmpty);
        expect(storage.objects, isEmpty);
        expect(await fixture.usedBytes(owner), 0);
      },
    );

    test(
      'accepts and stores a JPEG exactly at the upload size limit',
      () async {
        final maxSizeJpeg = _jpeg(length: kMaxImageUploadBytes);

        await fixture.upload(owner, subject, maxSizeJpeg);

        final key = await fixture.avatarKey(owner, subject);
        expect(storage.objects[key], maxSizeJpeg);
        expect(await fixture.usedBytes(owner), kMaxImageUploadBytes);
      },
    );

    test(
      'ordinary image uploads consume the quota available to private avatars',
      () async {
        await fixture.ordinaryUpload(
          owner,
          _jpeg(length: kMaxImageUploadBytes),
        );
        final bytesRemaining = jpeg.length - 1;
        final alreadyUsed = _dailyCap - bytesRemaining;
        await fixture.ordinaryUpload(
          owner,
          _jpeg(length: alreadyUsed - kMaxImageUploadBytes),
        );
        expect(await fixture.usedBytes(owner), alreadyUsed);

        final reply = await fixture.uploadReply(owner, subject, jpeg);

        _expectUploadError(reply, _quotaError);
        expect(await fixture.avatarRows(owner), isEmpty);
        expect(
          storage.puts.map((put) => put.key),
          everyElement(startsWith('images/$owner/')),
        );
        expect(
          storage.objects.keys,
          everyElement(startsWith('images/$owner/')),
        );
        expect(await fixture.usedBytes(owner), alreadyUsed);
      },
    );

    test(
      'private avatars consume the quota available to ordinary image uploads',
      () async {
        await fixture.ordinaryUpload(
          owner,
          _jpeg(length: kMaxImageUploadBytes),
        );
        await fixture.upload(owner, subject, jpeg);

        await expectLater(
          fixture.ordinaryUpload(
            owner,
            _jpeg(length: _dailyCap - kMaxImageUploadBytes),
          ),
          throwsA(
            isA<RateLimitedException>().having(
              (error) => error.description,
              'description',
              _quotaError.description,
            ),
          ),
        );
        expect(
          await fixture.usedBytes(owner),
          kMaxImageUploadBytes + jpeg.length,
        );
        expect(storage.puts, hasLength(2));
      },
    );

    test(
      'a failed object write reports an error and queues the abandoned key',
      () async {
        storage.failPuts = true;

        final reply = await fixture.uploadReply(owner, subject, jpeg);

        expect(reply['errors'], isNotEmpty, reason: jsonEncode(reply));
        expect(
          (reply['data'] as Map?)?[_avatarMutation],
          anyOf(isNull, isFalse),
        );
        expect(storage.puts, hasLength(1), reason: jsonEncode(reply));
        final attemptedKey = storage.puts.single.key;
        expect(attemptedKey, _avatarKeyPattern(owner));
        expect(await fixture.avatarRows(owner), isEmpty);
        expect(await fixture.retiredKeys(owner), [attemptedKey]);
      },
    );

    test(
      'replacing an avatar keeps one current row and queues the old object',
      () async {
        await fixture.upload(owner, subject, jpeg);
        final firstKey = await fixture.avatarKey(owner, subject);
        expect(await fixture.retiredKeys(owner), isEmpty);
        final replacement = _jpeg(red: 120);

        await fixture.upload(owner, subject, replacement);

        final newKey = await fixture.avatarKey(owner, subject);
        expect(newKey, _avatarKeyPattern(owner));
        expect(newKey, isNot(firstKey));
        expect(storage.objects[newKey], replacement);
        expect(await fixture.retiredKeys(owner), [firstKey]);
      },
    );
  }, skip: skip);

  group(
    'Private avatars on MinIO',
    () {
      late Uri origin;
      late String bucket;
      late _Fixture fixture;

      setUpAll(() async {
        final endpoint =
            Platform.environment['TENTURA_TEST_MINIO_ENDPOINT'] ??
            '127.0.0.1:9000';
        final accessKey =
            Platform.environment['TENTURA_TEST_MINIO_ACCESS_KEY'] ??
            'minioadmin';
        final secretKey =
            Platform.environment['TENTURA_TEST_MINIO_SECRET_KEY'] ??
            'minioadmin';
        origin = Uri.parse('http://$endpoint');
        final minio = Minio(
          endPoint: origin.host,
          port: origin.port,
          useSSL: false,
          accessKey: accessKey,
          secretKey: secretKey,
          pathStyle: true,
        );
        bucket = 'tentura-avatar-${const Uuid().v4()}';
        await minio.makeBucket(bucket);
        addTearDown(() async {
          final listed = await minio.listAllObjects(bucket, recursive: true);
          for (final object in listed.objects) {
            await minio.removeObject(bucket, object.key!);
          }
          await minio.removeBucket(bucket);
        });
        await minio.setBucketPolicy(
          bucket,
          {
            'Version': '2012-10-17',
            'Statement': [
              {
                'Effect': 'Allow',
                'Principal': '*',
                'Action': ['s3:GetObject'],
                'Resource': ['arn:aws:s3:::$bucket/images/*'],
              },
            ],
          },
        );

        fixture = await _Fixture.startWithDisposableDatabase(
          target,
          endpoint: endpoint,
          bucket: bucket,
          accessKey: accessKey,
          secretKey: secretKey,
        );
      });

      test(
        'the owner can download an uploaded avatar that MinIO denies to anonymous GET',
        () async {
          final owner = await fixture.user();
          final subject = (userId: await fixture.user(), phantomId: null);
          final jpeg = _jpeg();
          Uri objectUrl(String key) => origin.replace(path: '/$bucket/$key');
          final client = http.Client();
          addTearDown(client.close);

          final ordinaryId = await fixture.ordinaryUpload(owner, jpeg);
          final ordinary = await client.get(
            objectUrl('images/$owner/$ordinaryId.jpg'),
          );
          expect(ordinary.statusCode, HttpStatus.ok);
          expect(ordinary.bodyBytes, jpeg);

          await fixture.upload(owner, subject, jpeg);
          final key = await fixture.avatarKey(owner, subject);
          expect(key, _avatarKeyPattern(owner));
          expect(await getIt<RemoteStoragePort>().getObject(key), jpeg);

          final anonymous = await client.get(objectUrl(key));
          _expectNoImage(
            status: anonymous.statusCode,
            expectedStatus: HttpStatus.forbidden,
            contentType: anonymous.headers['content-type'],
            body: anonymous.bodyBytes,
          );
          await _expectOwnerDownload(
            fixture,
            key: key,
            owner: owner,
            jpeg: jpeg,
          );
        },
      );
    },
    skip:
        skip ??
        (Platform.environment[_minioOptIn] == '1'
            ? null
            : 'Set $_minioOptIn=1 to run against local MinIO.'),
  );
}

final class _Fixture {
  _Fixture(this._db, this._origin, this._client);

  final Connection _db;
  final Uri _origin;
  final http.Client _client;

  static Future<_Fixture> startWithDisposableDatabase(
    DisposablePgTarget target, {
    required String endpoint,
    required String bucket,
    required String accessKey,
    required String secretKey,
  }) async {
    final previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
    });
    final session = await setUpDisposablePgWriter(target: target);
    addTearDown(() => tearDownDisposablePgWriter(session: session));
    addTearDown(() async {
      getIt.skipDoubleRegistration = false;
      await getIt.reset();
    });
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final origin = Uri(scheme: 'http', host: '127.0.0.1', port: server.port);
    final db = target.databaseEnv;
    final env = Env(
      environment: db.environment,
      publicKey: Env.kJwtPublicKey,
      privateKey: Env.kJwtPrivateKey,
      pgHost: db.pgHost,
      pgPort: db.pgPort,
      pgDatabase: db.pgDatabase,
      pgUsername: db.pgUsername,
      pgPassword: db.pgPassword,
      workersCount: 1,
      printEnv: false,
      // Resolve the schema against each group's own database and storage.
      isDebugModeOn: true,
      serverUri: origin,
      publicOrigin: origin.origin,
      uploadDailyCapBytes: _dailyCap,
      kS3Endpoint: endpoint,
      kS3Bucket: bucket,
      kS3AccessKey: accessKey,
      kS3SecretKey: secretKey,
      kS3PathStyle: true,
      kS3UseSSL: false,
    );
    await configureSessionDatabaseTestGraph(env);
    final router = await getIt.getAsync<RootRouter>();
    shelf_io.serveRequests(server, router.routeHandler());
    final client = http.Client();
    addTearDown(client.close);
    return _Fixture(session.writer, origin, client);
  }

  Future<String> user() async {
    final id = generateId('U');
    await _db.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': 'pk-$id'},
    );
    return id;
  }

  Future<Result> avatarRows(String owner) => _db.execute(
    Sql.named('''
SELECT subject_user_id, subject_phantom_id, object_key, width, height, blurhash
FROM public.person_private_avatar WHERE owner_id = @owner
'''),
    parameters: {'owner': owner},
  );

  Future<String> avatarKey(String owner, _Subject subject) async {
    final rows = await avatarRows(owner);
    expect(rows, hasLength(1));
    final row = rows.single.toColumnMap();
    expect(row['subject_user_id'], subject.userId);
    expect(row['subject_phantom_id'], subject.phantomId);
    return row['object_key']! as String;
  }

  Future<List<String>> retiredKeys(String owner) async {
    final rows = await _db.execute(
      Sql.named('''
SELECT object_key FROM public.private_object_gc
WHERE object_key LIKE @prefix ORDER BY object_key
'''),
      parameters: {'prefix': 'private/$owner/%'},
    );
    return [for (final row in rows) row.single! as String];
  }

  Future<String> seedAvatar(
    String owner,
    _Subject subject,
    Uint8List jpeg,
  ) async {
    final key = 'private/$owner/${const Uuid().v4()}.jpg';
    await _db.executeWithOwnerScopes(
      [owner],
      Sql.named('''
INSERT INTO public.person_private_avatar
  (owner_id, subject_user_id, subject_phantom_id, object_key, blurhash, width, height)
VALUES (@owner, @userId, @phantomId, @key, 'LEHV6nWB2yk8pyo0adR*.7kCMdnj', 8, 8)
'''),
      parameters: {
        'owner': owner,
        'userId': subject.userId,
        'phantomId': subject.phantomId,
        'key': key,
      },
    );
    await getIt<RemoteStoragePort>().putObject(key, Stream.value(jpeg));
    return key;
  }

  Future<int> usedBytes(String owner) =>
      getIt<UploadQuotaRepositoryPort>().usedBytesToday(owner);

  Future<String> ordinaryUpload(String owner, Uint8List jpeg) =>
      getIt<ImageRepositoryPort>().put(
        authorId: owner,
        bytes: Stream.value(jpeg),
      );

  Future<void> upload(String owner, _Subject subject, Uint8List jpeg) async {
    final reply = await uploadReply(owner, subject, jpeg);
    expect(reply['errors'], isNull, reason: jsonEncode(reply));
    expect(reply['data'], containsPair(_avatarMutation, isTrue));
  }

  Future<Map<String, Object?>> uploadReply(
    String owner,
    _Subject subject,
    Uint8List jpeg,
  ) async {
    final uri = _origin.resolve(kPathGraphQLEndpointV2);
    final multipart = http.MultipartRequest('POST', uri)
      ..headers['authorization'] = _bearer(owner)
      ..fields['operations'] = jsonEncode({
        'operationName': 'UploadAvatar',
        'query': r'''
mutation UploadAvatar($userId: String, $phantomId: String, $file: Upload) {
  personPrivateAvatarUpload(subjectUserId: $userId, subjectPhantomId: $phantomId, file: $file)
}
''',
        'variables': {
          'userId': subject.userId,
          'phantomId': subject.phantomId,
          'file': {'filename': 'avatar.jpg', 'type': 'image/jpeg'},
        },
      })
      ..fields['map'] = jsonEncode({
        '0': ['variables.file'],
      })
      ..files.add(
        http.MultipartFile.fromBytes(
          '0',
          jpeg,
          filename: 'avatar.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      );
    final reply = await http.Response.fromStream(await _client.send(multipart));
    expect(reply.statusCode, HttpStatus.ok, reason: reply.body);
    return jsonDecode(reply.body) as Map<String, Object?>;
  }

  Future<http.Response> download(String key, {required String? viewer}) =>
      _client.get(
        _origin
            .resolve(_avatarPath)
            .replace(queryParameters: {'objectKey': key}),
        headers: {if (viewer != null) 'authorization': _bearer(viewer)},
      );

  String _bearer(String user) =>
      'Bearer ${getIt<AuthCase>().issueAccessToken(user).rawToken}';
}

final class _S3Recorder {
  static const bucket = 'avatar-test-bucket';

  final puts = <({String key, String? acl, String? contentType})>[];
  final objects = <String, Uint8List>{};
  bool failPuts = false;
  late final String endpoint;

  static Future<_S3Recorder> start() async {
    final storage = _S3Recorder();
    final server = await shelf_io.serve(
      storage._handle,
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    storage.endpoint = '127.0.0.1:${server.port}';
    return storage;
  }

  void reset() {
    puts.clear();
    objects.clear();
    failPuts = false;
  }

  Future<Response> _handle(Request request) async {
    final path = request.url.pathSegments;
    if (path.firstOrNull != bucket) {
      return Response.notFound(null);
    }
    if (request.url.queryParameters.containsKey('location')) {
      return Response.ok('<LocationConstraint>us-east-1</LocationConstraint>');
    }
    final key = path.skip(1).join('/');
    switch (request.method) {
      case 'PUT':
        puts.add((
          key: key,
          acl: request.headers['x-amz-acl'],
          contentType: request.headers['content-type'],
        ));
        final bytes = await _readBytes(request.read());
        if (failPuts) {
          return Response.internalServerError(
            body:
                '<Error><Code>InternalError</Code><Message>Put failed</Message></Error>',
          );
        }
        objects[key] = bytes;
        return Response.ok(null, headers: {'etag': '"test-etag"'});
      case 'GET':
        final bytes = objects[key];
        return bytes == null
            ? Response.notFound(null)
            : Response.ok(
                bytes,
                headers: {'content-length': '${bytes.length}'},
              );
      default:
        return Response.notFound(null);
    }
  }
}

Matcher _avatarKeyPattern(String owner) => matches(
  '^private/${RegExp.escape(owner)}/'
  r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$',
);

void _expectUploadError(Map<String, Object?> reply, ExceptionBase error) {
  expect(
    reply['errors'],
    contains(
      allOf(
        containsPair('message', error.description),
        containsPair(
          'extensions',
          containsPair('code', '${error.code.codeNumber}'),
        ),
      ),
    ),
    reason: jsonEncode(reply),
  );
  expect((reply['data'] as Map?)?[_avatarMutation], anyOf(isNull, isFalse));
}

Future<void> _expectOwnerDownload(
  _Fixture fixture, {
  required String key,
  required String owner,
  required Uint8List jpeg,
}) async {
  final reply = await fixture.download(key, viewer: owner);
  expect(reply.statusCode, HttpStatus.ok);
  expect(reply.headers['content-type'], 'image/jpeg');
  expect(reply.bodyBytes, jpeg);
}

void _expectNoImage({
  required int status,
  required int expectedStatus,
  required String? contentType,
  required Uint8List body,
}) {
  expect(status, expectedStatus);
  expect(contentType ?? '', isNot(startsWith('image/')));
  expect(body, isNot(containsAllInOrder([0xff, 0xd8, 0xff])));
}

Future<Uint8List> _readBytes(Stream<List<int>> stream) async {
  final buffer = BytesBuilder(copy: false);
  await stream.forEach(buffer.add);
  return buffer.takeBytes();
}

Uint8List _jpeg({int? length, int red = 255}) {
  final pixels = image.Image(width: 8, height: 8)
    ..clear(image.ColorRgb8(red, 30, 60));
  final jpeg = image.encodeJpg(pixels);
  if (length == null) return jpeg;

  // Pad with valid JPEG comment segments so the exact byte-limit fixtures
  // remain decodable images with the same pixels.
  final padded = Uint8List(length);
  var offset = 2;
  var remaining = length - jpeg.length;
  padded.setRange(0, offset, jpeg);
  while (remaining > 0) {
    var segmentSize = remaining.clamp(4, 65537);
    final tail = remaining - segmentSize;
    if (tail > 0 && tail < 4) segmentSize -= 4 - tail;
    final payloadSize = segmentSize - 2;
    padded[offset] = 0xff;
    padded[offset + 1] = 0xfe;
    padded[offset + 2] = payloadSize >> 8;
    padded[offset + 3] = payloadSize & 0xff;
    offset += segmentSize;
    remaining -= segmentSize;
  }
  padded.setRange(offset, length, jpeg, 2);
  return padded;
}

final _dimensionError = matches(
  RegExp(
    '(?:image|jpeg|avatar) dimensions'
    r'(?:\s*[:=]?\s*\(?[0-9,]+\s*[×x]\s*[0-9,]+\)?)?'
    r'\s+(?:(?:are\s+)?too large|exceed\b)',
    caseSensitive: false,
  ),
);

const _oversizedDimension = 30000;

(int, int) _jpegDimensionsAt(int cap) {
  const maxDimension = 65535;
  for (
    var width = math.min(math.sqrt(cap).floor(), maxDimension - 1);
    width > 0;
    width--
  ) {
    final height = cap ~/ width;
    if (height > maxDimension) break;
    if (cap % width == 0) return (width, height);
  }
  throw StateError(
    'The pixel cap $cap cannot be represented by a JPEG frame',
  );
}

Uint8List _oversizedJpeg(int frameMarker, {required bool completeScan}) {
  final small = _flatJpeg(frameMarker, width: 8, height: 8);
  final decoded = image.decodeJpg(small);
  expect((decoded?.width, decoded?.height), (8, 8));

  final jpeg = _flatJpeg(
    frameMarker,
    width: _oversizedDimension,
    height: _oversizedDimension,
    tinyScan: !completeScan,
  );
  expect(image.JpegDecoder().isValidFile(jpeg), isTrue);
  if (completeScan) {
    expect(jpeg.length, lessThan(kMaxImageUploadBytes));
  } else {
    expect(jpeg.length, lessThan(1024));
  }
  return jpeg;
}

Uint8List _flatJpeg(
  int frameMarker, {
  required int width,
  required int height,
  bool tinyScan = false,
}) {
  final blocks = tinyScan ? 1 : ((width + 7) ~/ 8) * ((height + 7) ~/ 8);
  final bytes = BytesBuilder(copy: false)..add([0xff, 0xd8]);

  void segment(int marker, List<int> payload) {
    final length = payload.length + 2;
    bytes
      ..add([0xff, marker, length >> 8, length & 0xff])
      ..add(payload);
  }

  void scan(int start, int end, int bits) {
    segment(0xda, [1, 1, 0, start, end, 0]);
    bytes.add(Uint8List(bits ~/ 8));
    if (bits % 8 != 0) bytes.addByte((1 << (8 - bits % 8)) - 1);
  }

  segment(0xdb, [0, ...List.filled(64, 1)]);
  segment(frameMarker, [
    8, // Sample precision.
    height >> 8, height & 0xff,
    width >> 8, width & 0xff,
    1, 1, 0x11, 0, // One grayscale component, 1×1 sampling, table 0.
  ]);
  // Each Huffman table has one code, a zero bit. It means a zero-valued
  // DC difference in the first table and end-of-block in the AC table.
  final huffmanCodes = [1, ...List.filled(15, 0), 0];
  segment(0xc4, [0, ...huffmanCodes, 0x10, ...huffmanCodes]);
  if (frameMarker == 0xc2) {
    scan(0, 0, blocks);
    scan(1, 63, blocks);
  } else {
    scan(0, 63, blocks * 2);
  }
  bytes.add([0xff, 0xd9]);
  return bytes.takeBytes();
}

Future<void> _expectRejectionWithinHeapLimit(Uint8List jpeg) async {
  final output = await _runDart(
    [
      '--old_gen_heap_size=192',
      '--disable-dart-dev',
      'test/support/private_avatar_decode_probe.dart',
    ],
    input: jpeg,
    timeout: const Duration(seconds: 25),
  );
  expect(output.code, 0, reason: output.diagnostics);
  expect(output.stdout.trim(), _dimensionError, reason: output.diagnostics);
}

Future<({int code, String stdout, String diagnostics})> _runDart(
  List<String> arguments, {
  required Duration timeout,
  Map<String, String>? environment,
  Uint8List? input,
}) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    arguments,
    environment: environment,
    includeParentEnvironment: environment == null,
  );
  final stdout = process.stdout.transform(utf8.decoder).join();
  final stderr = process.stderr.transform(utf8.decoder).join();
  final exit = process.exitCode.timeout(
    timeout,
    onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      throw StateError(
        'Private avatar upload subprocess timed out after $timeout',
      );
    },
  );
  if (input != null) process.stdin.add(input);
  await Future.wait([process.stdin.close(), exit]);
  return (
    code: await exit,
    stdout: await stdout,
    diagnostics: '${await stdout}\n${await stderr}',
  );
}
