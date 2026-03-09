import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'package:tentura_server/domain/entity/opinion_entity.dart';
import 'package:tentura_server/utils/format_date.dart';

import '../shared_view_styles.dart';
import 'avatar_component.dart';

class OpinionViewComponent extends StatelessComponent {
  const OpinionViewComponent({
    required this.opinion,
  });

  final OpinionEntity opinion;

  @override
  Component build(BuildContext context) => section(
    [
      // Avatar
      AvatarComponent(user: opinion.author),

      // Opinion text
      p(
        styles: const Styles(
          margin: Spacing.only(bottom: kEdgeInsetsS),
        ),
        [
          Component.text(opinion.content),
        ],
      ),

      // Date
      small(
        [
          Component.text(formatDate(opinion.createdAt)),
        ],
      ),
    ],
  );
}
