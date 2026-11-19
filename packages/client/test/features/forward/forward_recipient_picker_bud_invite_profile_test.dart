// The Post→Request invite step reuses the Forward picker under the
// `postBudInvite` profile (docs/plans/invite-picker-reuses-forward-1292.md,
// D5/D6): search, multi-select, per-person notes, the reach line, the row
// context sheet and the host header stay; the invite-new-person bar, band,
// lineage, tag chips, scope links, reasons, attribution and the picker's own
// send composer go. An empty list speaks of the post, not of connections.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/capability/forward_band_row.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/entity/forward_inbound_source.dart';
import 'package:tentura/features/forward/domain/entity/forward_reach.dart';
import 'package:tentura/features/forward/domain/forward_target_profile.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_band_strip.dart';
import 'package:tentura/features/forward/ui/widget/forward_bottom_composer.dart';
import 'package:tentura/features/forward/ui/widget/forward_invite_bar.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_row.dart';
import 'package:tentura/features/forward/ui/widget/forward_scope_links.dart';
import 'package:tentura/features/forward/ui/widget/forward_tag_picker.dart';
import 'package:tentura/features/forward/ui/widget/lineage_forward_section.dart';
import 'package:tentura/features/forward/ui/widget/per_recipient_note_input.dart';
import 'package:tentura/features/forward_candidate_context/domain/entity/candidate_connection_context.dart';
import 'package:tentura/features/forward_candidate_context/domain/port/forward_candidate_context_repository_port.dart';
import 'package:tentura/features/forward_candidate_context/domain/use_case/load_forward_candidate_context_case.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

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
  Future<InvitationFetchByIdResult?> fetchById(String id) async => null;

  @override
  Future<void> dispose() async {}
}

/// The connection path behind the context sheet never resolves: the sheet
/// stays on its loading state, which is enough to see it opened.
final class _PendingContextRepository
    implements ForwardCandidateContextRepositoryPort {
  @override
  Future<CandidateConnectionContext> load({
    required String candidateId,
    required String context,
  }) => Completer<CandidateConnectionContext>().future;
}

/// A bud-invite picker cubit with no network; counts inbound-source fetches
/// (the attribution dialog's data) and forwards.
class _BudInviteCubit extends ForwardCubit {
  _BudInviteCubit(ForwardState initial)
    : super(
        beaconId: '',
        debugSkipInitialLoad: true,
        debugInitialState: initial,
        targetProfile: ForwardTargetProfile.postBudInvite,
        budPostId: 'Ppost1',
        embedded: true,
        effects: FakeUiEffectPort(),
        clock: () => DateTime.utc(2026, 11, 16, 12),
      );

  int inboundSourceFetches = 0;
  int forwardCalls = 0;

  @override
  Future<List<ForwardInboundSource>> fetchInboundSources() async {
    inboundSourceFetches++;
    return [
      ForwardInboundSource(
        edgeId: 'E1',
        senderId: 'S1',
        senderName: 'Sender One',
        createdAt: DateTime.utc(2026),
        isSuggestedSource: true,
      ),
      ForwardInboundSource(
        edgeId: 'E2',
        senderId: 'S2',
        senderName: 'Sender Two',
        createdAt: DateTime.utc(2026),
        isSuggestedSource: false,
      ),
    ];
  }

  @override
  Future<bool> forward({List<String>? attributionParentEdgeIds}) async {
    forwardCalls++;
    return true;
  }
}

Profile _person(String id, String name) => Profile(
  id: id,
  displayName: name,
  score: 5,
  rScore: 1,
  sharesActiveContext: true,
);

final _anna = _person('Uanna', 'Anna');
final _boris = _person('Uboris', 'Boris');
final _clara = _person('Uclara', 'Clara');
final _viktor = _person('Uviktor', 'Viktor');

/// Anna and Boris are warm Post members; Clara came in through Viktor.
List<ForwardCandidate> _threeMembers() => [
  ForwardCandidate(
    profile: _anna,
    reach: const ForwardReach(kind: ForwardReachKind.direct),
  ),
  ForwardCandidate(
    profile: _boris,
    reach: const ForwardReach(kind: ForwardReachKind.direct),
  ),
  ForwardCandidate(
    profile: _clara,
    reach: ForwardReach(
      kind: ForwardReachKind.viaConnection,
      via: [_viktor],
      viaCount: 1,
    ),
  ),
];

