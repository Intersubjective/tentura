import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura/env.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import '../../support/counting_people_tags_repository.dart';
import '../../support/test_realtime_sync.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/fake_people_tags_repository.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _profile = Profile(
  id: 'U-peer',
  displayName: 'Peer',
  score: 1,
  rScore: 1,
);

const _neighbours = PersonTag(
  id: 'Ta',
  name: 'Neighbours',
  glyph: 'N',
  color: 0,
  ord: 0,
);

class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit() : super(const GraphPersonContextState());

  @override
  Stream<LazyWriteNotice> get lazyWriteNotices => const Stream.empty();

  @override
  Future<void> retryTrust([GraphTrustRevert? revert]) async {}

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {}

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  Future<void> untrustSelected() async {}

  @override
  void clearSelection() {}
}

void main() {
  late PeopleTagsCase peopleTags;
  late CountingPeopleTagsRepository repository;
  late TestRealtimeSyncPort realtimePort;

  setUp(() async {
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    repository = CountingPeopleTagsRepository(
      FakePeopleTagsRepository(
        tagList: [_neighbours],
        memberList: const [
          PersonTagMembers(tagId: 'Ta', personIds: ['U-peer']),
        ],
      ),
    );
    peopleTags = PeopleTagsCase(
      repository,
      realtime.case_,
      env: const Env(),
      logger: Logger('test'),
    );
    GetIt.I.registerSingleton<PeopleTagsCase>(peopleTags);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await peopleTags.dispose();
    await realtimePort.dispose();
  });

  /// [peopleTagsEnabled] null leaves the panel's own default (the gate).
  Future<void> pumpPanel(
    WidgetTester tester, {
    bool? peopleTagsEnabled,
  }) async {
    const size = Size(900, 700);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final ctx = _StubContextCubit();
    addTearDown(ctx.close);
    const focusedNode = UserNode(user: _profile);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: size),
          child: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<GraphPersonContextCubit>.value(value: ctx),
                BlocProvider<ScreenCubit>(
                  create: (_) => ScreenCubit(FakeUiEffectPort()),
                ),
              ],
              child: Scaffold(
                body: peopleTagsEnabled == null
                    ? const GraphPersonContextPanel(
                        profile: _profile,
                        focusedNode: focusedNode,
                      )
                    : GraphPersonContextPanel(
                        profile: _profile,
                        focusedNode: focusedNode,
                        peopleTagsEnabled: peopleTagsEnabled,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the person panel lists own tags on a cold session', (
    tester,
  ) async {
    await pumpPanel(tester);
    expect(find.text('Your tags'), findsOneWidget);
    expect(find.text('Neighbours'), findsOneWidget);
    expect(repository.tagsCalls, 1);
    expect(repository.membershipCalls, 1);
  });
  testWidgets(
    'the person panel reuses tags and reflects realtime membership changes',
    (tester) async {
      await pumpPanel(tester);
      expect(repository.tagsCalls, 1);
      expect(repository.membershipCalls, 1);
      await pumpPanel(tester);
      expect(repository.tagsCalls, 1);
      expect(repository.membershipCalls, 1);
      repository.store.memberList = const [];
      realtimePort.emitChange(
        RealtimeEntityChange(
          kind: RealtimeEntityKind.personTag,
          aggregateId: 'owner',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
          revision: BigInt.one,
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(repository.tagsCalls, 2);
      expect(repository.membershipCalls, 2);
      expect(find.text('Neighbours'), findsNothing);
    },
  );
}
