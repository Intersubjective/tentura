// #730 (the hint): someone who dismissed the Request stays out of the
// author's Forward picker, and their row now says how the author can still
// ask them — People › Invite, which carries a note — instead of a bare
// "Dismissed this request" next to a disabled box.
//
// #722: "Already involved N" counted people the viewer cannot see as people
// (no trust, no rank toward them, no shared Request), so the tab promised
// names it could not show. The count and the list hold only people the
// viewer can see.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_state.dart';
import 'package:tentura/features/forward/ui/model/forward_recipient_row_host.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

const _dismissed = ForwardCandidate(
  profile: Profile(id: 'carol', displayName: 'Carol', rScore: 1, score: 40),
  involvement: CandidateInvolvement.declined,
);

void main() {
  group('#730 a dismissed row in the author picker', () {
    test('tells the author to use People › Invite', () {
      expect(
        forwardRecipientRelationLabel(
          L10nEn(),
          _dismissed,
          viewerIsAuthor: true,
        ),
        'They dismissed it — use People › Invite',
      );
      expect(
        forwardRecipientRelationLabel(
          L10nRu(),
          _dismissed,
          viewerIsAuthor: true,
        ),
        'Убрал(а) запрос — позовите через «Люди › Позвать»',
      );
    });

    test('the row line carries the hint', () {
      final line = computeForwardRecipientLine2(
        candidate: _dismissed,
        host: ForwardRecipientRowHost.pickerStandard,
        todayUtc: DateTime.utc(2026, 10, 25),
        l10n: L10nEn(),
        locale: const Locale('en'),
        viewerIsAuthor: true,
      );
      expect(line.relationLabel, 'They dismissed it — use People › Invite');
    });

    test('the person stays blocked', () {
      expect(_dismissed.canForwardToOn(DateTime.utc(2026, 10, 25)), isFalse);
    });

    // Guards: someone who is not the author has no People › Invite, and a
    // Post has no invitations; both keep the plain words.
    test('a forwarder who is not the author keeps the plain words', () {
      expect(
        forwardRecipientRelationLabel(L10nEn(), _dismissed),
        'Dismissed this request',
      );
    });

    test('on a Post the author keeps the plain words', () {
      expect(
        forwardRecipientRelationLabel(
          L10nEn(),
          _dismissed,
          viewerIsAuthor: true,
          isPost: true,
        ),
        'Dismissed this request',
      );
    });
  });

  group('#722 Already involved counts only people the viewer can see', () {
    const seen = ForwardCandidate(
      profile: Profile(id: 'dave', displayName: 'Dave', rScore: 1, score: 30),
      involvement: CandidateInvolvement.forwarded,
    );
    const bonded = ForwardCandidate(
      profile: Profile(
        id: 'eve',
        displayName: 'Eve',
        sharesActiveContext: true,
      ),
      involvement: CandidateInvolvement.watching,
    );
    // Reaches the viewer, but the viewer neither trusts nor ranks them.
    const unseenByViewer = ForwardCandidate(
      profile: Profile(
        id: 'stranger',
        displayName: 'Stranger',
        rScore: 1,
        subjectExplicitlyTrustsViewer: true,
      ),
      involvement: CandidateInvolvement.forwarded,
    );

    ForwardState state({List<ForwardCandidate>? candidates}) => ForwardState(
      beaconId: 'B1',
      candidates: candidates ?? const [seen, bonded, unseenByViewer],
      activeFilter: ForwardFilter.alreadyInvolved,
    );

    test('the count leaves out people the viewer cannot see', () {
      expect(state().scopeCounts.involved, 2);
    });

    test('the count matches the rows the tab lists', () {
      final s = state();
      expect(
        s.visibleRecipients.map((c) => c.id).toSet(),
        {'dave', 'eve'},
      );
      expect(s.visibleRecipients, hasLength(s.scopeCounts.involved));
    });

    test('a Post author still counts on a Post', () {
      const author = ForwardCandidate(
        profile: Profile(id: 'alice', displayName: 'Alice'),
        involvement: CandidateInvolvement.author,
      );
      final s = ForwardState(
        beaconId: 'P1',
        beacon: Beacon.empty.copyWith(id: 'P1', kind: BeaconKind.post),
        candidates: const [author, unseenByViewer],
        activeFilter: ForwardFilter.alreadyInvolved,
      );
      expect(s.scopeCounts.involved, 1);
      expect(s.visibleRecipients.single.id, 'alice');
    });
  });
}
