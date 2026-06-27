import 'package:flutter/material.dart';

import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/polling/ui/widget/polling_question_input.dart';
import 'package:tentura/features/polling/ui/widget/polling_variant_input.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

Future<void> showBeaconRoomPollSheet(
  BuildContext context, {
  required RoomCubit cubit,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
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
        showSnackBar(context, isError: true, text: e.toString());
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: kSpacingMedium,
        right: kSpacingMedium,
        top: kSpacingMedium,
        bottom: MediaQuery.of(context).viewInsets.bottom + kSpacingMedium,
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
              const SizedBox(height: kSpacingMedium),
              PollingQuestionInput(
                labelText: l10n.pollQuestionFieldLabel,
                onChanged: (v) => _question = v,
              ),
              const SizedBox(height: kSpacingMedium),
              Text(
                l10n.pollOptionsLabel,
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: kSpacingSmall),
              ..._variants.asMap().entries.map(
                (entry) {
                  final idx = entry.key;
                  return Padding(
                    key: ValueKey(idx),
                    padding: const EdgeInsets.only(bottom: kSpacingSmall),
                    child: PollingVariantInput(
                      labelText: l10n.optionLabel(idx + 1),
                      onChanged: (v) => _variants[idx] = v,
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
              const SizedBox(height: kSpacingMedium),

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
              const SizedBox(height: kSpacingSmall),

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

              const SizedBox(height: kSpacingSmall),
              FilledButton(
                onPressed: _sending ? null : _send,
                child: Text(l10n.beaconRoomSendPollButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
