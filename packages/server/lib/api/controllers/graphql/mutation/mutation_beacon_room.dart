import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/exception.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationBeaconRoom extends GqlNodeBase {
  MutationBeaconRoom({BeaconRoomCase? beaconRoomCase})
      : _case = beaconRoomCase ?? GetIt.I<BeaconRoomCase>();

  final BeaconRoomCase _case;

  final _beaconIdStr = InputFieldString(fieldName: 'beaconId');

  final _body = InputFieldString(fieldName: 'body');

  final _replyToMessageId = InputFieldString(fieldName: 'replyToMessageId');

  final _participantUserId = InputFieldString(fieldName: 'participantUserId');

  final _stewardUserId = InputFieldString(fieldName: 'stewardUserId');

  final _messageId = InputFieldString(fieldName: 'messageId');

  final _emoji = InputFieldString(fieldName: 'emoji');

  final _currentPlan = InputFieldString(fieldName: 'currentPlan');

  final _targetUserId = InputFieldString(fieldName: 'targetUserId');

  final _nextMoveText = InputFieldString(fieldName: 'nextMoveText');

  final GraphQLFieldInput<int, int> _nextMoveSource =
      GraphQLFieldInput('nextMoveSource', graphQLInt.nonNullable());

  final _nextMoveStatus = InputFieldInt(fieldName: 'nextMoveStatus');

  final _title = InputFieldString(fieldName: 'title');

  final _affectedParticipantId =
      InputFieldString(fieldName: 'affectedParticipantId');

  final _resolverParticipantId =
      InputFieldString(fieldName: 'resolverParticipantId');

  final _blockerVisibility = InputFieldInt(fieldName: 'visibility');

  final _requestText = InputFieldString(fieldName: 'requestText');

  final InputFieldBool _resolveBlockerFlag =
      InputFieldBool(fieldName: 'resolveBlocker');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
        roomMessageCreate,
        roomMessageAttachmentAdd,
        participantOfferHelp,
        beaconRoomAdmit,
        beaconStewardPromote,
        roomMessageReactionToggle,
        beaconRoomStatePlanUpdate,
        beaconParticipantSetNextMove,
        beaconRoomMessageMarkBlocker,
        beaconRoomMessageNeedInfo,
        roomMessageMarkDone,
        beaconParticipantRoomSeen,
      ];

  GraphQLObjectField<dynamic, dynamic> get roomMessageCreate =>
      GraphQLObjectField(
        'RoomMessageCreate',
        gqlTypeRoomMessageCreatePayload.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _body.field,
          _replyToMessageId.fieldNullable,
          InputFieldUpload.fieldNullable,
        ],
        resolve: (_, args) async {
          final uploadMeta = InputFieldUpload.uploadVariablesFromArgs(args);
          final rawName = uploadMeta?['filename'];
          final rawType = uploadMeta?['type'];
          return _case
              .createMessage(
                beaconId: _beaconIdStr.fromArgsNonNullable(args),
                userId: getCredentials(args).sub,
                body: _body.fromArgs(args) ?? '',
                replyToMessageId: _replyToMessageId.fromArgs(args),
                attachmentBytes: InputFieldUpload.fromArgs(args),
                attachmentFilename:
                    rawName is String && rawName.trim().isNotEmpty
                    ? rawName
                    : null,
                attachmentMimeType:
                    rawType is String && rawType.trim().isNotEmpty
                    ? rawType
                    : null,
              )
              .then((m) => m);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get roomMessageAttachmentAdd =>
      GraphQLObjectField(
        'RoomMessageAttachmentAdd',
        graphQLBoolean.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _messageId.field,
          InputFieldUpload.field,
        ],
        resolve: (_, args) async {
          final uploadMeta = InputFieldUpload.uploadVariablesFromArgs(args);
          final rawName = uploadMeta?['filename'];
          final rawType = uploadMeta?['type'];
          final bytes = InputFieldUpload.fromArgs(args);
          if (bytes == null) {
            throw const BeaconCreateException(
              description: 'Attachment file is required',
            );
          }
          return _case
              .addMessageAttachment(
                beaconId: _beaconIdStr.fromArgsNonNullable(args),
                userId: getCredentials(args).sub,
                messageId: _messageId.fromArgsNonNullable(args),
                attachmentBytes: bytes,
                attachmentFilename:
                    rawName is String && rawName.trim().isNotEmpty
                    ? rawName
                    : null,
                attachmentMimeType:
                    rawType is String && rawType.trim().isNotEmpty
                    ? rawType
                    : null,
              )
              .then((_) => true);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get participantOfferHelp =>
      GraphQLObjectField(
        'BeaconParticipantOfferHelp',
        graphQLBoolean.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _body.field,
        ],
        resolve: (_, args) => _case
            .offerHelp(
              beaconId: _beaconIdStr.fromArgsNonNullable(args),
              userId: getCredentials(args).sub,
              note: _body.fromArgs(args) ?? '',
            )
            .then((_) => true),
      );

  GraphQLObjectField<dynamic, dynamic> get beaconRoomAdmit =>
      GraphQLObjectField(
        'BeaconRoomAdmit',
        graphQLBoolean.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _participantUserId.field,
        ],
        resolve: (_, args) => _case
            .admit(
              beaconId: _beaconIdStr.fromArgsNonNullable(args),
              participantUserId: _participantUserId.fromArgsNonNullable(args),
              actorUserId: getCredentials(args).sub,
            )
            .then((_) => true),
      );

  GraphQLObjectField<dynamic, dynamic> get beaconStewardPromote =>
      GraphQLObjectField(
        'BeaconStewardPromote',
        graphQLBoolean.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _stewardUserId.field,
        ],
        resolve: (_, args) => _case
            .stewardPromote(
              beaconId: _beaconIdStr.fromArgsNonNullable(args),
              stewardUserId: _stewardUserId.fromArgsNonNullable(args),
              authorUserId: getCredentials(args).sub,
            )
            .then((_) => true),
      );

  GraphQLObjectField<dynamic, dynamic> get roomMessageReactionToggle =>
      GraphQLObjectField(
        'RoomMessageReactionToggle',
        graphQLBoolean.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _messageId.field,
          _emoji.field,
        ],
        resolve: (_, args) => _case
            .reactionToggle(
              beaconId: _beaconIdStr.fromArgsNonNullable(args),
              messageId: _messageId.fromArgsNonNullable(args),
              userId: getCredentials(args).sub,
              emoji: _emoji.fromArgsNonNullable(args),
            )
            .then((_) => true),
      );

  GraphQLObjectField<dynamic, dynamic> get beaconParticipantSetNextMove =>
      GraphQLObjectField(
        'BeaconParticipantSetNextMove',
        graphQLBoolean.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _targetUserId.field,
          _nextMoveText.field,
          _nextMoveSource,
          _nextMoveStatus.fieldNullable,
        ],
        resolve: (_, args) {
          final src = args[_nextMoveSource.name]! as int;
          return _case.participantSetNextMove(
            beaconId: _beaconIdStr.fromArgsNonNullable(args),
            actorUserId: getCredentials(args).sub,
            targetUserId: _targetUserId.fromArgsNonNullable(args),
            nextMoveText: _nextMoveText.fromArgsNonNullable(args),
            nextMoveSource: src,
            nextMoveStatus: _nextMoveStatus.fromArgs(args),
          );
        },
      );

  GraphQLObjectField<dynamic, dynamic> get beaconRoomStatePlanUpdate =>
      GraphQLObjectField(
        'BeaconRoomStatePlanUpdate',
        graphQLBoolean.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _currentPlan.field,
        ],
        resolve: (_, args) => _case.beaconRoomStatePlanUpdate(
              beaconId: _beaconIdStr.fromArgsNonNullable(args),
              userId: getCredentials(args).sub,
              currentPlan: _currentPlan.fromArgsNonNullable(args),
            ),
      );

  GraphQLObjectField<dynamic, dynamic> get beaconRoomMessageMarkBlocker =>
      GraphQLObjectField(
        'BeaconRoomMessageMarkBlocker',
        graphQLBoolean.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _messageId.field,
          _title.field,
          _affectedParticipantId.fieldNullable,
          _resolverParticipantId.fieldNullable,
          _blockerVisibility.fieldNullable,
        ],
        resolve: (_, args) => _case.beaconRoomMessageMarkBlocker(
              beaconId: _beaconIdStr.fromArgsNonNullable(args),
              userId: getCredentials(args).sub,
              messageId: _messageId.fromArgsNonNullable(args),
              title: _title.fromArgsNonNullable(args),
              affectedParticipantId: _affectedParticipantId.fromArgs(args),
              resolverParticipantId: _resolverParticipantId.fromArgs(args),
              visibility: _blockerVisibility.fromArgs(args),
            ),
      );

  GraphQLObjectField<dynamic, dynamic> get beaconRoomMessageNeedInfo =>
      GraphQLObjectField(
        'BeaconRoomMessageNeedInfo',
        graphQLBoolean.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _messageId.field,
          _targetUserId.field,
          _requestText.field,
        ],
        resolve: (_, args) => _case.beaconRoomMessageNeedInfo(
              beaconId: _beaconIdStr.fromArgsNonNullable(args),
              userId: getCredentials(args).sub,
              messageId: _messageId.fromArgsNonNullable(args),
              targetUserId: _targetUserId.fromArgsNonNullable(args),
              requestText: _requestText.fromArgsNonNullable(args),
            ),
      );

  GraphQLObjectField<dynamic, dynamic> get roomMessageMarkDone =>
      GraphQLObjectField(
        'RoomMessageMarkDone',
        graphQLBoolean.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _messageId.field,
          _resolveBlockerFlag.field,
        ],
        resolve: (_, args) => _case.roomMessageMarkDone(
              beaconId: _beaconIdStr.fromArgsNonNullable(args),
              userId: getCredentials(args).sub,
              messageId: _messageId.fromArgsNonNullable(args),
              resolveBlocker: args[_resolveBlockerFlag.field.name]! as bool,
            ),
      );

  GraphQLObjectField<dynamic, dynamic> get beaconParticipantRoomSeen =>
      GraphQLObjectField(
        'BeaconParticipantRoomSeen',
        graphQLBoolean.nonNullable(),
        arguments: [
          _beaconIdStr.field,
        ],
        resolve: (_, args) => _case.beaconParticipantRoomSeen(
              beaconId: _beaconIdStr.fromArgsNonNullable(args),
              userId: getCredentials(args).sub,
            ),
      );
}
