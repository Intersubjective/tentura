import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/phantoms/data/repository/private_avatar_repository.dart';
import 'package:tentura/features/phantoms/domain/entity/phantom_import.dart';
import 'package:tentura/features/phantoms/domain/port/phantom_repository_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../data/repository/contact_import_operation_store.dart';
import '../../data/service/contact_import_file.dart';
import '../../domain/use_case/contact_import_case.dart';
import '../bloc/contact_import_cubit.dart';

Future<void> showContactImportSheet(
  BuildContext context, {
  required String accountId,
  required Iterable<String> Function() namesOnMap,
  required Future<void> Function() onImported,
}) async {
  final contacts = await pickContactFile();
  if (!context.mounted || contacts == null) return;
  final operations = ContactImportOperationStore(accountId);
  final import = ContactImportCase(
    GetIt.I<PhantomRepositoryPort>(),
    runOperation: operations.run,
    preparePhoto: prepareContactAvatar,
    uploadPhoto: const PrivateAvatarRepository().upload,
  );
  final onMap = namesOnMap().map(ContactImportRow.foldName).toSet();
  await showTenturaAdaptiveSheet<void>(
    context: context,
    limitCompactHeight: true,
    builder: (_) => BlocProvider(
      create: (_) => ContactImportCubit(import, contacts),
      child: _ContactImportSheet(onMap: onMap, onImported: onImported),
    ),
  );
}

class _ContactImportSheet extends StatelessWidget {
  const _ContactImportSheet({required this.onMap, required this.onImported});

  final Set<String> onMap;
  final Future<void> Function() onImported;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    final cubit = context.read<ContactImportCubit>();
    final state = context.watch<ContactImportCubit>().state;
    final visible = [
      for (final (index, row) in state.rows.indexed)
        if (ContactImportRow.foldName(row.name).contains(state.query)) index,
    ];
    return PopScope(
      canPop: !state.busy,
      child: Padding(
        padding: tt.cardPadding,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.contactImportEntry,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: l10n.buttonClose,
                  onPressed: state.busy
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            TextField(
              decoration: InputDecoration(
                hintText: l10n.contactImportSearch,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: cubit.search,
            ),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: Text(l10n.contactImportUsePhoto),
                          value: state.usePhoto,
                          onChanged: state.canEdit ? cubit.setUsePhoto : null,
                        ),
                        SwitchListTile(
                          title: Text(l10n.contactImportKeepDetails),
                          value: state.keepContacts,
                          onChanged: state.canEdit
                              ? cubit.setKeepContacts
                              : null,
                        ),
                      ],
                    ),
                  ),
                  if (visible.isEmpty)
                    SliverToBoxAdapter(
                      child: Text(
                        state.rows.isEmpty
                            ? l10n.contactImportEmptyFile
                            : l10n.contactImportNoMatches,
                      ),
                    ),
                  SliverList.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, position) {
                      final index = visible[position];
                      final row = state.rows[index];
                      return _ContactRow(
                        key: ValueKey(index),
                        row: row,
                        onMap:
                            row.created ||
                            onMap.contains(ContactImportRow.foldName(row.name)),
                        onSelected: state.canEdit && !row.created
                            ? (value) =>
                                  cubit.select(index, selected: value ?? false)
                            : null,
                        onEdited: state.canEdit && !row.created
                            ? (name) => cubit.rename(index, name)
                            : null,
                      );
                    },
                  ),
                ],
              ),
            ),
            if (state.status == ContactImportStatus.retry)
              Text(l10n.contactImportFailed),
            if (state.busy) const LinearProgressIndicator(),
            FilledButton(
              onPressed: state.canSubmit
                  ? () async {
                      if (await cubit.submit()) await onImported();
                    }
                  : null,
              child: Text(l10n.contactImportAction),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.row,
    required this.onMap,
    required this.onSelected,
    required this.onEdited,
    super.key,
  });

  final ContactImportRow row;
  final bool onMap;
  final ValueChanged<bool?>? onSelected;
  final ValueChanged<String>? onEdited;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    final statusStyle = Theme.of(context).textTheme.bodySmall;
    final outcomeMessage = switch (row.outcome) {
      PhantomImportCreated(alreadyOnTentura: true) =>
        l10n.contactImportAlreadyOnTentura,
      PhantomImportCreated(alreadyOnTentura: null)
          when row.source.emails.firstOrNull?.trim().isNotEmpty == true =>
        l10n.contactImportCheckLimitReached,
      PhantomImportRefused(
        message: 'Remove someone not on Tentura yet first.',
      ) =>
        l10n.contactImportCapReached,
      PhantomImportRefused() => l10n.contactImportRowRefused,
      _ => null,
    };
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tt.tightGap),
      child: Row(
        children: [
          Checkbox(value: row.selected, onChanged: onSelected),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (row.needsEditor)
                  TextFormField(
                    initialValue: row.name,
                    enabled: onEdited != null,
                    decoration: InputDecoration(
                      labelText: l10n.personCreateName,
                    ),
                    onChanged: onEdited,
                  )
                else
                  Text(row.name),
                if (!row.hasValidName)
                  Text(
                    l10n.contactImportShortName(kTitleMinLength),
                    style: statusStyle,
                  ),
                if (onMap) Text(l10n.contactImportOnMap, style: statusStyle),
                if (outcomeMessage != null)
                  Text(outcomeMessage, style: statusStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
