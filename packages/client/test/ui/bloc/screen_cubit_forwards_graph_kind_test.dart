// Issue #501: opening the forwards graph of a Post tells the screen it is a
// post, so the title does not read "request" until the beacon has loaded.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../effect/fake_ui_effect_port.dart';

void main() {
  late FakeUiEffectPort effects;
  late ScreenCubit cubit;

  setUp(() {
    effects = FakeUiEffectPort();
    cubit = ScreenCubit(effects);
  });

  tearDown(() => cubit.close());

  String lastPath() => effects.emitted.whereType<NavigatePush>().last.path;

  test('a post opens its forwards graph with the post kind', () {
    cubit.showForwardsGraphFor('B1', kind: BeaconKind.post);

    expect(lastPath(), '$kPathForwardsGraph/B1?$kQueryForwardsGraphKind=post');
  });

  test('a request keeps the plain forwards graph path', () {
    cubit.showForwardsGraphFor('B1', kind: BeaconKind.request);

    expect(lastPath(), '$kPathForwardsGraph/B1');
  });

  test('an unknown kind keeps the plain forwards graph path', () {
    cubit.showForwardsGraphFor('B1');

    expect(lastPath(), '$kPathForwardsGraph/B1');
  });
}
