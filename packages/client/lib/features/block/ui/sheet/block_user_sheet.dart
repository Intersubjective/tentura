import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/block/domain/entity/user_block.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Confirmation sheet for blocking another user (cascade toggle + impact preview).
Future<void> showBlockUserSheet(
  BuildContext context,
  Profile profile, {
  BlockCase? blockCase,
}) {
  final case_ = blockCase ?? GetIt.I<BlockCase>();
  return showTenturaAdaptiveSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => BlockUserSheetBody(
      profile: profile,
      blockCase: case_,
    ),
  );
}

/// Sheet body — exposed for widget tests via [showBlockUserSheet].
class BlockUserSheetBody extends StatefulWidget {
  const BlockUserSheetBody({
    required this.profile,
    required this.blockCase,
    super.key,
  });

  final Profile profile;
  final BlockCase blockCase;

  @override
  State<BlockUserSheetBody> createState() => _BlockUserSheetBodyState();
}

class _BlockUserSheetBodyState extends State<BlockUserSheetBody> {
  static const _previewDebounce = Duration(milliseconds: 300);

  bool _cascadeEnabled = false;
  BlockPreview? _preview;
  bool _previewLoading = true;
  bool _blocking = false;
  Timer? _previewDebounceTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_fetchPreview());
  }

  @override
  void dispose() {
    _previewDebounceTimer?.cancel();
    super.dispose();
  }

  int get _effectiveCascadeMode => _cascadeEnabled ? 1 : 0;

  void _schedulePreviewFetch() {
    _previewDebounceTimer?.cancel();
    _previewDebounceTimer = Timer(_previewDebounce, () {
      if (!mounted) return;
      unawaited(_fetchPreview());
    });
  }

  Future<void> _fetchPreview() async {
    setState(() => _previewLoading = true);
    try {
      final preview = await widget.blockCase.preview(
        objectId: widget.profile.id,
        cascadeMode: _effectiveCascadeMode,
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _previewLoading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _previewLoading = false);
    }
  }

  Future<void> _confirmBlock() async {
    setState(() => _blocking = true);
    try {
      await widget.blockCase.block(
        objectId: widget.profile.id,
        cascadeMode: _effectiveCascadeMode,
      );
      if (!mounted) return;
      final l10n = L10n.of(context)!;
      showSnackBar(
        context,
        text: l10n.blockConfirmedMessage,
        action: SnackBarAction(
          label: l10n.blockManageAction,
          onPressed: () =>
              GetIt.I<RootRouter>().push(const BlockedUsersRoute()),
        ),
      );
      Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() => _blocking = false);
    }
  }

  void _onCascadeToggled(bool enabled) {
    setState(() => _cascadeEnabled = enabled);
    _schedulePreviewFetch();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final tt = context.tt;
    final preview = _preview;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          tt.screenHPadding,
          tt.rowGap,
          tt.screenHPadding,
          tt.sectionGap + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.blockUserTitle(widget.profile.shownName),
              style: textTheme.titleMedium,
            ),
            SizedBox(height: tt.rowGap),
            Text(
              l10n.blockUserExplainer,
              style: textTheme.bodyMedium,
            ),
            SizedBox(height: tt.sectionGap),
            SwitchListTile(
              key: const Key('block_cascade_switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.blockCascadeToggle),
              subtitle: Text(l10n.blockCascadeToggleSubtitle),
              value: _cascadeEnabled,
              onChanged: _blocking ? null : _onCascadeToggled,
            ),
            if (preview?.willWithdrawEdge ?? false) ...[
              SizedBox(height: tt.sectionGap),
              _WithdrawalNotice(
                text: l10n.blockWithdrawNotice,
                color: scheme.onSurfaceVariant,
                style: textTheme.bodySmall,
                iconGap: tt.iconTextGap,
              ),
            ],
            SizedBox(height: tt.sectionGap),
            if (_previewLoading)
              const Center(child: CircularProgressIndicator.adaptive())
            else if (preview != null) ...[
              if (_cascadeEnabled) ...[
                Text(
                  l10n.blockPreviewCascade(preview.cascadeCandidateCount),
                  style: textTheme.bodyMedium,
                ),
                SizedBox(height: tt.rowGap),
              ],
              if (preview.openCommitmentCount > 0)
                _OpenCommitmentWarning(
                  text: l10n.blockPreviewOpenCommitments,
                  color: scheme.error,
                  style: textTheme.bodyMedium?.copyWith(color: scheme.error),
                  iconGap: tt.iconTextGap,
                ),
            ],
            SizedBox(height: tt.sectionGap),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _blocking ? null : () => Navigator.of(context).pop(),
                  child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
                ),
                SizedBox(width: tt.rowGap),
                FilledButton(
                  key: const Key('block_confirm_button'),
                  style: ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(scheme.error),
                    foregroundColor: WidgetStatePropertyAll(scheme.onError),
                  ),
                  onPressed: _blocking || _previewLoading ? null : _confirmBlock,
                  child: Text(l10n.blockConfirmButton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WithdrawalNotice extends StatelessWidget {
  const _WithdrawalNotice({
    required this.text,
    required this.color,
    required this.style,
    required this.iconGap,
  });

  final String text;
  final Color color;
  final TextStyle? style;
  final double iconGap;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('block_withdraw_notice'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, color: color, size: context.tt.iconSize),
        SizedBox(width: iconGap),
        Expanded(child: Text(text, style: style?.copyWith(color: color))),
      ],
    );
  }
}

class _OpenCommitmentWarning extends StatelessWidget {
  const _OpenCommitmentWarning({
    required this.text,
    required this.color,
    required this.style,
    required this.iconGap,
  });

  final String text;
  final Color color;
  final TextStyle? style;
  final double iconGap;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('block_open_commitment_warning'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_outlined, color: color, size: context.tt.iconSize),
        SizedBox(width: iconGap),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}
