import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_trust_badge.dart';

import '../../support/remote_field_fixture.dart';

void main() {
  group('Remote hints keep the Field current', () {
    test('an actorless relationship hint naming the viewer refreshes the '
        'contact edge within the freshness window', () {
      fakeAsync((async) {
        final h = RemoteFieldFixture(async);
        try {
          // The ordinary server shape must work while the lease stays visible:
          // the aggregate is the viewer and the actor is the changed contact.
          h.reads.field = fieldSnapshot(mutual: false);
          h
            ..hint('relationship', fieldViewerId, actor: fieldContactId)
            ..advance(const Duration(milliseconds: 1500));
          expect(h.reads.relationReads, [
            {fieldContactId},
          ]);
          expect(h.badge, ConstellationTrustBadge.youTrust);

          h.reads.field = fieldSnapshot();
          h
            ..hint('relationship', fieldViewerId, actor: fieldContactId)
            ..advance(const Duration(milliseconds: 1500));
          expect(h.badge, ConstellationTrustBadge.mutual);
          h.reads.relationReads.clear();

          h.reads.field = fieldSnapshot(mutual: false);
          h
            ..hint('relationship', fieldViewerId)
            ..advance(const Duration(milliseconds: 1500));

          expect(
            h.reads.relationReads.expand((ids) => ids),
            contains(fieldContactId),
          );
          expect(h.badge, ConstellationTrustBadge.youTrust);
        } finally {
          h.dispose();
        }
      });
    });

    test('a later actorless hint in one wire burst preserves the remote '
        'untrust refresh', () {
      fakeAsync((async) {
        final h = RemoteFieldFixture(async);
        try {
          h.reads.field = fieldSnapshot(mutual: false);
          h
            ..hint('relationship', fieldViewerId, actor: fieldContactId)
            ..hint('relationship', fieldViewerId)
            ..advance(const Duration(milliseconds: 1500));

          expect(
            h.reads.relationReads.expand((ids) => ids),
            contains(fieldContactId),
          );
          expect(h.badge, ConstellationTrustBadge.youTrust);
        } finally {
          h.dispose();
        }
      });
    });

    test('returning to the Field fetches the contact Request named by a '
        'hint received on another tab', () {
      fakeAsync((async) {
        final h = RemoteFieldFixture(async);
        try {
          // First publish while the Field remains open. This must perform an
          // authorized targeted read and display the Request within 1.5 s.
          h.reads.field = fieldSnapshot(published: true);
          h
            ..hint(
              'constellation_item',
              fieldRequest.id,
              actor: fieldContactId,
              event: 'insert',
            )
            ..advance(const Duration(milliseconds: 1500));
          expect(h.reads.requestReads, [
            {fieldRequest.id},
          ]);
          expect(h.store.current.field!.requests, contains(fieldRequest));

          final nextRequest = fieldRequest.copyWith(
            id: 'Bnext',
            title: 'Another published Request',
          );
          h.lease.setVisible(false);
          h.reads.field = fieldSnapshot().copyWith(
            requests: [fieldRequest, nextRequest],
          );
          h.reads.requestReads.clear();
          h
            ..hint(
              'constellation_item',
              nextRequest.id,
              actor: fieldContactId,
              event: 'insert',
            )
            ..advance(const Duration(milliseconds: 1500));
          expect(h.reads.requestReads, isEmpty);

          h.lease.setVisible(true);
          h.advance(const Duration(milliseconds: 1500));
          expect(
            h.reads.requestReads.expand((ids) => ids),
            contains(nextRequest.id),
          );
          expect(h.store.current.field!.requests, contains(nextRequest));
        } finally {
          h.dispose();
        }
      });
    });

    test('returning to the Field refreshes the contact edge named by a '
        'remote hint received on another tab', () {
      fakeAsync((async) {
        final h = RemoteFieldFixture(async);
        try {
          h.lease.setVisible(false);
          h.reads.field = fieldSnapshot(mutual: false);
          h
            ..hint('relationship', fieldViewerId, actor: fieldContactId)
            ..advance(const Duration(milliseconds: 1500));
          expect(h.reads.relationReads, isEmpty);

          h.lease.setVisible(true);
          h.advance(const Duration(milliseconds: 1500));
          expect(
            h.reads.relationReads.expand((ids) => ids),
            contains(fieldContactId),
          );
          expect(h.badge, ConstellationTrustBadge.youTrust);
        } finally {
          h.dispose();
        }
      });
    });
  });
}
