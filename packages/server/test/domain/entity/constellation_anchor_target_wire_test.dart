import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:test/test.dart';

void main() {
  const id = 'PH0123456789ab';

  ConstellationAnchorTarget? parse(String kind) =>
      ConstellationAnchorTarget.tryFromWire(kindWire: kind, targetId: id);

  test('pin target kinds round-trip with their own typed keys', () {
    final person = parse('PERSON');
    expect(person, isA<ConstellationAnchorPersonTarget>());
    expect(person?.kind, ConstellationAnchorTargetKind.person);
    expect(person?.id, id);
    expect(person?.mapKey, 'PERSON:$id');

    final beacon = parse('BEACON');
    expect(beacon, isA<ConstellationAnchorBeaconTarget>());
    expect(beacon?.kind, ConstellationAnchorTargetKind.beacon);
    expect(beacon?.id, id);
    expect(beacon?.mapKey, 'BEACON:$id');
    expect(ConstellationAnchorTargetKind.fromWire('GHOST'), isNull);
    expect(parse('GHOST'), isNull);

    final kind = ConstellationAnchorTargetKind.fromWire('PHANTOM');
    expect(kind?.name, 'phantom');
    expect(kind?.wireValue, 'PHANTOM');
    final phantom = parse('PHANTOM');
    expect(phantom, isNotNull);
    expect(phantom?.kind, kind);
    expect(phantom?.id, id);
    expect(phantom?.mapKey, 'PHANTOM:$id');
    expect(phantom, isNot(isA<ConstellationAnchorPersonTarget>()));
    expect(phantom, isNot(isA<ConstellationAnchorBeaconTarget>()));
  });

  test(
    'a placeholder sharing an account id remains a separate non-ego pin',
    () {
      final person = ConstellationAnchorTarget.person(id);
      final beacon = ConstellationAnchorTarget.beacon(id);
      final phantom = parse('PHANTOM');
      expect(phantom, isNotNull, reason: 'PHANTOM must parse to a target');
      expect(phantom, isNot(equals(person)));
      expect(phantom, isNot(equals(beacon)));
      expect(person.isViewerEgo(id), isTrue);
      expect(phantom?.isViewerEgo(id), isFalse);
      expect(
        {
          person.mapKey: person,
          beacon.mapKey: beacon,
          phantom!.mapKey: phantom,
        },
        {'PERSON:$id': person, 'BEACON:$id': beacon, 'PHANTOM:$id': phantom},
      );
    },
  );
}
