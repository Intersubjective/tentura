import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
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

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final q = _question.trim();
    final vs = _variants
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    if (q.isEmpty || vs.length < 2) return;

    setState(() => _sending = true);
    try {
      await widget.cubit.createPoll(
        question: q,
        variants: vs,
        pollType: _pollType,
        isAnonymous: _isAnonymous,
        allowRevote: _allowRevote,
      );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) {
        showSnackBar(context, isError: true, text: e.toString(), error: e);
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
              Text(
                l10n.beaconRoomCreatePoll,
                style: theme.textTheme.titleMedium,
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
                    key: ValueKey(idx),
                    padding: EdgeInsets.only(bottom: tt.rowGap),
                    child: PollingVariantInput(
                      labelText: l10n.optionLabel(idx + 1),
                      onChanged: (v) => setState(() => _variants[idx] = v),
                      onRemove: _variants.length > 2
                          ? () => setState(() => _variants.removeAt(idx))
                          : () {},
                    ),
                  );
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(l10n.addOptionButton),
                onPressed: _variants.length < 10
                    ? () => setState(() => _variants.add(''))
                    : null,
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
              FilledButton(
                onPressed: _sending ? null : _send,
                child: Text(l10n.beaconRoomSendPollButton),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
