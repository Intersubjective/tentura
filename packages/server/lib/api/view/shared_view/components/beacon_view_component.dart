import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/utils/format_date.dart';

import 'avatar_component.dart';

class BeaconViewComponent extends StatelessComponent {
  const BeaconViewComponent({
    required this.beacon,
  });

  final BeaconEntity beacon;

  @override
  Component build(BuildContext context) => Component.fragment([
    img(
      src: beacon.imageUrl,
      alt: 'beacon image',
    ),
    section(
      styles: const Styles(
        margin: Spacing.only(top: Unit.pixels(-68)),
      ),
      [
        // Avatar
        AvatarComponent(user: beacon.author),

        // Title
        h4(
          [
            Component.text(beacon.title),
          ],
        ),

        if (beacon.description.isNotEmpty)
          p(
            [
              Component.text(beacon.description),
            ],
          ),

        if (beacon.coordinates != null)
          small(
            [
              Component.text(beacon.coordinates.toString()),
              const br(),
            ],
          ),

        if (beacon.startAt != null)
          small(
            [
              Component.text('from ${formatDate(beacon.startAt)}'),
              if (beacon.endAt != null) const Component.text(', '),
            ],
          ),

        if (beacon.endAt != null)
          small(
            [
              Component.text('until ${formatDate(beacon.endAt)}'),
            ],
          ),
      ],
    ),
  ]);
}
