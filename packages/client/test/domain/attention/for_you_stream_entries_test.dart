import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/attention_dismissible_membership.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/for_you_stream_entries.dart';

AttentionReceipt _receipt({
  required String id,
  String? beaconId,
  AttentionItemKind itemKind = AttentionItemKind.receipt,
  AttentionForwardOutcome? forwardOutcome,
  int? digestCount,
  int? eventTotal,
  DateTime? createdAt,
}) => AttentionReceipt(
  id: id,
  category: 'requestProgress',
  kind: 'relayReceived',
  priority: 'normal',
  title: 'Title $id',
  body: 'Body',
  actionUrl: '/#/',
  createdAt: createdAt ?? DateTime.utc(2026, 9, 10, 12),
  collapsedCount: 1,
  presentationPayloadJson: '{}',
  surface: AttentionSurface.activity,
  itemKind: itemKind,
  forwardOutcome: forwardOutcome,
  digestCount: digestCount,
  eventTotal: eventTotal,
  beaconId: beaconId,
);

void main() {
  group('one representative per Request (spec §6, U16b acceptance)', () {
    // The server does NOT guarantee this pair away: a *watching* Request
    // (`inbox_item.status = 1`, not in helping scope, not pinned) satisfies
    // `eligible_forward` AND is excluded from neither `eligible_pinned` nor
    // `scope`, so `attention_repository.dart` emits a `forward` outcome row
    // and a `requestActivity` grouped row for the same beacon. Merging does
    // not collapse them either: `AttentionCase._requestIdentity` keys them
    // `request:forward:<beacon>` and `request:requestActivity:<beacon>`.
    test('a grouped card suppresses its own Request\'s tombstone row', () {
      final entries = forYouStreamEntries(
        receipts: [
          _receipt(
            id: 'f1',
            beaconId: 'b1',
            itemKind: AttentionItemKind.forward,
            forwardOutcome: AttentionForwardOutcome.watching,
          ),
          _receipt(
            id: 'ra1',
            beaconId: 'b1',
            itemKind: AttentionItemKind.requestActivity,
            eventTotal: 2,
          ),
        ],
        pinnedBeaconIds: const {},
      );

      expect(entries.length, 1);
      expect(entries.single.kind, ForYouStreamEntryKind.card);
      expect(entries.single.receipt.id, 'ra1');
    });

    test('the suppressed outcome survives as the card\'s relation chip', () {
      ForYouStreamEntry entryFor(AttentionForwardOutcome outcome) =>
          forYouStreamEntries(
            receipts: [
              _receipt(
                id: 'ra',
                beaconId: 'b1',
                itemKind: AttentionItemKind.requestActivity,
                eventTotal: 1,
              ),
              _receipt(
                id: 'f',
                beaconId: 'b1',
                itemKind: AttentionItemKind.forward,
                forwardOutcome: outcome,
              ),
            ],
            pinnedBeaconIds: const {},
          ).single;

      expect(
        entryFor(AttentionForwardOutcome.helping).relation,
        ForYouStreamRelation.helping,
      );
      expect(
        entryFor(AttentionForwardOutcome.watching).relation,
        ForYouStreamRelation.following,
      );
      // An answered-and-gone Request is not a standing relation.
      expect(
        entryFor(AttentionForwardOutcome.notInterested).relation,
        ForYouStreamRelation.none,
      );
    });

    test('the pinned zone wins over every stream row for its Request', () {
      final entries = forYouStreamEntries(
        receipts: [
          _receipt(
            id: 'ra1',
            beaconId: 'pinned',
            itemKind: AttentionItemKind.requestActivity,
            eventTotal: 1,
          ),
          _receipt(
            id: 'f1',
            beaconId: 'pinned',
            itemKind: AttentionItemKind.forward,
            forwardOutcome: AttentionForwardOutcome.helping,
          ),
          _receipt(
            id: 'ra2',
            beaconId: 'other',
            itemKind: AttentionItemKind.requestActivity,
            eventTotal: 1,
          ),
        ],
        pinnedBeaconIds: const {'pinned'},
      );

      expect(entries.map((e) => e.receipt.id), ['ra2']);
    });

    test('a loose receipt sharing a Request with a card is folded away', () {
      // The server keeps loose activity receipts beacon-less
      // (`WHERE v.beacon_id IS NULL`), so this cannot arrive today. The
      // filter is what makes that a guarantee rather than a hope.
      final entries = forYouStreamEntries(
        receipts: [
          _receipt(
            id: 'ra1',
            beaconId: 'b1',
            itemKind: AttentionItemKind.requestActivity,
            eventTotal: 1,
          ),
          _receipt(id: 'loose', beaconId: 'b1'),
        ],
        pinnedBeaconIds: const {},
      );

      expect(entries.map((e) => e.receipt.id), ['ra1']);
    });

    test('beacon-less receipts are never folded into each other', () {
      final entries = forYouStreamEntries(
        receipts: [
          _receipt(id: 'r1'),
          _receipt(id: 'r2'),
        ],
        pinnedBeaconIds: const {},
      );

      expect(entries.map((e) => e.receipt.id), ['r1', 'r2']);
      expect(
        entries.map((e) => e.kind),
        everyElement(ForYouStreamEntryKind.tile),
      );
    });

    test('an answered Request with no live events keeps its tombstone', () {
      final entries = forYouStreamEntries(
        receipts: [
          _receipt(
            id: 'f1',
            beaconId: 'b1',
            itemKind: AttentionItemKind.forward,
            forwardOutcome: AttentionForwardOutcome.notInterested,
          ),
        ],
        pinnedBeaconIds: const {},
      );

      expect(entries.single.kind, ForYouStreamEntryKind.tombstone);
    });

    test('a group takes the position of its first row', () {
      final entries = forYouStreamEntries(
        receipts: [
          _receipt(id: 'top'),
          _receipt(
            id: 'f1',
            beaconId: 'b1',
            itemKind: AttentionItemKind.forward,
            forwardOutcome: AttentionForwardOutcome.watching,
          ),
          _receipt(id: 'middle'),
          _receipt(
            id: 'ra1',
            beaconId: 'b1',
            itemKind: AttentionItemKind.requestActivity,
            eventTotal: 1,
          ),
        ],
        pinnedBeaconIds: const {},
      );

      expect(entries.map((e) => e.receipt.id), ['top', 'ra1', 'middle']);
    });
  });

  group('the Watching digest (U16b correction 1, option a)', () {
    // The digest row is one of exactly two placements it could have, and the
    // choice is recorded here so it cannot be mistaken for an oversight:
    //
    // (a) it KEEPS its list membership — `isInUnreadView` still answers
    //     `true`, mirroring the server's `true AS is_active_attention` — and
    //     stays reachable through the Watching collection in the For You
    //     overflow menu. The primary stream not drawing it is a *placement*
    //     decision, not a drop.
    // (b) it leaves the unread view, which would need the client mirror and
    //     the server branch to move together — a server change, out of scope.
    //
    // (a) is what ships. These two assertions are the pin: remove either and
    // the pair silently becomes "counted but unreachable", the §6 One
    // predicate failure in its other direction.
    final digest = _receipt(
      id: 'watching-digest',
      itemKind: AttentionItemKind.watchingDigest,
      digestCount: 3,
    );

    test('is not drawn in the primary stream', () {
      final entries = forYouStreamEntries(
        receipts: [digest, _receipt(id: 'r1')],
        pinnedBeaconIds: const {},
      );

      expect(entries.map((e) => e.receipt.id), ['r1']);
    });

    test('but keeps its membership in the unread view, deliberately', () {
      expect(
        isInUnreadView(digest),
        isTrue,
        reason: 'option (a): the row stays counted, and the Watching '
            'collection in the overflow menu is where it is reachable. '
            'Dropping it here without the server branch moving too is '
            'option (b), and option (b) is a server change.',
      );
    });
  });
}
