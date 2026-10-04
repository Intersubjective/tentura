import 'dart:async';

import 'package:auto_route/auto_route.dart' show PageRouteInfo;
import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/radius_recipient_selection.dart';
import '../bloc/constellation_composer_cubit.dart';

/// Recipient controls of the graph composer: «Получат · n», chips with ×, and
/// «Списком ›». The radius itself is controlled on the canvas (the composer
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

class _SheetBody extends StatefulWidget {
  const _SheetBody({required this.composer, required this.onOpenFullForm});

  final ConstellationComposerCubit composer;

  final ValueChanged<PageRouteInfo> onOpenFullForm;

  @override
  State<_SheetBody> createState() => _SheetBodyState();
}

class _SheetBodyState extends State<_SheetBody> {
  bool _listOpen = false;

  ConstellationComposerCubit get composer => widget.composer;

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
                  TextButton(
                    key: const Key('constellation.composer.list_button'),
                    onPressed: _toggleList,
                    child: Text(l10n.constellationComposerList),
                  ),
                  TextButton(
                    key: const Key('constellation.composer.details_button'),
                    onPressed: _openFullForm,
                    child: Text(
                      composer.kind == BeaconKind.post
                          ? l10n.constellationComposerCreate
                          : l10n.constellationComposerDetails,
                    ),
                  ),
                ],
              ),
              if (!_listOpen)
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
              if (_listOpen) _list(context),
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
    return id;
  }

  void _openFullForm() {
    final handoff = composer.fullFormHandoff();
    if (handoff == null) return;
    // A Post has no draft continuity into its full screen — close the
    // composer so the circle/sheet do not linger over an abandoned draft.
    if (composer.kind == BeaconKind.post) {
      unawaited(composer.finish());
    }
    widget.onOpenFullForm(handoff.toRoute());
  }

  void _toggleList() {
    if (composer.forwardCubit == null) return;
    setState(() => _listOpen = !_listOpen);
  }

  /// The embedded picker on the composer's own [ForwardCubit]; row toggles go
  /// through the radius selection.
  Widget _list(BuildContext context) {
    final forward = composer.forwardCubit!;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: BlocProvider<ForwardCubit>.value(
        value: forward,
        child: ForwardRecipientPicker(
          beaconId: forward.state.beaconId,
          embedded: true,
          onToggle: composer.toggle,
        ),
      ),
    );
  }
}
