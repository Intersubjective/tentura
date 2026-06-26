import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';

void main() {
  group('InboxProvenance.withoutViewer', () {
    test('removes viewer from senders and adjusts total', () {
      const provenance = InboxProvenance(
        senders: [
          InboxForwardSender(
            id: 'Uforwarder',
            displayName: 'Forwarder',
            mr: 1,
          ),
          InboxForwardSender(
            id: 'Uviewer',
            displayName: 'Viewer',
            mr: 0,
          ),
        ],
        totalDistinctSenders: 2,
        strongestNotePreview: '',
      );

      final out = provenance.withoutViewer('Uviewer');

      expect(out.senders, hasLength(1));
      expect(out.senders.single.id, 'Uforwarder');
      expect(out.totalDistinctSenders, 1);
    });

    test('invite-forward JSON keeps forwarder after parse', () {
      const raw = '''
{
  "senders": [
    {
      "id": "Uissuer",
      "displayName": "agent issuer",
      "mr": 0,
      "imageId": null,
      "notePreview": "",
      "reasonSlugs": []
    }
  ],
  "totalDistinctSenders": 1,
  "strongestNotePreview": ""
}
''';

      final parsed = InboxProvenance.parse(raw);
      expect(parsed.senders.single.id, 'Uissuer');
      expect(parsed.withoutViewer('Uinvitee').senders, hasLength(1));
    });
  });
}
