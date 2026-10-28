// The author's HUD "you" line nudges them to forward again when every person
// they forwarded the Request to has declined, instead of the generic "You can
// forward" (#486). Anywhere short of "everyone declined", or when the viewer
// cannot forward, the line stays what it was.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_hud_derivation.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/ui/l10n/l10n.dart';

final _t = DateTime.utc(2026, 6, 20);
const _author = Profile(id: 'auth', displayName: 'Author');

ForwardEdge _forward(
  String recipientId, {
  bool declined = false,
  bool cancelled = false,
}) => ForwardEdge(
  id: 'e-$recipientId',
  beaconId: 'b1',
  createdAt: _t,
  sender: _author,
  recipient: Profile(id: recipientId, displayName: recipientId),
  recipientRejected: declined,
  cancelledAt: cancelled ? _t : null,
);

BeaconViewState _authorState({
  required List<ForwardEdge> forwards,
  bool viewerCanForward = true,
}) => BeaconViewState(
  beacon: Beacon(
    id: 'b1',
    title: 'T',
    author: _author,
    createdAt: _t,
    updatedAt: _t,
    viewerCanForward: viewerCanForward,
  ),
  myProfile: _author,
  myForwards: forwards,
  forwardsLoaded: true,
);

/// The message key the decline-specific cue must live under, in both ARBs.
const _cueKey = 'beaconHudYouForwardAfterDecline';

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

/// The localized cue text as written in `l10n/app_<locale>.arb`, so the
/// assertions compare against the shipped copy rather than a guess at it.
String _cueCopy(String locale) {
  final copy = _arb(locale)[_cueKey] as String?;
  if (copy == null) fail('app_$locale.arb needs "$_cueKey"');
  return copy;
}

// Any of the Russian words for "declined / can't help".
final _ruDeclineWord = RegExp('отказ|отклон|не могут|не может|не смог');

void main() {
  final en = lookupL10n(const Locale('en'));
  final ru = lookupL10n(const Locale('ru'));

  group('decline-forward cue copy', () {
    test('English ARB defines it, distinct from the generic forward line', () {
      final copy = _cueCopy('en');

      expect(copy, isNotEmpty);
      expect(copy, isNot(en.beaconHudYouForward));
      expect(copy.toLowerCase(), contains('declin'));
      expect(copy.toLowerCase(), contains('forward'));
    });

    test('Russian ARB translates it, with decline and forwarding guidance', () {
      final copy = _cueCopy('ru');

      expect(copy, isNotEmpty);
      expect(copy, isNot(ru.beaconHudYouForward));
      expect(copy.toLowerCase(), matches(_ruDeclineWord));
      expect(copy.toLowerCase(), contains('перешл'));
    });
  });

  group('author HUD line when every forward was declined', () {
    test('is the dedicated decline-forward copy in English', () {
      final line = beaconHudYouLine(
        en,
        _authorState(
          forwards: [
            _forward('r1', declined: true),
            _forward('r2', declined: true),
          ],
        ),
      );

      expect(line, _cueCopy('en'));
    });

    test('is the dedicated decline-forward copy in Russian', () {
      final line = beaconHudYouLine(
        ru,
        _authorState(forwards: [_forward('r1', declined: true)]),
      );

      expect(line, _cueCopy('ru'));
    });

    test('a cancelled forward does not count against "everyone"', () {
      final line = beaconHudYouLine(
        en,
        _authorState(
          forwards: [
            _forward('r1', declined: true),
            _forward('r2', cancelled: true),
          ],
        ),
      );

      expect(line, _cueCopy('en'));
    });

    test('falls back to today\'s line when the viewer cannot forward', () {
      final state = _authorState(
        forwards: [_forward('r1', declined: true)],
        viewerCanForward: false,
      );
      final withoutDeclines = _authorState(
        forwards: const [],
        viewerCanForward: false,
      );

      final line = beaconHudYouLine(en, state);

      // Same line the author gets with nothing declined (the author-idle
      // fallback), and never the forward or decline copy.
      expect(line, beaconHudYouLine(en, withoutDeclines));
      expect(line, isNot(en.beaconHudYouForward));
      expect(line.toLowerCase(), isNot(contains('declin')));
      expect(line, en.beaconHudYouAuthorIdle);
    });
  });

  group('author HUD line short of everyone declining', () {
    test('some declined, some pending: generic forward line', () {
      final line = beaconHudYouLine(
        en,
        _authorState(
          forwards: [_forward('r1', declined: true), _forward('r2')],
        ),
      );

      expect(line, en.beaconHudYouForward);
    });

    test('nobody forwarded to yet: generic forward line', () {
      final line = beaconHudYouLine(en, _authorState(forwards: const []));

      expect(line, en.beaconHudYouForward);
    });

    test('only cancelled forwards: generic forward line', () {
      final line = beaconHudYouLine(
        en,
        _authorState(forwards: [_forward('r1', cancelled: true)]),
      );

      expect(line, en.beaconHudYouForward);
    });
  });
}
