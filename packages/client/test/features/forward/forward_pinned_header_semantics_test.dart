import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/forward/ui/widget/forward_scope_links.dart';
import 'package:tentura/features/forward/ui/widget/per_recipient_note_input.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _FakeInvitationRepository extends Fake implements InvitationRepository {
  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<InvitationsFetchResult> fetchMine({
    int pendingOffset = 0,
    int pendingLimit = 0,
    int acceptedOffset = 0,
    int acceptedLimit = 0,
  }) async => (
    pending: <InvitationEntity>[],
    accepted: <InvitationEntity>[],
    pendingCount: 0,
  );

  @override
  Future<void> dispose() async {}
}

/// Whether [header] precedes the sibling that holds [content], in
/// the traversal order Flutter hands to the platform.
bool _headerBeforeContent(SemanticsNode header, SemanticsNode content) {
  // Climb from the note field to the child of the header's parent.
  final parent = header.parent!;
  var node = content;
  while (node.parent != parent) {
    node = node.parent!;
  }
  final order = parent.debugListChildrenInOrder(
    DebugSemanticsDumpOrder.traversalOrder,
  );
  return order.indexOf(header) < order.indexOf(node);
}

void main() {
  setUp(() {
    GetIt.I
      ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
      ..registerSingleton<InvitationRepository>(_FakeInvitationRepository());
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  // Flutter Web moves a reordered semantics node in the DOM, which blurs a
  // focused text field inside it and closes the on-screen keyboard. The note
  // field lives in the scroll view's content node, so that node must keep its
  // place after the pinned headers however short the keyboard makes the list.
  for (final keyboard in [0.0, 330.0, 450.0]) {
    testWidgets('pinned headers stay ahead of the list (keyboard $keyboard)', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(412, 839)
        ..viewInsets = FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.reset);

      final cubit = ForwardCubit(
        beaconId: 'b1',
        debugSkipInitialLoad: true,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      cubit.emit(
        ForwardState(
          beaconId: 'b1',
          beacon: Beacon.empty.copyWith(
            id: 'b1',
            title: 'Help moving',
            viewerCanForward: true,
          ),
          candidates: [
            for (var i = 0; i < 10; i++)
              ForwardCandidate(
                profile: Profile(
                  id: 'u$i',
                  displayName: 'Person $i',
                  score: 10,
                  rScore: 1,
                ),
              ),
          ],
          selectedIds: const {'u0'},
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
            child: const Scaffold(
              body: ForwardRecipientPicker(beaconId: 'b1'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PerRecipientNoteInput));
      await tester.pumpAndSettle();

      final header = tester.getSemantics(find.byType(ForwardScopeLinks));
      final field = tester.getSemantics(
        find.descendant(
          of: find.byType(PerRecipientNoteInput),
          matching: find.byType(EditableText),
        ),
      );
      expect(_headerBeforeContent(header, field), isTrue);
      semantics.dispose();
    });
  }
}
