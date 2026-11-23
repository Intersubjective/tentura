import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/dialog/qr_scan_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/ui/util/tentura_id_input_formatter.dart';
import 'package:tentura/ui/util/ui_utils.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/invitation/domain/entity/invite_preview.dart';
import 'package:tentura/features/invitation/domain/invite_code.dart';
import 'package:tentura/features/invitation/domain/port/invitation_accept_port.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_accept_dialog.dart';
import 'package:tentura/features/invitation/ui/message/accept_invite_messages.dart';

/// Modal bottom sheet with the same code-entry flow as the former Connect tab.
class ConnectBottomSheet extends StatefulWidget {
  const ConnectBottomSheet({super.key});

  static const _dialogMaxWidth = 480.0;

  static Future<void> show(BuildContext context) {
    return showTenturaAdaptiveSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      showSnackBars: true,
      maxWidth: _dialogMaxWidth,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: const ConnectBottomSheet(),
      ),
    );
  }

  @override
  State<ConnectBottomSheet> createState() => _ConnectBottomSheetState();
}

class _ConnectBottomSheetState extends State<ConnectBottomSheet> {
  final _inputController = TextEditingController();

  final _invitationRepository = GetIt.I<InvitationRepository>();

  late final _l10n = L10n.of(context)!;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return SingleChildScrollView(
      padding: EdgeInsets.all(tt.screenHPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(top: tt.rowGap / 2),
            child: Text(_l10n.writeCodeHere, textAlign: TextAlign.center),
          ),

          // Input
          Padding(
            padding: EdgeInsets.only(top: tt.rowGap),
            child: TextFormField(
              controller: _inputController,
              contextMenuBuilder: (_, state) =>
                  AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: state.contextMenuAnchors,
                    buttonItems: [
                      ContextMenuButtonItem(
                        onPressed: _getCodeFromClipboard,
                        type: ContextMenuButtonType.paste,
                      ),
                    ],
                  ),
              decoration: const InputDecoration(filled: true),
              inputFormatters: const [EntityIdInputFormatter()],
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              textAlign: TextAlign.center,
              maxLength: kIdLength,
            ),
          ),

          // Button (search)
          Padding(
            padding: EdgeInsets.symmetric(vertical: tt.rowGap),
            child: FilledButton(
              child: Text(_l10n.buttonSearch),
              onPressed: () => _goWithCode(_inputController.text),
            ),
          ),

          Padding(
            padding: EdgeInsets.symmetric(vertical: tt.rowGap / 2),
            child: Text(_l10n.labelOr, textAlign: TextAlign.center),
          ),

          // Button (paste)
          Padding(
            padding: EdgeInsets.symmetric(vertical: tt.rowGap),
            // Alternatives to the primary Search are outlined: three filled
            // buttons read as three primaries (UI review).
            child: OutlinedButton.icon(
              onPressed: _getCodeFromClipboard,
              icon: const Icon(Icons.content_paste),
              label: Text(_l10n.buttonPaste),
            ),
          ),

          Padding(
            padding: EdgeInsets.symmetric(vertical: tt.rowGap / 2),
            child: Text(_l10n.labelOr, textAlign: TextAlign.center),
          ),

          // Button (scan qr)
          Padding(
            padding: EdgeInsets.symmetric(vertical: tt.rowGap),
            child: OutlinedButton.icon(
              onPressed: () async {
                final code = await QRScanDialog.show(context);
                if (context.mounted && code != null) {
                  await _goWithCode(code);
                }
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(_l10n.buttonScanQR),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _getCodeFromClipboard() async {
    final code = await GetIt.I<AuthCubit>().getCodeFromClipboard();
    if (!mounted) return;
    _inputController.text = code;
    if (code.length == kIdLength && code.startsWith('I')) {
      await _goWithCode(code);
    }
  }

  Future<void> _goWithCode(String input) async {
    // A scanned QR is the whole share link, not the bare id.
    final code = extractEntityIdFromText(input) ?? input.trim();
    if (code.length != kIdLength) {
      showSnackBar(context, isError: true, text: _l10n.codeLengthError);
      return;
    }

    switch (code[0]) {
      case 'U':
        await GetIt.I<AppNavigator>().openProfile(code);
      case 'B':
        await GetIt.I<AppNavigator>().openBeacon(
          code,
          entry: kBeaconEntryUnknown,
        );
      case 'C':
        await GetIt.I<AppNavigator>().openBeacon(
          code,
          entry: kBeaconEntryUnknown,
        );
      case 'I':
        await _acceptInvite(code);
      default:
        showSnackBar(context, isError: true, text: _l10n.codePrefixError);
    }
  }

  Future<void> _acceptInvite(String code) async {
    try {
      final preview = await _invitationRepository.fetchInvitePreview(code);
      if (!mounted) return;
      if (preview.callerStatus == InviteCallerStatus.isInviter) {
        showSnackBar(
          context,
          text: const InviteOwnInviteMessage().toL10n(_l10n.localeName),
        );
        return;
      }

      final inviter = preview.inviter;
      if (!preview.isAvailable || inviter == null || inviter.id.isEmpty) {
        showSnackBar(context, isError: true, text: _l10n.codeNotFoundError);
        return;
      }

      final request = switch (preview.beacon) {
        final InvitePreviewBeacon beacon when !beacon.isPost => beacon,
        _ => null,
      };
      final confirmed = await InvitationAcceptDialog.show(
        context,
        profile: inviter.toProfile(),
        beacon: request,
      );
      if (!mounted || confirmed != true) return;

      if (request != null) {
        final result = await _invitationRepository.acceptExistingInvite(code);
        if (!mounted ||
            request.lapsed ||
            result == ExistingInviteAcceptance.requestLapsed) {
          return;
        }
        await GetIt.I<AppNavigator>().openBeacon(
          request.id,
          entry: kBeaconEntryInvite,
        );
        return;
      }

      // Preserve the existing acceptance flow for plain and Post invites.
      await _invitationRepository.accept(code);
      if (!mounted) return;
      final navigator = GetIt.I<AppNavigator>();
      final navigation = navigator.openProfile(inviter.id);
      // Present the confirmation after the route push clears transient bars.
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) {
        showSnackBar(
          navigator.rootContext ?? context,
          text: const InviteAcceptedMessage().toL10n(_l10n.localeName),
        );
      }
      await navigation;
    } catch (e) {
      if (!mounted) return;
      showSnackBar(
        context,
        isError: true,
        text: _l10n.errorGenericAction,
        detail: e.toString(),
      );
    }
  }
}
