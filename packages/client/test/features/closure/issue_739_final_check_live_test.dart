// #739: a helper's open Final check page loaded once and ignored the
// Request. The same repository hint the Request page already listens to
// (`RepositoryEventInvalidate`) must reload this cubit. The page then
// returns to the Request, which is what the author's page already does
// when the epoch moves on.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/closure/domain/entity/closure_member.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/features/closure/domain/use_case/closure_case.dart';
import 'package:tentura/features/closure/ui/bloc/closure_author_cubit.dart';
import 'package:tentura/features/closure/ui/bloc/closure_helper_cubit.dart';
import 'package:tentura/features/closure/ui/screen/closure_review_page.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _beaconId = 'Bclosure739';

final class _LiveRepository implements ClosureRepository {
  _LiveRepository({this.role = ClosureRole.voter});

  final ClosureRole role;
  int status = 0;
  int fetches = 0;
  bool missing = false;

  @override
  Future<ClosureState> fetchState(String beaconId) async {
    fetches++;
    if (missing) throw Exception('Id not found: [$beaconId]');
    return ClosureState(
      epoch: 3,
      status: status,
      role: role,
      members: const [
        ClosureMember(id: 'bob', displayName: 'Bob'),
        ClosureMember(id: 'dave', displayName: 'Dave'),
      ],
      closesAt: DateTime.utc(2026, 10, 25, 18),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ClosureCase _case(_LiveRepository repo) =>
    ClosureCase(repo, env: const Env(), logger: Logger('test'));

void main() {
  test('a repository invalidation reloads the helper page cubit', () async {
    final repo = _LiveRepository();
    final events = StreamController<RepositoryEvent<Beacon>>.broadcast();
    addTearDown(events.close);
    final cubit = ClosureHelperCubit(
      _case(repo),
      beaconId: _beaconId,
      viewerId: 'bob',
      author: const ClosureMember(id: 'alice', displayName: 'Alice'),
      requestChanges: events.stream,
      readBeaconStatus: () async => BeaconStatus.closed,
    );
    addTearDown(cubit.close);
    await cubit.stream.firstWhere((s) => s.data != null);
    expect(repo.fetches, 1);
    expect(cubit.state.leftReview, isFalse);

    repo.status = 1;
    events.add(
      RepositoryEventInvalidate(Beacon.empty.copyWith(id: _beaconId)),
    );
    await cubit.stream.firstWhere((s) => s.leftReview);

    expect(repo.fetches, greaterThan(1));
    expect(cubit.state.data?.status, 1);
  });

  test(
    'a reopen hint ends the helper review when closure state is gone',
    () async {
      final repo = _LiveRepository();
      final events = StreamController<RepositoryEvent<Beacon>>.broadcast();
      addTearDown(events.close);
      final cubit = ClosureHelperCubit(
        _case(repo),
        beaconId: _beaconId,
        viewerId: 'bob',
        author: const ClosureMember(id: 'alice', displayName: 'Alice'),
        requestChanges: events.stream,
      );
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((s) => s.data != null);

      repo.missing = true;
      events.add(
        RepositoryEventUpdate(
          Beacon.empty.copyWith(id: _beaconId, status: BeaconStatus.open),
        ),
      );
      await cubit.stream.firstWhere((s) => s.leftReview);
      expect(cubit.state.data?.status, 0);
    },
  );

  testWidgets('the helper page returns to the Request when it closes', (
    tester,
  ) async {
    final repo = _LiveRepository();
    final events = StreamController<RepositoryEvent<Beacon>>.broadcast();
    addTearDown(events.close);
    final cubit = ClosureHelperCubit(
      _case(repo),
      beaconId: _beaconId,
      viewerId: 'bob',
      author: const ClosureMember(id: 'alice', displayName: 'Alice'),
      requestChanges: events.stream,
      readBeaconStatus: () async => BeaconStatus.closed,
    );
    addTearDown(cubit.close);
    await cubit.stream.firstWhere((s) => s.data != null);

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ClosureReviewPage(
                      beaconId: _beaconId,
                      role: ClosureRole.voter,
                      viewerId: 'bob',
                      author: const ClosureMember(
                        id: 'alice',
                        displayName: 'Alice',
                      ),
                      helperCubit: cubit,
                    ),
                  ),
                ),
                child: const Text('request'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('request'));
    await tester.pumpAndSettle();
    expect(find.text('request'), findsNothing);

    repo.status = 1;
    events.add(
      RepositoryEventInvalidate(Beacon.empty.copyWith(id: _beaconId)),
    );
    await tester.pumpAndSettle();

    expect(find.text('request'), findsOneWidget);
  });

  test(
    'a reopen hint ends the author review when closure state is gone',
    () async {
      final repo = _LiveRepository(role: ClosureRole.author);
      final events = StreamController<RepositoryEvent<Beacon>>.broadcast();
      addTearDown(events.close);
      final cubit = ClosureAuthorCubit(
        _case(repo),
        beaconId: _beaconId,
        requestChanges: events.stream,
      );
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((s) => s.data != null);

      repo.missing = true;
      events.add(
        RepositoryEventUpdate(
          Beacon.empty.copyWith(id: _beaconId, status: BeaconStatus.open),
        ),
      );
      await cubit.stream.firstWhere((s) => s.ended);
      expect(cubit.state.data?.status, 0);
    },
  );

  test('the author page cubit reloads from the same hint', () async {
    final repo = _LiveRepository(role: ClosureRole.author);
    final events = StreamController<RepositoryEvent<Beacon>>.broadcast();
    addTearDown(events.close);
    final cubit = ClosureAuthorCubit(
      _case(repo),
      beaconId: _beaconId,
      requestChanges: events.stream,
      readBeaconStatus: () async => BeaconStatus.closed,
    );
    addTearDown(cubit.close);
    await cubit.stream.firstWhere((s) => s.data != null);
    final before = repo.fetches;

    repo.status = 1;
    events.add(
      RepositoryEventInvalidate(Beacon.empty.copyWith(id: _beaconId)),
    );
    await cubit.stream.firstWhere((s) => s.data?.status == 1);

    expect(repo.fetches, greaterThan(before));
  });
}
