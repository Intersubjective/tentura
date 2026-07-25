import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';

import '../bloc/beacon_create_cubit.dart';
import 'cover_symbol_sheet.dart';

/// "Request cover" block: identity preview, helper copy, and the persisted
/// photo/symbol preference control.
///
/// The control is bound to [BeaconCreateState.coverSource], never to the
/// resolved identity, so a preference survives having nothing to show yet.
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

        final control = SegmentedButton<BeaconCoverSource>(
          key: const Key('BeaconCover.SourceControl'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: BeaconCoverSource.photo,
              label: Text(l10n.beaconCoverSourcePhoto),
            ),
            ButtonSegment(
              value: BeaconCoverSource.symbol,
              label: Text(l10n.beaconCoverSourceSymbol),
              enabled: state.canSelectSymbolSource,
            ),
          ],
          selected: {state.coverSource},
          onSelectionChanged: (selection) => _onSourceChanged(
            context,
            cubit: cubit,
            source: selection.first,
            state: state,
          ),
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                windowClassForWidth(constraints.maxWidth) ==
                WindowClass.compact;
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

  void _onSourceChanged(
    BuildContext context, {
    required BeaconCreateCubit cubit,
    required BeaconCoverSource source,
    required BeaconCreateState state,
  }) {
    switch (source) {
      case BeaconCoverSource.photo:
        cubit.selectPhotoCoverSource();
      case BeaconCoverSource.symbol:
        cubit.selectSymbolCoverSource();
        // More than one capability means the author has a real choice to make.
        if (state.needs.length > 1) {
          unawaited(
            CoverSymbolSheet.show(
              context,
              cubit: cubit,
              onManageCapabilities: onManageCapabilities,
            ),
          );
        }
    }
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
      return l10n.beaconCoverHintPhotoSelected;
    }
    if (capability != null) {
      return l10n.beaconCoverHintNoPhotoUsingSymbol(capability);
    }
    return '${l10n.beaconCoverHintPhotoPick} '
        '${l10n.beaconCoverSymbolNeedsCapability}';
  }
}
