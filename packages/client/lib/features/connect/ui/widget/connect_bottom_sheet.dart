import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/dialog/qr_scan_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_accept_dialog.dart';

/// Modal bottom sheet with the same code-entry flow as the former Connect tab.
class ConnectBottomSheet extends StatefulWidget {
  const ConnectBottomSheet({super.key});

  static const _dialogMaxWidth = 480.0;

  static Future<void> show(BuildContext context) {
    final windowClass = windowClassForWidth(MediaQuery.sizeOf(context).width);
    if (windowClass == WindowClass.compact) {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: const ConnectBottomSheet(),
        ),
      );
    }

    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final bottomInset = MediaQuery.viewInsetsOf(dialogContext).bottom;
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _dialogMaxWidth),
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: const ConnectBottomSheet(),
            ),
          ),
        );
      },
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
            child: FilledButton(
              onPressed: _getCodeFromClipboard,
              child: Text(_l10n.buttonPaste),
            ),
          ),

          Padding(
            padding: EdgeInsets.symmetric(vertical: tt.rowGap / 2),
            child: Text(_l10n.labelOr, textAlign: TextAlign.center),
          ),

          // Button (scan qr)
          Padding(
            padding: EdgeInsets.symmetric(vertical: tt.rowGap),
            child: FilledButton(
              onPressed: () async {
                final code = await QRScanDialog.show(context);
                if (context.mounted && code != null) {
                  await _goWithCode(code);
                }
              },
              child: Text(_l10n.buttonScanQR),
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

  Future<void> _goWithCode(String code) async {
    if (code.length != kIdLength) {
      showSnackBar(context, isError: true, text: _l10n.codeLengthError);
      return;
    }

    switch (code[0]) {
      case 'U':
        await context.pushRoute(ProfileViewRoute(id: code));
      case 'B':
        await context.pushRoute(
          BeaconViewRoute(id: code, entry: kBeaconEntryUnknown),
        );
      case 'C':
        await context.pushRoute(
          BeaconViewRoute(id: code, entry: kBeaconEntryUnknown),
        );
      case 'I':
        final result = await _invitationRepository.fetchById(code);
        if (mounted) {
          if (result == null) {
            showSnackBar(context, isError: true, text: _l10n.codeNotFoundError);
          } else if (await InvitationAcceptDialog.show(
                context,
                profile: result.issuer,
              ) ??
              false) {
            // TBD: tell reason enum
            await _invitationRepository.accept(code);
            if (mounted) {
              // TBD: l10n
              showSnackBar(context, text: 'Invitation accepted!');
              await context.pushRoute(ProfileViewRoute(id: result.issuer.id));
            }
          }
        }
      default:
        showSnackBar(context, isError: true, text: _l10n.codePrefixError);
    }
  }
}
