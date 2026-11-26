@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';

import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/screen/forward_beacon_screen.dart';
import 'package:tentura/features/my_work/data/repository/my_work_repository.dart';
import 'package:tentura/features/phantoms/data/repository/phantom_repository.dart';
import 'package:tentura/features/phantoms/domain/entity/phantom.dart';
import 'package:tentura/features/phantoms/domain/port/phantom_repository_port.dart';
import 'package:tentura/features/phantoms/ui/widget/phantom_context_panel.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/constellation_field_wire_fixture.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../my_work/my_work_test_support.dart';

const _owner = Profile(id: 'Uviewer000001', displayName: 'Owner');
const _contact = Profile(id: 'U000000000099', displayName: 'Clara');
const _placeholderId = 'PH000000000011';
const _name = 'Vasya';
const _foreignName = 'Masha';
const _foreignId = 'PH000000000099';
const _requestId = 'B000000000042';
const _title = 'Fix the bike';
const _note = 'can you help?';
const _link = '/invite/I000000000011?r=$_requestId';
const _shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
const _recordField = 'beaconForwardToPhantom';
final _now = DateTime.utc(2026, 11, 26);

void main() {
  for (final locale in const [Locale('en'), Locale('ru')]) {
    final language = locale.languageCode;
    testWidgets(
      'the $language forward sheet offers only my placeholders and preserves my note in the forward',
      (tester) async {
        await _withInviteSurface(tester, locale, (wire, platform) async {
          expect(
            find.byKey(TestIds.key(TestIds.forwardInviteNewPerson)),
            findsOneWidget,
          );
          await _tapLocalizedAction(
            tester,
            locale,
            english: RegExp(r'^Pick from my placeholders$'),
            russian: RegExp(
              r'^Выб\p{L}*.*(?:мо\p{L}*|сво\p{L}*)',
              unicode: true,
            ),
          );
          expect(find.text(_name).hitTestable(), findsOneWidget);
          expect(
            find.text(_foreignName),
            findsNothing,
            reason: 'The response also contains a placeholder owned by Clara',
          );
          expect(find.text(_contact.displayName).hitTestable(), findsNothing);
          expect(wire, isEmpty);

          await _tap(tester, find.text(_name).hitTestable());
          expect(wire, [
            {
              'phantomId': _placeholderId,
              'beaconId': _requestId,
              'note': _note,
            },
          ]);
          await platform.checkActions(tester, locale);
          expect(wire, hasLength(1));
        });
      },
    );

    testWidgets(
      'the $language person panel attaches a chosen Request and offers its invite link',
      (tester) async {
        await _withInviteSurface(tester, locale, (wire, platform) async {
          expect(find.text(_name), findsOneWidget);
          await _tapLocalizedAction(
            tester,
            locale,
            english: RegExp(r'^Attach a request$', caseSensitive: false),
            russian: RegExp(r'^(?:Прикрепить|Добавить|Привязать) запрос$'),
          );
          expect(wire, isEmpty, reason: 'Opening the chooser sends no forward');
          await _tap(tester, find.text(_title).hitTestable());
          expect(wire, hasLength(1));
          expect(wire.single, containsPair('phantomId', _placeholderId));
          expect(wire.single, containsPair('beaconId', _requestId));
          await platform.checkActions(tester, locale);
          expect(wire, hasLength(1));
        }, panel: true);
      },
    );
  }
}

Future<void> _tapLocalizedAction(
  WidgetTester tester,
  Locale locale, {
  required RegExp english,
  required RegExp russian,
}) async => _tap(
  tester,
  _localizedAction(tester, locale, english: english, russian: russian),
);

