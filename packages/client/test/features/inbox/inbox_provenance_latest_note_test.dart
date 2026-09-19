import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';

/// U15R-b — R4, the client half of D-171-5a.
///
/// The card's first collapsed slot is the latest forward carrying a note. The
/// payload it reads is not hand-written here: `rawPayload` below is the exact
/// text `attention_provenance_data` returned for Astra's four-sender fixture,
/// captured and pinned by
/// `packages/server/test/data/repository/attention_latest_note_forward_pg_test.dart`.
/// A JSON literal that merely looks right would let the two layers agree on a
/// field neither of them actually produces.
void main() {
  final raw = _capturedServerPayload();

  group('InboxProvenance, on a real server response', () {
    test('carries the latest note-bearing forward the card pins first', () {
      final provenance = InboxProvenance.parse(raw);

      final latest = provenance.latestNoteForward;
      expect(
        latest,
        isNotNull,
        reason: 'D-171-5a: the first slot cannot be derived from senders[]',
      );
      expect(latest!.notePreview, isNotEmpty);
      expect(latest.senderId, isNotEmpty);
      expect(latest.displayName, isNotEmpty);
      expect(latest.forwardId, isNotEmpty);
    });

    test('the pinned forward is outside the MR-ranked window', () {
      final provenance = InboxProvenance.parse(raw);

      expect(
        provenance.senders.map((s) => s.id),
        isNot(contains(provenance.latestNoteForward!.senderId)),
        reason:
            'this is the whole point of R4 — the note U16 must show first '
            'belongs to a sender senders[] never mentions',
      );
      expect(
        provenance.strongestNotePreview,
        isEmpty,
        reason:
            'the MR-top sender is silent in this fixture, which is exactly '
            'why the old field could not serve as the first slot',
      );
    });

    test('the pinned forward carries a usable timestamp and attribution', () {
      final latest = InboxProvenance.parse(raw).latestNoteForward!;

      expect(latest.forwardedAt, isNotNull);
      expect(latest.forwardedAt!.isUtc, isTrue);
      expect(latest.reasonSlugs, isNotEmpty);
    });

    test('parse stays tolerant of the payload without the new field', () {
      final withoutField =
          jsonDecode(raw) as Map<String, dynamic>
            ..remove('latestNoteForward');

      final provenance = InboxProvenance.parse(jsonEncode(withoutField));

      expect(provenance.latestNoteForward, isNull);
      expect(provenance.senders, isNotEmpty);
      expect(provenance.totalDistinctSenders, greaterThan(0));
    });

    test('withoutViewer never leaves the viewer as the pinned forwarder', () {
      final provenance = InboxProvenance.parse(raw);
      final viewerId = provenance.latestNoteForward!.senderId;

      final out = provenance.withoutViewer(viewerId);

      expect(
        out.latestNoteForward,
        isNull,
        reason: 'never show self as forwarder — the rule the senders list '
            'already obeys applies to the pinned slot too',
      );
    });
  });
}

String _capturedServerPayload() {
  for (final candidate in const [
    '../../docs/contracts/attention-provenance-latest-note.json',
    'docs/contracts/attention-provenance-latest-note.json',
  ]) {
    final file = File(candidate);
    if (file.existsSync()) {
      return (jsonDecode(file.readAsStringSync())
          as Map<String, dynamic>)['rawPayload']! as String;
    }
  }
  throw StateError(
    'docs/contracts/attention-provenance-latest-note.json is missing; it is '
    'captured by attention_latest_note_forward_pg_test.dart',
  );
}
