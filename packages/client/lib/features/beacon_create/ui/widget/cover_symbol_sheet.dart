import 'package:flutter/material.dart';
import 'package:tentura_root/domain/capability/capability_slugs.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/unfocus_sheet_body.dart';

import '../bloc/beacon_create_cubit.dart';

/// Picks the capability behind symbol identity. Only capabilities the request
/// already asks for are offered; the global catalog is deliberately not shown.
class CoverSymbolSheet extends StatelessWidget {
  const CoverSymbolSheet({
    required this.onManageCapabilities,
    super.key,
  });

  /// Escape hatch when the request has no capabilities yet.
  final VoidCallback onManageCapabilities;

  static Future<void> show(
    BuildContext context, {
    required BeaconCreateCubit cubit,
    required VoidCallback onManageCapabilities,
  }) => showTenturaAdaptiveSheet<void>(
    context: context,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: CoverSymbolSheet(onManageCapabilities: onManageCapabilities),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    final cubit = context.read<BeaconCreateCubit>();

    return UnfocusSheetBody(
      child: BlocBuilder<BeaconCreateCubit, BeaconCreateState>(
        bloc: cubit,
        buildWhen: (p, c) =>
            p.needs != c.needs || p.primaryNeedSlug != c.primaryNeedSlug,
        builder: (context, state) {
          final tags = _orderedTags(state.needs);
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                tt.screenHPadding,
                tt.sectionGap,
                tt.screenHPadding,
                tt.sectionGap,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.beaconCoverSymbolSheetTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                  SizedBox(height: tt.tightGap * 2),
                  Text(
                    tags.isEmpty
                        ? l10n.beaconCoverSymbolSheetEmpty
                        : l10n.beaconCoverSymbolSheetHint,
                    style: TenturaText.bodySmall(tt.textMuted),
                  ),
                  SizedBox(height: tt.rowGap),
                  if (tags.isEmpty)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        key: const Key('BeaconCover.ManageCapabilities'),
                        onPressed: () {
                          Navigator.of(context).pop();
                          onManageCapabilities();
                        },
                        icon: Icon(Icons.tune_rounded, size: tt.iconSize),
                        label: Text(l10n.beaconCoverSymbolSheetManage),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: tags.length,
                        itemBuilder: (context, index) {
                          final tag = tags[index];
                          return ListTile(
                            key: Key('BeaconCover.Symbol.${tag.slug}'),
                            leading: TenturaCapabilityGlyph(
                              tag: tag,
                              size: tt.avatarSize,
                            ),
                            title: Text(tag.labelOf(l10n)),
                            trailing: tag.slug == state.primaryNeedSlug
                                ? Icon(Icons.check_rounded, size: tt.iconSize)
                                : null,
                            selected: tag.slug == state.primaryNeedSlug,
                            onTap: () {
                              cubit.setPrimaryNeedSlug(tag.slug);
                              Navigator.of(context).pop();
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Canonical capability order; slugs with no client tag are skipped.
  static List<CapabilityTag> _orderedTags(Set<String> needs) => [
    for (final slug in kCapabilitySlugOrder)
      if (needs.contains(slug)) ?CapabilityTag.fromSlug(slug),
  ];
}
