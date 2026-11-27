import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/util/share_link.dart';

import '../../domain/entity/phantom.dart';
import '../../domain/port/phantom_repository_port.dart';

String? phantomInviteAge(Phantom person, DateTime now, L10n l10n) {
  final sentAt = person.inviteCreatedAt;
  if (person.inviteState != PhantomInviteState.live || sentAt == null) {
    return null;
  }
  return l10n.personPanelInviteAge(math.max(0, now.difference(sentAt).inDays));
}

Future<void> copyPhantomInviteLink(
  BuildContext context, {
  required String id,
  bool rotate = false,
}) async {
  final repository = GetIt.I<PhantomRepositoryPort>();
  final code = rotate
      ? await repository.inviteRotate(id: id)
      : await repository.inviteEnsure(id: id);
  if (context.mounted) {
    await copyShareLink(context, link: inviteShareUri(code).toString());
  }
}

Future<void> sharePlaceholderRequest(
  BuildContext context, {
  required String phantomId,
  required String beaconId,
  String? note,
}) async {
  final link = await GetIt.I<PhantomRepositoryPort>().forwardRequest(
    phantomId: phantomId,
    beaconId: beaconId,
    note: note,
  );
  if (!context.mounted) return;
  await ShareCodeDialog.show(
    context,
    header: L10n.of(context)!.forwardInviteDialogTitle,
    link: link,
  );
}

Future<String?> pickPlaceholderForwardItem(
  BuildContext context, {
  required String title,
  required String empty,
  required List<({String id, String name})> items,
  Widget? input,
}) => showTenturaAdaptiveSheet<String>(
  context: context,
  builder: (context) {
    final tt = context.tt;
    return Padding(
      padding: tt.cardPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: tt.rowGap),
          if (items.isEmpty)
            Text(empty)
          else ...[
            ?input,
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    title: Text(item.name),
                    onTap: () => Navigator.of(context).pop(item.id),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  },
);
