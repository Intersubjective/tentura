import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/constellation_field.dart';

/// Bottom panel of the tag lens: "{tags} · N people · M Requests" and the way
/// to forward one of the viewer's Requests to the selected tags.
class ConstellationTagLensPanel extends StatelessWidget {
  const ConstellationTagLensPanel({
    required this.tagNames,
    required this.peopleCount,
    required this.requestCount,
    required this.onForward,
    this.onOpenTagView,
    super.key,
  });

  final List<String> tagNames;
  final int peopleCount;
  final int requestCount;
  final VoidCallback onForward;

  /// Opens the tag view; null where it is not offered.
  final VoidCallback? onOpenTagView;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.all(tt.rowGap),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: TenturaSpacing.listPaneWidth,
          ),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tt.cardRadius),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tt.screenHPadding,
                vertical: tt.tightGap,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      l10n.constellationTagLensSummary(
                        tagNames.join(', '),
                        peopleCount,
                        requestCount,
                      ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Wrap(
                      children: [
                        if (onOpenTagView != null)
                          TextButton(
                            onPressed: onOpenTagView,
                            child: Text(l10n.constellationTagViewOpen),
                          ),
                        TextButton(
                          onPressed: onForward,
                          child: Text(l10n.constellationTagLensForward),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets the viewer pick one of [requests]; null when dismissed.
Future<ConstellationRequest?> showConstellationTagLensRequestPicker(
  BuildContext context,
  List<ConstellationRequest> requests,
) => showModalBottomSheet<ConstellationRequest>(
  context: context,
  showDragHandle: true,
  builder: (context) {
    final l10n = L10n.of(context)!;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(
              l10n.constellationTagLensPickRequest,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (requests.isEmpty)
            ListTile(title: Text(l10n.constellationTagLensNoRequests))
          else
            for (final request in requests)
              ListTile(
                title: Text(request.title),
                onTap: () => Navigator.of(context).pop(request),
              ),
        ],
      ),
    );
  },
);
