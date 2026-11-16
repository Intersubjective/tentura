// Source-level invariants behind the Post→Request invite step reusing the
// Forward picker (docs/plans/invite-picker-reuses-forward-1292.md):
// - its empty-state copy is a real localized string (both ARB files and the
//   generated L10n class) that the shared picker reads through L10n, never a
//   literal in feature code;
// - people are picked through one picker: no parallel picker cubit, recipient
//   row or list, and new picker widgets compose the existing forward ones.
//
// Reads files by relative path: run from packages/client.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _inviteEmptyEn = 'No one else in this post to invite';
const _inviteEmptyRu = 'В посте больше некого позвать';

const _forwardWidgetDir = 'lib/features/forward/ui/widget';

const _budInviteStepPath =
    'lib/features/beacon_create/ui/widget/post_bud_invite_step.dart';

/// [source] without `//` line comments, so a mention in a comment does not
/// count as code.
String _stripComments(String source) =>
    source.replaceAll(RegExp(r'//[^\n]*'), '');

Map<String, dynamic> _arb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// The ARB key whose English value is [_inviteEmptyEn], or null.
String? _inviteEmptyKey() {
  final keys = [
    for (final e in _arb('l10n/app_en.arb').entries)
      if (!e.key.startsWith('@') && e.value == _inviteEmptyEn) e.key,
  ];
  return keys.length == 1 ? keys.single : null;
}

