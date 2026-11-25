import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
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
