import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/ui/dialog/qr_scan_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_accept_dialog.dart';

@RoutePage()
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _inputController = TextEditingController();

  final _invitationRepository = GetIt.I<InvitationRepository>();

  late final _l10n = L10n.of(context)!;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      minimum: kPaddingAll,
      child: Padding(
        padding: kPaddingAll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: kPaddingSmallT,
              child: Text(_l10n.writeCodeHere, textAlign: TextAlign.center),
            ),

            // Input
            Padding(
              padding: kPaddingT,
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
              padding: kPaddingV,
              child: FilledButton(
                child: Text(_l10n.buttonSearch),
                onPressed: () => _goWithCode(_inputController.text),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(vertical: kSpacingSmall),
              child: Text(_l10n.labelOr, textAlign: TextAlign.center),
            ),

            // Button (paste)
            Padding(
              padding: kPaddingV,
              child: FilledButton(
                onPressed: _getCodeFromClipboard,
                child: Text(_l10n.buttonPaste),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(vertical: kSpacingSmall),
              child: Text(_l10n.labelOr, textAlign: TextAlign.center),
            ),

            // Button (scan qr)
            Padding(
              padding: kPaddingV,
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
      ),
    ),
  );

  Future<void> _getCodeFromClipboard() async =>
      _inputController.text = await GetIt.I<AuthCubit>().getCodeFromClipboard();

  Future<void> _goWithCode(String code) async {
    if (code.length != kIdLength) {
      showSnackBar(context, isError: true, text: _l10n.codeLengthError);
      return;
    }

    switch (code[0]) {
      case 'U':
        await context.pushRoute(ProfileViewRoute(id: code));

      case 'B':
        await context.pushRoute(BeaconViewRoute(id: code));

      case 'C':
        await context.pushRoute(BeaconViewRoute(id: code));

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
