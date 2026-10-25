import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/polling.dart';
import 'package:tentura/features/beacon_plan/domain/exception/beacon_plan_exceptions.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/polling/ui/widget/polling_question_input.dart';
import 'package:tentura/features/polling/ui/widget/polling_variant_input.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

Future<void> showBeaconRoomPollSheet(
  BuildContext context, {
  required RoomCubit cubit,
}) async {
  await showTenturaAdaptiveSheet<void>(
    context: context,
    useRootNavigator: true,
    enableDrag: false,
    builder: (_) => _PollCreateSheet(cubit: cubit),
  );
}

class _PollCreateSheet extends StatefulWidget {
  const _PollCreateSheet({required this.cubit});
  final RoomCubit cubit;

  @override
  State<_PollCreateSheet> createState() => _PollCreateSheetState();
}

class _PollCreateSheetState extends State<_PollCreateSheet> {
  final _formKey = GlobalKey<FormState>();
  String _question = '';
  final List<String> _variants = ['', ''];
  // One stable key per option row, so a field keeps its own text when an
  // option above it is removed.
  final List<Key> _variantKeys = [UniqueKey(), UniqueKey()];
  String _pollType = 'single';
  bool _isAnonymous = true;
  bool _allowRevote = true;
  bool _sending = false;

  late final String _initialQuestion;
  late final List<String> _initialVariants;
  late final String _initialPollType;
  late final bool _initialIsAnonymous;
  late final bool _initialAllowRevote;

  @override
  void initState() {
    super.initState();
    _initialQuestion = _question;
    _initialVariants = List<String>.from(_variants);
    _initialPollType = _pollType;
    _initialIsAnonymous = _isAnonymous;
    _initialAllowRevote = _allowRevote;
  }

  bool get _isDirty =>
      _question != _initialQuestion ||
      _variants.length != _initialVariants.length ||
      !_variants.asMap().entries.every(
        (e) => e.value == _initialVariants[e.key],
      ) ||
      _pollType != _initialPollType ||
      _isAnonymous != _initialIsAnonymous ||
      _allowRevote != _initialAllowRevote;

  /// Whether another non-empty option equals [value] the way the server
  /// compares options ([Polling.variantKey]).
  bool _isDuplicateAt(int index, String value) {
    final key = Polling.variantKey(value);
    if (key.isEmpty) return false;
    for (var i = 0; i < _variants.length; i++) {
      if (i != index && Polling.variantKey(_variants[i]) == key) return true;
    }
    return false;
  }

  void _addVariant() => setState(() {
    _variants.add('');
    _variantKeys.add(UniqueKey());
  });

  void _removeVariant(int index) => setState(() {
    _variants.removeAt(index);
    _variantKeys.removeAt(index);
  });

  /// A question and at least two options are filled in (#728). Until then
  /// Send stays disabled instead of answering with an error bar.
  bool get _canSend =>
      _question.trim().isNotEmpty &&
      _variants.where((v) => v.trim().isNotEmpty).length >= 2;

  Future<void> _requestClose() => TenturaSheetDismissGuard.requestClose(
    context,
    isDirty: _isDirty,
    useRootNavigator: true,
  );

  Future<void> _send() async {
    // Too short a question or option is marked on its own field (#728).
    if (!_canSend || !(_formKey.currentState?.validate() ?? false)) return;
    final q = _question.trim();
    final vs = _variants
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();

    setState(() => _sending = true);
    try {
      final created = await widget.cubit.createPoll(
        question: q,
        variants: vs,
        pollType: _pollType,
        isAnonymous: _isAnonymous,
        allowRevote: _allowRevote,
      );
      if (!mounted) return;
      if (created) {
        Navigator.of(context).pop();
      } else {
        // The cubit already showed why; keep the draft so nothing is lost.
        setState(() => _sending = false);
      }
    } on PollDuplicateVariantException catch (e) {
      // The only refusal createPoll rethrows; every other one returns false
      // after the cubit has shown it.
      if (mounted) {
        showSnackBar(
          context,
          isError: true,
          text: L10n.of(context)!.pollErrorDuplicateVariant,
          error: e,
        );
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    return TenturaSheetDismissGuard(
      isDirty: _isDirty,
      useRootNavigator: true,
      child: Padding(
        padding: EdgeInsets.only(
          left: tt.screenHPadding,
          right: tt.screenHPadding,
          top: tt.sectionGap,
          bottom: MediaQuery.viewInsetsOf(context).bottom + tt.sectionGap,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.beaconRoomCreatePoll,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    // Same discard check as the scrim and Escape (#737).
                    IconButton(
                      tooltip: l10n.buttonClose,
                      onPressed: () => unawaited(_requestClose()),
                      icon: Icon(Icons.close, size: tt.iconSize),
                    ),
                  ],
                ),
                SizedBox(height: tt.sectionGap),
                PollingQuestionInput(
                  labelText: l10n.pollQuestionFieldLabel,
                  onChanged: (v) => setState(() => _question = v),
                ),
                SizedBox(height: tt.sectionGap),
                Text(
                  l10n.pollOptionsLabel,
                  style: theme.textTheme.labelLarge,
                ),
                SizedBox(height: tt.rowGap),
                ..._variants.asMap().entries.map(
                  (entry) {
                    final idx = entry.key;
                    return Padding(
                      key: _variantKeys[idx],
                      padding: EdgeInsets.only(bottom: tt.rowGap),
                      child: PollingVariantInput(
                        labelText: l10n.optionLabel(idx + 1),
                        isDuplicate: (v) => _isDuplicateAt(idx, v),
                        onChanged: (v) => setState(() => _variants[idx] = v),
                        onRemove: _variants.length > 2
                            ? () => _removeVariant(idx)
                            : () {},
                      ),
                    );
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(l10n.addOptionButton),
                  onPressed: _variants.length < 10 ? _addVariant : null,
                ),
                SizedBox(height: tt.sectionGap),

                // Poll type selector
                Align(
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'single',
                        label: Text(l10n.beaconRoomPollTypeSingle),
                      ),
                      ButtonSegment(
                        value: 'multiple',
                        label: Text(l10n.beaconRoomPollTypeMultiple),
                      ),
                      ButtonSegment(
                        value: 'range',
                        label: Text(l10n.beaconRoomPollTypeRange),
                      ),
                    ],
                    selected: {_pollType},
                    onSelectionChanged: (s) =>
                        setState(() => _pollType = s.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                SizedBox(height: tt.rowGap),

                // Anonymous / open toggle
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.beaconRoomPollAnonymousTitle),
                  subtitle: Text(l10n.beaconRoomPollAnonymousSubtitle),
                  value: _isAnonymous,
                  onChanged: (v) => setState(() => _isAnonymous = v),
                ),

                // Allow revote toggle
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.beaconRoomPollAllowRevoteTitle),
                  value: _allowRevote,
                  onChanged: (v) => setState(() => _allowRevote = v),
                ),

                SizedBox(height: tt.rowGap),
                // Says why Send poll is disabled before any field is touched
                // (#728), as the recipients step does (#720).
                if (!_canSend) ...[
                  Text(
                    l10n.beaconRoomPollSendHint,
                    textAlign: TextAlign.center,
                    style: TenturaText.bodySmall(tt.textMuted),
                  ),
                  SizedBox(height: tt.rowGap / 2),
                ],
                TenturaSheetActions(
                  cancelLabel: l10n.buttonCancel,
                  onCancel: () => unawaited(_requestClose()),
                  primaryLabel: l10n.beaconRoomSendPollButton,
                  onPrimary: _sending || !_canSend
                      ? null
                      : () => unawaited(_send()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
