import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/invitation_entity.dart';
import 'package:tentura_server/domain/entity/opinion_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';

import 'components/beacon_view_component.dart';
import 'components/invitation_view_component.dart';
import 'components/opinion_view_component.dart';
import 'components/user_view_component.dart';
import 'shared_view_styles.dart';

class SharedViewDocument extends StatelessComponent {
  const SharedViewDocument({
    required this.entity,
  });

  final Object entity;

  @override
  Component build(BuildContext context) => switch (entity) {
    // User
    final UserEntity user => _buildDocument(
      body: [
        UserViewComponent(user: user),
      ],
      meta: _buildMeta(
        id: user.id,
        title: user.title,
        description: user.description,
        imagePath: user.imageUrl,
      ),
    ),

    // Beacon
    final BeaconEntity beacon => _buildDocument(
      body: [
        BeaconViewComponent(beacon: beacon),
      ],
      meta: _buildMeta(
        id: beacon.id,
        title: beacon.title,
        description: beacon.description,
        imagePath: beacon.imageUrl,
      ),
    ),

    // Opinion
    final OpinionEntity opinion => _buildDocument(
      body: [
        UserViewComponent(user: opinion.user),
        _hr,
        OpinionViewComponent(opinion: opinion),
      ],
      meta: _buildMeta(
        id: opinion.id,
        title: opinion.user.title,
        description: opinion.content,
        imagePath: opinion.user.imageUrl,
      ),
    ),

    // Invitation
    final InvitationEntity invitation => _buildDocument(
      body: [
        InvitationViewComponent(user: invitation.issuer),
      ],
      meta: _buildMeta(
        id: invitation.id,
        title: invitation.issuer.title,
        // TBD: need real text with l10n
        description: 'Invite you to join Tentura!',
        imagePath: invitation.issuer.imageUrl,
      ),
    ),

    // Unsupported
    _ => throw Exception('Unsupported'),
  };

  Document _buildDocument({
    required List<Component> body,
    required Map<String, String> meta,
  }) => Document(
    head: _head,
    meta: meta,
    title: kAppTitle,
    styles: defaultStyles,
    viewport:
        'width=device-width, initial-scale=1, '
        'minimum-scale=1, maximum-scale=1 user-scalable=no',
    body: article(body),
  );

  static Map<String, String> _buildMeta({
    required String id,
    required String title,
    required String description,
    required String imagePath,
  }) => {
    'referrer': 'origin-when-cross-origin',
    'robots': 'noindex',
    'og:type': 'website',
    'og:site_name': 'Tentura',
    'og:title': title,
    'og:description': description,
    'og:url': '$kServerName/shared/view?id=$id',
    'og:image': imagePath,
  };

  static const _hr = hr(
    styles: Styles(
      margin: Spacing.symmetric(horizontal: kEdgeInsetsS),
    ),
  );

  static final _head = [
    link(
      href: '$kServerName$kPathIcons/web_24dp.png',
      rel: 'shortcut icon',
    ),
    link(
      href: '$kServerName$kPathIcons/web_32dp.png',
      rel: 'shortcut icon',
    ),
    link(
      href: '$kServerName$kPathIcons/web_36dp.png',
      rel: 'shortcut icon',
    ),
    link(
      href: '$kServerName$kPathIcons/web_48dp.png',
      rel: 'shortcut icon',
    ),
    link(
      href: '$kServerName$kPathIcons/web_64dp.png',
      rel: 'shortcut icon',
    ),
    link(
      href: '$kServerName$kPathIcons/web_96dp.png',
      rel: 'shortcut icon',
    ),
    link(
      href: '$kServerName$kPathIcons/web_512dp.png',
      rel: 'shortcut icon',
    ),
  ];
}
