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

  final _threadItemId = InputFieldString(fieldName: 'threadItemId');

  final _participantUserId = InputFieldString(fieldName: 'participantUserId');

  final _stewardUserId = InputFieldString(fieldName: 'stewardUserId');

  final _messageId = InputFieldString(fieldName: 'messageId');

  final _emoji = InputFieldString(fieldName: 'emoji');

  final _questionInput = InputFieldString(fieldName: 'question');

  final _variantsInput = InputFieldStringList(fieldName: 'variants');

  final _pollTypeInput = InputFieldString(fieldName: 'pollType');

  final _isAnonymousInput = InputFieldBool(fieldName: 'isAnonymous');

  final _allowRevoteInput = InputFieldBool(fieldName: 'allowRevote');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
        roomMessageCreate,
        roomMessageAttachmentAdd,
        roomMessageEdit,
        roomMessageDelete,
        participantOfferHelp,
        beaconRoomAdmit,
        beaconStewardPromote,
        roomMessageReactionToggle,
        roomMessageMarkSemanticDone,
        beaconParticipantRoomSeen,
        markBeaconRoomSeen,
        roomPollCreate,
      ];

  GraphQLObjectField<dynamic, dynamic> get roomMessageCreate =>
      GraphQLObjectField(
        'RoomMessageCreate',
        gqlTypeRoomMessageCreatePayload.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _body.field,
          _replyToMessageId.fieldNullable,
          _threadItemId.fieldNullable,
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
                threadItemId: _threadItemId.fromArgs(args),
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

  GraphQLObjectField<dynamic, dynamic> get roomMessageEdit =>
      GraphQLObjectField(
        'RoomMessageEdit',
        graphQLBoolean.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _messageId.field,
          _body.field,
        ],
        resolve: (_, args) => _case
            .editMessage(
              beaconId: _beaconIdStr.fromArgsNonNullable(args),
              messageId: _messageId.fromArgsNonNullable(args),
              userId: getCredentials(args).sub,
              newBody: _body.fromArgsNonNullable(args),
            )
            .then((_) => true),
      );

  GraphQLObjectField<dynamic, dynamic> get roomMessageDelete =>
      GraphQLObjectField(
        'RoomMessageDelete',
        graphQLBoolean.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _messageId.field,
        ],
        resolve: (_, args) => _case.deleteMessage(
              beaconId: _beaconIdStr.fromArgsNonNullable(args),
              messageId: _messageId.fromArgsNonNullable(args),
              userId: getCredentials(args).sub,
            ),
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

  GraphQLObjectField<dynamic, dynamic> get roomMessageMarkSemanticDone =>
      GraphQLObjectField(
        'RoomMessageMarkSemanticDone',
        graphQLBoolean.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _messageId.field,
        ],
        resolve: (_, args) => _case.roomMessageMarkSemanticDone(
              beaconId: _beaconIdStr.fromArgsNonNullable(args),
              userId: getCredentials(args).sub,
              messageId: _messageId.fromArgsNonNullable(args),
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

  GraphQLObjectField<dynamic, dynamic> get markBeaconRoomSeen =>
      GraphQLObjectField(
        'MarkBeaconRoomSeen',
        graphQLBoolean.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _threadItemId.fieldNullable,
        ],
        resolve: (_, args) => _case.markBeaconRoomSeen(
              beaconId: _beaconIdStr.fromArgsNonNullable(args),
              userId: getCredentials(args).sub,
              threadItemId: _threadItemId.fromArgs(args),
            ),
      );

  GraphQLObjectField<dynamic, dynamic> get roomPollCreate =>
      GraphQLObjectField(
        'RoomPollCreate',
        gqlTypeRoomMessageRow.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _questionInput.field,
          _variantsInput.field,
          _pollTypeInput.fieldNullable,
          _isAnonymousInput.fieldNullable,
          _allowRevoteInput.fieldNullable,
        ],
        resolve: (_, args) => _case.createPoll(
          beaconId: _beaconIdStr.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
          question: _questionInput.fromArgsNonNullable(args),
          variants: _variantsInput.fromArgsNonNullable(args),
          pollType: _pollTypeInput.fromArgs(args),
          isAnonymous: _isAnonymousInput.fromArgs(args),
          allowRevote: _allowRevoteInput.fromArgs(args),
        ),
      );
}
