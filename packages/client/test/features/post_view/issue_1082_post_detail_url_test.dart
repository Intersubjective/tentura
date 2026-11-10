// Refs #1082 — in-app navigation and legacy URLs use /post/view for Posts.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/beacon_detail_path.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/post_view/data/repository/beacon_kind_repository.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../support/remote_wire_harness.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _postId = 'B1082post0001';
const _requestId = 'B1082request1';

void main() {
  test('ScreenCubit.showPost emits /post/view navigation', () {
    final effects = FakeUiEffectPort();
    ScreenCubit.local(effects).showPost(_postId, entry: kBeaconEntryInbox);
    expect(effects.emitted, hasLength(1));
    final path = (effects.emitted.single as NavigatePush).path;
    expect(path, '$kPathPostView/$_postId?$kQueryBeaconEntry=inbox');
  });

  test('ScreenCubit.showBeacon with post kind uses /post/view', () {
    final effects = FakeUiEffectPort();
    ScreenCubit.local(effects).showBeacon(_postId, kind: BeaconKind.post);
    final path = (effects.emitted.single as NavigatePush).path;
    expect(path.startsWith('$kPathPostView/$_postId'), isTrue);
  });

  test('request opened at /post/view rewrites to /beacon/view', () {
    expect(
      beaconDetailPathFor(_requestId, isPost: false),
      '$kPathBeaconView/$_requestId',
    );
  });

  test('beaconDetailPathFor matches product vocabulary', () {
    expect(
      beaconDetailPathFor(_postId, isPost: true),
      '$kPathPostView/$_postId',
    );
    expect(
      beaconDetailPathFor(
        _requestId,
        isPost: false,
        queryParameters: {kQueryBeaconEntry: 'my_work'},
      ),
      '$kPathBeaconView/$_requestId?$kQueryBeaconEntry=my_work',
    );
  });

  test(
    'wire-mapped beacon kind builds /post/view for kind=1',
    () async {
      final sent = <WireSent>[];
      await withRemoteWire(
        {
          'BeaconKindFetch': {
            '__typename': 'query_root',
            'beacon_by_pk': {
              '__typename': 'beacon',
              'id': _postId,
              'kind': 1,
            },
          },
        },
        sent,
        (remote) async {
          await remote.setSessionAuth();
          final repo = BeaconKindRepository(remote);
          final kind = await repo.fetchKind(_postId);
          expect(kind, BeaconKind.post);
          expect(
            beaconDetailPathFor(_postId, isPost: kind == BeaconKind.post),
            '$kPathPostView/$_postId',
          );
        },
      );
      expect(sent.map((w) => w.operationName), contains('BeaconKindFetch'));
    },
  );
}
