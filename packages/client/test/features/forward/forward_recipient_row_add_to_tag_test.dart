// A forward-picker recipient row offers "Add to tag…" through a visible
// overflow button, a touch long press and a mouse secondary tap; the entry
// opens the add-to-tag sheet of that row's person. The viewer's own row and
// every row while the people-tags feature is off offer nothing, and the row's
// existing tap (open details) and checkbox keep working.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/model/forward_recipient_row_host.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_row.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/add_to_tag_sheet_probe.dart';
import '../../support/fake_people_tags_repository.dart';
import '../../support/optional_gate_call.dart';
import '../../support/person_menu_open_way.dart';

const _viewer = Profile(id: 'U-viewer', displayName: 'Viewer');
const _peerId = 'U-peer';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _viewer);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

ForwardCandidate _candidate(String id, String name) => ForwardCandidate(
  profile: Profile(id: id, displayName: name, score: 1, rScore: 1),
);

void main() {
  late PeopleTagsTestRig rig;
  var detailsOpened = 0;
  var toggled = 0;

  setUp(() async {
    detailsOpened = 0;
    toggled = 0;
    rig = await PeopleTagsTestRig.create(addToTagProbeRepository(_peerId));
    GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await rig.dispose();
  });

  /// [peopleTagsEnabled] null leaves the row's own default (the gate).
  Future<void> pumpRow(
    WidgetTester tester, {
    required ForwardCandidate candidate,
    bool? peopleTagsEnabled,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: BlocProvider<ProfileCubit>.value(
          value: _MockProfileCubit(),
          child: Scaffold(
            body:
                callWithPeopleTagsGate(
                      ForwardRecipientRow.new,
                      gate: peopleTagsEnabled,
                      named: {
                        #host: ForwardRecipientRowHost.pickerStandard,
                        #candidate: candidate,
                        #isSelected: false,
                        #onToggle: () => toggled++,
                        #onOpenDetails: () => detailsOpened++,
                      },
                    )!
                    as Widget,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final peer = _candidate(_peerId, 'Peer Person');
  final overflowButton = find.byIcon(Icons.more_vert);

  group('Forward recipient row: add to tag', () {
    testWidgets('a plain tap on the row opens its details, not a menu', (
      tester,
    ) async {
      await pumpRow(tester, candidate: peer, peopleTagsEnabled: true);

      await tester.tap(find.text('Peer Person'));
      await tester.pumpAndSettle();

      expect(detailsOpened, 1);
      expect(find.text('Add to tag…'), findsNothing);
    });

    testWidgets('the overflow button does not select the recipient', (
      tester,
    ) async {
      await pumpRow(tester, candidate: peer, peopleTagsEnabled: true);

      await tester.tap(overflowButton);
      await tester.pumpAndSettle();

      expect(toggled, 0);
      expect(detailsOpened, 0);
    });

    for (final way in PersonMenuOpenWay.values) {
      testWidgets('"Add to tag…" opened by ${way.name} shows in the menu', (
        tester,
      ) async {
        await pumpRow(tester, candidate: peer, peopleTagsEnabled: true);
        expect(find.text('Add to tag…'), findsNothing);

        await way.open(
          tester,
          overflow: overflowButton,
          target: find.text('Peer Person'),
        );

        expect(find.text('Add to tag…'), findsOneWidget);
      });

      testWidgets(
        '"Add to tag…" opened by ${way.name} opens the sheet for the row '
        'person',
        (tester) async {
          await pumpRow(tester, candidate: peer, peopleTagsEnabled: true);

          await way.open(
            tester,
            overflow: overflowButton,
            target: find.text('Peer Person'),
          );
          await tester.tap(find.text('Add to tag…'));

          await expectAddToTagSheetIsForPerson(
            tester,
            rig.repository,
            _peerId,
          );
        },
      );
    }

    testWidgets('the viewer row has no overflow button and no menu', (
      tester,
    ) async {
      await pumpRow(
        tester,
        candidate: _candidate(_viewer.id, 'Viewer'),
        peopleTagsEnabled: true,
      );

      expect(overflowButton, findsNothing);
      await expectNoPersonMenuFromGestures(
        tester,
        target: find.text('You'),
      );
    });

    testWidgets('is absent when the feature is switched off', (tester) async {
      await pumpRow(tester, candidate: peer, peopleTagsEnabled: false);

      expect(overflowButton, findsNothing);
      await expectNoPersonMenuFromGestures(
        tester,
        target: find.text('Peer Person'),
      );
    });

    testWidgets('is absent when phase 1 is explicitly disabled', (
      tester,
    ) async {
      await pumpRow(tester, candidate: peer, peopleTagsEnabled: false);

      expect(overflowButton, findsNothing);
      await expectNoPersonMenuFromGestures(
        tester,
        target: find.text('Peer Person'),
      );
    });
  });
}
