// #380: after «Extend final check» the new end date was only in a toast.
// The status sheet and the Overview kept showing no date, nothing said how
// many extensions were left, and the Log stayed silent.
//
// Spec:
// - the status sheet shows the final check end date (refreshed after an
//   extension) and an «extensions used X of 2» hint (or «no extensions left»
//   at the limit, with Extend gone);
// - the Overview (pinned HUD block) shows the end date while the Request is
//   in its final check, for the author and for a helper;
// - the Log labels the server lifecycle event with reason `closureExtended`
//   (diff carries `closesAt`) as «Final check extended to <date>».

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_pinned_block.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_status_bottom_sheet.dart';
import 'package:tentura/features/closure/domain/entity/beacon_close_result.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_activity_event_presenter.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

const _beaconId = 'B380extend';
const _author = Profile(id: 'U380author', displayName: 'Author');
const _helper = Profile(id: 'U380helper', displayName: 'Helper');

/// Server wire value of the new lifecycle reason (both consts files).
const _closureExtendedReason = 'closureExtended';

/// Local times, as the server's UTC ISO strings come back after toLocal().
final _firstEnd = DateTime(2026, 10, 20, 14);
final _extendedEnd = DateTime(2026, 10, 27, 14);

/// Matches [local]'s calendar day in any reasonable [locale] format: the day
/// number next to the month name or its abbreviation, in either order
/// («Oct 27», «October 27», «27 окт.», «27 октября», with or without a year
/// or time), or a numeric day/month («27.10», «10/27»).
RegExp _day(DateTime local, String locale) {
  final stem = RegExp.escape(
    DateFormat.MMM(
      locale,
    ).format(local).replaceAll('.', '').substring(0, 3).toLowerCase(),
  );
  final d = '${local.day}';
  final m = '${local.month}'.padLeft(2, '0');
  const tail = r'[^\s\d,]*';
  return RegExp(
    '(?<!\\d)$d\\D{0,3}$stem$tail'
    '|$stem$tail\\s*$d(?!\\d)'
    '|(?<!\\d)$d[./]$m(?!\\d)'
    '|(?<!\\d)$m/$d(?!\\d)',
    caseSensitive: false,
  );
}

ClosureState _closure({
  required DateTime closesAt,
  int extensionsUsed = 0,
  ClosureRole role = ClosureRole.author,
}) => ClosureState(
  epoch: 1,
  status: 0,
  role: role,
  members: const [],
  closesAt: closesAt.toUtc(),
  extensionsUsed: extensionsUsed,
);

/// Closure backend: `fetchState` returns [current]; extending moves the end
/// by 7 days and counts the extension, like `ClosureRepository.extendEpoch`.
class _ClosureRepo extends FakeBeaconViewClosureRepository {
  _ClosureRepo(this.current);

  ClosureState current;

  @override
  Future<ClosureState> fetchState(String beaconId) async => current;

  @override
  Future<BeaconExtendReviewResult> beaconExtendReview(String beaconId) async {
    current = current.copyWith(
      closesAt: current.closesAt.add(const Duration(days: 7)),
      extensionsUsed: current.extensionsUsed + 1,
    );
    return BeaconExtendReviewResult(
      beaconId: beaconId,
      closesAt: current.closesAt.toIso8601String(),
    );
  }
}

