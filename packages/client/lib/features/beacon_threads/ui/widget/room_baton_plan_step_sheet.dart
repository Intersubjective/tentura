import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_edit_state.dart'
    show PlanLimits;
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/baton_select_result.dart';

/// «Create a plan step with {name}?» (#479, D9): offered once, right after
/// the author picks who takes a «Who'll take it?» ask. The title is prefilled
/// from the ask and editable; «Not now» creates nothing.
///
/// [onCreate] saves the step and says whether it is in the plan now. On
/// `false` (the error has been shown) the sheet stays open so the author can
/// try again; the offer keeps its step id, so a retry never adds a second
/// step.
class RoomBatonPlanStepSheet extends StatefulWidget {
  const RoomBatonPlanStepSheet({
    required this.offer,
    required this.onCreate,
    super.key,
  });

  static Future<void> show(
    BuildContext context, {
    required BatonPlanStepOffer offer,
    required Future<bool> Function(String title) onCreate,
  }) => showTenturaAdaptiveSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (_) => RoomBatonPlanStepSheet(offer: offer, onCreate: onCreate),
  );

  final BatonPlanStepOffer offer;
  final Future<bool> Function(String title) onCreate;

  @override
  State<RoomBatonPlanStepSheet> createState() => _RoomBatonPlanStepSheetState();
}

class _RoomBatonPlanStepSheetState extends State<RoomBatonPlanStepSheet> {
  late final _controller = TextEditingController(text: widget.offer.title);

  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The server counts the title in UTF-16 units, which the field's
  /// character counter does not (an emoji is one character, two units).
  bool get _canCreate {
    final title = _controller.text.trim();
    return !_saving &&
        title.isNotEmpty &&
        title.length <= PlanLimits.maxTitleLength;
  }

  Future<void> _create() async {
    if (!_canCreate) return;
    setState(() => _saving = true);
    final created = await widget.onCreate(_controller.text.trim());
    if (!mounted) return;
    if (created) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final name = widget.offer.assigneeName;
    return Padding(
      padding: EdgeInsets.only(
        left: tt.screenHPadding,
        right: tt.screenHPadding,
        top: tt.rowGap,
        bottom: MediaQuery.viewInsetsOf(context).bottom + tt.sectionGap,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.batonPlanStepPromptTitle(name),
            style: theme.textTheme.titleLarge,
          ),
          SizedBox(height: tt.tightGap),
          Text(
            l10n.batonPlanStepPromptBody(name),
            style: TenturaText.bodySmall(theme.colorScheme.onSurfaceVariant),
          ),
          SizedBox(height: tt.sectionGap),
          TextField(
            controller: _controller,
            enabled: !_saving,
            maxLength: PlanLimits.maxTitleLength,
            decoration: tenturaNoteInputDecoration(
              context,
              labelText: l10n.batonPlanStepTitleLabel,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _create(),
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          ),
          SizedBox(height: tt.sectionGap),
          TenturaSheetActions(
            cancelLabel: l10n.batonPlanStepNotNow,
            onCancel: _saving ? null : () => Navigator.of(context).pop(),
            primaryLabel: l10n.batonPlanStepCreate,
            onPrimary: _canCreate ? _create : null,
          ),
        ],
      ),
    );
  }
}
