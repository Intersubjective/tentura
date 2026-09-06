import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';

/// A separate footer attached to the parent's promoted source message,
/// pointing at the promoted child (plan §6.2). Never a faux source-author
/// message or a duplicate inline request card. Resolves the child through
/// an ordinary, guarded single-beacon read — an inaccessible or deleted
/// child renders a safe, non-leaking state (no title/avatar/body), never
/// an error. Reflects current state reactively; never caches across a
/// changed [childBeaconId].
class BeaconChildPromotionFooter extends StatefulWidget {
  const BeaconChildPromotionFooter({required this.childBeaconId, super.key});

  final String childBeaconId;

  @override
  State<BeaconChildPromotionFooter> createState() =>
      _BeaconChildPromotionFooterState();
}

class _BeaconChildPromotionFooterState
    extends State<BeaconChildPromotionFooter> {
  late Future<Beacon?> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant BeaconChildPromotionFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childBeaconId != widget.childBeaconId) {
      _load();
    }
  }

  void _load() {
    _future = GetIt.I<BeaconWritePort>()
        .fetchBeaconById(widget.childBeaconId)
        .then<Beacon?>((b) => b)
        .catchError((Object _) => null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return FutureBuilder<Beacon?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final beacon = snapshot.data;
        if (beacon == null) {
          return Semantics(
            container: true,
            label: l10n.beaconChildFooterUnavailable,
            child: BeaconCardShell(
              muted: true,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: tt.tightGap),
                child: Text(
                  l10n.beaconChildFooterUnavailable,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }
        final title = beacon.title.trim().isNotEmpty
            ? beacon.title.trim()
            : l10n.beaconUntitled;
        return BeaconCardShell(
          onTap: () => context.router.push(BeaconViewRoute(id: beacon.id)),
          tapSemanticsLabel: title,
          child: Row(
            children: [
              Icon(
                Icons.subdirectory_arrow_right,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              SizedBox(width: tt.iconTextGap),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
