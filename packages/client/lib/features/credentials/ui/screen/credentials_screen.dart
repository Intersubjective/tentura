import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../domain/entity/credential_entity.dart';
import '../bloc/credentials_cubit.dart';

@RoutePage()
class CredentialsScreen extends StatelessWidget implements AutoRouteWrapper {
  const CredentialsScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
    create: (_) => GetIt.I<CredentialsCubit>(),
    child: this,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.signInMethods)),
      body: BlocConsumer<CredentialsCubit, CredentialsState>(
        listener: commonScreenBlocListener,
        builder: (context, state) {
          if (state.credentials.isEmpty) {
            return Center(
              child: Padding(
                padding: kPaddingAll,
                child: Text(
                  state.isLoading ? '' : l10n.signInMethodsEmpty,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: kPaddingV,
            itemCount: state.credentials.length,
            separatorBuilder: separatorBuilder,
            itemBuilder: (context, index) {
              final credential = state.credentials[index];
              return ListTile(
                leading: const Icon(Icons.key_outlined),
                title: Text(_typeLabel(l10n, credential.type)),
                subtitle: Text(_subtitle(credential)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l10n.buttonRemove,
                  onPressed: () => _confirmRemove(context, l10n, credential),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    L10n l10n,
    CredentialEntity credential,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.removeCredentialTitle),
        content: Text(l10n.removeCredentialBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.buttonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.buttonRemove),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && context.mounted) {
      await context.read<CredentialsCubit>().remove(credential.id);
    }
  }

  String _typeLabel(L10n l10n, String type) => switch (type) {
    'ed25519_device' => l10n.credentialDeviceKey,
    _ => type,
  };

  String _subtitle(CredentialEntity credential) {
    final identifier = credential.identifier.length > 16
        ? '${credential.identifier.substring(0, 16)}…'
        : credential.identifier;
    final created = credential.createdAt;
    return created == null
        ? identifier
        : '$identifier · ${created.toLocal().toString().split(' ').first}';
  }
}
