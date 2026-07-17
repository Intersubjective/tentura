import 'dart:convert';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/port/attention_query_port.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryAttention extends GqlNodeBase {
  QueryAttention({AttentionQueryPort? query})
    : _query = query ?? GetIt.I<AttentionQueryPort>();

  final AttentionQueryPort _query;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    attentionFeed,
    attentionMarkers,
  ];

  GraphQLObjectField<dynamic, dynamic> get attentionMarkers =>
      GraphQLObjectField(
        'attentionMarkers',
        gqlTypeAttentionMarkers.nonNullable(),
        arguments: [_beaconIds.field],
        resolve: (_, args) async {
          final beaconIds = _beaconIds.fromArgsNonNullable(args).toSet();
          if (beaconIds.length > 500) {
            throw ArgumentError.value(
              beaconIds.length,
              'beaconIds',
              'must contain at most 500 unique ids',
            );
          }
          final unreadBeaconIds = await _query.unreadForBeacons(
            accountId: getCredentials(args).sub,
            beaconIds: beaconIds,
          );
          return {
            'unreadBeaconIds': unreadBeaconIds.toList()..sort(),
          };
        },
      );

  GraphQLObjectField<dynamic, dynamic> get attentionFeed => GraphQLObjectField(
    'attentionFeed',
    gqlTypeAttentionFeed.nonNullable(),
    arguments: [
      _view.field,
      _cursor.fieldNullable,
      _search.fieldNullable,
      _limit.fieldNullable,
    ],
    resolve: (_, args) async {
      final feed = await _query.attentionFeed(
        accountId: getCredentials(args).sub,
        view: _parseView(_view.fromArgsNonNullable(args)),
        cursor: _decodeCursor(_cursor.fromArgs(args)),
        search: _parseSearch(_search.fromArgs(args)),
        limit: _limit.fromArgs(args) ?? 50,
      );
      return {
        'summary': {
          'unreadTotal': feed.summary.unreadTotal,
          'needsYouTotal': feed.summary.needsYouTotal,
        },
        'page': {
          'items': [
            for (final receipt in feed.page.items) _mapReceipt(receipt),
          ],
          'nextCursor': feed.page.nextCursor == null
              ? null
              : _encodeCursor(feed.page.nextCursor!),
        },
      };
    },
  );

  static final _view = InputFieldString(fieldName: 'view');
  static final _cursor = InputFieldString(fieldName: 'cursor');
  static final _search = InputFieldString(fieldName: 'search');
  static final _limit = InputFieldInt(fieldName: 'limit');
  static final _beaconIds = InputFieldStringList(fieldName: 'beaconIds');

  static AttentionFeedView _parseView(String value) => switch (value) {
    'all' => AttentionFeedView.all,
    'unread' => AttentionFeedView.unread,
    'needsYou' => AttentionFeedView.needsYou,
    _ => throw ArgumentError.value(value, 'view', 'must be all or unread'),
  };

  static String? _parseSearch(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (trimmed.length > 120) {
      throw ArgumentError.value(
        value,
        'search',
        'must contain at most 120 characters',
      );
    }
    return trimmed;
  }

  static String _encodeCursor(AttentionCursor cursor) => base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'createdAt': cursor.createdAt.toUtc().toIso8601String(),
            'id': cursor.id,
          }),
        ),
      )
      .replaceAll('=', '');

  static AttentionCursor? _decodeCursor(String? value) {
    if (value == null) return null;
    try {
      final padding = '=' * ((4 - value.length % 4) % 4);
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode('$value$padding')),
      );
      if (decoded is! Map) throw const FormatException();
      final createdAt = DateTime.tryParse(
        decoded['createdAt'] is String ? decoded['createdAt'] as String : '',
      );
      final id = decoded['id'] is String ? decoded['id'] as String : null;
      if (createdAt == null || id == null || id.isEmpty || id.length > 256) {
        throw const FormatException();
      }
      return AttentionCursor(createdAt: createdAt.toUtc(), id: id);
    } on FormatException {
      throw ArgumentError.value(value, 'cursor', 'invalid attention cursor');
    }
  }

  static Map<String, Object?> _mapReceipt(AttentionReceipt receipt) {
    final payload = receipt.presentationPayload;
    const allowedPayloadKeys = {
      'eventType',
      'actorUserId',
      'beaconId',
      'coordinationItemId',
      'targetEntityId',
      'messageId',
    };
    if (payload.keys.any((key) => !allowedPayloadKeys.contains(key)) ||
        payload.values.any((value) => value is! String)) {
      throw StateError('Unexpected attention presentation payload');
    }
    return {
      'id': receipt.id,
      'category': receipt.category.name,
      'kind': receipt.kind.name,
      'priority': receipt.priority.name,
      'title': receipt.title,
      'body': receipt.body,
      'actionUrl': receipt.actionUrl,
      'createdAt': receipt.createdAt.toUtc().toIso8601String(),
      'seenAt': receipt.seenAt?.toUtc().toIso8601String(),
      'collapsedCount': receipt.collapsedCount,
      'beaconId': receipt.beaconId,
      'coordinationItemId': receipt.coordinationItemId,
      'actorUserId': receipt.actorUserId,
      'sourceEventKey': receipt.sourceEventKey,
      'destinationKind': receipt.destinationKind?.wireName,
      'targetEntityId': receipt.targetEntityId,
      'presentationKey': receipt.presentationKey,
      'presentationPayloadJson': jsonEncode(payload),
      'inAppPreferenceClass': receipt.inAppPreferenceClass?.wireName,
      'requiresAction': receipt.requiresAction,
      'attentionThreadKey': receipt.attentionThreadKey,
      'settlementKind': receipt.settlementKind?.wireName,
      'settledAt': receipt.settledAt?.toUtc().toIso8601String(),
    };
  }
}