Finder _localizedAction(
  WidgetTester tester,
  Locale locale, {
  required RegExp english,
  required RegExp russian,
}) {
  final action = find
      .textContaining(
        locale.languageCode == 'ru' ? russian : english,
        findRichText: true,
      )
      .hitTestable();
  expect(action, findsOneWidget);
  final label = switch (tester.widget(action)) {
    Text(:final data, :final textSpan) => data ?? textSpan!.toPlainText(),
    RichText(:final text) => text.toPlainText(),
    final widget => throw StateError('Unexpected label widget: $widget'),
  };
  final en = _readArb('en');
  final ru = _readArb('ru');
  final local = locale.languageCode == 'ru' ? ru : en;
  final keys = local.keys.where((key) => local[key] == label);
  final forbidden = RegExp('phantom|фантом|beacon|маяк', caseSensitive: false);
  expect(
    keys.any((key) {
      final enText = en[key];
      final ruText = ru[key];
      return enText is String &&
          ruText is String &&
          english.hasMatch(enText) &&
          russian.hasMatch(ruText) &&
          !forbidden.hasMatch(enText) &&
          !forbidden.hasMatch(ruText);
    }),
    isTrue,
    reason: 'Both ARB catalogs provide the rendered action «$label»',
  );
  return action;
}

Map<String, Object?> _readArb(String language) =>
    (jsonDecode(File('l10n/app_$language.arb').readAsStringSync()) as Map)
        .cast<String, Object?>();

Future<void> _tap(WidgetTester tester, Finder control) async {
  expect(control, findsOneWidget);
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 3),
  );
  expect(tester.takeException(), isNull);
}

Future<void> _withInviteSurface(
  WidgetTester tester,
  Locale locale,
  Future<void> Function(List<Map<String, Object?>> writes, _PlatformLinks links)
  check, {
  bool panel = false,
}) async {
  if (locale.languageCode == 'ru') await usePhoneSurface(tester);
  final links = _PlatformLinks(tester);
  final effects = FakeUiEffectPort();
  final person = Phantom(
    id: _placeholderId,
    displayName: _name,
    hasPrivateAvatar: false,
    ownTagIds: const [],
    inviteState: PhantomInviteState.live,
    inviteCreatedAt: _now,
    createdAt: _now,
  );
  final request = Beacon.empty.copyWith(
    id: _requestId,
    title: _title,
    author: _owner,
    viewerCanForward: true,
    startAt: _now.subtract(const Duration(days: 1)),
    endAt: _now.add(const Duration(days: 7)),
  );

  final cubit = ForwardCubit(
    beaconId: _requestId,
    debugSkipInitialLoad: true,
    clock: () => _now,
    effects: effects,
    debugInitialState: ForwardState(
      beaconId: _requestId,
      beacon: request,
      note: _note,
      candidates: const [ForwardCandidate(profile: _contact)],
      candidatesLoad: const ForwardCandidatesReady(),
    ),
  );
  final profile = _Profile();
  final sent = <WireSent>[];
  final writes = <Map<String, Object?>>[];

  await withRemoteWire(
    const {},
    sent,
    (remote) async {
      final field = ConstellationRepository(remote);
      if (!panel) {
        // Validate the existing read before the picker attempts to use it.
        // The owner assertion concerns the displayed candidates, so either
        // the repository mapper or the picker may enforce the filter.
        final snapshot = await field.fetch();
        expect(
          snapshot.phantoms.map((person) => person.id),
          contains(_placeholderId),
        );
      }
      GetIt.I.pushNewScope(
        init: (scope) {
          scope
            ..registerSingleton<UiEffectPort>(effects)
            ..registerSingleton<RemoteApiService>(remote)
            ..registerSingleton<RemoteRequestClient>(remote)
            ..registerSingleton<PhantomRepositoryPort>(
              PhantomRepository(remote),
            )
            ..registerSingleton<ConstellationRepositoryPort>(field)
            ..registerSingleton<MyWorkRepository>(
              FakeMyWorkRepository()
                ..initResult = (
                  authoredNonArchived: [request],
                  helpOfferedNonArchived: const [],
                  obligationBeacons: const [],
                  archivedCountHint: 0,
                ),
            );
        },
      );
      try {
        await tester.pumpPeopleTagsWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            theme: TenturaTheme.light(),
            home: TenturaResponsiveScope(
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<ProfileCubit>.value(value: profile),
                  BlocProvider<ForwardCubit>.value(value: cubit),
                ],
                child: panel
                    ? Scaffold(
                        body: PhantomContextPanel(
                          person: person,
                          tags: const [],
                          nowUtc: _now,
                          linkCandidates: () => const [],
                          onChanged: () async {},
                          onClose: () {},
                        ),
                      )
                    : const ForwardBeaconPage(beaconId: _requestId),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await check(writes, links);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await GetIt.I.popScope();
        await profile.close();
        await cubit.close();
      }
    },
    responseFor: (request) async =>
        request.operationName == 'ConstellationFieldFetch'
        ? _fieldResponse()
        : request.variables,
    selectResponse: (document, variables) {
      if (variables.containsKey('constellationField')) return variables;
      final operation = parseString(
        document,
      ).definitions.whereType<OperationDefinitionNode>().single;
      final field = operation.selectionSet.selections
          .whereType<FieldNode>()
          .singleWhere((field) => field.name.value == _recordField);
      writes.add({
        for (final argument in field.arguments)
          argument.name.value: switch (argument.value) {
            VariableNode(:final name) => variables[name.value],
            StringValueNode(:final value) => value,
            NullValueNode() => null,
            final node => throw StateError(
              'Unexpected forward argument: $node',
            ),
          },
      });
      return {
        '__typename': 'mutation_root',
        field.alias?.value ?? field.name.value: _link,
      };
    },
  );
}

