import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';

import '../bloc/beacon_create_cubit.dart';
import 'cover_symbol_sheet.dart';

/// "Request cover" block: identity preview and compact photo/symbol actions.
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
              _statusText(l10n, state, capability),
              style: TenturaText.bodySmall(tt.textMuted),
            ),
          ],
        );

        final control = _sourceActions(
          context,
          state: state,
          cubit: cubit,
          l10n: l10n,
          tt: tt,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
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
  }

  /// Always-firing Photo / Symbol icon actions with selected styling.
  Widget _sourceActions(
    BuildContext context, {
    required BeaconCreateState state,
    required BeaconCreateCubit cubit,
    required L10n l10n,
    required TenturaTokens tt,
  }) {
    final photoSelected = state.coverSource == BeaconCoverSource.photo;
    final photo = _sourceActionButton(
      key: const Key('BeaconCover.SourcePhoto'),
      label: l10n.beaconCoverSourcePhoto,
      icon: Icons.photo_outlined,
      selected: photoSelected,
      tt: tt,
      onPressed: () => unawaited(cubit.pickCoverPhoto()),
    );
    final symbol = _sourceActionButton(
      key: const Key('BeaconCover.SourceSymbol'),
      label: l10n.beaconCoverSourceSymbol,
      icon: Icons.category_outlined,
      selected: !photoSelected,
      tt: tt,
      onPressed: () => _onSymbolPressed(context, cubit: cubit, state: state),
    );
    final gap = SizedBox(width: tt.tightGap);
    return KeyedSubtree(
      key: const Key('BeaconCover.SourceControl'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          photo,
          gap,
          symbol,
        ],
      ),
    );
  }

  Widget _sourceActionButton({
    required Key key,
    required String label,
    required IconData icon,
    required bool selected,
    required TenturaTokens tt,
    required VoidCallback onPressed,
  }) {
    final iconWidget = Icon(icon, size: tt.iconSize);
    if (selected) {
      return IconButton.filledTonal(
        key: key,
        tooltip: label,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: Size(tt.buttonHeight, tt.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tt.buttonRadius),
          ),
        ),
        icon: iconWidget,
      );
    }
    return IconButton.outlined(
      key: key,
      tooltip: label,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: Size(tt.buttonHeight, tt.buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tt.buttonRadius),
        ),
      ),
      icon: iconWidget,
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

  String _statusText(
    L10n l10n,
    BeaconCreateState state,
    String? capability,
  ) {
    if (state.coverSource == BeaconCoverSource.symbol) {
      return capability == null
          ? l10n.beaconCoverStatusNeedCapability
          : l10n.beaconCoverStatusSymbolNamed(capability);
    }
    if (state.coverImage != null) {
      return l10n.beaconCoverStatusPhoto;
    }
    if (capability != null) {
      return l10n.beaconCoverStatusSymbolNamed(capability);
    }
    return l10n.beaconCoverStatusAddCover;
  }
}
