import 'dart:async';

import 'package:auto_route/auto_route.dart' show PageRouteInfo;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/radius_recipient_selection.dart';
import '../bloc/constellation_composer_cubit.dart';

/// Recipient controls of the graph composer: «Получат · n» and chips with ×.
/// The radius itself is controlled on the canvas (the composer
/// circle's rim handle), not here. There is no inline send: the single
/// trailing button hands off to the full create screen (Post or Request)
/// with these recipients already selected; anchoring the result at the drop
/// point is a separate, manual step afterward (drag the new node once it
/// appears, same as any other beacon on the field).
///
/// A bottom sheet on narrow layouts, a side panel on wide ones.
class ConstellationComposerSheet extends StatelessWidget {
  const ConstellationComposerSheet({
    required this.composer,
    required this.onOpenFullForm,
    super.key,
  });

  final ConstellationComposerCubit composer;

  /// Receives the full-form route.
  final ValueChanged<PageRouteInfo> onOpenFullForm;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final wide = context.windowClass == WindowClass.expanded;
    final body = _SheetBody(composer: composer, onOpenFullForm: onOpenFullForm);
    if (wide) {
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          key: const Key('constellation.composer.side_panel'),
          width: tt.chatColumnMaxWidth / 2,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: body,
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        key: const Key('constellation.composer.sheet'),
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: body,
      ),
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.composer, required this.onOpenFullForm});

  final ConstellationComposerCubit composer;

  final ValueChanged<PageRouteInfo> onOpenFullForm;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    return BlocBuilder<ConstellationComposerCubit, RadiusRecipientSelection>(
      bloc: composer,
      builder: (context, selection) {
        final selected = selection.selected.toList()..sort();
        return SingleChildScrollView(
          padding: EdgeInsets.all(tt.screenHPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.constellationComposerRecipients(selected.length),
                      style: TenturaText.title(
                        Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('constellation.composer.add_person'),
                    tooltip: l10n.constellationComposerAddPerson,
                    isSelected: selection.manualSelectionEnabled,
                    onPressed: composer.toggleManualSelection,
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    selectedIcon: const Icon(Icons.person_add_alt_1),
                  ),
                  TextButton(
                    key: const Key('constellation.composer.details_button'),
                    onPressed: () => unawaited(_openFullForm()),
                    child: Text(
                      composer.kind == BeaconKind.post
                          ? l10n.constellationComposerCreate
                          : l10n.constellationComposerDetails,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: tt.tightGap,
                children: [
                  for (final id in selected)
                    InputChip(
                      key: Key('constellation.composer.chip.$id'),
                      label: Text(_nameOf(id)),
                      deleteButtonTooltipMessage: l10n
                          .constellationComposerRemoveRecipient(_nameOf(id)),
                      deleteIcon: KeyedSubtree(
                        key: Key('constellation.composer.chip_remove.$id'),
                        child: const Icon(Icons.close),
                      ),
                      onDeleted: () => composer.toggle(id),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _nameOf(String id) {
    final candidates = composer.forwardCubit?.state.candidates ?? const [];
    for (final c in candidates) {
      if (c.id == id) return c.profile.displayName;
    }
    return composer.personName?.call(id) ?? id;
  }

  Future<void> _openFullForm() async {
    final handoff = await composer.prepareFullFormHandoff();
    if (handoff == null || composer.isClosed) return;
    onOpenFullForm(
      handoff.toRoute(
        onRecipientsChanged: composer.restoreRecipients,
        onPublished: () => unawaited(composer.finish()),
      ),
    );
  }
}
