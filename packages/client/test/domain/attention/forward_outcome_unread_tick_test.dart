// A forward row relabelled to an outcome by somebody else carries one unread
// tick until the viewer sees it; the viewer's own relabel never does. The
// server encodes the tick as `seen_at IS NULL` on the forward row and the
// position as `created_at = GREATEST(entry_at, outcome_changed_at)`
// (docs/contracts/attention-active-attention-axis.json § forwardOutcomeTick).
// The client mirror is `isInUnreadView`'s forward branch.

@Tags(['repo-files'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/attention_dismissible_membership.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';

import '../../support/attention_axis_contract.dart';
import '../../support/forward_outcome_wire.dart';

const _beaconId = 'Bbookswap0001';

/// When the viewer was forwarded the Request (`entry_at`, which is also the
/// row's `latest_forward_at`).
const _entryAt = '2026-11-01T09:00:00.000Z';

/// When somebody changed the forward's status (`outcome_changed_at`).
const _outcomeChangedAt = '2026-11-03T15:30:00.000Z';

AttentionReceipt _forwardReceipt({DateTime? seenAt}) => AttentionReceipt(
  id: 'inbox:$_beaconId',
  category: 'requestProgress',
  kind: 'roomActivityLowPriority',
  priority: 'normal',
  title: 'Book swap Sunday',
  body: '',
  presentationPayloadJson: '{}',
  actionUrl: '/#/',
  createdAt: DateTime.parse(_outcomeChangedAt),
  seenAt: seenAt,
  collapsedCount: 1,
  surface: AttentionSurface.activity,
  beaconId: _beaconId,
  itemKind: AttentionItemKind.forward,
  forwardOutcome: AttentionForwardOutcome.watching,
);

void main() {
  group('isInUnreadView on a forward outcome row', () {
    test('an unseen outcome (seenAt null) is in the unread view', () {
      expect(isInUnreadView(_forwardReceipt()), isTrue);
    });

    test('a seen outcome (seenAt = latest forward) is not', () {
      expect(
        isInUnreadView(_forwardReceipt(seenAt: DateTime.parse(_entryAt))),
        isFalse,
      );
    });

    test('every outcome kind ticks while unseen', () {
      for (final outcome in AttentionForwardOutcome.values) {
        expect(
          isInUnreadView(_forwardReceipt().copyWith(forwardOutcome: outcome)),
          isTrue,
          reason: '$outcome relabelled by somebody else is unseen',
        );
      }
    });
  });

  group('isInUnreadView on the other row kinds is unchanged', () {
    AttentionReceipt base(AttentionItemKind kind) => _forwardReceipt().copyWith(
      itemKind: kind,
      forwardOutcome: null,
      id: 'r-${kind.name}',
    );

    test('a receipt follows the active-attention rule, not seenAt', () {
      final optional = base(AttentionItemKind.receipt);
      expect(isInUnreadView(optional), isTrue);
      expect(
        isInUnreadView(optional.copyWith(seenAt: DateTime.parse(_entryAt))),
        isTrue,
        reason: 'reading a receipt does not take it off the unread view',
      );
      expect(
        isInUnreadView(
          optional.copyWith(clearedAt: DateTime.parse(_outcomeChangedAt)),
        ),
        isFalse,
      );
      expect(
        isInUnreadView(optional.copyWith(historyLifecycleEligible: false)),
        isFalse,
      );
    });

    test('a requestActivity card counts its unseen events only', () {
      final card = base(AttentionItemKind.requestActivity);
      expect(isInUnreadView(card.copyWith(eventUnseenCount: 2)), isTrue);
      expect(isInUnreadView(card.copyWith(eventUnseenCount: 0)), isFalse);
      expect(isInUnreadView(card.copyWith(eventUnseenCount: null)), isFalse);
    });

    test('the watching digest is always in', () {
      final digest = base(AttentionItemKind.watchingDigest);
      expect(isInUnreadView(digest), isTrue);
      expect(
        isInUnreadView(digest.copyWith(seenAt: DateTime.parse(_entryAt))),
        isTrue,
      );
    });
  });

  group('the forward outcome row through the real client mapper', () {
    test('seenAt null maps to an unseen forward outcome receipt', () async {
      final receipt = await mapStreamRowThroughRepository(
        forwardOutcomeRowWire(
          beaconId: _beaconId,
          createdAt: _outcomeChangedAt,
          seenAt: null,
        ),
      );

      expect(receipt.id, 'inbox:$_beaconId');
      expect(receipt.itemKind, AttentionItemKind.forward);
      expect(receipt.forwardOutcome, AttentionForwardOutcome.watching);
      expect(receipt.seenAt, isNull);
      expect(receipt.createdAt, DateTime.parse(_outcomeChangedAt));
      expect(isInUnreadView(receipt), isTrue);
    });

    test('a seenAt timestamp maps to that instant and no tick', () async {
      final receipt = await mapStreamRowThroughRepository(
        forwardOutcomeRowWire(
          beaconId: _beaconId,
          createdAt: _outcomeChangedAt,
          seenAt: _entryAt,
        ),
      );

      expect(receipt.itemKind, AttentionItemKind.forward);
      expect(receipt.seenAt, DateTime.parse(_entryAt));
      expect(isInUnreadView(receipt), isFalse);
    });
  });

  group('the client mirror agrees with the shared forwardOutcomeTick cases', () {
    test(
      'every recorded case maps to the server-defined tick and position',
      () async {
        final cases = AttentionAxisContract.load().forwardOutcomeTick.cases;
        expect(
          cases.length,
          4,
          reason: 'otherUser/unseen, otherUser+seen, viewer, nobody',
        );

        final timestamps = {
          'entry_at': _entryAt,
          'outcome_changed_at': _outcomeChangedAt,
        };
        for (final c in cases) {
          final position = timestamps[c.positionKey];
          expect(
            position,
            isNotNull,
            reason: 'case "${c.name}" names an unknown positionKey',
          );
          final receipt = await mapStreamRowThroughRepository(
            forwardOutcomeRowWire(
              beaconId: _beaconId,
              createdAt: position!,
              // The server: seen_at IS NULL iff unseen, else latest_forward_at.
              seenAt: c.unseen ? null : _entryAt,
            ),
          );

          expect(
            isInUnreadView(receipt),
            c.unseen,
            reason: 'case "${c.name}" (relabelled by ${c.relabelledBy})',
          );
          expect(
            receipt.createdAt,
            DateTime.parse(position),
            reason: 'case "${c.name}" sits at its ${c.positionKey}',
          );
        }
      },
    );
  });

  group('a malformed forwardOutcomeTick contract fails with a clear error', () {
    Matcher namedError(String fragment) => throwsA(
      isA<StateError>().having(
        (e) => e.message,
        'message',
        allOf(contains('forwardOutcomeTick'), contains(fragment)),
      ),
    );

    test('a contract without the section names the missing section', () {
      expect(
        () => AttentionAxisContract.fromJson(const {}).forwardOutcomeTick,
        namedError('forwardOutcomeTick'),
      );
    });

    test('a section without cases names the missing cases list', () {
      expect(
        () => AttentionAxisContract.fromJson(const {
          'forwardOutcomeTick': <String, dynamic>{},
        }).forwardOutcomeTick.cases,
        namedError('"cases"'),
      );
      expect(
        () => AttentionAxisContract.fromJson(const {
          'forwardOutcomeTick': {'cases': <Object>[]},
        }).forwardOutcomeTick.cases,
        namedError('"cases"'),
      );
    });
  });
}