BeaconActivityEvent _extendedEvent(DateTime closesAtLocal) =>
    BeaconActivityEvent(
      id: 'ev-extended',
      beaconId: _beaconId,
      visibility: BeaconActivityEventVisibilityBits.public,
      type: BeaconActivityEventTypeBits.beaconLifecycleChanged,
      createdAt: DateTime.utc(2026, 10, 18),
      actorId: _author.id,
      diffJson: jsonEncode({
        'fromStatus': BeaconStatus.reviewOpen.smallintValue,
        'toStatus': BeaconStatus.reviewOpen.smallintValue,
        'reason': _closureExtendedReason,
        'closesAt': closesAtLocal.toUtc().toIso8601String(),
      }),
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ru');
  });

  group('#380 Log: «Final check extended to <date>»', () {
    test('en label names the final check and the new end date', () {
      final l10n = lookupL10n(const Locale('en'));
      final label = beaconActivityEventLabel(
        l10n,
        _extendedEvent(_extendedEnd),
      );
      expect(label, startsWith('Final check extended to'));
      expect(label, contains(_day(_extendedEnd, 'en')));
      expect(label, isNot(contains(_day(_firstEnd, 'en'))));
      // Guard: not the unknown-reason fallback.
      expect(label, isNot(l10n.beaconLifecycleClosed));
    });

    test('ru label uses the «итоги» vocabulary and the new end date', () {
      final l10n = lookupL10n(const Locale('ru'));
      final label = beaconActivityEventLabel(
        l10n,
        _extendedEvent(_extendedEnd),
      );
      expect(label.toLowerCase(), contains('итог'));
      expect(label, contains(_day(_extendedEnd, 'ru')));
      expect(label, isNot(contains(_day(_firstEnd, 'ru'))));
      expect(label, isNot(l10n.beaconLifecycleClosed));
    });

    test('an extension is an author action, not a system line', () {
      final e = _extendedEvent(_extendedEnd);
      expect(beaconLifecycleEventIsSystem(e), isFalse);
      expect(beaconActivityLogTier(e), BeaconActivityLogTier.high);
    });
  });

  group('#380 status sheet shows the end date and extensions left', () {
    Future<BeaconViewCubit> loadCubit(
      WidgetTester tester,
      _ClosureRepo closure,
    ) async {
      final cubit = (await tester.runAsync(() async {
        final cubit = BeaconViewCubit(
          id: _beaconId,
          myProfile: _author,
          beaconViewCase: buildTestBeaconViewCase(
            beaconRepo: TrackingBeaconRepository()
              ..fetchByIdHandler = (_) async => Beacon(
                id: _beaconId,
                title: 'Final check beacon',
                createdAt: DateTime.utc(2026),
                updatedAt: DateTime.utc(2026),
                status: BeaconStatus.reviewOpen,
                author: _author,
              ),
            closureRepo: closure,
          ),
          effects: FakeUiEffectPort(),
        );
        await pumpUntil(cubit.stream, () => cubit.state.closureState != null);
        return cubit;
      }))!;
      addTearDown(cubit.close);
      return cubit;
    }

    Future<void> openSheet(WidgetTester tester, BeaconViewCubit cubit) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 1400)),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: Builder(
                  builder: (ctx) => TextButton(
                    onPressed: () => showBeaconViewUpdateStatusSheet(
                      ctx,
                      cubit.state,
                      cubit,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('after one extension: new end date and «1 of 2»', (
      tester,
    ) async {
      final closure = _ClosureRepo(_closure(closesAt: _firstEnd));
      final cubit = await loadCubit(tester, closure);

      await tester.runAsync(cubit.extendReview);
      expect(cubit.state.closureState?.extensionsUsed, 1);

      await openSheet(tester, cubit);
      final l10n = lookupL10n(const Locale('en'));
      expect(find.text(l10n.beaconStatusSheetTitle), findsOneWidget);

      expect(
        find.textContaining(_day(_extendedEnd, 'en')),
        findsWidgets,
        reason: 'the sheet shows the new final check end date',
      );
      expect(
        find.textContaining(_day(_firstEnd, 'en')),
        findsNothing,
        reason: 'not the end date from before the extension',
      );
      expect(
        find.textContaining(RegExp(r'\b1\s*(of|/)\s*2\b')),
        findsWidgets,
        reason: 'extensions used hint next to Extend',
      );
      // One extension left: Extend is still offered.
      expect(find.text(l10n.beaconReviewExtendAction), findsOneWidget);
    });

    testWidgets('at the limit: no Extend, says no extensions are left', (
      tester,
    ) async {
      final closure = _ClosureRepo(
        _closure(closesAt: _extendedEnd, extensionsUsed: 2),
      );
      final cubit = await loadCubit(tester, closure);

      await openSheet(tester, cubit);
      final l10n = lookupL10n(const Locale('en'));

      expect(find.text(l10n.beaconReviewExtendAction), findsNothing);
      expect(
        find.textContaining(
          RegExp(
            r'\b2\s*(of|/)\s*2\b|no (more )?extensions',
            caseSensitive: false,
          ),
        ),
        findsWidgets,
        reason: 'the sheet says why Extend is gone',
      );
      expect(find.textContaining(_day(_extendedEnd, 'en')), findsWidgets);
    });
  });

  group('#380 Overview shows the final check end date', () {
    Future<void> pumpBlock(WidgetTester tester, BeaconViewState state) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: TenturaResponsiveScope(
            child: Scaffold(
              body: BeaconHudPinnedBlock(
                state: state,
                now: DateTime(2026, 10, 18, 12),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    BeaconViewState reviewState({
      required Profile viewer,
      required ClosureState? closure,
      BeaconStatus status = BeaconStatus.reviewOpen,
    }) => BeaconViewState(
      beacon: Beacon.empty.copyWith(
        id: _beaconId,
        title: 'Final check beacon',
        status: status,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        author: _author,
        accessLevel: viewer.id == _author.id
            ? BeaconAccessLevel.author
            : BeaconAccessLevel.member,
        admittedHelperCount: 1,
      ),
      myProfile: viewer,
      closureState: closure,
    );

    testWidgets('author sees the (extended) end date', (tester) async {
      await pumpBlock(
        tester,
        reviewState(
          viewer: _author,
          closure: _closure(closesAt: _extendedEnd, extensionsUsed: 1),
        ),
      );
      expect(find.textContaining(_day(_extendedEnd, 'en')), findsWidgets);
    });

    testWidgets('a helper sees the end date too', (tester) async {
      await pumpBlock(
        tester,
        reviewState(
          viewer: _helper,
          closure: _closure(
            closesAt: _extendedEnd,
            extensionsUsed: 1,
            role: ClosureRole.voter,
          ),
        ),
      );
      expect(find.textContaining(_day(_extendedEnd, 'en')), findsWidgets);
      expect(
        find.textContaining(RegExp(r'(?<!\d)\d\s*(of|/)\s*2(?!\d)')),
        findsNothing,
        reason: 'the extensions counter is author-only',
      );
    });

    testWidgets('guard: no end date once the Request is no longer in review', (
      tester,
    ) async {
      await pumpBlock(
        tester,
        reviewState(
          viewer: _author,
          status: BeaconStatus.enoughHelp,
          closure: _closure(closesAt: _extendedEnd),
        ),
      );
      expect(find.textContaining(_day(_extendedEnd, 'en')), findsNothing);
    });
  });
}
