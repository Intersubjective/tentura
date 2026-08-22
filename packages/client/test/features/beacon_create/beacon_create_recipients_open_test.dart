import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/widget/recipients_tab.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

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
  Future<InvitationEntity> create({
    required String addresseeName,
    String? beaconId,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteById(String id) async {}

  @override
  Future<void> dispose() async {}
}

/// Mirrors [BeaconCreateScreen]'s draft-load guard and
/// [_BeaconCreateScreenState._buildRecipientsTab] blocked-tab branch.
class _RecipientsTabGateProbe extends StatelessWidget {
  const _RecipientsTabGateProbe({required this.widgetDraftId});

  final String widgetDraftId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BeaconCreateCubit, BeaconCreateState>(
      builder: (context, state) {
        if ((widgetDraftId.isNotEmpty && state.draftId == null) &&
            state.isLoading) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }

        if (state.isEditMode) {
          return const Text('edit-mode');
        }

        final draftId = state.draftId;
        if (draftId == null || draftId.isEmpty) {
          if (state.publishBlocker != null) {
            return const BeaconRecipientsBlockedTab();
          }
          return const Center(child: CircularProgressIndicator.adaptive());
        }

        return const Text('recipients-ready');
      },
    );
  }
}

Beacon _validDraftBeacon() => Beacon.empty.copyWith(
  id: 'draft-1',
  status: BeaconStatus.draft,
  title: 'My draft title',
  description: 'Valid description for recipients tab.',
);

Future<void> _pumpGateProbe(
  WidgetTester tester, {
  required BeaconCreateCubit createCubit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: BlocProvider<BeaconCreateCubit>.value(
        value: createCubit,
        child: const _RecipientsTabGateProbe(widgetDraftId: 'draft-1'),
      ),
    ),
  );
}

void main() {
  const blockedTitle = 'Complete required fields';

  setUp(() {
    if (!GetIt.I.isRegistered<UiEffectPort>()) {
      GetIt.I.registerSingleton<UiEffectPort>(FakeUiEffectPort());
    }
    if (!GetIt.I.isRegistered<InvitationRepository>()) {
      GetIt.I.registerSingleton<InvitationRepository>(
        _FakeInvitationRepository(),
      );
    }
  });

  tearDown(() async {
    if (GetIt.I.isRegistered<InvitationRepository>()) {
      await GetIt.I.unregister<InvitationRepository>();
    }
    if (GetIt.I.isRegistered<UiEffectPort>()) {
      await GetIt.I.unregister<UiEffectPort>();
    }
  });

  testWidgets(
    'My Work Send guard never shows blocked tab while draft fetch is in flight',
    (tester) async {
      final release = Completer<void>();
      final write = DelayedFakeBeaconWritePort(
        release: release,
        beacon: _validDraftBeacon(),
      );
      final createCubit = BeaconCreateCubit(
        beaconCreateCase: fakeBeaconCreateCase(write: write),
        draftBeaconIdToLoad: 'draft-1',
        effects: FakeUiEffectPort(),
      );
      addTearDown(createCubit.close);

      await _pumpGateProbe(tester, createCubit: createCubit);
      await tester.pump();

      expect(find.text(blockedTitle), findsNothing);
      expect(find.byType(BeaconRecipientsBlockedTab), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      release.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(blockedTitle), findsNothing);
      expect(find.byType(BeaconRecipientsBlockedTab), findsNothing);
      expect(find.text('recipients-ready'), findsOneWidget);
    },
  );

  testWidgets(
    'draft with title never reaches blocked tab after async fetch resolves',
    (tester) async {
      final write = FakeBeaconWritePort(beacon: _validDraftBeacon());
      final createCubit = BeaconCreateCubit(
        beaconCreateCase: fakeBeaconCreateCase(write: write),
        draftBeaconIdToLoad: 'draft-1',
        effects: FakeUiEffectPort(),
      );
      addTearDown(createCubit.close);

      await _pumpGateProbe(tester, createCubit: createCubit);
      await tester.pump();
      expect(find.text(blockedTitle), findsNothing);
      expect(find.byType(BeaconRecipientsBlockedTab), findsNothing);

      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(blockedTitle), findsNothing);
      expect(find.byType(BeaconRecipientsBlockedTab), findsNothing);
      expect(find.text('recipients-ready'), findsOneWidget);
      expect(createCubit.state.draftId, 'draft-1');
      expect(createCubit.state.publishBlocker, isNull);
    },
  );

  testWidgets(
    'makeLive keeps the recipients picker, not the edit stub',
    (tester) async {
      final write = FakeBeaconWritePort(beacon: _validDraftBeacon());
      final createCubit = BeaconCreateCubit(
        beaconCreateCase: fakeBeaconCreateCase(write: write),
        draftBeaconIdToLoad: 'draft-1',
        effects: FakeUiEffectPort(),
      );
      addTearDown(createCubit.close);

      await _pumpGateProbe(tester, createCubit: createCubit);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await createCubit.makeLive(context: '');
      await tester.pump();

      expect(createCubit.state.isLive, isTrue);
      expect(createCubit.state.isEditMode, isFalse);
      expect(find.text('edit-mode'), findsNothing);
      expect(find.text('recipients-ready'), findsOneWidget);
    },
  );

  testWidgets(
    'new draft without required fields shows blocked tab before draft exists',
    (tester) async {
      final createCubit = BeaconCreateCubit(
        beaconCreateCase: fakeBeaconCreateCase(),
        effects: FakeUiEffectPort(),
      );
      addTearDown(createCubit.close);

      await _pumpGateProbe(tester, createCubit: createCubit);
      await tester.pump();

      expect(createCubit.state.draftId, isNull);
      expect(createCubit.state.publishBlocker, BeaconPublishBlocker.title);
      expect(find.text(blockedTitle), findsWidgets);
      expect(find.byType(BeaconRecipientsBlockedTab), findsOneWidget);
    },
  );
}