Map<String, dynamic> _fieldResponse() {
  final response = constellationFieldWire(
    now: _now,
    viewerId: _owner.id,
    contacts: {_contact.id: _contact.displayName},
    phantoms: [
      {
        ...constellationPhantomWire(
          _placeholderId,
          _name,
          now: _now,
          inviteDaysAgo: 0,
        ),
        'ownerId': _owner.id,
      },
      {
        ...constellationPhantomWire(_foreignId, _foreignName, now: _now),
        'ownerId': _contact.id,
      },
    ],
  );
  final field = response['constellationField'] as Map<String, dynamic>;
  field['requests'] = [
    {
      '__typename': 'v2_ConstellationRequest',
      'id': _requestId,
      'authorId': _owner.id,
      'title': _title,
      'status': 0,
      'coverSource': 0,
      'hasCoordinates': false,
      'hasUnread': false,
      'helpOfferCount': 0,
      'isMine': true,
      'needs': <String>[],
      'viewerHasActiveHelpOffer': false,
      'viewerHasForwardEdge': false,
      'viewerIsRoomParticipant': false,
    },
  ];
  return response;
}

class _Profile extends Cubit<ProfileState> implements ProfileCubit {
  _Profile() : super(const ProfileState(profile: _owner));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PlatformLinks {
  _PlatformLinks(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text']);
        }
        return null;
      })
      ..setMockMethodCallHandler(_shareChannel, (call) async {
        expect(call.method, 'share');
        final arguments = call.arguments as Map;
        shared.add(arguments['uri'] ?? arguments['text']);
        return 'dev.fluttercommunity.plus/share/success';
      });
    addTearDown(() {
      messenger
        ..setMockMethodCallHandler(SystemChannels.platform, null)
        ..setMockMethodCallHandler(_shareChannel, null);
    });
  }

  final copied = <Object?>[];
  final shared = <Object?>[];

  Future<void> checkActions(WidgetTester tester, Locale locale) async {
    expect(copied, isEmpty, reason: 'The link is copied on demand');
    expect(shared, isEmpty, reason: 'The share sheet opens on demand');
    final share = _localizedAction(
      tester,
      locale,
      english: RegExp(r'^Share(?: link|…)?$'),
      russian: RegExp(r'^Поделиться(?: ссылкой|…)?$'),
    );
    final copy = _localizedAction(
      tester,
      locale,
      english: RegExp(r'^Copy(?: link| invite link| to clipboard)?$'),
      russian: RegExp(r'^Скопировать(?: ссылку(?:-приглашение)?| в буфер)?$'),
    );
    await _tap(tester, share);
    expect(shared, [_link]);
    await _tap(tester, copy);
    expect(copied, [_link]);
  }
}
