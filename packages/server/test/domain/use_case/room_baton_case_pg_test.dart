@Tags(['pg'])
library;

import 'package:test/test.dart';

/// Placeholder for B4 (`docs/plans/baton-who-takes-it-plan.md`): the contract
/// declares `batonAsked`/`batonTaken`/`batonAllAnswered` in
/// `pendingProducerEventTypes` with `producerTests` pointing here before the
/// producer exists (B3), so the path must exist now. B4 replaces this group
/// with `RoomBatonCase.create`/`respond`'s real coverage.
void main() {
  group('RoomBatonCase.create / respond', () {
    test(
      'create on own message sends one batonAsked receipt per candidate',
      () {},
      skip: 'B4 — RoomBatonCase.create is not implemented yet',
    );
  });
}
