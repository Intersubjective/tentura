import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/beacon_create/ui/dialog/beacon_send_confirmation_dialog.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';
import 'package:tentura_root/domain/entity/beacon_child_command_outcome.dart';
import 'package:tentura/features/beacon/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_child_request_card.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_now_surface.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../support/test_realtime_sync.dart';
import '../../support/people_tags_widget_harness.dart';
import 'child_request_send_widget_support.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_view/beacon_view_screen_harness.dart';
import 'fake_beacon_ports.dart';

const _parentId = 'parent-request';
const _childId = 'child-request';
const _title = 'Borrow a truck ramp';
const _contexts = <String, BeaconCreationContext>{
  'child': BeaconCreationContextChild(parentBeaconId: _parentId),
  'message-promoted child': BeaconCreationContextPromotedChild(
    parentBeaconId: _parentId,
    sourceMessageId: 'room-message',
  ),
};

/// Delivery is a separate dependency: acknowledge the selected recipient so
/// these tests exercise publication without a forwarding backend.
class _DeliveredForwardCubit extends ForwardCubit {
  _DeliveredForwardCubit()
    : super(
        beaconId: _childId,
        embedded: true,
        debugSkipInitialLoad: true,
        debugInitialState: const ForwardState(
          beaconId: _childId,
          selectedIds: {'recipient'},
        ),
        effects: FakeUiEffectPort(),
      );

  @override
  Future<bool> forward({List<String>? attributionParentEdgeIds}) async {
    emit(
      state.copyWith(
        lastDeliveryOutcome: const ForwardDeliveryOutcome(
          requestedRecipientIds: ['recipient'],
          deliveredRecipientIds: ['recipient'],
          availabilitySkippedRecipientIds: [],
        ),
      ),
    );
    return true;
  }
}

/// The backend exposes the child in the hierarchy as soon as publish succeeds.
/// It deliberately sends no realtime hint.
class _PublishingWritePort extends FakeBeaconWritePort {
  _PublishingWritePort(this.hierarchy)
    : super(
        beacon: Beacon.empty.copyWith(
          id: _childId,
          title: _title,
          description: 'For moving equipment upstairs.',
          status: BeaconStatus.draft,
        ),
      );

  final FakeBeaconHierarchyRepositoryPort hierarchy;

  @override
  Future<void> publishDraft(String id) async {
    await super.publishDraft(id);
    hierarchy.childrenByGroup[BeaconHierarchyChildGroup.active] =
        BeaconHierarchyPage(
          summaries: [
            BeaconHierarchySummary(
              beaconId: id,
              title: _title,
              status: BeaconStatus.open,
              publishedAt: DateTime.utc(2026, 10, 28),
              isTombstone: false,
              owner: const BeaconHierarchyOwnerSummary(
                id: 'bob',
                displayName: 'Bob',
              ),
            ),
          ],
        );
  }
}

/// Records the public use-case boundary while executing its real behavior.
class _RecordingCreateCase extends BeaconCreateCase {
  _RecordingCreateCase(FakeBeaconWritePort write)
    : super(write, FakeBeaconImagePort());

  final plainPublications = <String>[];

  @override
  Future<void> publishDraft(String id) {
    plainPublications.add(id);
    return super.publishDraft(id);
  }
}

class _RecordingHierarchyCase extends BeaconHierarchyCase {
  _RecordingHierarchyCase(
    super._hierarchy,
    super._createCase,
    super._beacons,
    super._commandStore,
    super._realtimeSyncCase, {
    this.notificationGate,
  });

  final publications = <({String beaconId, BeaconChildSaveCommand command})>[];

  /// Holds delivery to the mounted parent, leaving the genuine event source
  /// intact. The widget test can prove the parent stays stale before delivery.
  final Completer<void>? notificationGate;
  int heldParentNotifications = 0;

  @override
  Stream<void> localHierarchyChangesFor(String beaconId) {
    final source = super.localHierarchyChangesFor(beaconId);
    final gate = notificationGate;
    if (gate == null || beaconId != _parentId) return source;
    return source.asyncMap<void>((_) async {
      heldParentNotifications++;
      await gate.future;
    });
  }

  @override
  Future<void> publishChildDraft({
    required String beaconId,
    required BeaconChildSaveCommand command,
    required List<ImageEntity> images,
    required String? coverKey,
    required ImageEntity? coverThumb,
  }) {
    publications.add((beaconId: beaconId, command: command));
    return super.publishChildDraft(
      beaconId: beaconId,
      command: command,
      images: images,
      coverKey: coverKey,
      coverThumb: coverThumb,
    );
  }
}