/// Every Dart file under lib/ except the generated localizations.
Iterable<File> _libSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where(
      (f) =>
          f.path.endsWith('.dart') &&
          !f.path.replaceAll(r'\', '/').startsWith('lib/ui/l10n/'),
    );

String _rel(File f) => f.path.replaceAll(r'\', '/');

void main() {
  group('The invite empty-state copy', () {
    test(
      'exists once in app_en.arb and with the Russian text in app_ru.arb',
      () {
        final key = _inviteEmptyKey();
        expect(
          key,
          isNotNull,
          reason: 'app_en.arb has exactly one key «$_inviteEmptyEn»',
        );
        expect(_arb('l10n/app_ru.arb')[key], _inviteEmptyRu);
      },
    );

    test('is generated into the L10n class for both locales', () {
      final key = _inviteEmptyKey();
      expect(key, isNotNull, reason: 'app_en.arb has «$_inviteEmptyEn»');

      final base = File('lib/ui/l10n/l10n.dart').readAsStringSync();
      expect(base, contains('String get $key;'));
      for (final (path, text) in [
        ('lib/ui/l10n/l10n_en.dart', _inviteEmptyEn),
        ('lib/ui/l10n/l10n_ru.dart', _inviteEmptyRu),
      ]) {
        final generated = File(path).readAsStringSync();
        expect(
          RegExp(
            'String get ${RegExp.escape(key!)}\\s*=>\\s*'
            "'${RegExp.escape(text)}';",
          ).hasMatch(generated),
          isTrue,
          reason: '$path returns «$text» for $key',
        );
      }
    });

    test('is read by the shared picker through L10n, never inlined', () {
      final key = _inviteEmptyKey();
      expect(key, isNotNull, reason: 'app_en.arb has «$_inviteEmptyEn»');
      // The picker reads strings as `l10n.<key>` (`final l10n = L10n.of(…)`).
      final getter = RegExp('\\bl10n!?\\.${RegExp.escape(key!)}\\b');
      final readers = [
        for (final f in Directory(_forwardWidgetDir).listSync())
          if (f is File &&
              f.path.endsWith('.dart') &&
              getter.hasMatch(_stripComments(f.readAsStringSync())))
            _rel(f),
      ];
      expect(
        readers,
        isNotEmpty,
        reason: 'a forward picker widget shows l10n.$key',
      );
      final inlined = [
        for (final f in _libSources())
          if (f.readAsStringSync().contains(_inviteEmptyEn) ||
              f.readAsStringSync().contains(_inviteEmptyRu))
            _rel(f),
      ];
      expect(inlined, isEmpty);
    });
  });

  // The reuse contract (docs/plans/invite-picker-reuses-forward-1292.md) is
  // enforced strictly on purpose: the invite step and every Forward flow pick
  // people through ForwardRecipientPicker, ForwardRecipientRow /
  // ForwardRecipientPickerEntry and ForwardCubit. The allowlists below are the
  // people rows, lists and selection cubits that exist today; a new one fails
  // here and must either reuse the forward widgets/cubit instead or be added
  // to the allowlist in a reviewed change that explains why it is not a
  // parallel picker.
  group('People are picked through the one Forward picker', () {
    test('no cubit besides ForwardCubit holds ForwardState', () {
      final cubits = [
        for (final f in _libSources())
          for (final m in RegExp(
            r'class\s+(\w+)[^{;]*?\bextends\s+'
            r'(?:(?:Cubit|Bloc)<\s*ForwardState\b|ForwardCubit\b)',
          ).allMatches(f.readAsStringSync()))
            m.group(1)!,
      ];
      expect(cubits, ['ForwardCubit']);
    });

    test('no new picker, recipient or invite cubit exists', () {
      const allowed = {
        'AcceptInviteCubit',
        'BeaconAuthorInvitesCubit',
        'BeaconMyInviteCubit',
        'ConstellationComposerCubit',
        'FactPickerCubit',
        'ForwardCandidateContextCubit',
        'ForwardCubit',
        'OrientationInviterCubit',
        'PersonForwardCubit',
        'RegisterInviteCubit',
      };
      final found = {
        for (final f in _libSources())
          for (final m in RegExp(
            r'(?:^|\n)(?:abstract |final |base |sealed )*class\s+(\w+)'
            r'[^{;]*?\bextends\s+(?:Cubit|Bloc)<\s*(\w+)',
          ).allMatches(f.readAsStringSync()))
            if (RegExp(
              'Recipient|Invitee|Invite|Picker|Candidate|Forward',
            ).hasMatch('${m.group(1)} ${m.group(2)}'))
              m.group(1)!,
      };
      expect(found.difference(allowed), isEmpty);
    });

    test('no new recipient or invitee row, tile, list or picker widget '
        'exists', () {
      const allowed = {
        'AcceptedInviteListTile',
        'ForwardRecipientPicker',
        'ForwardRecipientPickerEntry',
        'ForwardRecipientPickerHoverCardBody',
        'ForwardRecipientPickerNameHover',
        'ForwardRecipientRow',
        'UpdatesCollapsedInvitePromptRow',
        '_ForwardRecipientPickerHoverCardOverlay',
        '_InviteListTile',
        '_InviteRow',
        // The bud invite step's own list, removed when the step embeds the
        // picker.
        '_InviteeRow',
        '_InvitesSegmentList',
      };
      final found = {
        for (final f in _libSources())
          for (final m in RegExp(
            r'(?:^|\n)(?:abstract |final |base |sealed )*class\s+'
            r'(\w*(?:Recipient|Invitee|Invite|Candidate)\w*'
            r'(?:Row|Tile|List|Picker|Entry)\w*)'
            r'[^{;]*?\bextends\s+(?:StatelessWidget|StatefulWidget)\b',
          ).allMatches(f.readAsStringSync()))
            m.group(1)!,
      };
      expect(found.difference(allowed), isEmpty);
    });

    test('picker entry rows are laid out only by forward widgets', () {
      final outside = [
        for (final f in _libSources())
          if (!_rel(f).startsWith('$_forwardWidgetDir/') &&
              RegExp(
                r'\b(?:ForwardRecipientPickerEntry|ForwardRecipientRow)\s*\(',
              ).hasMatch(_stripComments(f.readAsStringSync())))
            _rel(f),
      ];
      expect(outside, isEmpty);
    });

    test('a new widget in the forward picker or the bud invite step '
        'composes an existing forward widget', () {
      const existing = {
        'CompactBeaconContextStrip',
        'ForwardBandStrip',
        'ForwardBottomComposer',
        'ForwardEditPanel',
        'ForwardInviteBar',
        'ForwardRecipientExpandedPersonalNote',
        'ForwardRecipientPersonalNoteSlot',
        'ForwardRecipientPicker',
        'ForwardRecipientPickerEntry',
        'ForwardRecipientPickerHoverCardBody',
        'ForwardRecipientPickerNameHover',
        'ForwardRecipientRow',
        'ForwardRecipientWiderExpander',
        'ForwardScopeLinks',
        'ForwardTagPicker',
        'LineageForwardSectionHeader',
        'PerRecipientNoteInput',
        'PostBudFormWarnings',
        'PostBudInviteStep',
        '_CapabilityHintChip',
        '_ForwardPickerContactAvatar',
        '_ForwardPickerEmptyState',
        '_ForwardReadReceipt',
        '_ForwardRecipientPickerHoverCardOverlay',
        '_ForwardRowCheckbox',
        '_InviteeRow',
        '_JoinedOnceContextLoaded',
        '_Line2Content',
        '_LineageMemoryBadge',
        '_Notice',
        '_PreviewBody',
        '_UncoveredRecipientsSheet',
      };
      final forwardWidgets = {
        for (final n in existing)
          if (!n.startsWith('_') && !n.startsWith('PostBud')) n,
      };
      final files = [
        for (final f in Directory(_forwardWidgetDir).listSync())
          if (f is File && f.path.endsWith('.dart')) f,
        File(_budInviteStepPath),
      ];
      final notComposing = <String>[];
      for (final f in files) {
        if (!f.existsSync()) continue;
        final source = _stripComments(f.readAsStringSync());
        final decls = RegExp(
          r'(?:^|\n)(?:abstract |final |base |sealed )*class\s+(\w+)'
          r'[^{;]*?\bextends\s+(?:StatelessWidget|StatefulWidget)\b',
        ).allMatches(source).toList();
        for (final (i, m) in decls.indexed) {
          final name = m.group(1)!;
          if (existing.contains(name)) continue;
          final end = i + 1 < decls.length ? decls[i + 1].start : source.length;
          final body = source.substring(m.end, end);
          final composes = forwardWidgets.any(
            (w) => RegExp('\\b$w\\s*[(.<]').hasMatch(body),
          );
          if (!composes) notComposing.add('${_rel(f)}: $name');
        }
      }
      expect(notComposing, isEmpty);
    });
  });
}
