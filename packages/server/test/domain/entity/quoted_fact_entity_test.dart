import 'package:test/test.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/domain/entity/quoted_fact_entity.dart';

/// tentura-617.4 — plan §14.2: `QuotedFactEntity(factCardId, seq, factText,
/// pinnedById?, pinnedByTitle, visibility, status, currentSeq,
/// attachmentsJson)`, the server side of client `QuotedFact`.
void main() {
  test('carries the quoted snapshot and the current head', () {
    const quoted = QuotedFactEntity(
      factCardId: 'Fabc',
      seq: 2,
      factText: 'quoted text',
      pinnedById: 'Uaaa',
      pinnedByTitle: 'Alice',
      visibility: BeaconFactCardVisibilityBits.room,
      status: BeaconFactCardStatusBits.active,
      currentSeq: 5,
      attachmentsJson: '[]',
    );
    expect(quoted.factCardId, 'Fabc');
    expect(quoted.seq, 2);
    expect(quoted.factText, 'quoted text');
    expect(quoted.pinnedById, 'Uaaa');
    expect(quoted.pinnedByTitle, 'Alice');
    expect(quoted.visibility, BeaconFactCardVisibilityBits.room);
    expect(quoted.status, BeaconFactCardStatusBits.active);
    expect(quoted.currentSeq, 5);
    expect(quoted.attachmentsJson, '[]');
  });

  test('pinnedById is optional (pinner account deleted)', () {
    const quoted = QuotedFactEntity(
      factCardId: 'Fabc',
      seq: 1,
      factText: 't',
      pinnedByTitle: '',
      visibility: BeaconFactCardVisibilityBits.public,
      status: BeaconFactCardStatusBits.removed,
      currentSeq: 1,
      attachmentsJson: '[]',
    );
    expect(quoted.pinnedById, isNull);
  });
}
