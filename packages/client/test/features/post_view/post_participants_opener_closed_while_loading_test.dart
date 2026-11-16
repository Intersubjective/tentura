// The «О посте» participants opener waits for the Post to load. When the Post
// screen goes away first (route popped, pane changed) the wait must end quietly:
// no uncaught StateError from the closed cubit's stream, and no sheet.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/post_view/ui/bloc/post_view_cubit.dart';
import 'package:tentura/features/post_view/ui/util/post_participants_sheet_request.dart';
import 'package:tentura/features/post_view/ui/widget/post_info_sheet.dart';
import 'package:tentura/features/post_view/ui/widget/post_participants_sheet_opener.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

const _postId = 'Bpostopener01';
const _me = Profile(id: 'Uviewer0001', displayName: 'Мария');

class _NeverLoadingRepository implements BeaconRepository {
  final pending = Completer<Beacon>();
  final _changes = StreamController<RepositoryEvent<Beacon>>.broadcast();

  @override
  Stream<RepositoryEvent<Beacon>> get changes => _changes.stream;

  @override
  Future<Beacon> fetchBeaconById(String id) => pending.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpOpener(
  WidgetTester tester, {
  required bool openWhenReady,
}) async {
  final repo = _NeverLoadingRepository();
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<PostViewCubit>(
        create: (_) {
          final cubit = PostViewCubit(
            id: _postId,
            myProfile: _me,
            beaconRepository: repo,
            effects: FakeUiEffectPort(),
          );
          unawaited(cubit.fetch());
          return cubit;
        },
        child: BlocProvider<ThreadHostCubit>(
          create: (_) => ThreadHostCubit(
            beaconId: _postId,
            capabilities: const RoomCapabilities.post(),
          ),
          child: PostParticipantsSheetOpener(
            postId: _postId,
            openWhenReady: openWhenReady,
            child: const Text('post screen'),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _unmountAndSettle(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
}

void main() {
  tearDown(() => PostParticipantsSheetRequest.instance.pending = '');

  group('Participants opener when the Post screen closes while loading', () {
    testWidgets('openWhenReady: no uncaught error and no sheet', (
      tester,
    ) async {
      await _pumpOpener(tester, openWhenReady: true);
      await _unmountAndSettle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(PostInfoSheet), findsNothing);
    });

    testWidgets('one-shot request: no uncaught error, request is used up', (
      tester,
    ) async {
      PostParticipantsSheetRequest.instance.pending = _postId;
      await _pumpOpener(tester, openWhenReady: false);
      await _unmountAndSettle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(PostInfoSheet), findsNothing);
      expect(PostParticipantsSheetRequest.instance.takeFor(_postId), isFalse);
    });
  });
}
