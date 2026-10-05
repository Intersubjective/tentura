import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/room_baton_repository_port.dart';
import 'package:tentura_server/domain/use_case/room_baton_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

/// `[RoomBatonCandidateInput!]` typed over `dynamic`, so a decoded
/// `List<dynamic>` of maps passes validation on executors that do not
/// re-type variable lists.
final class _CandidateListType extends GraphQLListType<dynamic, dynamic> {
  _CandidateListType() : super(gqlInputRoomBatonCandidate.nonNullable());

  @override
  GraphQLType<List<dynamic>, List<dynamic>> coerceToInputObject() => this;
}

/// `String` scalar that accepts an explicit `null` variable (validated as
/// `''`, read back as «no user»), so «pick automatically» also works on
/// executors without the production schema's null-safe argument coercion.
final class _NullableStringType extends GraphQLScalarType<String?, String?> {
  @override
  String get name => 'String';

  @override
  String get description => 'A character sequence.';

  @override
  GraphQLType<String?, String?> coerceToInputObject() => this;

  @override
  String? serialize(String? value) => value;

  @override
  String? deserialize(String? serialized) => serialized;

  @override
  ValidationResult<String?> validate(String key, Object? input) =>
      graphQLString.validate(key, input ?? '');
}

/// «Who'll take it?» (baton) mutations — plan B7
/// (`docs/plans/baton-who-takes-it-plan.md`). Create/respond/select return the
/// calling viewer's `batonDataJson` for the message, read after the write.
final class MutationRoomBaton extends GqlNodeBase {
  MutationRoomBaton({
    RoomBatonCase? roomBatonCase,
    RoomBatonRepositoryPort? batonRepository,
    BeaconRoomRepositoryPort? roomRepository,
  }) : _case = roomBatonCase ?? GetIt.I<RoomBatonCase>(),
       _batonRepository = batonRepository ?? GetIt.I<RoomBatonRepositoryPort>(),
       _roomRepository = roomRepository ?? GetIt.I<BeaconRoomRepositoryPort>();

  final RoomBatonCase _case;

  final RoomBatonRepositoryPort _batonRepository;

  final BeaconRoomRepositoryPort _roomRepository;

  final _messageId = InputFieldString(fieldName: 'messageId');

  final _batonId = InputFieldString(fieldName: 'batonId');

  final _userId = GraphQLFieldInput<String?, String?>(
    'userId',
    _NullableStringType(),
    defaultsToNull: true,
  );

  final _canHelp = InputFieldBool(fieldName: 'canHelp');

  final _candidates = GraphQLFieldInput(
    'candidates',
    _CandidateListType().nonNullable(),
  );

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    roomBatonCreate,
    roomBatonRespond,
    roomBatonSelect,
    roomBatonCancel,
  ];

  GraphQLObjectField<dynamic, dynamic> get roomBatonCreate =>
      GraphQLObjectField(
        'roomBatonCreate',
        graphQLString,
        arguments: [
          _messageId.field,
          _candidates,
        ],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          final baton = await _case.create(
            actorId: jwt.sub,
            messageId: _messageId.fromArgsNonNullable(args),
            candidates: [
              for (final raw in args[_candidates.name]! as List)
                (
                  userId: (raw as Map)['userId']! as String,
                  tier: (raw['tier']! as num).toInt(),
                ),
            ],
          );
          return _batonDataJson(
            beaconId: baton.beaconId,
            messageId: baton.messageId,
            viewerId: jwt.sub,
          );
        },
      );

  GraphQLObjectField<dynamic, dynamic> get roomBatonRespond =>
      GraphQLObjectField(
        'roomBatonRespond',
        graphQLString,
        arguments: [
          _batonId.field,
          _canHelp.field,
        ],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          final batonId = _batonId.fromArgsNonNullable(args);
          await _case.respond(
            actorId: jwt.sub,
            batonId: batonId,
            canHelp: _canHelp.fromArgsNonNullable(args),
          );
          return _batonDataJsonById(batonId: batonId, viewerId: jwt.sub);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get roomBatonSelect =>
      GraphQLObjectField(
        'roomBatonSelect',
        graphQLString,
        arguments: [
          _batonId.field,
          _userId,
        ],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          final batonId = _batonId.fromArgsNonNullable(args);
          await _case.select(
            actorId: jwt.sub,
            batonId: batonId,
            userId: switch (args[_userId.name]) {
              final String id when id.isNotEmpty => id,
              _ => null,
            },
          );
          return _batonDataJsonById(batonId: batonId, viewerId: jwt.sub);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get roomBatonCancel =>
      GraphQLObjectField(
        'roomBatonCancel',
        graphQLBoolean.nonNullable(),
        arguments: [
          _batonId.field,
        ],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          await _case.cancel(
            actorId: jwt.sub,
            batonId: _batonId.fromArgsNonNullable(args),
          );
          return true;
        },
      );

  Future<String?> _batonDataJsonById({
    required String batonId,
    required String viewerId,
  }) async {
    final baton =
        await _batonRepository.getById(batonId) ??
        (throw const BatonNotFoundException());
    return _batonDataJson(
      beaconId: baton.beaconId,
      messageId: baton.messageId,
      viewerId: viewerId,
    );
  }

  Future<String?> _batonDataJson({
    required String beaconId,
    required String messageId,
    required String viewerId,
  }) async {
    final target = await _roomRepository.roomMessageTarget(
      beaconId: beaconId,
      messageId: messageId,
      viewerUserId: viewerId,
    );
    return target?['batonDataJson'] as String?;
  }
}
