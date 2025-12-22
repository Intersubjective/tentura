import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'package:tentura_server/domain/entity/user_entity.dart';

import 'avatar_component.dart';

class InvitationViewComponent extends StatelessComponent {
  const InvitationViewComponent({
    required this.user,
  });

  final UserEntity user;

  @override
  Component build(BuildContext context) => section(
    [
      AvatarComponent(user: user),

      if (user.description.isNotEmpty)
        const p(
          [
            Component.text('Invite you to join Tentura!'),
          ],
        ),
    ],
  );
}
