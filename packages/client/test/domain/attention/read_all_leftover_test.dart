import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/attention_dismissible_membership.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';

AttentionReceipt _receipt({
  AttentionItemKind itemKind = AttentionItemKind.receipt,
  AttentionSurface surface = AttentionSurface.myWork,
  bool requiresAction = false,
  bool cleared = false,
  String? presentationKey,
}) => AttentionReceipt(
  id: 'r',
  category: 'c',
  kind: 'k',
  priority: 'normal',
  title: 't',
  body: 'b',
  actionUrl: '/',
  createdAt: DateTime.utc(2026),
  collapsedCount: 1,
  presentationPayloadJson: '{}',
  itemKind: itemKind,
  surface: surface,
  requiresAction: requiresAction,
  clearedAt: cleared ? DateTime.utc(2026) : null,
  presentationKey: presentationKey,
);

/// What Read all clears after its sweep: the gate (`canReadAll`) and the
/// action (`AttentionCase.readAll`) both ask [isReadAllLeftover].
void main() {
  group('isReadAllLeftover', () {
    final rows = <(String, AttentionReceipt, bool, bool)>[
      // (name, receipt, before sweep / sweep incomplete, sweep completed)
      ('optional receipt on My Work', _receipt(), true, true),
      (
        'optional receipt on Activity',
        _receipt(surface: AttentionSurface.activity),
        false,
        true,
      ),
      ('obligation', _receipt(requiresAction: true), false, false),
      ('cleared receipt', _receipt(cleared: true), false, false),
      (
        'forward shell (relay_received)',
        _receipt(presentationKey: 'relay_received'),
        false,
        false,
      ),
      (
        'relay_received on Activity',
        _receipt(
          surface: AttentionSurface.activity,
          presentationKey: 'relay_received',
        ),
        false,
        false,
      ),
      (
        'other presentation key',
        _receipt(presentationKey: 'offer_accepted'),
        true,
        true,
      ),
      (
        'grouped forward row',
        _receipt(itemKind: AttentionItemKind.forward),
        false,
        false,
      ),
      (
        'grouped request activity row',
        _receipt(itemKind: AttentionItemKind.requestActivity),
        false,
        false,
      ),
      (
        'watching digest row',
        _receipt(itemKind: AttentionItemKind.watchingDigest),
        false,
        false,
      ),
    ];
    for (final (name, receipt, incomplete, completed) in rows) {
      test(name, () {
        expect(isReadAllLeftover(receipt, sweepCompleted: false), incomplete);
        expect(isReadAllLeftover(receipt, sweepCompleted: true), completed);
      });
    }
  });
}
