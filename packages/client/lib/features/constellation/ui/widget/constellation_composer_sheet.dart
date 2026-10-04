import 'dart:math' as math;

import 'package:auto_route/auto_route.dart' show PageRouteInfo;
import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/radius_recipient_selection.dart';
import '../bloc/constellation_composer_cubit.dart';

/// Recipient controls of the graph composer: «Получат · n», chips with ×, the
/// radius slider and «Списком ›».
///
/// A bottom sheet on narrow layouts, a side panel on wide ones.
class ConstellationComposerSheet extends StatelessWidget {
  const ConstellationComposerSheet({
    required this.composer,
    required this.onOpenFullForm,
    super.key,
  });

  final ConstellationComposerCubit composer;

  /// Receives the full-form route for «Подробнее».
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
                    child: Text(l10n.constellationComposerDetails),
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
              Text(l10n.constellationComposerRadius),
              Slider(
                key: const Key('constellation.composer.radius_slider'),
                max: _maxRadius(selection),
                value: selection.radius.clamp(0, _maxRadius(selection)),
                label: l10n.constellationComposerRadius,
                onChanged: composer.setRadius,
              ),
            ],
          ),
        );
      },
    );
  }

  /// The farthest eligible person's distance with some room; stable while the
  /// slider moves, so the thumb does not slide under the pointer.
  double _maxRadius(RadiusRecipientSelection selection) {
    final farthest = selection.positions.entries
        .where((e) => selection.eligible.contains(e.key))
        .map((e) => (e.value - selection.center).distance)
        .fold<double>(0, math.max);
    return math.max(
      math.max(farthest * 1.1, kComposerMinRadius),
      selection.radius,
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
    if (handoff != null) widget.onOpenFullForm(handoff.toRoute());
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
