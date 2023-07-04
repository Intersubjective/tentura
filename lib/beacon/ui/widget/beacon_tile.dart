import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'package:gravity/user/entity/user.dart';
import 'package:gravity/beacon/entity/beacon.dart';
import 'package:gravity/image/ui/widget/future_image.dart';
import 'package:gravity/image/ui/widget/placeholder_image.dart';

class BeaconTile extends StatelessWidget {
  final Beacon beacon;

  final Future<Uint8List?> Function(User user) futureAvatarImage;
  final Future<Uint8List?> Function(Beacon beacon) futureBeaconImage;

  const BeaconTile({
    required this.beacon,
    required this.futureAvatarImage,
    required this.futureBeaconImage,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar
          Container(
            key: Key('AvatarImage:${beacon.author.id}'),
            width: 40,
            height: 40,
            clipBehavior: Clip.hardEdge,
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
            ),
            child: FutureImage(
              key: Key('AvatarImage:${beacon.author.id}'),
              placeholder: const PlaceholderImage.avatar(),
              futureImage: futureAvatarImage(beacon.author),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // User displayName
                    Text(
                      beacon.author.title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(width: 16),
                    Text(
                      beacon.createdAt.toString(),
                    ),
                    const Spacer(),
                    // Menu
                    PopupMenuButton(
                      itemBuilder: (context) => const [
                        PopupMenuItem<void>(child: Text('Share the code')),
                        PopupMenuItem<void>(child: Text('Graph view')),
                      ],
                    ),
                  ],
                ),
                // Beacon Image
                Container(
                  width: 300,
                  clipBehavior: Clip.hardEdge,
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  margin: const EdgeInsets.symmetric(vertical: 16),
                  child: FutureImage(
                    key: Key('BeaconImage:${beacon.author.id + beacon.id}'),
                    placeholder: const PlaceholderImage.beacon(),
                    futureImage: futureBeaconImage(beacon),
                  ),
                ),
                // Beacon Title
                Text(
                  beacon.title,
                  maxLines: 1,
                  textAlign: TextAlign.left,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                // Beacon Description
                Text(
                  beacon.description,
                  maxLines: 3,
                  textAlign: TextAlign.left,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
                // Bottom Buttons Block
                Row(
                  children: [
                    // Like\Dislike
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.thumb_up_outlined),
                            onPressed: () {},
                          ),
                          const Text('10'),
                          IconButton(
                            icon: const Icon(Icons.thumb_down_outlined),
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    // Reply
                    FilledButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.comment_outlined),
                      label: const Text('4'),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.percent_outlined),
                      label: const Text('90%'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      );
}