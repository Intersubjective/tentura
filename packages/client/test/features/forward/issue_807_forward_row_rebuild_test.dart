import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/forward_target_profile.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/model/forward_recipient_row_host.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker_entry.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

void main() {
  testWidgets('toggling one forward recipient rebuilds only that row', (
    tester,
  ) async {
    final builds = <String, int>{'u1': 0, 'u2': 0, 'u3': 0};
    final expanded = ValueNotifier<String?>(null);
    addTearDown(expanded.dispose);

    final cubit = ForwardCubit(
      beaconId: 'draft-1',
      debugSkipInitialLoad: true,
      embedded: true,
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    cubit.emit(
      ForwardState(
        beaconId: 'draft-1',
        beacon: Beacon.empty.copyWith(id: 'draft-1', title: 'Draft'),
        candidates: const [
          ForwardCandidate(
            profile: Profile(id: 'u1', displayName: 'One', score: 3, rScore: 1),
          ),
          ForwardCandidate(
            profile: Profile(id: 'u2', displayName: 'Two', score: 2, rScore: 1),
          ),
          ForwardCandidate(
            profile: Profile(
              id: 'u3',
              displayName: 'Three',
              score: 1,
              rScore: 1,
            ),
          ),
        ],
        candidatesLoad: const ForwardCandidatesReady(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: MultiBlocProvider(
          providers: [
            BlocProvider<ForwardCubit>.value(value: cubit),
            BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
          ],
          child: Scaffold(
            body: ListView(
              children: [
                for (final id in ['u1', 'u2', 'u3'])
                  ForwardRecipientPickerEntry(
                    key: ValueKey(id),
                    candidate: cubit.state.candidates.firstWhere(
                      (c) => c.id == id,
                    ),
                    host: ForwardRecipientRowHost.pickerStandard,
                    beacon: cubit.state.beacon,
                    profile: ForwardTargetProfile.request,
                    viewerIsAuthor: false,
                    expandedPersonalNoteRecipientId: expanded,
                    onToggle: () => cubit.toggleSelection(id),
                    onOpenDetails: null,
                    onEditReasons: null,
                    onEditForward: null,
                    onCancelForward: null,
                    onOpenPersonalNote: () {},
                    onPersonalNoteCollapsed: () {},
                    recipientNoteController: TextEditingController(),
                    onRecipientNoteChanged: (_) {},
                    onBuild: () => builds[id] = builds[id]! + 1,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final afterFirstFrame = Map<String, int>.from(builds);

    cubit.toggleSelection('u2');
    await tester.pumpAndSettle();

    expect(builds['u1'], afterFirstFrame['u1']);
    expect(builds['u3'], afterFirstFrame['u3']);
    expect(builds['u2'], greaterThan(afterFirstFrame['u2']!));
  });
}
