import 'package:test/test.dart';

import 'package:tentura_server/domain/closure/author_split.dart';

const _beaconId = 'B1';

String _h(int index) => 'h${index.toString().padLeft(2, '0')}';

Map<String, int> _equalOnes(int count) =>
    {for (var i = 1; i <= count; i++) _h(i): 1};

void _expectSplit(Map<String, int> actual, Map<String, int> expected) {
  expect(actual, expected);
  expect(actual.values.fold<int>(0, (sum, v) => sum + v), 100);
}

void main() {
  group('Author split fixed vectors', () {
    test('E1 renormalize adds member u4', () {
      final result = renormalize(
        current: {'u1': 70, 'u2': 20, 'u3': 10},
        newA: {'u1', 'u2', 'u3', 'u4'},
        beaconId: _beaconId,
      );
      _expectSplit(result!, {'u1': 55, 'u2': 15, 'u3': 10, 'u4': 20});
    });

    test('E2 apportion water-fill with skewed weights', () {
      final result = apportion(
        total: 100,
        weights: {'u1': 90, 'u2': 4, 'u3': 3, 'u4': 3},
        min: 5,
        beaconId: _beaconId,
      );
      _expectSplit(result, {'u1': 85, 'u2': 5, 'u3': 5, 'u4': 5});
    });

    test('E3 moveSlider equal three members u1 to 50', () {
      final result = moveSlider(
        current: {'u1': 1, 'u2': 1, 'u3': 1},
        helperId: 'u1',
        value: 50,
        beaconId: _beaconId,
      );
      _expectSplit(result, {'u1': 50, 'u2': 25, 'u3': 25});
    });

    test('E4 moveSlider equal three members u1 to 45 tie-break', () {
      final result = moveSlider(
        current: {'u1': 1, 'u2': 1, 'u3': 1},
        helperId: 'u1',
        value: 45,
        beaconId: _beaconId,
      );
      _expectSplit(result, {'u1': 45, 'u2': 30, 'u3': 25});
    });

    test('E5 moveSlider nineteen members h01 to 30 clamps to 10', () {
      final result = moveSlider(
        current: _equalOnes(19),
        helperId: _h(1),
        value: 30,
        beaconId: _beaconId,
      );
      final expected = {for (var i = 1; i <= 19; i++) _h(i): 5};
      expected[_h(1)] = 10;
      _expectSplit(result, expected);
    });

    test('E6 moveSlider twenty members h01 to 30 all five', () {
      final result = moveSlider(
        current: _equalOnes(20),
        helperId: _h(1),
        value: 30,
        beaconId: _beaconId,
      );
      _expectSplit(
        result,
        {for (var i = 1; i <= 20; i++) _h(i): 5},
      );
    });

    test('E7 renormalize shrinks A to two members', () {
      final result = renormalize(
        current: {'u1': 70, 'u2': 20, 'u3': 10},
        newA: {'u1', 'u2'},
        beaconId: _beaconId,
      );
      _expectSplit(result!, {'u1': 80, 'u2': 20});
    });

    test('E8 renormalize singleton A', () {
      final result = renormalize(
        current: {'u1': 70, 'u2': 20, 'u3': 10},
        newA: {'u1'},
        beaconId: _beaconId,
      );
      _expectSplit(result!, {'u1': 100});
    });

    test('E9 moveSlider equal three members u1 to 100 clamps to 90', () {
      final result = moveSlider(
        current: {'u1': 1, 'u2': 1, 'u3': 1},
        helperId: 'u1',
        value: 100,
        beaconId: _beaconId,
      );
      _expectSplit(result, {'u1': 90, 'u2': 5, 'u3': 5});
    });

    test('E10 renormalize twenty members to twenty-one returns null', () {
      final current = {for (var i = 1; i <= 20; i++) _h(i): 5};
      final newA = {for (var i = 1; i <= 21; i++) _h(i)};
      expect(
        renormalize(current: current, newA: newA, beaconId: _beaconId),
        isNull,
      );
    });

    test('E11 renormalize empty newA returns null', () {
      expect(
        renormalize(
          current: {'u1': 50, 'u2': 50},
          newA: {},
          beaconId: _beaconId,
        ),
        isNull,
      );
    });

    test('E12 validate twenty-one members returns splitTooLarge', () {
      final a = {for (var i = 1; i <= 21; i++) _h(i)};
      final split = {for (final id in a) id: 5};
      expect(() => validate(split, a), returnsNormally);
      expect(validate(split, a), 'splitTooLarge');
    });
  });
}