/// Bud-invite state as the cubit would hold it. Reasons, and with
/// [withForwardOnlyData] a band and lineage suggestions, are Forward-only
/// data this profile must never surface.
ForwardState _budInviteState({
  List<ForwardCandidate>? candidates,
  Set<String> selectedIds = const {},
  bool withForwardOnlyData = false,
}) {
  final list = candidates ?? _threeMembers();
  return ForwardState(
    targetProfile: ForwardTargetProfile.postBudInvite,
    candidates: list,
    selectedIds: selectedIds,
    band: withForwardOnlyData && list.isNotEmpty
        ? [ForwardBandRow(userId: list.first.id)]
        : const [],
    lineageSuggestions: withForwardOnlyData && list.isNotEmpty
        ? [
            ForwardCandidate(
              profile: list.last.profile,
              lineageReasonCode: 'prior_forward',
            ),
          ]
        : const [],
    recipientReasons: list.isEmpty
        ? const {}
        : {
            list.first.id: const ['knows_topic'],
          },
    candidatesLoad: list.isEmpty
        ? const ForwardCandidatesEmpty()
        : const ForwardCandidatesReady(),
  );
}

const _noteHint = 'Note for the invite';

/// Pumps the picker the way the bud invite step embeds it: no beacon id, no
/// send action of its own, a host header above the search field.
///
/// [beaconId], [isLive] and [onSendPressed] let a test hand the picker every
/// input that would switch on the invite bar and the send composer in the
/// Forward profiles, to prove this profile alone keeps them off.
Future<_BudInviteCubit> _pump(
  WidgetTester tester, {
  ForwardState? state,
  Locale locale = const Locale('en'),
  Widget? header,
  String beaconId = '',
  bool isLive = false,
  VoidCallback? onSendPressed,
}) async {
  tester.view
    ..physicalSize = const Size(1200, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final cubit = _BudInviteCubit(state ?? _budInviteState());
  addTearDown(cubit.close);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
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
            beaconId: beaconId,
            embedded: true,
            isLive: isLive,
            onSendPressed: onSendPressed,
            sendEnabled: onSendPressed != null,
            copyProfile: ForwardTargetProfile.postBudInvite,
            recipientNoteHint: _noteHint,
            header: header,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}

/// The embedded picker's pinned recipient search field.
final _en = lookupL10n(const Locale('en'));

/// The picker's recipient search field, found by its localized hint.
Finder _searchField() => find.descendant(
  of: find.byType(ForwardRecipientPicker),
  matching: find.byWidgetPredicate(
    (w) =>
        w is TextField &&
        w.decoration?.hintText == _en.forwardOverlaySearchHint,
  ),
);

/// The forward candidate context sheet, found by its localized heading.
Finder _contextSheet() => find.text(_en.forwardCandidateConnectionHeading);

Finder _rowOf(String id) => find.byWidgetPredicate(
  (w) => w is ForwardRecipientRow && w.candidate.id == id,
);

Finder _row(String id) => find.byKey(TestIds.key(TestIds.forwardRecipient(id)));

Future<void> _tapRow(WidgetTester tester, String id) async {
  await tester.ensureVisible(_row(id));
  await tester.tap(_row(id));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    GetIt.I
      ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
      ..registerSingleton<InvitationRepository>(_FakeInvitationRepository())
      ..registerSingleton<LoadForwardCandidateContextCase>(
        LoadForwardCandidateContextCase(
          _PendingContextRepository(),
        ),
      );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  group('Inviting Post members to a budded Request', () {
    testWidgets(
      'lists the members with names, reach line and search, and none of the '
      'Forward-only chrome',
      (tester) async {
        await _pump(tester);

        expect(find.text('Anna'), findsOneWidget);
        expect(find.text('Boris'), findsOneWidget);
        expect(find.text('Clara'), findsOneWidget);
        expect(find.textContaining('Viktor'), findsOneWidget);
        expect(_searchField(), findsOneWidget);

        expect(
          find.byType(ForwardInviteBar, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byType(ForwardBandStrip, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byType(LineageForwardSectionHeader, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byType(ForwardTagPicker, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byType(ForwardScopeLinks, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byType(ForwardBottomComposer, skipOffstage: false),
          findsNothing,
        );
      },
    );

    testWidgets(
      'keeps the invite-new-person bar and the send composer off even when '
      'the host passes a live beacon id and a send action',
      (tester) async {
        await _pump(
          tester,
          beaconId: 'Bbud1',
          isLive: true,
          onSendPressed: () {},
        );

        expect(find.text('Anna'), findsOneWidget);
        expect(
          find.byType(ForwardInviteBar, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byType(ForwardBottomComposer, skipOffstage: false),
          findsNothing,
        );
      },
    );

    testWidgets('band and lineage data never surface as their sections', (
      tester,
    ) async {
      await _pump(tester, state: _budInviteState(withForwardOnlyData: true));

      expect(find.byType(ForwardBandStrip, skipOffstage: false), findsNothing);
      expect(
        find.byType(LineageForwardSectionHeader, skipOffstage: false),
        findsNothing,
      );
      expect(find.byType(ForwardRecipientRow), findsNWidgets(3));
      for (final name in ['Anna', 'Boris', 'Clara']) {
        expect(find.text(name), findsOneWidget);
      }
    });

    testWidgets('a ticked row offers no forward-reason editing', (
      tester,
    ) async {
      await _pump(tester);
      await _tapRow(tester, _anna.id);

      expect(
        find.byWidgetPredicate(
          (w) => w is ForwardRecipientRow && w.onEditReasons != null,
        ),
        findsNothing,
      );
    });

    testWidgets('ticking people never asks for attribution', (tester) async {
      final cubit = await _pump(tester);
      await _tapRow(tester, _anna.id);
      await _tapRow(tester, _boris.id);

      expect(cubit.inboundSourceFetches, 0);
      expect(cubit.forwardCalls, 0);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Sender One'), findsNothing);
    });

    testWidgets('rows multi-select and untick one at a time', (tester) async {
      final cubit = await _pump(tester);

      await _tapRow(tester, _anna.id);
      await _tapRow(tester, _clara.id);
      expect(cubit.state.selectedIds, {_anna.id, _clara.id});

      await _tapRow(tester, _anna.id);
      expect(cubit.state.selectedIds, {_clara.id});
    });

    testWidgets('search narrows the list to matching members', (
      tester,
    ) async {
      await _pump(tester);

      await tester.enterText(_searchField(), 'Ann');
      await tester.pumpAndSettle();

      expect(find.text('Anna'), findsOneWidget);
      expect(find.text('Boris'), findsNothing);
      expect(find.text('Clara'), findsNothing);
      expect(find.byType(ForwardTagPicker, skipOffstage: false), findsNothing);
    });

    testWidgets('a search matching no one shows the no-match copy', (
      tester,
    ) async {
      await _pump(tester);

      await tester.enterText(_searchField(), 'Zzzz');
      await tester.pumpAndSettle();

      expect(find.text(_en.forwardSearchNoMatches), findsOneWidget);
      expect(find.text('No one else in this post to invite'), findsNothing);
      expect(find.byType(ForwardScopeLinks, skipOffstage: false), findsNothing);
    });

    testWidgets('a ticked person gets a note with the host hint', (
      tester,
    ) async {
      final cubit = await _pump(tester);
      await _tapRow(tester, _anna.id);

      await tester.tap(
        find.byTooltip(_en.forwardAddPersonalNoteForName('Anna')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PerRecipientNoteInput), findsOneWidget);
      final note = find.widgetWithText(TextField, _noteHint);
      expect(note, findsOneWidget);

      await tester.enterText(note, 'see you');
      await tester.pump();
      expect(cubit.state.perRecipientNotes[_anna.id], 'see you');
      expect(
        find.byType(ForwardBottomComposer, skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets('only the member brought in by a person names them', (
      tester,
    ) async {
      await _pump(tester);

      expect(
        find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is ForwardRecipientRow && w.candidate.id == _clara.id,
          ),
          matching: find.textContaining('Viktor'),
        ),
        findsOneWidget,
      );
      for (final id in [_anna.id, _boris.id]) {
        expect(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) => w is ForwardRecipientRow && w.candidate.id == id,
            ),
            matching: find.textContaining('Viktor'),
          ),
          findsNothing,
        );
      }
      expect(find.byType(ForwardScopeLinks, skipOffstage: false), findsNothing);
    });

    testWidgets('the details button opens the person context sheet', (
      tester,
    ) async {
      await _pump(tester);

      final details = find.byKey(
        TestIds.key(TestIds.forwardRecipientDetails(_boris.id)),
      );
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(_contextSheet(), findsOneWidget);
      expect(find.byType(ForwardTagPicker, skipOffstage: false), findsNothing);
    });

    testWidgets('a secondary click on a row opens the person context sheet', (
      tester,
    ) async {
      final cubit = await _pump(tester);

      await tester.ensureVisible(_row(_clara.id));
      await tester.tap(_row(_clara.id), buttons: kSecondaryMouseButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(_contextSheet(), findsOneWidget);
      expect(cubit.state.selectedIds, isEmpty);
      expect(find.byType(ForwardTagPicker, skipOffstage: false), findsNothing);
    });

    testWidgets('the host header sits above the search field', (
      tester,
    ) async {
      await _pump(tester, header: const Text('Bud header'));

      final header = find.text('Bud header');
      expect(header, findsOneWidget);
      expect(
        tester.getTopLeft(header).dy,
        lessThan(tester.getTopLeft(_searchField()).dy),
      );
      expect(find.byType(ForwardTagPicker, skipOffstage: false), findsNothing);
    });

    for (final (locale, invite, connections) in [
      (
        const Locale('en'),
        'No one else in this post to invite',
        'No one to send to yet',
      ),
      (
        const Locale('ru'),
        'В посте больше некого позвать',
        'Пока некому отправить',
      ),
    ]) {
      testWidgets(
        'with no one left to invite speaks of the post (${locale.languageCode})',
        (tester) async {
          await _pump(
            tester,
            locale: locale,
            state: _budInviteState(candidates: const []),
          );

          expect(find.text(invite), findsOneWidget);
          expect(find.text(connections), findsNothing);
        },
      );
    }
  });

  // Guard: the Request and Post pickers keep their Forward chrome and copy.
  for (final profile in [
    ForwardTargetProfile.request,
    ForwardTargetProfile.post,
  ]) {
    group('The ${profile.name} picker beside the invite profile', () {
      Future<void> pumpForward(
        WidgetTester tester, {
        required List<ForwardCandidate> candidates,
      }) async {
        tester.view
          ..physicalSize = const Size(1200, 2400)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final cubit = ForwardCubit(
          beaconId: 'B1',
          debugSkipInitialLoad: true,
          embedded: true,
          targetProfile: profile,
          effects: FakeUiEffectPort(),
          debugInitialState: ForwardState(
            beaconId: 'B1',
            targetProfile: profile,
            candidates: candidates,
            candidatesLoad: candidates.isEmpty
                ? const ForwardCandidatesEmpty()
                : const ForwardCandidatesReady(),
          ),
        );
        addTearDown(cubit.close);
        await tester.pumpWidget(
          MaterialApp(
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
                  beaconId: 'B1',
                  embedded: true,
                  isLive: true,
                  onSendPressed: () {},
                  sendEnabled: true,
                  copyProfile: profile,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      testWidgets('an empty list keeps the connections copy', (tester) async {
        await pumpForward(tester, candidates: const []);

        expect(find.text('No one to send to yet'), findsOneWidget);
        expect(find.text('No one else in this post to invite'), findsNothing);
      });

      testWidgets(
        'rows keep the reach line, and reason editing only on a Request',
        (tester) async {
          await pumpForward(tester, candidates: _threeMembers());

          expect(
            find.descendant(
              of: _rowOf(_clara.id),
              matching: find.textContaining('Viktor'),
            ),
            findsOneWidget,
          );
          expect(
            find.byWidgetPredicate(
              (w) => w is ForwardRecipientRow && w.onEditReasons != null,
            ),
            profile == ForwardTargetProfile.request
                ? findsNWidgets(3)
                : findsNothing,
          );
        },
      );

      testWidgets('keeps invite bar, tag picker, scope links and composer', (
        tester,
      ) async {
        await pumpForward(tester, candidates: _threeMembers());

        expect(
          find.byType(ForwardInviteBar, skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.byType(ForwardTagPicker, skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.byType(ForwardScopeLinks, skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.byType(ForwardBottomComposer, skipOffstage: false),
          findsOneWidget,
        );
      });
    });
  }
}
