import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/request_access_reason_banner.dart';
import 'package:tentura/features/inbox/data/repository/posts_repository.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

/// #724 real path: PostSummary wire data maps through PostsRepository and
/// BeaconViewCase into cubit state and the access banner.
void main() {
  const myProfile = Profile(id: 'Udave', displayName: 'Dave');
  const requestId = 'Bea026c489fab';
  const postId = 'B797e767f5da1';
  const excerpt = 'GQ1024: planning a weekend';

  const postReference = BeaconParentReference(
    state: BeaconParentReferenceState.available,
    beaconId: postId,
    title: '',
    isPost: true,
  );

  final postBeacon = Beacon(
    id: postId,
    kind: BeaconKind.post,
    createdAt: DateTime.utc(2026, 10, 24),
    updatedAt: DateTime.utc(2026, 10, 24),
    author: const Profile(id: 'Ualice', displayName: 'Alice'),
  );

  Beacon request({int accessReasons = 32 | 64}) => Beacon(
    id: requestId,
    title: 'GQ1024 Garden cleanup Saturday',
    createdAt: DateTime.utc(2026, 10, 24, 1),
    updatedAt: DateTime.utc(2026, 10, 24, 1),
    accessLevel: BeaconAccessLevel.observer,
    accessReasons: accessReasons,
    author: const Profile(id: 'Ualice', displayName: 'Alice'),
  );

  Map<String, dynamic> postSummaryRow({String rootExcerpt = excerpt}) => {
    '__typename': 'v2_PostSummary',
    'id': postId,
    'authorId': 'Ualice',
    'authorName': 'Alice',
    'authorAvatar': '',
    'rootImageUrl': null,
    'rootExcerpt': rootExcerpt,
    'lastMessageExcerpt': null,
    'lastMessageIsRoot': true,
    'lastMessageAt': null,
    'lastActivityAt': '2026-10-24T12:00:00.000Z',
    'pinnedAt': null,
    'mutedUntil': null,
    'mutedForever': false,
    'unreadCount': 0,
    'isAuthor': false,
    'status': 0,
    'expiresAt': null,
  };

  test('wire PostSummary maps through cubit to banner copy', () async {
    final sent = <WireSent>[];
    await withRemoteWire(
      {
        'PostSummary': {
          '__typename': 'query_root',
          'postSummary': postSummaryRow(),
        },
      },
      sent,
      (remote) async {
        final beaconRepo = TrackingBeaconRepository()
          ..fetchByIdHandler = (id) async {
            if (id == postId) return postBeacon;
            return request();
          };
        addTearDown(beaconRepo.dispose);

        final cubit = BeaconViewCubit(
          id: requestId,
          myProfile: myProfile,
          beaconViewCase: buildTestBeaconViewCase(
            beaconRepo: beaconRepo,
            hierarchyRepository: FakeBeaconHierarchyRepositoryPort(
              parentReference: postReference,
            ),
            postsRepository: PostsRepository(remote),
          ),
          effects: FakeUiEffectPort(),
        );
        addTearDown(cubit.close);

        await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);
        await pumpUntilCondition(
          () => cubit.state.accessParentPostExcerpt == excerpt,
        );

        expect(cubit.state.accessParent?.id, postId);
        expect(cubit.state.accessParent?.title, isEmpty);
        expect(sent.single.operationName, 'PostSummary');
        expect(sent.single.variables['id'], postId);

        final l10n = lookupL10n(const Locale('en'));
        expect(
          l10n.requestAccessViaParentPost(cubit.state.accessParentPostExcerpt),
          "You can see this request because you're in the post "
          '«$excerpt» it grew from.',
        );
      },
    );
  });

  test('empty PostSummary keeps untitled excerpt in cubit state', () async {
    await withRemoteWire(
      {
        'PostSummary': {
          '__typename': 'query_root',
          'postSummary': postSummaryRow(rootExcerpt: ''),
        },
      },
      <WireSent>[],
      (remote) async {
        final beaconRepo = TrackingBeaconRepository()
          ..fetchByIdHandler = (id) async {
            if (id == postId) return postBeacon;
            return request();
          };
        addTearDown(beaconRepo.dispose);

        final cubit = BeaconViewCubit(
          id: requestId,
          myProfile: myProfile,
          beaconViewCase: buildTestBeaconViewCase(
            beaconRepo: beaconRepo,
            hierarchyRepository: FakeBeaconHierarchyRepositoryPort(
              parentReference: postReference,
            ),
            postsRepository: PostsRepository(remote),
          ),
          effects: FakeUiEffectPort(),
        );
        addTearDown(cubit.close);

        await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);
        await pumpUntilCondition(() => cubit.state.accessParent != null);

        expect(cubit.state.accessParentPostExcerpt, isEmpty);
      },
    );
  });

  testWidgets('RU phone surface shows named post on the banner', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: RequestAccessReasonBanner(
              beacon: request(),
              parent: postBeacon,
              parentPostExcerpt: excerpt,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Вы видите этот запрос, потому что участвуете в посте '
        '«$excerpt», из которого он вырос.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('RU phone surface shows untitled copy when excerpt is empty', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: RequestAccessReasonBanner(
              beacon: request(),
              parent: postBeacon,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Вы видите этот запрос, потому что участвуете в посте, '
        'из которого он вырос.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
