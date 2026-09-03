import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';

import '../bloc/beacon_create_cubit.dart';
import 'cover_symbol_sheet.dart';

/// "Request cover" block: identity preview, helper copy, and the persisted
/// photo/symbol preference control.
///
/// Photo / Symbol are **actions** (open picker / symbol sheet), not a mute
/// mode toggle: re-tapping the already-selected source still runs the action.
/// Selected styling still reflects [BeaconCreateState.coverSource].
class CoverBlock extends StatelessWidget {
  const CoverBlock({
    required this.onManageCapabilities,
    super.key,
  });

  static const previewSize = 56.0;

  /// Opens the capabilities editor when there is no capability to symbolize.
  final VoidCallback onManageCapabilities;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<BeaconCreateCubit>();
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);

    return BlocBuilder<BeaconCreateCubit, BeaconCreateState>(
      bloc: cubit,
      buildWhen: (p, c) =>
          p.images != c.images ||
          p.coverKey != c.coverKey ||
          p.coverThumb != c.coverThumb ||
          p.coverSource != c.coverSource ||
          p.needs != c.needs ||
          p.primaryNeedSlug != c.primaryNeedSlug,
      builder: (context, state) {
        final capability = state.primaryCapability?.labelOf(l10n);
        final preview = Semantics(
          identifier: 'BeaconCover.Preview',
          button: true,
          label: l10n.beaconCoverPreviewSemantics,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('BeaconCover.Preview'),
              borderRadius: BorderRadius.circular(tt.buttonRadius),
              onTap: () => unawaited(cubit.pickCoverPhoto()),
              child: Padding(
                padding: EdgeInsets.all(tt.tightGap),
                child: BeaconIdentityTile(
                  beacon: state.coverPreview,
                  size: previewSize,
                ),
              ),
            ),
          ),
        );

        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.beaconCoverTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: tt.tightGap),
            Text(
              _helperText(l10n, state, capability),
              style: TenturaText.bodySmall(tt.textMuted),
            ),
            if (state.coverSource == BeaconCoverSource.symbol &&
                capability != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const Key('BeaconCover.ChangeSymbol'),
                  onPressed: () => unawaited(
                    CoverSymbolSheet.show(
                      context,
                      cubit: cubit,
                      onManageCapabilities: onManageCapabilities,
                    ),
                  ),
                  child: Text(l10n.beaconCoverChangeSymbol),
                ),
              ),
          ],
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                windowClassForWidth(constraints.maxWidth) ==
                WindowClass.compact;
            final control = _sourceActions(
              context,
              compact: compact,
              state: state,
              cubit: cubit,
              l10n: l10n,
              tt: tt,
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      preview,
                      SizedBox(width: tt.avatarTextGap),
                      Expanded(child: text),
                    ],
                  ),
                  SizedBox(height: tt.rowGap),
                  control,
                ],
              );
            }
            return Row(
              children: [
                preview,
                SizedBox(width: tt.avatarTextGap),
                Expanded(child: text),
                SizedBox(width: tt.cardGap),
                control,
              ],
            );
          },
        );
      },
    );
  }

  /// Always-firing Photo / Symbol actions with selected styling from [state].
  ///
  /// Compact: full-width [Expanded] pair. Wide: intrinsic [MainAxisSize.min]
  /// so the trailing slot in an unbounded [Row] does not flex-explode.
  Widget _sourceActions(
    BuildContext context, {
    required bool compact,
    required BeaconCreateState state,
    required BeaconCreateCubit cubit,
    required L10n l10n,
    required TenturaTokens tt,
  }) {
    final photoSelected = state.coverSource == BeaconCoverSource.photo;
    final photo = _sourceActionButton(
      key: const Key('BeaconCover.SourcePhoto'),
      label: l10n.beaconCoverSourcePhoto,
      selected: photoSelected,
      tt: tt,
      onPressed: () => unawaited(cubit.pickCoverPhoto()),
    );
    final symbol = _sourceActionButton(
      key: const Key('BeaconCover.SourceSymbol'),
      label: l10n.beaconCoverSourceSymbol,
      selected: !photoSelected,
      tt: tt,
      onPressed: () => _onSymbolPressed(context, cubit: cubit, state: state),
    );
    final gap = SizedBox(width: tt.tightGap);
    return KeyedSubtree(
      key: const Key('BeaconCover.SourceControl'),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (compact) Expanded(child: photo) else photo,
          gap,
          if (compact) Expanded(child: symbol) else symbol,
        ],
      ),
    );
  }

  Widget _sourceActionButton({
    required Key key,
    required String label,
    required bool selected,
    required TenturaTokens tt,
    required VoidCallback onPressed,
  }) {
    final child = Text(label, overflow: TextOverflow.ellipsis);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tt.buttonRadius),
    );
    final minSize = Size(0, tt.buttonHeight);
    if (selected) {
      return FilledButton.tonal(
        key: key,
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: minSize,
          shape: shape,
        ),
        child: child,
      );
    }
    return OutlinedButton(
      key: key,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: minSize,
        shape: shape,
      ),
      child: child,
    );
  }

  void _onSymbolPressed(
    BuildContext context, {
    required BeaconCreateCubit cubit,
    required BeaconCreateState state,
  }) {
    if (state.canSelectSymbolSource) {
      cubit.selectSymbolCoverSource();
    }
    unawaited(
      CoverSymbolSheet.show(
        context,
        cubit: cubit,
        onManageCapabilities: onManageCapabilities,
      ),
    );
  }

  String _helperText(
    L10n l10n,
    BeaconCreateState state,
    String? capability,
  ) {
    if (state.coverSource == BeaconCoverSource.symbol) {
      return capability == null
          ? l10n.beaconCoverSymbolNeedsCapability
          : l10n.beaconCoverHintSymbolSelected(capability);
    }
    if (state.coverImage != null) {
      return '${l10n.beaconCoverHintPhotoSelected} '
          '${l10n.beaconCoverHintThumbOnCard}';
    }
    if (capability != null) {
      return l10n.beaconCoverHintNoPhotoUsingSymbol(capability);
    }
    return '${l10n.beaconCoverHintPhotoPick} '
        '${l10n.beaconCoverSymbolNeedsCapability}';
  }
}
