// #758: a helper who withdrew or was removed has no live offer, so the
// closed Request hid the result card. The server already answers for them
// (`closureResultForViewer`: band none, notDone, unjudgedLeaver). The card
// shows for any non-author who offered help, and the server's line is the
// copy. Someone who never offered still sees no card.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_operational_header_card.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/closure/domain/entity/closure_band.dart';
import 'package:tentura/features/closure/domain/entity/closure_draft_flag.dart';
import 'package:tentura/features/closure/domain/entity/closure_member.dart';
import 'package:tentura/features/closure/domain/entity/closure_outcome.dart';
import 'package:tentura/features/closure/domain/entity/closure_result.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/features/closure/domain/use_case/closure_case.dart';
import 'package:tentura/features/closure/ui/widget/closure_result_card.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';

const _author = Profile(id: 'uAuthor', displayName: 'Alice');
const _helper = Profile(id: 'uHelper', displayName: 'Dave');
const _stranger = Profile(id: 'uStranger', displayName: 'Eve');

final _t = DateTime.utc(2026, 10, 25);

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this.profile);

  final Profile profile;

  @override
  ProfileState get state => ProfileState(profile: profile);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

final class _LeaverRepository implements ClosureRepository {
  @override
  Future<ClosureResult?> fetchResultForViewer(String beaconId) async =>
      const ClosureResult(
        outcome: ClosureOutcome.notDone,
        band: ClosureBand.none,
        draftFlag: ClosureDraftFlag.none,
        unjudgedLeaver: true,
      );

