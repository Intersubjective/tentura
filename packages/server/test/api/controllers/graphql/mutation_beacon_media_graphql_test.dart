import 'dart:async';
import 'dart:typed_data';

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_beacon.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_media_state.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/fake_beacon_access_guard.dart';

class _StubBeaconRepo extends Fake implements BeaconRepositoryPort {
  BeaconEntity locked = BeaconEntity(
    id: 'B1',
    title: 'Title',
    author: const UserEntity(id: 'Uauth'),
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    status: BeaconStatus.open,
  );
  String? lastPrimaryNeedSlug;
  bool lastPrimaryNeedSlugProvided = false;
  int createCalls = 0;

  @override
  Future<int> countRecentByAuthor({
    required String userId,
    required Duration window,
  }) async => 0;

  @override
  Future<BeaconEntity> createBeacon({
    required String authorId,
    required String title,
    String? description,
    String? context,
    List<String>? imageIds,
    double? latitude,
    double? longitude,
    DateTime? startAt,
    DateTime? endAt,
    Set<String>? tags,
    Set<String>? needs,
    int ticker = 0,
    String? primaryNeedSlug,
    String? coverImageId,
    BeaconCoverSource coverSource = BeaconCoverSource.photo,
    BeaconStatus? status,
    String? addressLabel,
    String? lineageParentBeaconId,
    String? lineageRootBeaconId,
  }) async {
    createCalls++;
    return BeaconEntity(
      id: 'Bnew',
      title: title,
      author: UserEntity(id: authorId),
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      primaryNeedSlug: primaryNeedSlug,
    );
  }

  @override
  Future<T> runInBeaconStateTransaction<T>({
    required String beaconId,
    required String userId,
    required Future<T> Function(BeaconEntity locked) fn,
  }) => fn(locked);

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async => locked;

  @override
  Future<BeaconMediaSnapshot> getMediaSnapshot(String beaconId) async =>
      const BeaconMediaSnapshot(attachedImageIds: ['I1'], stagedImageIds: {});

  @override
  Future<List<String>> replaceMedia({
    required String beaconId,
    required List<String> imageIds,
    required String? coverImageId,
    required BeaconCoverSource coverSource,
    String? coverThumbImageId,
  }) async => const [];
}

class _FakeImageRepo extends Fake implements ImageRepositoryPort {}

class _FakeImageObjectGc extends Fake implements ImageObjectGcPort {}

class _FakeTaskRepo extends Fake implements TaskRepositoryPort {}

class _FakeCoordinationRepo extends Fake
    implements CoordinationRepositoryPort {}

class _FakeHelpOfferRepo extends Fake implements HelpOfferRepositoryPort {}

/// Unwraps `nonNullable()`/list wrappers to the innermost named type.
String _baseTypeName(GraphQLType type) {
  var t = type;
  while (true) {
    if (t is GraphQLNonNullableType) {
      t = t.ofType;
    } else if (t is GraphQLListType) {
      t = t.ofType;
    } else {
      return t.name ?? t.toString();
    }
  }
}

bool _isNonNullable(GraphQLType type) => type is GraphQLNonNullableType;

bool _isListOf(GraphQLType type, String innerName) {
  final unwrapped = type is GraphQLNonNullableType ? type.ofType : type;
  return unwrapped is GraphQLListType &&
      _baseTypeName(unwrapped.ofType) == innerName;
}

