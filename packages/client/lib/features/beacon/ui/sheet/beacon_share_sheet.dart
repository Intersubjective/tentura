import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/features/invitation/ui/bloc/invitation_cubit.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_addressee_dialog.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_remove_dialog.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Lists pending beacon invites, creates/regenerates codes, shares QR links.
Future<void> showBeaconShareSheet(
  BuildContext context, {
  required Beacon beacon,
}) async {
  if (!beacon.allowsForward) return;
  await showTenturaAdaptiveSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (_) => _BeaconShareSheet(beacon: beacon),
  );
}

class _BeaconShareSheet extends StatefulWidget {
  const _BeaconShareSheet({required this.beacon});

  final Beacon beacon;

  @override
  State<_BeaconShareSheet> createState() => _BeaconShareSheetState();
}

class _BeaconShareSheetState extends State<_BeaconShareSheet> {
  late final InvitationCubit _invitationCubit;

  @override
  void initState() {
    super.initState();
    _invitationCubit = InvitationCubit();
    unawaited(_invitationCubit.fetch());
  }

  @override
  void dispose() {
    unawaited(_invitationCubit.close());
    super.dispose();
  }

  List<InvitationEntity> _pendingForBeacon(InvitationState state) => state
      .invitations
      .where(
        (i) =>
            i.beaconId == widget.beacon.id &&
            (i.invitedId == null || i.invitedId!.isEmpty),
      )
      .toList();

  Future<void> _shareInvitation(
    BuildContext context,
    InvitationEntity invitation,
    L10n l10n,
  ) async {
    await ShareCodeDialog.show(
      context,
      header: l10n.labelInvitationCode,
      link: inviteShareUri(invitation.id),
    );
  }

  Future<void> _createInvite(BuildContext context, L10n l10n) async {
    final addresseeName = await InvitationAddresseeDialog.show(context);
    if (addresseeName == null || !context.mounted) return;
    final invitation = await _invitationCubit.createInvitation(
      addresseeName: addresseeName,
      beaconId: widget.beacon.id,
    );
    if (invitation == null || !context.mounted) return;
    await _shareInvitation(context, invitation, l10n);
    if (!context.mounted) return;
    showSnackBar(context, text: l10n.forwardInviteCreatedHint);
  }

  Future<void> _regenerateInvite(
    BuildContext context,
    InvitationEntity invitation,
    L10n l10n,
  ) async {
    final addressee = invitation.addresseeName ?? '';
    if (await InvitationRemoveDialog.show(context) != true) return;
    await _invitationCubit.deleteInvitationById(invitation.id);
    if (!context.mounted) return;
    final created = await _invitationCubit.createInvitation(
      addresseeName: addressee.isEmpty ? invitation.id : addressee,
      beaconId: widget.beacon.id,
    );
    if (created == null || !context.mounted) return;
    await _shareInvitation(context, created, l10n);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt = context.tt;
    final title = widget.beacon.title.isEmpty
        ? l10n.beaconViewTitle
        : widget.beacon.title;

    return BlocProvider.value(
      value: _invitationCubit,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return Material(
            color: scheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    tt.screenHPadding,
                    tt.sectionGap,
                    tt.screenHPadding,
                    tt.rowGap,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.beaconShareSheetTitle,
                        style: theme.textTheme.titleLarge,
                      ),
                      SizedBox(height: tt.tightGap),
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: BlocBuilder<InvitationCubit, InvitationState>(
                    bloc: _invitationCubit,
                    buildWhen: (_, c) => c.isSuccess || c.isLoading,
                    builder: (context, state) {
                      final pending = _pendingForBeacon(state);
                      return ListView(
                        controller: scrollController,
                        padding: EdgeInsets.fromLTRB(
                          tt.screenHPadding,
                          0,
                          tt.screenHPadding,
                          tt.sectionGap,
                        ),
                        children: [
                          if (state.isLoading && pending.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(
                                child: CircularProgressIndicator.adaptive(),
                              ),
                            )
                          else if (pending.isEmpty)
                            Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: tt.sectionGap,
                              ),
                              child: Text(
                                l10n.beaconShareNoPendingInvites,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            )
                          else
                            ...pending.map(
                              (invitation) {
                                final addressee = invitation.addresseeName;
                                final name =
                                    addressee == null || addressee.isEmpty
                                    ? invitation.id
                                    : addressee;
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(name),
                                  subtitle: Text(
                                    compactRelativeTimeAgo(
                                      when: invitation.createdAt,
                                      now: DateTime.now(),
                                      l10n: l10n,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    tooltip: l10n.beaconShareRegenerateInvite,
                                    icon: const Icon(Icons.refresh),
                                    onPressed: () => unawaited(
                                      _regenerateInvite(
                                        context,
                                        invitation,
                                        l10n,
                                      ),
                                    ),
                                  ),
                                  onTap: () => unawaited(
                                    _shareInvitation(
                                      context,
                                      invitation,
                                      l10n,
                                    ),
                                  ),
                                );
                              },
                            ),
                          SizedBox(height: tt.sectionGap),
                          FilledButton.icon(
                            icon: const Icon(Icons.add),
                            label: Text(l10n.beaconShareCreateInvite),
                            onPressed: state.isLoading
                                ? null
                                : () => unawaited(_createInvite(context, l10n)),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
