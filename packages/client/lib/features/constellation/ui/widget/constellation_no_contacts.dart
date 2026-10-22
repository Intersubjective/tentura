import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/constellation_field.dart';
import '../bloc/constellation_cubit.dart';

/// True when the loaded field holds nobody but the viewer (#252).
///
/// The field always carries the viewer's direct contacts (#246), so an empty
/// field means the viewer has not added anyone yet.
bool constellationFieldHasNoContacts(
  ConstellationField field,
  String viewerId,
) => field.peers.every((p) => p.id == viewerId);

/// People › Invitations, where a new invite link is made.
void _openInvitations() => unawaited(GetIt.I<RootRouter>().openInvitations());

/// Map-surface banner for a field with nobody on it but the viewer (#252):
/// what is missing, why trust matters, and an invite.
class ConstellationNoContactsBanner extends StatelessWidget {
  const ConstellationNoContactsBanner({this.onInvite, super.key});

  static const bannerKey = Key('constellation.no_contacts');
  static const inviteKey = Key('constellation.no_contacts.invite');

  /// Defaults to opening People › Invitations.
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConstellationCubit, ConstellationState>(
      buildWhen: (previous, current) =>
          previous.field != current.field ||
          previous.viewMode != current.viewMode,
      builder: (context, state) {
        final field = state.field;
        final cubit = context.read<ConstellationCubit>();
        if (field == null ||
            state.viewMode != ConstellationViewMode.map ||
            !constellationFieldHasNoContacts(field, cubit.viewerId)) {
          return const SizedBox.shrink();
        }
        final l10n = L10n.of(context)!;
        final tt = context.tt;
        final scheme = Theme.of(context).colorScheme;
        return Material(
          key: bannerKey,
          color: scheme.surfaceContainerHighest,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tt.screenHPadding,
              vertical: tt.rowGap,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.constellationNoContactsTitle,
                  style: TenturaText.titleSmall(scheme.onSurface),
                ),
                SizedBox(height: tt.tightGap),
                Text(
                  l10n.trustWidensReachHint,
                  style: TenturaText.bodySmall(scheme.onSurfaceVariant),
                ),
                SizedBox(height: tt.tightGap),
                TextButton.icon(
                  key: inviteKey,
                  onPressed: onInvite ?? _openInvitations,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(l10n.emptyInviteSomeoneAction),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// List-view empty state for a field with nobody on it but the viewer.
class ConstellationNoContactsEmptyState extends StatelessWidget {
  const ConstellationNoContactsEmptyState({this.onInvite, super.key});

  static const emptyKey = Key('constellation.text.no_contacts');

  /// Defaults to opening People › Invitations.
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return TenturaEmptyState(
      key: emptyKey,
      icon: Icons.group_add_outlined,
      title: l10n.constellationNoContactsTitle,
      body: l10n.trustWidensReachHint,
      actionLabel: l10n.emptyInviteSomeoneAction,
      onAction: onInvite ?? _openInvitations,
    );
  }
}
