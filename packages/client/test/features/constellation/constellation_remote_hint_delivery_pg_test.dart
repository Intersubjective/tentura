@Tags(['repo-files'])
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_trust_badge.dart';

import '../../support/field_remote_hint_contract.dart';
import '../../support/remote_field_fixture.dart';

void _receive(RemoteFieldFixture field, List<Map<String, dynamic>> frames) {
  expect(frames, isNotEmpty, reason: 'the wire contract includes a hint');
  frames.forEach(field.socket.add);
  field.async.flushMicrotasks();
  field.advance(const Duration(milliseconds: 1500));
}

void main() {
  test('Request and untrust socket frames update an open Field and fetch a '
      'later Request on tab return', () {
    expect(remoteHintViewerId, fieldViewerId);
    expect(remoteHintContactId, fieldContactId);
    final firstRequest = fieldRequest.copyWith(id: 'Bfirst');
    final secondRequest = fieldRequest.copyWith(id: 'Bsecond');
    final firstId = firstRequest.id;
    final secondId = secondRequest.id;
    final firstFrames = [remoteRequestFrame(firstId)];
    final secondFrames = [remoteRequestFrame(secondId)];
    // The server PG test checks real delivered envelopes against these same
    // contracts. This client test requires no server imports, codegen or DB.
    for (final operation in ['insert', 'update', 'delete']) {
      final untrustFrames = [remoteUntrustFrame(operation)];
      fakeAsync((async) {
        final field = RemoteFieldFixture(async);
        try {
          field.reads.field = fieldSnapshot().copyWith(
            requests: [firstRequest],
          );
          _receive(field, firstFrames);
          expect(field.reads.requestReads, [
            {firstId},
          ]);
          expect(field.store.current.field!.requests, contains(firstRequest));

          field.reads.field = fieldSnapshot(mutual: false).copyWith(
            requests: [firstRequest],
          );
          _receive(field, untrustFrames);
          expect(field.reads.relationReads, [
            {fieldContactId},
          ]);
          expect(field.badge, ConstellationTrustBadge.youTrust);

          field.lease.setVisible(false);
          field.reads.field = fieldSnapshot(mutual: false).copyWith(
            requests: [firstRequest, secondRequest],
          );
          _receive(field, secondFrames);
          expect(field.reads.requestReads, [
            {firstId},
          ]);

          field.lease.setVisible(true);
          field.advance(const Duration(milliseconds: 1500));
          expect(
            field.reads.requestReads.expand((ids) => ids),
            contains(secondId),
            reason: 'the deferred server hint must reach the targeted read',
          );
          expect(field.store.current.field!.requests, contains(secondRequest));
        } finally {
          field.dispose();
        }
      });
    }
  });
}
