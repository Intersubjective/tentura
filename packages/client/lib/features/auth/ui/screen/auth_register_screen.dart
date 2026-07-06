import 'dart:async';
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/invitation/domain/invite_code.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/string_input_validator.dart';
import 'package:tentura/ui/utils/tentura_id_input_formatter.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import '../bloc/auth_cubit.dart';
import '../bloc/register_invite_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import '../widget/auth_form_field.dart';

@RoutePage()
class AuthRegisterScreen extends StatefulWidget implements AutoRouteWrapper {
  const AuthRegisterScreen({
    @PathParam('id') this.id = '',
    @QueryParam(kQueryIsDeepLink) this.isDeepLink,
    super.key,
  });

  final String id;

  final String? isDeepLink;

  @override
  State<AuthRegisterScreen> createState() => _AuthRegisterScreenState();

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
    create: (_) => GetIt.I<RegisterInviteCubit>(),
    child: this,
  );
}

class _AuthRegisterScreenState extends State<AuthRegisterScreen>
    with StringInputValidator {
  final _env = GetIt.I<Env>();

  final _authCubit = GetIt.I<AuthCubit>();

  final _formKey = GlobalKey<FormState>();

  final _codeController = TextEditingController();

  final _titleController = TextEditingController();

  final _handleController = TextEditingController();

  late final _textTheme = Theme.of(context).textTheme;

  late final _l10n = L10n.of(context)!;

  @override
  void initState() {
    super.initState();
    final invitationId = normalizeInviteCode(widget.id);
    if (invitationId.isNotEmpty) {
      _codeController.text = invitationId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(context.read<RegisterInviteCubit>().load(invitationId));
      });
    } else {
      unawaited(_getCodeFromClipboard(supressError: true));
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _titleController.dispose();
    _handleController.dispose();
    super.dispose();
  }

  void _onAuthStateChanged(AuthState auth) {
    if (!auth.isAuthenticated || auth.isLoading) return;
    final preview = context.read<RegisterInviteCubit>().state.preview;
    final beacon = preview?.beacon;
    if (beacon == null || beacon.id.isEmpty) return;
    GetIt.I<PostJoinNavigationCubit>().setFromBeaconInvite(
      beaconId: beacon.id,
      beaconTitle: beacon.title,
      inviterName: preview?.inviter?.displayName ?? '',
      showSnackbar: true,
    );
  }

  @override
  Widget build(BuildContext context) => BlocListener<AuthCubit, AuthState>(
    bloc: _authCubit,
    listenWhen: (prev, curr) =>
        !prev.isAuthenticated && curr.isAuthenticated && !curr.isLoading,
    listener: (_, auth) => _onAuthStateChanged(auth),
    child: Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(_l10n.createNewAccount),
        leading: const AutoLeadingButton(),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: BlocSelector<AuthCubit, AuthState, bool>(
            key: Key('Loader:${_authCubit.hashCode}'),
            selector: (state) => state.isLoading,
            builder: LinearPiActive.builder,
            bloc: _authCubit,
          ),
        ),
      ),
      body: TenturaContentColumn(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Invite Code
              if (_env.needInviteCode)
                AuthFormField(
                  child: TextFormField(
                    // Do NOT autofocus when the id is pre-filled from a deep link.
                    // On iOS, autofocus during cold-start (e.g. QR-code launch) fires
                    // while UIKit still rejects firstResponder requests; Flutter marks
                    // the field as focused but the keyboard never appears, breaking
                    // all subsequent taps on any field for the rest of the session.
                    autofocus: widget.id.trim().isEmpty,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    controller: _codeController,
                    contextMenuBuilder: (_, state) =>
                        AdaptiveTextSelectionToolbar.buttonItems(
                          anchors: state.contextMenuAnchors,
                          buttonItems: [
                            ContextMenuButtonItem(
                              type: ContextMenuButtonType.paste,
                              onPressed: _getCodeFromClipboard,
                            ),
                          ],
                        ),

                    decoration: InputDecoration(
                      hintText: _l10n.pleaseEnterCode,
                      labelText: _l10n.labelInvitationCode,
                      suffix: IconButton(
                        tooltip: _l10n.buttonPaste,
                        constraints: const BoxConstraints(
                          minWidth: kMinInteractiveDimension,
                          minHeight: kMinInteractiveDimension,
                        ),
                        onPressed: _getCodeFromClipboard,
                        icon: const Icon(Icons.paste_rounded),
                      ),
                    ),
                    maxLength: kIdLength,
                    keyboardType: TextInputType.text,
                    style: _textTheme.headlineLarge,
                    inputFormatters: const [
                      InviteCodeInputFormatter(),
                    ],
                    validator: (text) => invitationCodeValidator(_l10n, text),
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    onChanged: (value) {
                      if (value.trim().length >= kIdLength) {
                        unawaited(
                          context.read<RegisterInviteCubit>().load(value),
                        );
                      }
                    },
                  ),
                ),

              // Username
              AuthFormField(
                child: TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _titleController,
                  decoration: InputDecoration(
                    hintText: _l10n.pleaseFillDisplayName,
                    labelText: _l10n.labelDisplayName,
                  ),
                  maxLength: kTitleMaxLength,
                  style: _textTheme.headlineLarge,
                  validator: (text) => displayNameValidator(_l10n, text),
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                ),
              ),

              // Handle (optional)
              AuthFormField(
                child: TextFormField(
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _handleController,
                  decoration: InputDecoration(
                    hintText: _l10n.userHandleHint,
                    labelText: _l10n.labelUserHandle,
                  ),
                  maxLength: kUserHandleMaxLength,
                  keyboardType: TextInputType.text,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[a-z0-9_]')),
                  ],
                  validator: (text) {
                    final t = (text ?? '').trim().toLowerCase();
                    if (t.isEmpty) return null;
                    if (!isValidUserHandleFormat(t)) {
                      return _l10n.userHandleInvalidFormat;
                    }
                    return null;
                  },
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                ),
              ),

              // Register
              AuthFormField(
                child: BlocSelector<AuthCubit, AuthState, bool>(
                  bloc: _authCubit,
                  selector: (state) => state.isLoading,
                  builder: (context, isLoading) => FilledButton(
                    onPressed: isLoading ? null : _submitSignUp,
                    child: Text(_l10n.buttonCreate),
                  ),
                ),
              ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  void _submitSignUp() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    unawaited(
      _authCubit.signUp(
        invitationCode: normalizeInviteCode(_codeController.text),
        displayName: _titleController.text,
        handle: _handleController.text.trim().toLowerCase().isEmpty
            ? null
            : _handleController.text.trim().toLowerCase(),
      ),
    );
  }

  Future<void> _getCodeFromClipboard({
    bool supressError = false,
  }) async {
    final code = await _authCubit.getInvitationCodeFromClipboard(
      supressError: supressError,
    );
    if (code.isNotEmpty) {
      _codeController.text = code;
      if (mounted) {
        unawaited(context.read<RegisterInviteCubit>().load(code));
      }
    }
  }
}