class _SendHarness {
  _SendHarness({this.notificationGate});

  final Completer<void>? notificationGate;
  final port = FakeBeaconHierarchyRepositoryPort(childrenByGroup: {})
    ..createOutcomeOverride = const BeaconChildCreateOutcome(
      outcome: BeaconChildCommandOutcome.created,
      beaconId: _childId,
    );
  final store = InMemoryBeaconChildCommandStore();
  final realtime = buildTestRealtimeSync();
  late final write = _PublishingWritePort(port);
  late final createCase = _RecordingCreateCase(write);
  late final hierarchy = _RecordingHierarchyCase(
    port,
    createCase,
    write,
    store,
    realtime.case_,
    notificationGate: notificationGate,
  );

  Future<BeaconCreateCubit> open(
    BeaconCreationContext context, {
    bool restored = false,
  }) async {
    final cubit = BeaconCreateCubit(
      beaconCreateCase: createCase,
      hierarchyCase: hierarchy,
      childCreationContext: context,
      draftBeaconIdToLoad: restored ? _childId : null,
      postBuddingEnabled: false,
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    await cubit.stream.firstWhere(
      (s) => restored ? s.draftId == _childId : s.clientCommandId != null,
    );
    cubit
      ..setTitle(_title)
      ..setDescription('For moving equipment upstairs.');
    return cubit;
  }

  Future<void> send(BeaconCreateCubit cubit) async {
    final forward = _DeliveredForwardCubit();
    try {
      final outcome = await cubit.sendRequest(
        context: '',
        forwardCubit: forward,
      );
      expect(outcome?.deliveredRecipientIds, ['recipient']);
      expect(cubit.state.isLive, isTrue);
      expect(cubit.state.draftId, isNotEmpty);
      expect(write.publishedIds, [cubit.state.draftId]);
    } finally {
      await forward.close();
    }
  }
}

void main() {
  group('Sending a child Request', () {
    for (final entry in _contexts.entries) {
      test(
        'publishes a ${entry.key} through the child hierarchy use case',
        () async {
          final harness = _SendHarness();
          addTearDown(harness.realtime.port.dispose);
          final cubit = await harness.open(entry.value);

          await harness.send(cubit);

          expect(
            harness.hierarchy.publications,
            hasLength(1),
            reason: 'Child-mode Send must call publishChildDraft.',
          );
          final publication = harness.hierarchy.publications.single;
          expect(publication.beaconId, cubit.state.draftId);
          expect(publication.command.creationContext, entry.value);
          expect(
            harness.createCase.plainPublications,
            isEmpty,
            reason: 'Child-mode Send must not use standalone publishDraft.',
          );
        },
      );

      test(
        '${entry.key} publication notifies the parent exactly once',
        () async {
          final harness = _SendHarness();
          addTearDown(harness.realtime.port.dispose);
          final cubit = await harness.open(entry.value);
          var parentChanges = 0;
          final subscription = harness.hierarchy
              .localHierarchyChangesFor(_parentId)
              .listen((_) => parentChanges++);
          addTearDown(subscription.cancel);

          await harness.send(cubit);
          await pumpEventQueue();

          expect(
            parentChanges,
            1,
            reason:
                'Send must publish through the hierarchy use case even when '
                'no realtime hint arrives.',
          );
          expect(await harness.store.read(entry.value), isNull);
        },
      );

      test(
        'sending a restored ${entry.key} clears its stored command identity',
        () async {
          final harness = _SendHarness();
          addTearDown(harness.realtime.port.dispose);
          // A canonical draft can be reopened while a durable command identity
          // remains from an interrupted composer session.
          await harness.store.write(entry.value, 'interrupted-command');
          const unrelated = BeaconCreationContextChild(parentBeaconId: 'other');
          await harness.store.write(unrelated, 'keep-other-command');
          final cubit = await harness.open(entry.value, restored: true);
          expect(await harness.store.read(entry.value), 'interrupted-command');

          await harness.send(cubit);

          expect(await harness.store.read(unrelated), 'keep-other-command');
          expect(
            await harness.store.read(entry.value),
            isNull,
            reason:
                'Successful child publication must retire the command '
                'identity for that creation context.',
          );
        },
      );
    }
  });

  testWidgets('returning after Send shows the child and sub-request count '
      'on the mounted parent without a realtime hint', (tester) async {
    final notificationGate = Completer<void>();
    final harness = _SendHarness(notificationGate: notificationGate);
    addTearDown(harness.realtime.port.dispose);
    final composer = await harness.open(_contexts['message-promoted child']!);
    final parent = BeaconHierarchyCubit(
      beaconId: _parentId,
      hierarchyCase: harness.hierarchy,
    );
    addTearDown(parent.close);
    // Release before parent.close even if an assertion fails, allowing the
    // paused stream subscription to cancel cleanly.
    addTearDown(() {
      if (!notificationGate.isCompleted) notificationGate.complete();
    });
    await parent.load();
    final contextCubit = await registerChildSendCollaborators();
    addTearDown(contextCubit.close);
    final parentState = beaconViewHarnessAuthorState(beaconId: _parentId);
    final childBase = beaconViewHarnessAuthorState(beaconId: _childId);
    final childState = childBase.copyWith(
      beacon: childBase.beacon.copyWith(
        title: _title,
        lineageParentBeaconId: _parentId,
      ),
    );
    final router = RootStackRouter.build(
      routes: [
        AutoRoute(
          page: PageInfo(
            'ParentRequest',
            builder: (_) => buildBeaconViewHarnessWidget(
              beaconState: parentState,
              threadsState: beaconViewHarnessThreadsState(),
              hierarchyCubit: parent,
            ),
          ),
          initial: true,
        ),
        AutoRoute(
          page: PageInfo(
            BeaconCreateRoute.name,
            builder: (_) => MultiBlocProvider(
              providers: [
                BlocProvider<BeaconCreateCubit>.value(value: composer),
                BlocProvider.value(value: contextCubit),
                BlocProvider<ProfileCubit>.value(
                  value: GetIt.I<ProfileCubit>(),
                ),
              ],
              child: const BeaconCreateScreen(
                initialTab: kBeaconCreateTabRecipients,
                forwardToUserId: 'recipient',
                parentBeaconId: _parentId,
                sourceMessageId: 'room-message',
              ),
            ),
          ),
        ),
        AutoRoute(
          page: PageInfo(
            BeaconViewRoute.name,
            builder: (_) => buildBeaconViewHarnessWidget(
              beaconState: childState,
              threadsState: beaconViewHarnessThreadsState(),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpPeopleTagsWidget(
      MaterialApp.router(
        routerConfig: router.config(),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    final mountedParent = tester.state(find.byType(BeaconNowSurface));
    final l10n = L10n.of(tester.element(find.byType(BeaconNowSurface)))!;
    expect(find.text(l10n.beaconChildRequestsTitle), findsOneWidget);
    expect(find.byType(BeaconChildRequestCard), findsNothing);
    expect(find.text('1 sub-request'), findsNothing);

    unawaited(
      router.push(
        BeaconCreateRoute(
          parentBeaconId: _parentId,
          sourceMessageId: 'room-message',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BeaconCreateScreen), findsOneWidget);
    await tester.tap(find.byKey(TestIds.key(TestIds.forwardSubmit)));
    await tester.pumpAndSettle();
    expect(harness.write.publishedIds, [composer.state.draftId]);
    expect(find.byType(BeaconSendConfirmationDialog), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(BeaconSendConfirmationDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();
    // The real Send handler must remove the composer and open the live child.
    expect(find.byType(BeaconCreateScreen, skipOffstage: false), findsNothing);
    expect(router.current.name, BeaconViewRoute.name);
    expect(
      router.current.argsAs<BeaconViewRouteArgs>().id,
      composer.state.draftId,
    );
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(router.current.name, 'ParentRequest');
    expect(tester.state(find.byType(BeaconNowSurface)), same(mountedParent));

    // Publication changed only the backend snapshot. Neither returning to the
    // page nor a second refresh mechanism may make the card visible before
    // the genuine local hierarchy event reaches the mounted parent.
    expect(find.byType(BeaconChildRequestCard), findsNothing);
    expect(find.text('1 sub-request'), findsNothing);
    expect(parent.state.active.items, isEmpty);
    expect(
      harness.hierarchy.heldParentNotifications,
      1,
      reason:
          'Send must emit exactly one local event for the parent; '
          'the test never emits a realtime hint or a synthetic local event.',
    );
    notificationGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text(l10n.beaconChildRequestsTitle), findsOneWidget);
    expect(find.byType(BeaconChildRequestCard), findsOneWidget);
    expect(find.text(_title), findsOneWidget);
    expect(find.text('1 sub-request'), findsOneWidget);
  });
}