void main() {
  const auth = {kGlobalInputQueryJwt: JwtEntity(sub: 'Uauth')};

  late _StubBeaconRepo beaconRepo;
  late MutationBeacon mutation;

  setUp(() {
    beaconRepo = _StubBeaconRepo();
    final beaconCase = BeaconCase(
      beaconRepo,
      _FakeImageRepo(),
      _FakeImageObjectGc(),
      _FakeTaskRepo(),
      _FakeCoordinationRepo(),
      _FakeHelpOfferRepo(),
      FakeBeaconAccessGuard(),
      env: Env(environment: Environment.test),
      logger: Logger('MutationBeaconMediaGraphqlTest'),
    );
    mutation = MutationBeacon(beaconCase: beaconCase);
  });

  group('numeric error codes (§3.5)', () {
    test('the five new beacon codes are exact and additive (1304-1308)', () {
      expect(
        const BeaconExceptionCodes(
          BeaconExceptionCode.beaconPrimaryNeedInvalid,
        ).codeNumber,
        1304,
      );
      expect(
        const BeaconExceptionCodes(
          BeaconExceptionCode.beaconPrimaryNeedNotInNeeds,
        ).codeNumber,
        1305,
      );
      expect(
        const BeaconExceptionCodes(
          BeaconExceptionCode.beaconImageNotAttached,
        ).codeNumber,
        1306,
      );
      expect(
        const BeaconExceptionCodes(
          BeaconExceptionCode.beaconCoverNotAttached,
        ).codeNumber,
        1307,
      );
      expect(
        const BeaconExceptionCodes(
          BeaconExceptionCode.beaconMediaInvalid,
        ).codeNumber,
        1308,
      );
    });
  });

  group('new payload types (§2.3, §3.6)', () {
    test('BeaconImageAdded and BeaconImageStaged are registered', () {
      expect(
        customTypes.any((t) => t.name == 'BeaconImageAdded'),
        isTrue,
      );
      expect(
        customTypes.any((t) => t.name == 'BeaconImageStaged'),
        isTrue,
      );
      expect(gqlTypeBeaconImageAdded.fields.map((f) => f.name), [
        'id',
        'imageId',
        'beacon',
      ]);
      expect(gqlTypeBeaconImageStaged.fields.map((f) => f.name), [
        'imageId',
        'beaconId',
      ]);
    });

    test('Beacon exposes the additive cover/primary fields', () {
      final names = gqlTypeBeacon.fields.map((f) => f.name).toSet();
      expect(names, containsAll(['primaryNeedSlug', 'coverImageId', 'coverSource']));
      final coverSourceField = gqlTypeBeacon.fields.singleWhere(
        (f) => f.name == 'coverSource',
      );
      expect(_isNonNullable(coverSourceField.type), isTrue);
      expect(_baseTypeName(coverSourceField.type), 'Int');
    });

    test('mutation.all exposes the new stage/media fields alongside legacy ones', () {
      final names = mutation.all.map((f) => f.name).toSet();
      expect(
        names,
        containsAll([
          'beaconCreate',
          'beaconUpdate',
          'beaconUpdateDraft',
          'beaconAddImage',
          'beaconStageImage',
          'beaconSetMedia',
          'beaconRemoveImage',
          'beaconReorderImages',
        ]),
      );
    });
  });

  group('actual list/upload/int introspection (§3.6)', () {
    test('beaconSetMedia declares imageIds as a non-null list of non-null String', () {
      final field = mutation.all.singleWhere((f) => f.name == 'beaconSetMedia');
      final imageIds = field.inputs.singleWhere((i) => i.name == 'imageIds');
      expect(_isListOf(imageIds.type, 'String'), isTrue);
    });

    test('beaconSetMedia declares coverSource as a required Int', () {
      final field = mutation.all.singleWhere((f) => f.name == 'beaconSetMedia');
      final coverSource = field.inputs.singleWhere(
        (i) => i.name == 'coverSource',
      );
      expect(_isNonNullable(coverSource.type), isTrue);
      expect(_baseTypeName(coverSource.type), 'Int');
    });

    test('beaconSetMedia declares coverImageId as optional', () {
      final field = mutation.all.singleWhere((f) => f.name == 'beaconSetMedia');
      final coverImageId = field.inputs.singleWhere(
        (i) => i.name == 'coverImageId',
      );
      expect(_isNonNullable(coverImageId.type), isFalse);
    });

    test('beaconStageImage declares the upload as Upload (Hasura: v2_Upload)', () {
      final field = mutation.all.singleWhere(
        (f) => f.name == 'beaconStageImage',
      );
      final upload = field.inputs.singleWhere((i) => i.name == 'image');
      expect(InputFieldUpload.type.name, 'Upload');
      expect(_baseTypeName(upload.type), 'Upload');
    });

    test('beaconStageImage and beaconSetMedia return the new payload types', () {
      final stage = mutation.all.singleWhere(
        (f) => f.name == 'beaconStageImage',
      );
      final setMedia = mutation.all.singleWhere(
        (f) => f.name == 'beaconSetMedia',
      );
      expect(_baseTypeName(stage.type), 'BeaconImageStaged');
      expect(_baseTypeName(setMedia.type), 'Beacon');
    });
  });

  group('missing required list is rejected', () {
    test('beaconSetMedia throws when imageIds is omitted entirely', () {
      final field = mutation.all.singleWhere((f) => f.name == 'beaconSetMedia');
      expect(
        () => field.resolve!(null, {
          ...auth,
          'id': 'B1',
          'coverSource': 0,
        }),
        throwsA(isA<Error>()),
      );
    });
  });

  group('old documents validate: omitted vs explicit primaryNeedSlug', () {
    test('create without primaryNeedSlug key derives it (legacy compatibility)', () async {
      final field = mutation.all.singleWhere((f) => f.name == 'beaconCreate');
      final result = await field.resolve!(null, {
        ...auth,
        'title': 'Pickup request',
        'description': 'A description that is long enough.',
        'needs': 'food',
      }) as Map;
      expect(result['primaryNeedSlug'], 'food');
    });

    test('create with an explicit null primaryNeedSlug and non-empty needs is rejected', () async {
      final field = mutation.all.singleWhere((f) => f.name == 'beaconCreate');
      await expectLater(
        field.resolve!(null, {
          ...auth,
          'title': 'Pickup request',
          'description': 'A description that is long enough.',
          'needs': 'food',
          'primaryNeedSlug': null,
        }),
        throwsA(isA<BeaconPrimaryNeedNotInNeedsException>()),
      );
    });
  });
}
