// tentura-id8.19 landing gate: issue #178 plan §P6 last row — two accounts,
// the author opens People and the pending offerer's own footer flips to
// "Seen by the author" without a reload.
//
// The two-browser journey itself needs the full local stack
// (`scripts/run_realtime_multiclient_web_local.sh` with
// REALTIME_MULTICLIENT_DRIVER=help_offer_author_seen_multiclient_web_test.dart)
// and cannot run under `flutter test`. This file pins what can be pinned
// offline: the observer People surface a pending offerer lands on renders
// their own offer footer and flips it in place, the runner accepts the
// driver, and the journal records the two-browser result.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_people_tab_body.dart';
import 'package:tentura/features/beacon_view/ui/widget/help_offer_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// Exact EN copy from l10n/app_en.arb (helpOfferAuthor*).
const _notSeen = 'Sent · not seen by the author yet';
const _seen = 'Seen by the author · awaiting decision';

const _driverName = 'help_offer_author_seen_multiclient_web_test.dart';
const _journalPath =
    'docs/plans/issue-178-help-offer-author-seen-implementation-journal.md';
const _reportsPath = 'reports/realtime-multiclient';
const _flipBudgetMs = 5000;

final _t = DateTime.utc(2025);
const _offerer = Profile(id: 'offerer', displayName: 'Offerer');
const _author = Profile(id: 'auth', displayName: 'Author');

class _FakePlatformRepository implements PlatformRepositoryPort {
  @override
  Future<String> getAppVersion() async => 'test';

  @override
  Future<String> getStringFromClipboard() async => '';

  @override
  Future<void> launchUri(Uri uri) async {}

  @override
  Future<void> launchUrl(String uri) async {}

  @override
  Future<void> launchUserLink(Uri uri) async {}
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _offerer);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _MockBeaconViewCubit extends Mock implements BeaconViewCubit {
  _MockBeaconViewCubit(this._state);

  final BeaconViewState _state;

  @override
  BeaconViewState get state => _state;

  @override
  Stream<BeaconViewState> get stream => Stream<BeaconViewState>.value(_state);
}

File _repoFile(String repoRelativePath) {
  for (final prefix in const ['../../', '']) {
    final candidate = File('$prefix$repoRelativePath');
    if (candidate.existsSync()) {
      return candidate.absolute;
    }
  }
  throw StateError('Repo file not found: $repoRelativePath');
}

/// Pending offerer A viewing the Request as an observer (not yet admitted).
BeaconViewState _offererState({DateTime? authorSeenAt}) => BeaconViewState(
  beacon: Beacon(
    id: 'B1',
    title: 'T',
    author: _author,
    createdAt: _t,
    updatedAt: _t,
    accessLevel: BeaconAccessLevel.observer,
  ),
  myProfile: _offerer,
  helpOffers: [
    TimelineHelpOffer(
      user: _offerer,
      message: 'I can help',
      createdAt: _t,
      updatedAt: _t,
      authorSeenAt: authorSeenAt,
    ),
  ],
);

