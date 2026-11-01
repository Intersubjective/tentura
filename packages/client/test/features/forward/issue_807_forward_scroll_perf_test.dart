import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/domain/forward_target_profile.dart';
import 'package:tentura/features/forward/ui/model/forward_recipient_row_host.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker_entry.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

int _elementSubtreeSize(Element root) {
  var count = 1;
  root.visitChildren((child) => count += _elementSubtreeSize(child));
  return count;
}

Element _rowElement(WidgetTester tester, String userId) {
  return tester.element(
    find.byKey(TestIds.key(TestIds.forwardRecipient(userId))),
  );
}

ForwardCubit _cubitWithManyCandidates({required Set<String> selectedIds}) {
  final candidates = List.generate(
    50,
    (i) => ForwardCandidate(
      profile: Profile(
        id: 'u$i',
        displayName: 'Person $i',
        score: (100 - i).toDouble(),
        rScore: 1,
      ),
    ),
  );
  return ForwardCubit(
    beaconId: 'draft-807',
    debugSkipInitialLoad: true,
    embedded: true,
    effects: FakeUiEffectPort(),
  )..emit(
    ForwardState(
      beaconId: 'draft-807',
      beacon: Beacon.empty.copyWith(id: 'draft-807', title: 'Draft'),
      candidates: candidates,
      candidatesLoad: const ForwardCandidatesReady(),
      selectedIds: selectedIds,
    ),
  );
}

Future<void> _pumpPicker(
  WidgetTester tester, {
  required ForwardCubit cubit,
  required Map<String, int> builds,
}) async {
  await usePhoneSurface(tester);
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
          body: ForwardRecipientPicker(
            beaconId: 'draft-807',
            embedded: true,
            debugOnRowBuild: (id) => builds[id] = (builds[id] ?? 0) + 1,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'selected and unselected forward rows share the same action chrome depth',
    (tester) async {
      final selected = {for (var i = 0; i < 50; i += 4) 'u$i'};
      final cubit = _cubitWithManyCandidates(selectedIds: selected);
      addTearDown(cubit.close);
      final expanded = ValueNotifier<String?>(null);
      addTearDown(expanded.dispose);

      await usePhoneSurface(tester);
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
                  ForwardRecipientPickerEntry(
                    key: const ValueKey('u0'),
                    candidate: cubit.state.candidates.firstWhere(
                      (c) => c.id == 'u0',
                    ),
                    host: ForwardRecipientRowHost.pickerStandard,
                    beacon: cubit.state.beacon,
                    profile: ForwardTargetProfile.request,
                    viewerIsAuthor: false,
                    expandedPersonalNoteRecipientId: expanded,
                    onToggle: () {},
                    onOpenDetails: null,
                    onEditReasons: () {},
                    onEditForward: null,
                    onCancelForward: null,
                    onOpenPersonalNote: () {},
                    onPersonalNoteCollapsed: () {},
                    recipientNoteController: null,
                    onRecipientNoteChanged: (_) {},
                  ),
                  ForwardRecipientPickerEntry(
                    key: const ValueKey('u1'),
                    candidate: cubit.state.candidates.firstWhere(
                      (c) => c.id == 'u1',
                    ),
                    host: ForwardRecipientRowHost.pickerStandard,
                    beacon: cubit.state.beacon,
                    profile: ForwardTargetProfile.request,
                    viewerIsAuthor: false,
                    expandedPersonalNoteRecipientId: expanded,
                    onToggle: () {},
                    onOpenDetails: null,
                    onEditReasons: () {},
                    onEditForward: null,
                    onCancelForward: null,
                    onOpenPersonalNote: () {},
                    onPersonalNoteCollapsed: () {},
                    recipientNoteController: null,
                    onRecipientNoteChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final selectedSize = _elementSubtreeSize(_rowElement(tester, 'u0'));
      final unselectedSize = _elementSubtreeSize(_rowElement(tester, 'u1'));

      expect(
        (selectedSize - unselectedSize).abs(),
        lessThanOrEqualTo(8),
        reason:
            'selection must not swap trailing controls (Flex/placeholder); '
            'was selected=$selectedSize unselected=$unselectedSize',
      );
    },
  );

  testWidgets(
    'wheel-scrolling a 50-row picker with 12 selected does not rebuild rows',
    (tester) async {
      final selected = {for (var i = 0; i < 50; i += 4) 'u$i'};
      final cubit = _cubitWithManyCandidates(selectedIds: selected);
      addTearDown(cubit.close);

      final builds = <String, int>{for (final id in selected) id: 0};
      for (var i = 0; i < 50; i++) {
        builds.putIfAbsent('u$i', () => 0);
      }

      await _pumpPicker(tester, cubit: cubit, builds: builds);

      final scrollable = find.byType(Scrollable).first;
      // Warm-up scroll (settle layout / keep-alive edge cases).
      await tester.drag(scrollable, const Offset(0, -200));
      await tester.pump();
      await tester.drag(scrollable, const Offset(0, 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final baseline = Map<String, int>.from(builds);

      for (var pass = 0; pass < 6; pass++) {
        await tester.drag(scrollable, const Offset(0, -140));
        await tester.pump();
      }
      for (var pass = 0; pass < 6; pass++) {
        await tester.drag(scrollable, const Offset(0, 140));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 200));

      for (final id in selected) {
        expect(
          builds[id]! - baseline[id]!,
          lessThanOrEqualTo(builds['u1']! - baseline['u1']!),
          reason: 'selected row $id rebuilt more than unselected peer during scroll',
        );
      }
    },
  );
}