  @override
  Future<ClosureState> fetchState(String beaconId) async => ClosureState(
    epoch: 1,
    status: 1,
    role: ClosureRole.member,
    members: const [
      ClosureMember(id: 'uHelper', displayName: 'Dave'),
      ClosureMember(id: 'uBob', displayName: 'Bob'),
    ],
    closesAt: DateTime.utc(2026, 10, 25, 12),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Beacon _closed() => Beacon(
  id: 'Bclosed00001',
  title: 'Closed request',
  author: _author,
  createdAt: _t,
  updatedAt: _t,
  status: BeaconStatus.closed,
);

TimelineHelpOffer _offer({
  required Profile user,
  bool withdrawn = false,
  HelpOfferAdmissionAction? admission,
}) => TimelineHelpOffer(
  user: user,
  message: 'I can help',
  createdAt: _t,
  updatedAt: _t,
  isWithdrawn: withdrawn,
  admissionAction: admission,
);

BeaconViewState _view({
  required Profile viewer,
  List<TimelineHelpOffer> offers = const [],
  bool liveOffer = false,
}) => BeaconViewState(
  beacon: _closed(),
  myProfile: viewer,
  beaconContextLoaded: true,
  isHelpOffered: liveOffer,
  helpOffers: offers,
);

Future<void> _pump(
  WidgetTester tester, {
  required BeaconViewState state,
  required ClosureRepository repository,
  Locale locale = const Locale('en'),
  bool phone = false,
}) async {
  if (phone) await usePhoneSurface(tester);
  GetIt.I.registerSingleton<ClosureCase>(
    ClosureCase(repository, env: const Env(), logger: Logger('test')),
  );
  addTearDown(() async {
    if (GetIt.I.isRegistered<ClosureCase>()) {
      await GetIt.I.unregister<ClosureCase>();
    }
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      home: BlocProvider<ProfileCubit>.value(
        value: _MockProfileCubit(state.myProfile),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: SingleChildScrollView(
              child: BeaconOperationalHeaderCard(
                state: state,
                onAuthorTap: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectWholeLine(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  expect(paragraph.text.toPlainText(), text);
  expect(paragraph.didExceedMaxLines, isFalse, reason: 'cut: $text');
  expect(tester.takeException(), isNull);
}

void main() {
  final leaverLine = lookupL10n(
    const Locale('en'),
  ).closureResultLeftNoShare;
  final leaverLineRu = lookupL10n(
    const Locale('ru'),
  ).closureResultLeftNoShare;

  testWidgets(
    'a helper who withdrew sees the server no-share line',
    (tester) async {
      await _pump(
        tester,
        repository: _LeaverRepository(),
        state: _view(
          viewer: _helper,
          offers: [_offer(user: _helper, withdrawn: true)],
        ),
      );

      expect(find.byType(ClosureResultCard), findsOneWidget);
      expect(find.text(leaverLine), findsOneWidget);
    },
  );

  testWidgets(
    'a helper the author removed sees the server no-share line',
    (tester) async {
      await _pump(
        tester,
        repository: _LeaverRepository(),
        state: _view(
          viewer: _helper,
          offers: [
            _offer(
              user: _helper,
              admission: HelpOfferAdmissionAction.remove,
            ),
          ],
        ),
      );

      expect(find.byType(ClosureResultCard), findsOneWidget);
      expect(find.text(leaverLine), findsOneWidget);
    },
  );

  testWidgets('a helper still in the request still sees the result card', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _LeaverRepository(),
      state: _view(
        viewer: _helper,
        liveOffer: true,
        offers: [_offer(user: _helper)],
      ),
    );

    expect(find.text(leaverLine), findsOneWidget);
  });

  testWidgets('a viewer who never offered sees no result card', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _LeaverRepository(),
      state: _view(viewer: _stranger),
    );

    expect(find.byType(ClosureResultCard), findsNothing);
    expect(find.text(leaverLine), findsNothing);
  });

  testWidgets(
    'the no-share line renders in full at 375×667 in Russian',
    (tester) async {
      await _pump(
        tester,
        phone: true,
        locale: const Locale('ru'),
        repository: _LeaverRepository(),
        state: _view(
          viewer: _helper,
          offers: [_offer(user: _helper, withdrawn: true)],
        ),
      );

      _expectWholeLine(tester, leaverLineRu);
    },
  );

  testWidgets(
    'the leaver line comes from a real closureResultForViewer response',
    (tester) async {
      final sent = <WireSent>[];
      await withRemoteWire(
        {
          'ClosureResultForViewer': {
            '__typename': 'query_root',
            'closureResultForViewer': {
              '__typename': 'ClosureResult',
              'outcome': 'notDone',
              'band': 'none',
              'draftFlag': 'none',
              'marks': <String>[],
              'story': null,
              'unjudgedLeaver': true,
            },
          },
          'ClosureState': {
            '__typename': 'query_root',
            'closureState': {
              '__typename': 'ClosureState',
              'epoch': 1,
              'status': 1,
              'role': 'member',
              'members': [
                {
                  '__typename': 'ClosureMember',
                  'id': _helper.id,
                  'displayName': 'Dave',
                  'avatarId': null,
                  'helpTypes': null,
                  'offerText': null,
                  'notInRequest': true,
                  'departure': 'voluntary',
                },
                {
                  '__typename': 'ClosureMember',
                  'id': 'uBob',
                  'displayName': 'Bob',
                  'avatarId': null,
                  'helpTypes': null,
                  'offerText': null,
                  'notInRequest': false,
                  'departure': null,
                },
              ],
              'outcomes': null,
              'split': null,
              'mySupport': <String>[],
              'inCalcText': null,
              'myMarks': <String>[],
              'closesAt': '2026-10-25T12:00:00.000Z',
              'earlyCloseAt': null,
              'canCloseNow': false,
              'canReopen': false,
              'extensionsUsed': 0,
              'story': null,
            },
          },
        },
        sent,
        (RemoteApiService remote) async {
          await _pump(
            tester,
            repository: ClosureRepository(remote),
            state: _view(
              viewer: _helper,
              offers: [_offer(user: _helper, withdrawn: true)],
            ),
          );
          expect(find.text(leaverLine), findsOneWidget);
          expect(
            sent.map((call) => call.operationName),
            contains('ClosureResultForViewer'),
          );
          expect(
            sent
                .firstWhere(
                  (call) => call.operationName == 'ClosureResultForViewer',
                )
                .variables['beaconId'],
            'Bclosed00001',
          );
        },
      );
    },
  );
}
