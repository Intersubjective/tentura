import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/add_to_tag_sheet_probe.dart';
import '../../support/fake_people_tags_repository.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _profile = Profile(
  id: 'U-peer',
  displayName: 'Peer',
  score: 1,
  rScore: 1,
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
  late PeopleTagsTestRig rig;

  setUp(() async {
    rig = await PeopleTagsTestRig.create(addToTagProbeRepository(_profile.id));
    GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await rig.dispose();
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

  group('graph person panel: add to tag action', () {
    testWidgets('shows an "Add to tag…" action', (tester) async {
      await pumpPanel(tester, peopleTagsEnabled: true);

      expect(find.text('Add to tag…'), findsOneWidget);
    });

    testWidgets('the action opens the sheet for the selected person', (
      tester,
    ) async {
      await pumpPanel(tester, peopleTagsEnabled: true);

      await tester.tap(find.text('Add to tag…'));

      await expectAddToTagSheetIsForPerson(
        tester,
        rig.repository,
        _profile.id,
      );
    });

    testWidgets('is absent when the feature is switched off', (tester) async {
      await pumpPanel(tester, peopleTagsEnabled: false);

      expect(find.text('Add to tag…'), findsNothing);
    });

    testWidgets('is absent when phase 1 is explicitly disabled', (
      tester,
    ) async {
      await pumpPanel(tester, peopleTagsEnabled: false);

      expect(find.text('Add to tag…'), findsNothing);
    });
  });
}
