import 'package:test/test.dart';

import 'package:tentura_server/domain/trust/ledger_evidence.dart';
import 'package:tentura_server/domain/trust/trust_evidence_kind.dart';

/// A2: ledger domain types (Arch §4.4).
void main() {
  group('TrustEvidenceKind', () {
    test('codes match trust_kind_config.kind', () {
      expect(
        {for (final k in TrustEvidenceKind.values) k.name: k.code},
        {
          'vouch': 1,
          'helped': 2,
          'marked': 3,
          'routed': 4,
          'usefulForward': 5,
          'engaged': 6,
          'noisy': 7,
          'workedWithAuthor': 8,
          'supportedColleague': 9,
        },
      );
    });
  });

  group('LedgerEvidence', () {
    LedgerEvidence make({
      String subject = 'Ua',
      String object = 'Ub',
      num count = 1,
    }) => LedgerEvidence(
      subjectId: subject,
      objectId: object,
      kind: TrustEvidenceKind.vouch,
      count: count.toDouble(),
      sourceKey: 'k:1',
    );

    test('keeps fields and defaults', () {
      final e = make();
      expect(e.subjectId, 'Ua');
      expect(e.objectId, 'Ub');
      expect(e.kind, TrustEvidenceKind.vouch);
      expect(e.count, 1);
      expect(e.sourceKey, 'k:1');
      expect(e.beaconId, isNull);
      expect(e.epoch, isNull);
      expect(e.relatedUserId, isNull);
      expect(e.occurredAt, isNull);
      expect(e.metadata, isEmpty);
    });

    test('rejects self pair', () {
      expect(() => make(object: 'Ua'), throwsA(isA<AssertionError>()));
    });

    test('rejects non-positive count', () {
      expect(() => make(count: 0), throwsA(isA<AssertionError>()));
      expect(() => make(count: -1), throwsA(isA<AssertionError>()));
    });
  });
}