Widget _people(BeaconViewState state) {
  final cubit = _MockBeaconViewCubit(state);
  return MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
        BlocProvider<BeaconViewCubit>.value(value: cubit),
      ],
      child: Scaffold(
        body: SingleChildScrollView(
          child: BeaconPeopleTabBody(
            state: state,
            beaconViewCubit: cubit,
            l10n: lookupL10n(const Locale('en')),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('help offer author seen e2e landing check (tentura-id8.19)', () {
    setUp(() async {
      await GetIt.I.reset();
      GetIt.I.registerSingleton<PlatformRepositoryPort>(
        _FakePlatformRepository(),
      );
    });

    tearDown(() async {
      await GetIt.I.reset();
    });

    testWidgets(
      'pending offerer (observer) sees own offer footer: not seen, Icons.done',
      (tester) async {
        await tester.pumpWidget(_people(_offererState()));
        await tester.pumpAndSettle();

        expect(find.byType(HelpOfferTile), findsOneWidget);
        expect(find.text(_notSeen), findsOneWidget);
        expect(find.byIcon(Icons.done), findsOneWidget);
        expect(find.text(_seen), findsNothing);
        expect(find.byIcon(Icons.done_all), findsNothing);
      },
    );

    testWidgets(
      'people_seen patch flips the mounted footer to Seen + Icons.done_all '
      'without remounting the tile',
      (tester) async {
        await tester.pumpWidget(_people(_offererState()));
        await tester.pumpAndSettle();
        expect(find.text(_notSeen), findsOneWidget);
        final tileElement = tester.element(find.byType(HelpOfferTile));

        await tester.pumpWidget(
          _people(_offererState(authorSeenAt: DateTime.utc(2025, 1, 2))),
        );
        await tester.pumpAndSettle();

        expect(find.text(_seen), findsOneWidget);
        expect(find.byIcon(Icons.done_all), findsOneWidget);
        expect(find.text(_notSeen), findsNothing);
        expect(find.byIcon(Icons.done), findsNothing);
        expect(
          tester.element(find.byType(HelpOfferTile)),
          same(tileElement),
          reason: 'the flip is an in-place rebuild, not a reload',
        );
      },
    );

    test('multiclient runner accepts the author-seen driver', () {
      final runner = _repoFile(
        'scripts/run_realtime_multiclient_web_local.sh',
      ).readAsStringSync();
      expect(runner, contains('"\$DRIVER" == $_driverName'));
      expect(
        _repoFile('packages/client/test_driver/$_driverName').existsSync(),
        isTrue,
      );
    });

    group('journal evaluator (manual route)', () {
      const passing =
          """
## Manual two-browser check

Account A (offerer) opened the Request's People tab and saw its own pending
offer with "$_notSeen".
Account B (author) then opened People; A flipped to "$_seen" after about
1.8 s, with no reload.
B's help_offer_submitted receipt in Activity was marked seen.
""";

      test('accepts a passing entry without a bead tag', () {
        expect(_manualJournalProblems(passing), isEmpty);
      });

      test('accepts "within 5 s" without a numeric measurement', () {
        expect(
          _manualJournalProblems(
            passing.replaceFirst('after about\n1.8 s', 'within 5 s'),
          ),
          isEmpty,
        );
      });

      test('accepts a later passing entry after an earlier failed attempt', () {
        const failedFirst =
            '''
## Attempt 1

Account A (offerer) opened People and saw its own pending offer with
"$_notSeen". Account B (author) opened People, but the footer never
flipped and the check timed out after 20 s.

''';
        expect(_manualJournalProblems(failedFirst + passing), isEmpty);
        expect(_manualJournalProblems(failedFirst), isNotEmpty);
      });

      test('rejects a timed-out flip', () {
        expect(
          _manualJournalProblems(
            passing.replaceFirst(
              'after about\n1.8 s',
              'only after the check timed out at 20 s',
            ),
          ),
          isNotEmpty,
        );
      });

      test('rejects a flip slower than 5 s', () {
        expect(
          _manualJournalProblems(
            passing.replaceFirst('about\n1.8 s', 'about 7 seconds'),
          ),
          isNotEmpty,
        );
      });

      test('rejects a flip that needed a reload', () {
        expect(
          _manualJournalProblems(
            passing.replaceFirst('with no reload', 'but only after a reload'),
          ),
          isNotEmpty,
        );
      });

      test('rejects an Activity receipt left unseen', () {
        expect(
          _manualJournalProblems(
            passing.replaceFirst('was marked seen', 'stayed unseen'),
          ),
          isNotEmpty,
        );
      });

      test('rejects a generic Activity "seen" not tied to the author', () {
        expect(
          _manualJournalProblems(
            passing.replaceFirst(
              "B's help_offer_submitted receipt in Activity was marked seen.",
              'Activity looked seen.',
            ),
          ),
          isNotEmpty,
        );
      });

      test('rejects an entry missing A viewing its own offer on People', () {
        expect(
          _manualJournalProblems(
            passing.replaceFirst(
              "Account A (offerer) opened the Request's People tab and saw "
                  'its own pending\noffer with',
              'The footer read',
            ),
          ),
          isNotEmpty,
        );
      });

      test('rejects an entry missing B opening People', () {
        expect(
          _manualJournalProblems(
            passing.replaceFirst('Account B (author) then opened People;', ''),
          ),
          isNotEmpty,
        );
      });

      test('rejects an entry missing a footer state', () {
        expect(
          _manualJournalProblems(
            passing.replaceFirst('with "$_notSeen"', 'with a footer'),
          ),
          isNotEmpty,
        );
      });
    });

    test('§P6 two-account result is recorded as passing '
        '(multiclient report or manual journal entry)', () {
      final reportProblems = _multiclientReportProblems();
      final journal = _optionalRepoFile(_journalPath);
      final journalProblems = journal == null
          ? ['$_journalPath does not exist']
          : _manualJournalProblems(journal.readAsStringSync());
      expect(
        reportProblems.isEmpty || journalProblems.isEmpty,
        isTrue,
        reason:
            'Neither acceptance route is satisfied.\n'
            'Route A (multiclient report under $_reportsPath):\n'
            '  ${reportProblems.join('\n  ')}\n'
            'Route B (manual journal entry in $_journalPath):\n'
            '  ${journalProblems.join('\n  ')}',
      );
    });
  });
}

File? _optionalRepoFile(String repoRelativePath) {
  for (final prefix in const ['../../', '']) {
    final candidate = File('$prefix$repoRelativePath');
    if (candidate.existsSync()) {
      return candidate.absolute;
    }
  }
  return null;
}

/// Route A: some local multiclient session ran this driver end to end.
/// Returns why no session qualifies (empty when one does).
List<String> _multiclientReportProblems() {
  final root = [
    for (final prefix in const ['../../', ''])
      Directory('$prefix$_reportsPath'),
  ].where((d) => d.existsSync()).firstOrNull;
  if (root == null) {
    return ['$_reportsPath does not exist'];
  }
  final problems = <String>[];
  for (final session in root.listSync().whereType<Directory>()) {
    final name = session.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final gates = File('${session.path}/release-gates.json');
    if (!gates.existsSync()) {
      continue;
    }
    final gatesJson = jsonDecode(gates.readAsStringSync()) as Map;
    if (gatesJson['realtime_multiclient_driver'] != _driverName) {
      continue;
    }
    final runs = session
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path.split('/').last.startsWith('run-'))
        .toList();
    if (runs.isEmpty) {
      problems.add('$name: no runs');
      continue;
    }
    if (runs.any((r) => File('${r.path}/failure.txt').existsSync())) {
      problems.add('$name: a run failed');
      continue;
    }
    final summary = File('${session.path}/timings-summary.json');
    if (!summary.existsSync()) {
      problems.add('$name: no timings-summary.json (runner did not finish)');
      continue;
    }
    final timings = jsonDecode(summary.readAsStringSync()) as Map;
    List<num> samples(String key) =>
        ((timings[key] as Map?)?['samples_ms'] as List?)?.cast<num>() ??
        const [];
    final flips = samples('a_footer_seen_ms');
    final receipts = samples('b_activity_offer_receipt_seen_ms');
    if (flips.length != runs.length || receipts.length != runs.length) {
      problems.add(
        '$name: a_footer_seen_ms / b_activity_offer_receipt_seen_ms not '
        'measured in every run',
      );
      continue;
    }
    if (flips.any((ms) => ms > _flipBudgetMs)) {
      problems.add('$name: footer flip exceeded $_flipBudgetMs ms ($flips)');
      continue;
    }
    return const [];
  }
  return problems.isEmpty
      ? ['no session under $_reportsPath ran $_driverName']
      : problems;
}

final _duration = RegExp(
  r'(\d+(?:\.\d+)?)\s*(ms|milliseconds?|s|secs?|seconds?)\b',
  caseSensitive: false,
);
final _liveWording = RegExp(
  r'\b(instant(ly)?|immediately|live|real-?time|without (any )?delay)\b',
  caseSensitive: false,
);
final _failureLanguage = RegExp(
  r"\b(timed out|time-?out|failed|fails|failure|did not flip|didn't flip|"
  'never flipped|not flip|(required|requires|needed|needs|after|on|with) '
  r'(a |the )?(page )?(reload|refresh))\b',
  caseSensitive: false,
);
final _noReload = RegExp(
  r'\b(no|without( a| any)?|never|did not|didn.t|zero) (page )?'
  r'(reloads?|refresh(es)?|re-?navigation)\b',
  caseSensitive: false,
);
final _flipWording = RegExp(
  r'\b(flip(ped|s)?|turn(ed|s)?|chang(ed|es)|switch(ed|es)?|updat(ed|es))\b',
  caseSensitive: false,
);
final _offererSubject = RegExp(r'\bA\b|\bofferer\b', caseSensitive: false);
final _authorSubject = RegExp(r'\bB\b|\bauthor\b');
final _peopleWord = RegExp(r'\bPeople\b');
final _ownOffer = RegExp(
  r'\b(own|pending|offer|footer)\b',
  caseSensitive: false,
);
final _opened = RegExp(r'\bopen(ed|s|ing)?\b', caseSensitive: false);
final _activityReceipt = RegExp(r'\bActivity\b|help_offer_submitted');
final _receiptNoun = RegExp(
  r'\b(receipt|entry|item|offer|help_offer_submitted)\b',
  caseSensitive: false,
);
final _receiptSeen = RegExp(
  r'\b(seen|seenAt|read)\b',
  caseSensitive: false,
);
final _receiptNotSeen = RegExp(
  r"\b(unseen|unread|not (yet )?(marked )?(seen|read)|never|didn't|did not|"
  r'stayed|remained|still)\b',
  caseSensitive: false,
);

double _toMs(RegExpMatch m) {
  final value = double.parse(m.group(1)!);
  return m.group(2)!.toLowerCase().startsWith('m') ? value : value * 1000;
}

/// Splits the journal into entries at markdown headings, so an earlier failed
/// attempt does not taint a later successful check.
List<String> _journalEntries(String journal) {
  final entries = <StringBuffer>[StringBuffer()];
  for (final line in journal.split('\n')) {
    if (line.startsWith('#')) {
      entries.add(StringBuffer());
    }
    entries.last.writeln(line);
  }
  return [
    for (final e in entries)
      if (e.toString().trim().isNotEmpty) e.toString(),
  ];
}

/// Unwraps paragraphs / list items and splits them into sentences, so a
/// statement wrapped over several markdown lines is read as one.
List<String> _statements(String entry) {
  final blocks = <String>[];
  var current = <String>[];
  void flush() {
    if (current.isNotEmpty) {
      blocks.add(current.join(' '));
      current = [];
    }
  }

  for (final raw in entry.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty ||
        line.startsWith('#') ||
        RegExp(r'^([-*+]|\d+[.)])\s').hasMatch(line)) {
      flush();
    }
    if (line.isNotEmpty) {
      current.add(line);
    }
  }
  flush();
  return [
    for (final block in blocks)
      ...block.split(RegExp(r'(?<=[.;!?])\s+')).where((s) => s.isNotEmpty),
  ];
}

