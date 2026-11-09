import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/inbox/data/repository/inbox_repository.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_room_card_hints.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/widget/inbox_watchlist_row.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';

const _beaconId = 'B1109post00001';
const _userId = 'Uviewer000001';
const _at = '2026-11-09T12:00:00.000Z';

const _qaMarkupExcerpt =
    'QA-FX 1109 <b>bold</b> and <script>alert(1)</script> test';

const _qaStrippedExcerpt = 'QA-FX 1109 bold and alert(1) test';

class _FakeProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'viewer', displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

Map<String, dynamic> _beaconWire() => {
  '__typename': 'beacon',
  'id': _beaconId,
  'cover_source': 0,
  'title': '',
  'description': '',
  'needs': '',
  'created_at': _at,
  'updated_at': _at,
  'status': 0,
  'tags': '',
  'beacon_images': <dynamic>[],
  'author': {
    '__typename': 'user',
    'id': 'Ualice0000001',
    'display_name': 'Alex QA',
    'description': '',
  },
  'help_offers_aggregate': {
    '__typename': 'beacon_help_offer_aggregate',
    'aggregate': null,
  },
  'active_help_offers': <dynamic>[],
  'participant_help_offers': <dynamic>[],
  'unanswered_help_offers': {
    '__typename': 'beacon_help_offer_aggregate',
    'aggregate': null,
  },
  'admitted_helpers_aggregate': {
    '__typename': 'beacon_admitted_helper_aggregate',
    'aggregate': null,
  },
  'is_discoverable': false,
  'kind': 1,
  'forward_policy': 1,
  'last_activity_at': _at,
  'post_root_message_id': 'Mroot00000001',
  'viewer_can_forward': true,
  'can_read_content': true,
  'can_read_involvement': true,
  'can_read_admitted_helpers': true,
  'my_forward_edges': <dynamic>[],
};

void _expectNoLiteralMarkupOnScreen(WidgetTester tester) {
  expect(find.textContaining('bold'), findsWidgets);
  expect(find.textContaining('alert(1)'), findsWidgets);
  expect(find.textContaining('<b>'), findsNothing);
  expect(find.textContaining('<script>'), findsNothing);
}

Future<void> _pumpWatchlistRow(
  WidgetTester tester, {
  required Locale locale,
}) async {
  final at = DateTime.parse(_at);
  await tester.pumpWidget(
    BlocProvider<ProfileCubit>.value(
      value: _FakeProfileCubit(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: locale,
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: kPhoneSurface),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: InboxWatchlistRow(
                item: InboxItem(
                  beaconId: _beaconId,
                  latestForwardAt: at,
                  status: InboxItemStatus.watching,
                  roomHints: const InboxRoomCardHints(
                    isRoomMember: true,
                    roomUnreadCount: 0,
                    postRootExcerpt: _qaMarkupExcerpt,
                  ),
                  beacon: Beacon(
                    id: _beaconId,
                    kind: BeaconKind.post,
                    author: const Profile(
                      id: 'ualice',
                      displayName: 'Alex QA',
                    ),
                    createdAt: at,
                    updatedAt: at,
                  ),
                ),
                onOpenBeacon: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'InboxRoomContextBatch maps postRootExcerpt verbatim through the repository',
    () async {
      await withRemoteWire(
        {
          'InboxFetch': {
            '__typename': 'query_root',
            'inbox_item': [
              {
                '__typename': 'inbox_item',
                'beacon_id': _beaconId,
                'context': '',
                'forward_count': 0,
                'latest_forward_at': _at,
                'latest_note_preview': '',
                'status': 0,
                'private_note': '',
                'rejection_message': '',
                'before_response_terminal_at': null,
                'tombstone_dismissed_at': null,
                'inbox_provenance_data': null,
                'beacon': _beaconWire(),
              },
            ],
          },
          'InboxRoomContextBatch': {
            '__typename': 'query_root',
            'InboxRoomContextBatch': [
              {
                '__typename': 'v2_InboxRoomContextRow',
                'beaconId': _beaconId,
                'postRootExcerpt': _qaMarkupExcerpt,
                'isRoomMember': true,
                'roomUnreadCount': 0,
              },
            ],
          },
        },
        <WireSent>[],
        (remote) async {
          final repo = InboxRepository(
            remote,
            BeaconRoomHintsRepository(remote),
          );
          final item = (await repo.fetch(userId: _userId)).single;
          expect(item.roomHints?.postRootExcerpt, _qaMarkupExcerpt);
        },
      );
    },
  );

  group('#1109 Activity watchlist Post preview', () {
    testWidgets('RU 375×667 shows stripped excerpt, not literal tags', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await _pumpWatchlistRow(tester, locale: const Locale('ru'));

      final l10n = await L10n.delegate.load(const Locale('ru'));
      expect(
        find.text(l10n.postRowSharedBy('Alex QA')),
        findsOneWidget,
      );
      expect(find.text(_qaStrippedExcerpt), findsOneWidget);
      expect(find.text(_qaMarkupExcerpt), findsNothing);
      _expectNoLiteralMarkupOnScreen(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('EN 375×667 shows stripped excerpt, not literal tags', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await _pumpWatchlistRow(tester, locale: const Locale('en'));

      final l10n = await L10n.delegate.load(const Locale('en'));
      expect(
        find.text(l10n.postRowSharedBy('Alex QA')),
        findsOneWidget,
      );
      expect(find.text(_qaStrippedExcerpt), findsOneWidget);
      _expectNoLiteralMarkupOnScreen(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
