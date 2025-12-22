import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'package:tentura_server/domain/entity/user_entity.dart';

import '../shared_view_styles.dart';

class AvatarComponent extends StatelessComponent {
  const AvatarComponent({
    required this.user,
    this.size = 80,
  });

  final UserEntity user;

  final int size;

  @override
  Component build(BuildContext context) => fragment([
    // Avatar
    img(
      src: user.imageUrl,
      alt: 'avatar',
      height: size,
      width: size,
      styles: const Styles(
        radius: BorderRadius.circular(Unit.percent(50)),
        shadow: BoxShadow(
          offsetX: Unit.zero,
          offsetY: Unit.zero,
          blur: kEdgeInsetsM,
          spread: kEdgeInsetsS,
          color: Color.variable(kShadowColorVarName),
        ),

        raw: {
          'object-fit': 'cover',
        },
      ),
    ),

    // Title
    h3(
      [
        text(user.title),
      ],
    ),
  ]);
}
