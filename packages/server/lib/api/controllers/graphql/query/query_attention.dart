import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:tentura_server/domain/attention/attention_clear_models.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/port/attention_query_port.dart';
import 'package:tentura_server/domain/use_case/attention_clear_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryAttention extends GqlNodeBase {
  QueryAttention({AttentionQueryPort? query, AttentionClearCase? clear})
    : _query = query ?? GetIt.I<AttentionQueryPort>(),
      _clearOverride = clear;

  final AttentionQueryPort _query;
  final AttentionClearCase? _clearOverride;

  AttentionClearCase get _clear =>
      _clearOverride ?? GetIt.I<AttentionClearCase>();

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    attentionFeed,
    attentionSurfaceSummary,
    attentionMarkers,
    myWorkAttention,
    activityOffers,
    activityAttention,
    attentionRequestHistory,
    attentionClearSnapshot,
    liveObligationBeacons,
  ];

  /// Issues the capture D05 needs: the client cannot clear anything without
  /// first being handed the exact membership a clear may touch. The Request
  /// *page* query (`attentionRequest`, manifest §0.2) is U10's; this field is
  /// only the snapshot issue, so the two cannot collide.
  GraphQLObjectField<dynamic, dynamic> get attentionClearSnapshot =>
      GraphQLObjectField(
        'attentionClearSnapshot',
        gqlTypeAttentionClearSnapshot.nonNullable(),
        arguments: [
          _beaconId.fieldNullable,
          _receiptId.fieldNullable,
          _kind.field,
        ],
        resolve: (_, args) async {
          final accountId = getCredentials(args).sub;
          final snapshot = await _clear.captureSnapshot(
            accountId: accountId,
            beaconId: _boundedId(_beaconId.fromArgs(args), 'beaconId'),
            receiptId: _boundedId(_receiptId.fromArgs(args), 'receiptId'),
            kind: AttentionClearCaptureKind.fromWireName(
              _kind.fromArgsNonNullable(args),
            ),
          );
          return {
            'snapshotToken': snapshot.token,
            'receiptIds': snapshot.receiptIds,
            'outcomeGeneration': snapshot.outcomeGeneration,
            'decisionRevision': snapshot.decisionRevision,
          };
        },
      );

  static String? _boundedId(String? value, String name) {
    if (value == null) return null;
    if (value.isEmpty || value.length > 64) {
      throw ArgumentError.value(value, name, 'must be 1..64 characters');
    }
    return value;
  }

  GraphQLObjectField<dynamic, dynamic> get attentionSurfaceSummary =>
      GraphQLObjectField(
        'attentionSurfaceSummary',
        gqlTypeAttentionSurfaceSummary.nonNullable(),
        resolve: (_, args) async {
          final summary = await _query.surfaceSummary(
            accountId: getCredentials(args).sub,
          );
          return {
            'activityUnreadTotal': summary.activityUnreadTotal,
            'myWorkUnreadTotal': summary.myWorkUnreadTotal,
            'needsYouTotal': summary.needsYouTotal,
            'myDeskDot': summary.myDeskDot,
            'myDeskCount': summary.myDeskCount,
            'forYouDot': summary.forYouDot,
          };
        },
      );

  GraphQLObjectField<dynamic, dynamic> get liveObligationBeacons =>
      GraphQLObjectField(
        'liveObligationBeacons',
        GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        resolve: (_, args) async {
          final beaconIds = await _query.liveObligationBeacons(
            accountId: getCredentials(args).sub,
          );
          return beaconIds.toList()..sort();
        },
      );

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

  GraphQLObjectField<dynamic, dynamic> get myWorkAttention =>
      GraphQLObjectField(
        'myWorkAttention',
        GraphQLListType(
          gqlTypeMyWorkBeaconAttention.nonNullable(),
        ).nonNullable(),
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
          final projections = await _query.myWorkAttention(
            accountId: getCredentials(args).sub,
            beaconIds: beaconIds,
          );
          return [
            for (final projection in projections)
              {
                'beaconId': projection.beaconId,
                'unseenCount': projection.unseenCount,
                'latestUnseen': projection.latestUnseen == null
                    ? null
                    : _mapReceipt(projection.latestUnseen!),
                'liveObligations': [
                  for (final obligation in projection.liveObligations)
                    _mapReceipt(obligation),
                ],
                'needsYouAt': projection.needsYouAt
                    ?.toUtc()
                    .toIso8601String(),
                'firstEntryAt': projection.firstEntryAt
                    ?.toUtc()
                    .toIso8601String(),
              },
          ];
        },
      );

  GraphQLObjectField<dynamic, dynamic> get activityOffers => GraphQLObjectField(
    'activityOffers',
    gqlTypeActivityOfferPage.nonNullable(),
    arguments: [_cursor.fieldNullable, _limit.fieldNullable],
    resolve: (_, args) async {
      final page = await _query.activityOffers(
        accountId: getCredentials(args).sub,
        cursor: _decodeCursor(_cursor.fromArgs(args)),
        limit: _limit.fromArgs(args) ?? 20,
      );
      return {
        'items': [
          for (final item in page.items)
            {
              'beaconId': item.beaconId,
              'listPositionAt': item.listPositionAt.toUtc().toIso8601String(),
              'effectiveActivityAt': item.effectiveActivityAt
                  .toUtc()
                  .toIso8601String(),
              'latestForwardAt': item.latestForwardAt.toUtc().toIso8601String(),
              'unseen': item.unseen,
              'eventTotal': item.eventTotal,
              'eventUnseenCount': item.eventUnseenCount,
              'eventsPreview': [
                for (final event in item.eventsPreview) _mapReceipt(event),
              ],
            },
        ],
        'totalCount': page.totalCount,
        'nextCursor': page.nextCursor == null
            ? null
            : _encodeCursor(page.nextCursor!),
      };
    },
  );

  GraphQLObjectField<dynamic, dynamic> get activityAttention =>
      GraphQLObjectField(
        'activityAttention',
        gqlTypeActivityBeaconAttention.nonNullable(),
        arguments: [
          _beaconId.field,
          _cursor.fieldNullable,
          _limit.fieldNullable,
        ],
        resolve: (_, args) async {
          final beaconId = _beaconId.fromArgsNonNullable(args);
          if (beaconId.isEmpty || beaconId.length > 64) {
            throw ArgumentError.value(
              beaconId,
              'beaconId',
              'must be a non-empty id of at most 64 characters',
            );
          }
          final page = await _query.activityAttention(
            accountId: getCredentials(args).sub,
            beaconId: beaconId,
            cursor: _decodeCursor(_cursor.fromArgs(args)),
            limit: _limit.fromArgs(args) ?? 20,
          );
          return {
            'beaconId': page.beaconId,
            'eventTotal': page.eventTotal,
            'unseenCount': page.unseenCount,
            'latestAt': page.latestAt.toUtc().toIso8601String(),
            'events': [for (final event in page.events) _mapReceipt(event)],
            'nextCursor': page.nextCursor == null
                ? null
                : _encodeCursor(page.nextCursor!),
          };
        },
      );

  /// The viewer's own receipt history for one Request (D17) — cleared and
  /// settled rows included. Same cursor codec as [attentionFeed].
  GraphQLObjectField<dynamic, dynamic> get attentionRequestHistory =>
      GraphQLObjectField(
        'attentionRequestHistory',
        gqlTypeAttentionPage.nonNullable(),
        arguments: [
          _beaconId.field,
          _cursor.fieldNullable,
          _limit.fieldNullable,
        ],
        resolve: (_, args) async {
          final beaconId = _beaconId.fromArgsNonNullable(args);
          if (beaconId.isEmpty || beaconId.length > 64) {
            throw ArgumentError.value(
              beaconId,
              'beaconId',
              'must be a non-empty id of at most 64 characters',
            );
          }
          final page = await _query.attentionRequestHistory(
            accountId: getCredentials(args).sub,
            beaconId: beaconId,
            cursor: _decodeCursor(_cursor.fromArgs(args)),
            limit: _limit.fromArgs(args) ?? 50,
          );
          return {
            'items': [for (final receipt in page.items) _mapReceipt(receipt)],
            'nextCursor': page.nextCursor == null
                ? null
                : _encodeCursor(page.nextCursor!),
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
      _surface.fieldNullable,
      _limit.fieldNullable,
    ],
    resolve: (_, args) async {
      final parsedSurface = _parseSurface(_surface.fromArgs(args));
      final parsedSearch = _parseSearch(_search.fromArgs(args));
      if (parsedSurface == AttentionSurface.activity && parsedSearch != null) {
        throw ArgumentError.value(
          parsedSearch,
          'search',
          'must be null when surface is activity',
        );
      }
      final feed = await _query.attentionFeed(
        accountId: getCredentials(args).sub,
        view: _parseView(_view.fromArgsNonNullable(args)),
        cursor: _decodeCursor(_cursor.fromArgs(args)),
        search: parsedSearch,
        surface: parsedSurface,
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
  static final _surface = InputFieldString(fieldName: 'surface');
  static final _limit = InputFieldInt(fieldName: 'limit');
  static final _beaconIds = InputFieldStringList(fieldName: 'beaconIds');
  static final _beaconId = InputFieldString(fieldName: 'beaconId');
  static final _receiptId = InputFieldString(fieldName: 'receiptId');
  static final _kind = InputFieldString(fieldName: 'kind');

  static AttentionSurface? parseSurfaceArgument(String? value) =>
      _parseSurface(value);

  static AttentionSurface? _parseSurface(String? value) {
    if (value == null) return null;
    return switch (value) {
      'myWork' => AttentionSurface.myWork,
      'activity' => AttentionSurface.activity,
      _ => throw ArgumentError.value(
        value,
        'surface',
        "must be 'myWork' or 'activity'",
      ),
    };
  }

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
            'v': cursor.version,
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
      // U10c — a cursor is only meaningful under the sort keys that minted
      // it. An unversioned cursor is a pre-U10c one; either way, anything
      // that is not the current generation is refused rather than resumed
      // from, because resuming would drop or repeat rows without saying so.
      if (decoded['v'] != kAttentionCursorVersion) {
        throw const FormatException();
      }
      return AttentionCursor(createdAt: createdAt.toUtc(), id: id);
    } on FormatException {
      throw ArgumentError.value(value, 'cursor', 'invalid attention cursor');
    }
  }

  @visibleForTesting
  static const attentionPresentationPayloadAllowedKeys = {
    'eventType',
    'actorUserId',
    'beaconId',
    'coordinationItemId',
    'targetEntityId',
    'messageId',
    'beaconTitle',
    'inviteOrigin',
  };

  @visibleForTesting
  static void validateAttentionPresentationPayload(
    Map<String, Object?> payload,
  ) {
    if (payload.keys.any(
          (key) => !attentionPresentationPayloadAllowedKeys.contains(key),
        ) ||
        payload.values.any((value) => value is! String)) {
      throw StateError('Unexpected attention presentation payload');
    }
  }

  @visibleForTesting
  static Map<String, Object?> mapReceiptForTesting(AttentionReceipt receipt) =>
      _mapReceipt(receipt);

  static Map<String, Object?> _mapReceipt(AttentionReceipt receipt) {
    final payload = receipt.presentationPayload;
    validateAttentionPresentationPayload(payload);
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
      'clearedAt': receipt.clearedAt?.toUtc().toIso8601String(),
      'clearReason': receipt.clearReason,
      'surface': receipt.surface.name,
      'itemKind': receipt.itemKind.name,
      'forwardOutcome': receipt.forwardOutcome,
      'forwardCount': receipt.forwardCount,
      'digestCount': receipt.digestCount,
      'eventTotal': receipt.eventTotal,
      'eventUnseenCount': receipt.eventUnseenCount,
      'eventsPreview': [
        for (final event in receipt.eventsPreview) _mapReceipt(event),
      ],
      'provenanceJson': receipt.provenanceJson,
      'beaconAuthorId': receipt.beaconAuthorId,
      'beaconAuthorName': receipt.beaconAuthorName,
      'beaconAuthorImageId': receipt.beaconAuthorImageId,
      'beaconImageId': receipt.beaconImageId,
      'beaconEndAt': receipt.beaconEndAt?.toUtc().toIso8601String(),
      'allowsForward': receipt.allowsForward,
    };
  }
}