String _withoutFooterCopy(String s) =>
    s.replaceAll(_notSeen, ' ').replaceAll(_seen, ' ');

/// Problems with one journal entry as a passing manual two-browser result.
List<String> _entryProblems(String entry) {
  final problems = <String>[];
  final statements = _statements(entry);
  if (!entry.replaceAll(RegExp(r'\s+'), ' ').contains(_notSeen)) {
    problems.add('first footer state "$_notSeen" not recorded');
  }
  if (!entry.replaceAll(RegExp(r'\s+'), ' ').contains(_seen)) {
    problems.add('second footer state "$_seen" not recorded');
  }

  // A viewed its own pending offer on People.
  if (!statements.any((s) {
    final bare = _withoutFooterCopy(s);
    return _offererSubject.hasMatch(bare) &&
        _peopleWord.hasMatch(bare) &&
        (_ownOffer.hasMatch(bare) || s.contains(_notSeen));
  })) {
    problems.add(
      'A (offerer) viewing its own pending offer on People not '
      'recorded',
    );
  }

  // B, the author, opened People.
  if (!statements.any((s) {
    final bare = _withoutFooterCopy(s);
    return _authorSubject.hasMatch(bare) &&
        _opened.hasMatch(bare) &&
        _peopleWord.hasMatch(bare);
  })) {
    problems.add('B (author) opening People not recorded');
  }

  // The live flip: stated, no failure wording, no reload, within 5 s.
  final flipStatements = [
    for (final s in statements)
      if (s.contains(_seen) || _flipWording.hasMatch(_withoutFooterCopy(s))) s,
  ];
  final reloadStatements = [
    for (final s in statements)
      if (RegExp('reload|refresh', caseSensitive: false).hasMatch(s)) s,
  ];
  if (!flipStatements.any((s) => s.contains(_seen))) {
    problems.add('the flip to "$_seen" is not recorded');
  }
  for (final s in [...flipStatements, ...reloadStatements]) {
    final failure = _failureLanguage.firstMatch(_withoutFooterCopy(s));
    if (failure != null) {
      problems.add('records a non-passing flip: "${failure.group(0)}" in "$s"');
    }
  }
  if (!statements.any(_noReload.hasMatch)) {
    problems.add('does not state the flip happened without a reload');
  }
  final flipDurations = [
    for (final s in flipStatements)
      for (final m in _duration.allMatches(s)) _toMs(m),
  ];
  if (flipDurations.any((ms) => ms > _flipBudgetMs)) {
    problems.add('flip took longer than $_flipBudgetMs ms: $flipDurations');
  } else if (flipDurations.isEmpty &&
      !flipStatements.any(_liveWording.hasMatch)) {
    problems.add('does not record that the flip came within 5 s');
  }

  // B's help_offer_submitted Activity receipt turned seen.
  final receiptStatements = [
    for (final s in statements)
      if (_activityReceipt.hasMatch(s) &&
          _authorSubject.hasMatch(_withoutFooterCopy(s)) &&
          _receiptNoun.hasMatch(s))
        s,
  ];
  if (!receiptStatements.any(
    (s) =>
        _receiptSeen.hasMatch(_withoutFooterCopy(s)) &&
        !_receiptNotSeen.hasMatch(_withoutFooterCopy(s)),
  )) {
    problems.add("B's (author's) Activity offer receipt not recorded as seen");
  }
  return problems;
}

/// Route B: some journal entry records an unambiguous passing manual
/// two-browser result. Returns the closest entry's gaps (empty on pass).
List<String> _manualJournalProblems(String journal) {
  List<String>? best;
  for (final entry in _journalEntries(journal)) {
    final problems = _entryProblems(entry);
    if (problems.isEmpty) {
      return const [];
    }
    if (best == null || problems.length < best.length) {
      final heading = entry.split('\n').first.trim();
      best = ['closest entry "$heading":', ...problems];
    }
  }
  return best ?? ['journal has no entries'];
}
