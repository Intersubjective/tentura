import 'package:tentura_server/domain/entity/beacon_activity_event_record.dart';
import 'package:tentura_server/domain/entity/beacon_thread_record.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import 'query_coordination_item.dart';

final class QueryBeaconRoom extends GqlNodeBase {
  QueryBeaconRoom({BeaconRoomCase? beaconRoomCase})
    : _case = beaconRoomCase ?? GetIt.I<BeaconRoomCase>();

  final BeaconRoomCase _case;

  final _beaconIdStr = InputFieldString(fieldName: 'beaconId');

  final _beforeIso = InputFieldString(fieldName: 'beforeIso');

  final _threadItemId = InputFieldString(fieldName: 'threadItemId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    roomMessageList,
    roomMessageTarget,
    beaconParticipantList,
    beaconRoomStateGet,
    beaconActivityEventList,
    inboxRoomContextBatch,
    myWorkLastActivityEvent,
    beaconThreads,
  ];

  GraphQLObjectField<dynamic, dynamic> get roomMessageList =>
      GraphQLObjectField(
        'RoomMessageList',
        GraphQLListType(gqlTypeRoomMessageRow.nonNullable()),
        arguments: [
          _beaconIdStr.field,
          _beforeIso.fieldNullable,
          _threadItemId.fieldNullable,
        ],
        resolve: (_, args) => _case.listMessages(
          beaconId: _beaconIdStr.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
          beforeIso: _beforeIso.fromArgs(args),
          threadItemId: _threadItemId.fromArgs(args),
        ),
      );

  GraphQLObjectField<dynamic, dynamic> get roomMessageTarget =>
      GraphQLObjectField(
        'roomMessageTarget',
        gqlTypeRoomMessageRow,
        arguments: [_beaconIdStr.field, _messageId.field],
        resolve: (_, args) => _case.roomMessageTarget(
          beaconId: _beaconIdStr.fromArgsNonNullable(args),
          messageId: _messageId.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
        ),
      );

  final _messageId = InputFieldString(fieldName: 'messageId');

  GraphQLObjectField<dynamic, dynamic> get beaconParticipantList =>
      GraphQLObjectField(
        'BeaconParticipantList',
        GraphQLListType(gqlTypeBeaconParticipantRow.nonNullable()),
        arguments: [
          _beaconIdStr.field,
        ],
        resolve: (_, args) => _case.listParticipants(
          beaconId: _beaconIdStr.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
        ),
      );

  GraphQLObjectField<dynamic, dynamic> get beaconRoomStateGet =>
      GraphQLObjectField(
        'BeaconRoomStateGet',
        gqlTypeBeaconRoomStateRow.nonNullable(),
        arguments: [
          _beaconIdStr.field,
        ],
        resolve: (_, args) => _case.beaconRoomStateGet(
          beaconId: _beaconIdStr.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
        ),
      );

  GraphQLObjectField<dynamic, dynamic> get beaconActivityEventList =>
      GraphQLObjectField(
        'BeaconActivityEventList',
        GraphQLListType(gqlTypeBeaconActivityEventRow.nonNullable()),
        arguments: [
          _beaconIdStr.field,
        ],
        resolve: (_, args) => _case.listActivityEvents(
          beaconId: _beaconIdStr.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
        ),
      );

  GraphQLObjectField<dynamic, dynamic> get inboxRoomContextBatch =>
      GraphQLObjectField(
        'InboxRoomContextBatch',
        GraphQLListType(gqlTypeInboxRoomContextRow.nonNullable()),
        arguments: [InputFieldBeaconIds.field],
        resolve: (_, args) => _case.inboxRoomContextBatch(
          userId: getCredentials(args).sub,
          beaconIds: InputFieldBeaconIds.fromArgs(args),
        ),
      );

  GraphQLObjectField<dynamic, dynamic> get myWorkLastActivityEvent =>
      GraphQLObjectField(
        'myWorkLastActivityEvent',
        GraphQLListType(gqlTypeMyWorkLastActivityEventRow.nonNullable()),
        arguments: [InputFieldBeaconIds.field],
        resolve: (_, args) async {
          final rows = await _case.myWorkLastActivityEventsByBeaconIds(
            userId: getCredentials(args).sub,
            beaconIds: InputFieldBeaconIds.fromArgs(args),
          );
          return rows.map(_myWorkLastActivityEventToMap).toList();
        },
      );

  GraphQLObjectField<dynamic, dynamic> get beaconThreads => GraphQLObjectField(
        'beaconThreads',
        GraphQLListType(gqlTypeBeaconThreadRow.nonNullable()),
        arguments: [_beaconIdStr.field],
        resolve: (_, args) async {
          final rows = await _case.listThreads(
            beaconId: _beaconIdStr.fromArgsNonNullable(args),
            userId: getCredentials(args).sub,
          );
          return rows.map(beaconThreadRecordToMap).toList();
        },
      );
}

Map<String, Object?> beaconThreadRecordToMap(BeaconThreadRecord row) {
  final preview = row.lastMessagePreview;
  return {
    'threadId': row.threadId,
    'threadKind': row.threadKind,
    'unreadCount': row.unreadCount,
    'messageCount': row.messageCount,
    'lastSeenAt': row.lastSeenAt?.toUtc().toIso8601String(),
    'lastMessageAt': row.lastMessageAt?.toUtc().toIso8601String(),
    'lastMessageAuthorId': row.lastMessageAuthorId,
    'lastMessagePreview': preview == null
        ? null
        : {
            'kind': preview.kind,
            'excerpt': preview.excerpt,
            'hasAttachment': preview.hasAttachment,
            'joinedUserId': preview.joinedUserId,
            'admissionReason': preview.admissionReason,
            'linkedItemId': preview.linkedItemId,
            'linkedEventKind': preview.linkedEventKind,
            'itemKind': preview.itemKind,
            'itemTitle': preview.itemTitle,
            'pollTitle': preview.pollTitle,
            'factTitle': preview.factTitle,
            'factVisibility': preview.factVisibility,
          },
    'item': row.item == null
        ? null
        : coordinationItemWithCountsToMap(row.item!),
  };
}

Map<String, Object?> _myWorkLastActivityEventToMap(
  MyWorkLastActivityEventRow row,
) {
  final event = row.event;
  return {
    'beaconId': row.beaconId,
    'id': event?.id,
    'type': event?.type,
    'actorId': event?.actorId,
    'actorTitle': row.actorTitle,
    'actorImageId': row.actorImageId,
    'createdAt': event?.createdAt.toUtc().toIso8601String(),
    'diffJson': event?.diffJson,
  };
}
