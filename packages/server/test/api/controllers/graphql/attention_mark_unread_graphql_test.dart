import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_attention.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/attention_ack_port.dart';

/// #601 (option B, decided 2026-10-22) — "Mark unread" on a cleared Updates
/// item must bring it back under Unread. The Unread view is the CLEAR axis
/// (`cleared_at`), so the existing `attentionMarkUnseen` (read axis only)
/// cannot do it. The server gets one new command, `attentionMarkUnread`,
/// backed by `AttentionAckPort.markUnread`, which un-clears (and un-reads)
/// the caller's own visible optional receipts. Same contract as
/// `attentionMarkUnseen`: authenticated, scoped to the caller, at most 200
/// ids, answers the number of rows it changed.
void main() {
  const auth = {kGlobalInputQueryJwt: JwtEntity(sub: 'U1')};

  test('attentionMarkUnread is a mutation of its own', () {
    final names = MutationAttention(
      ack: _UnreadAck(),
    ).all.map((field) => field.name).toList();
    expect(names, contains('attentionMarkUnread'));
    expect(
      names,
      contains('attentionMarkUnseen'),
      reason: 'the read-axis-only command stays as it is',
    );
  });

  test(
    'attentionMarkUnread un-clears through AttentionAckPort.markUnread, '
    'scoped to the caller',
    () async {
      final ack = _UnreadAck();
      final field = MutationAttention(
        ack: ack,
      ).all.singleWhere((field) => field.name == 'attentionMarkUnread');

      expect(
        await field.resolve!(null, {
          ...auth,
          'ids': ['N1'],
        }),
        1,
      );
      expect(ack.unreadAccountId, 'U1');
      expect(ack.unreadIds, ['N1']);
      expect(
        ack.unseenCalls,
        0,
        reason: 'un-clearing is its own command, not markUnseen in disguise',
      );

      // A foreign account smuggled into the arguments is ignored.
      await field.resolve!(null, {
        ...auth,
        'accountId': 'U2',
        'ids': ['N2'],
      });
      expect(ack.unreadAccountId, 'U1');
    },
  );

  test('attentionMarkUnread caps ids at 200 and needs a caller', () {
    final ack = _UnreadAck();
    final field = MutationAttention(
      ack: ack,
    ).all.singleWhere((field) => field.name == 'attentionMarkUnread');
    expect(
      () => field.resolve!(null, {...auth, 'ids': List.filled(201, 'N')}),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => field.resolve!(null, {
        'ids': ['N1'],
      }),
      throwsA(isA<UnauthorizedException>()),
    );
    expect(ack.unreadIds, isNull, reason: 'nothing reached the store');
  });
}

class _UnreadAck implements AttentionAckPort {
  String? unreadAccountId;
  List<String>? unreadIds;
  int unseenCalls = 0;

  // #601: the new port method the fix adds.
  @override
  Future<int> markUnread({
    required String accountId,
    required List<String> ids,
  }) async {
    unreadAccountId = accountId;
    unreadIds = ids;
    return ids.length;
  }

  @override
  Future<int> markUnseen({
    required String accountId,
    required List<String> ids,
  }) async {
    unseenCalls++;
    return ids.length;
  }

  @override
  Future<int> markSeen({
    required String accountId,
    required List<String> ids,
  }) async => ids.length;

  @override
  Future<int> markAllSeen(String accountId, {AttentionSurface? surface}) async =>
      0;

  @override
  Future<int> markSeenForBeacon({
    required String accountId,
    required String beaconId,
  }) async => 0;

  @override
  Future<int> bridgeRoomWatermark({
    required String accountId,
    required String beaconId,
    required String? threadItemId,
    required DateTime lastSeenAt,
  }) async => 0;
}
