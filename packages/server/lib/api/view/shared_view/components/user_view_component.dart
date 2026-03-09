import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'package:tentura_server/domain/entity/user_entity.dart';

import 'avatar_component.dart';

class UserViewComponent extends StatelessComponent {
  const UserViewComponent({
    required this.user,
  });

  final UserEntity user;

  @override
  Component build(BuildContext context) => section(
    [
      AvatarComponent(user: user),

      if (user.description.isNotEmpty)
        p(
          [
            Component.text(user.description),
          ],
        ),
    ],
  );
}
