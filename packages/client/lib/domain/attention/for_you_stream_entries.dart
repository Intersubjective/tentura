import 'entity/attention_feed.dart';
import 'entity/attention_receipt.dart';

/// What a For You stream row is drawn as (card spec §6, §8, §9).
enum ForYouStreamEntryKind {
  /// A `RequestAttentionCard` in its grouped variant: the Request, headed by
  /// what is being asked, with its live events as mini-cards underneath.
  card,

  /// A `TombstoneRow`: a memory of an act, with the private ×.
  tombstone,

  /// An ungrouped receipt — not about a Request — kept as a feed tile.
  tile,
}

/// The viewer's standing relation, as the stream reads it off the suppressed
/// outcome row. Mirrors `RequestAttentionRelation`, which is UI.
enum ForYouStreamRelation { none, helping, following }

/// One drawable row of the For You stream.
class ForYouStreamEntry {
  const ForYouStreamEntry({
    required this.receipt,
    required this.kind,
    this.relation = ForYouStreamRelation.none,
  });

  final AttentionReceipt receipt;
  final ForYouStreamEntryKind kind;

  /// Carried over from an outcome row this entry replaced, so suppressing a
  /// duplicate never loses what it said.
  final ForYouStreamRelation relation;
}

/// **One representative per Request** (card spec §6, §9) — the acceptance
/// rule of the For You stream, enforced here because the server does not
/// enforce it.
///
/// The server's stream union in `packages/server/.../attention_repository.dart`
/// rules out three of the four collisions and not the fourth:
///
/// | pair | why it cannot happen |
/// | --- | --- |
/// | pinned + `requestActivity` | `stats.beacon_id NOT IN eligible_representative` |
/// | pinned + `forward` | `eligible_pinned` is `status = 0`, `eligible_forward` is `status <> 0` or in scope |
/// | loose `receipt` + anything | the receipt branch is `WHERE v.beacon_id IS NULL` |
/// | **`forward` + `requestActivity`** | **nothing** — a *watching* Request (`status = 1`, not in scope, not pinned) is in `eligible_forward` and excluded from neither guard on the `requestActivity` branch |
///
/// and the merge does not collapse the fourth either: `_requestIdentity` keys
/// the two `request:forward:<beacon>` and `request:requestActivity:<beacon>`.
/// A Request would then show a grouped card *and* a tombstone — the exact
/// "offer card and grouped card and forward row for one Request" the unified
/// card exists to end. The card wins, because it is the surface that carries
/// the live events and the actions; the outcome it displaced comes back as
/// the card's relation chip (§9 state matrix: grouped + «Помогаю» / «Слежу»).
///
/// The Watching digest is deliberately **not** drawn here, while
/// `isInUnreadView` deliberately still counts it — see
/// `for_you_stream_entries_test.dart`, which pins that pair.
List<ForYouStreamEntry> forYouStreamEntries({
  required Iterable<AttentionReceipt> receipts,
  required Set<String> pinnedBeaconIds,
}) {
  final entries = <ForYouStreamEntry>[];
  // Where in [entries] a Request's representative already sits. Not a cache of
  // attention rows — an index into the list being built (§0.3).
  final slotByBeacon = <String, int>{};

  for (final receipt in receipts) {
    // Correction 1, option (a): a placement decision. The Watching collection
    // in the For You overflow menu is the digest's home; its membership in the
    // unread view is untouched.
    if (receipt.itemKind == AttentionItemKind.watchingDigest) continue;

    final beaconId = receipt.beaconId ?? '';
    if (beaconId.isEmpty) {
      entries.add(
        ForYouStreamEntry(
          receipt: receipt,
          kind: ForYouStreamEntryKind.tile,
        ),
      );
      continue;
    }
    // The pinned zone is the Request's representative already.
    if (pinnedBeaconIds.contains(beaconId)) continue;

    final candidate = ForYouStreamEntry(
      receipt: receipt,
      kind: switch (receipt.itemKind) {
        AttentionItemKind.requestActivity => ForYouStreamEntryKind.card,
        AttentionItemKind.forward => ForYouStreamEntryKind.tombstone,
        AttentionItemKind.receipt ||
        AttentionItemKind.watchingDigest => ForYouStreamEntryKind.tile,
      },
      relation: _relationOf(receipt),
    );

    final slot = slotByBeacon[beaconId];
    if (slot == null) {
      slotByBeacon[beaconId] = entries.length;
      entries.add(candidate);
      continue;
    }
    // A group keeps the position its first row took, so resolving a duplicate
    // never moves the Request under the reader.
    entries[slot] = _preferred(entries[slot], candidate);
  }

  return List.unmodifiable(entries);
}

/// The card outranks the tombstone, which outranks a loose tile; whichever
/// loses still hands over its relation.
ForYouStreamEntry _preferred(ForYouStreamEntry a, ForYouStreamEntry b) {
  final winner = _rank(b.kind) > _rank(a.kind) ? b : a;
  final relation = a.relation != ForYouStreamRelation.none
      ? a.relation
      : b.relation;
  return ForYouStreamEntry(
    receipt: winner.receipt,
    kind: winner.kind,
    relation: relation,
  );
}

int _rank(ForYouStreamEntryKind kind) => switch (kind) {
  ForYouStreamEntryKind.card => 2,
  ForYouStreamEntryKind.tombstone => 1,
  ForYouStreamEntryKind.tile => 0,
};

/// A standing relation, not a closed one: «Не интересно» and the two
/// before-response terminals are memories, and a memory is not a chip.
ForYouStreamRelation _relationOf(AttentionReceipt receipt) =>
    switch (receipt.forwardOutcome) {
      AttentionForwardOutcome.helping => ForYouStreamRelation.helping,
      AttentionForwardOutcome.watching => ForYouStreamRelation.following,
      _ => ForYouStreamRelation.none,
    };
