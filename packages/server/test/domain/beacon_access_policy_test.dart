import 'package:tentura_root/domain/entity/beacon_access.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/beacon_access_policy.dart';
import 'package:tentura_server/domain/beacon_visibility.dart';
import 'package:test/test.dart';

// Bit indices into the 11-boolean fact vector, in BeaconAccessFacts order.
const _blocked = 0;
const _author = 1;
const _steward = 2;
const _admitted = 3;
const _forwarded = 4;
const _applied = 5;
const _discoverable = 6;
const _published = 7;
const _trustVisible = 8;
const _parentMember = 9;
const _descendantMember = 10;
const _factCount = 11;

bool _bit(int v, int i) => v & (1 << i) != 0;

BeaconAccessFacts _facts(BeaconStatus status, int v) => BeaconAccessFacts(
  status: status,
  isBlocked: _bit(v, _blocked),
  isAuthor: _bit(v, _author),
  isSteward: _bit(v, _steward),
  isAdmitted: _bit(v, _admitted),
  hasActiveForwardEdgeAsRecipient: _bit(v, _forwarded),
  isActiveHelpOfferer: _bit(v, _applied),
  isDiscoverable: _bit(v, _discoverable),
  isPublished: _bit(v, _published),
  isTrustVisibleWithAuthor: _bit(v, _trustVisible),
  isMemberOfImmediateParent: _bit(v, _parentMember),
  isMemberOfDescendant: _bit(v, _descendantMember),
);

BeaconContentVisibilityFacts _visibilityFacts(BeaconAccessFacts f) =>
    BeaconContentVisibilityFacts(
      status: f.status,
      isAuthor: f.isAuthor,
      hasActiveForwardEdgeAsRecipient: f.hasActiveForwardEdgeAsRecipient,
      isRoomAdmittedOrSteward: f.isSteward || f.isAdmitted,
      isActiveHelpOfferer: f.isActiveHelpOfferer,
      isDiscoverable: f.isDiscoverable,
      isPublished: f.isPublished,
      isMutuallyVisibleWithAuthor: f.isTrustVisibleWithAuthor,
    );

void main() {
  const combos = 1 << _factCount;
  const grantFacts =
      (1 << _author) |
      (1 << _steward) |
      (1 << _admitted) |
      (1 << _forwarded) |
      (1 << _applied) |
      (1 << _discoverable);
  const contextFacts = (1 << _parentMember) | (1 << _descendantMember);

  test('exhaustive sweep: invariants and parity with BeaconVisibility', () {
    var cases = 0;
    var parityCases = 0;
    for (final status in BeaconStatus.values) {
      for (var v = 0; v < combos; v++) {
        cases++;
        final f = _facts(status, v);
        final level = BeaconAccessPolicy.level(f);
        final label = '$status facts=${v.toRadixString(2)}';

        // S4-11: context facts alone never grant membership.
        if (!f.isBlocked && v & grantFacts == 0 && v & contextFacts != 0) {
          expect(level.value, greaterThan(1), reason: label);
        }

        // S4-02: blocked is always stranger.
        if (f.isBlocked) {
          expect(level, BeaconAccessLevel.stranger, reason: label);
        }

        if (status == BeaconStatus.draft) {
          expect(
            level,
            f.isAuthor && !f.isBlocked
                ? BeaconAccessLevel.author
                : BeaconAccessLevel.stranger,
            reason: label,
          );
        }
        if (status == BeaconStatus.deleted) {
          expect(level, BeaconAccessLevel.stranger, reason: label);
        }

        // Phase-1 parity with today's content predicate.
        if (!f.isBlocked && v & contextFacts == 0) {
          parityCases++;
          expect(
            level.canReadContent,
            BeaconVisibility.canReadContent(_visibilityFacts(f)),
            reason: label,
          );
        }
      }
    }
    expect(cases, 16384);
    expect(parityCases, 8 * 256);
  });

  test('S4-01: gaining one non-block fact never worsens the level', () {
    var flips = 0;
    for (final status in BeaconStatus.values) {
      for (var v = 0; v < combos; v++) {
        if (_bit(v, _blocked)) continue;
        final before = BeaconAccessPolicy.level(_facts(status, v)).value;
        for (var i = 1; i < _factCount; i++) {
          if (_bit(v, i)) continue;
          flips++;
          final after = BeaconAccessPolicy.level(
            _facts(status, v | (1 << i)),
          ).value;
          expect(
            after,
            lessThanOrEqualTo(before),
            reason: '$status facts=${v.toRadixString(2)} flip=$i',
          );
        }
      }
    }
    // Each of 10 bits is false in half of the 1024 unblocked vectors.
    expect(flips, 8 * 10 * 512);
  });
}
