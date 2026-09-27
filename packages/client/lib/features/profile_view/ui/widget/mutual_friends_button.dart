import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/my_work/ui/widget/compact_forwarder_avatars.dart';
import 'package:tentura/features/profile_view/data/repository/mutual_friends_repository.dart';
import 'package:tentura/features/profile_view/ui/widget/mutual_friends_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// On-demand mutual friends: button, then overlapping mini-avatars + optional +N.
class MutualFriendsButton extends StatefulWidget {
  const MutualFriendsButton({
    required this.userId,
    super.key,
  });

  final String userId;

  @override
  State<MutualFriendsButton> createState() => _MutualFriendsButtonState();
}

class _MutualFriendsButtonState extends State<MutualFriendsButton> {
  static const _maxAvatars = 5;

  bool _loading = false;
  List<Profile>? _profiles;

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      final list = await GetIt.I<MutualFriendsRepository>().fetchMutualFriends(
        widget.userId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _profiles = list;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;

    final tt = context.tt;
    final profiles = _profiles;
    if (profiles != null && profiles.isEmpty) {
      return TenturaMenuTile(
        icon: Icons.people_outline,
        title: l10n.showMutualFriends,
        subtitle: l10n.noMutualFriends,
        opensPage: false,
      );
    }
    if (profiles != null) {
      final shown = profiles.take(_maxAvatars).toList();
      final overflow = profiles.length > _maxAvatars
          ? profiles.length - _maxAvatars
          : 0;
      return TenturaMenuTile(
        icon: Icons.people_outline,
        title: l10n.showMutualFriends,
        onTap: () => showMutualFriendsSheet(context, profiles),
        trailing: CompactForwarderAvatars(
          profiles: shown,
          overflowCount: overflow,
        ),
      );
    }
    return TenturaMenuTile(
      icon: Icons.people_outline,
      title: l10n.showMutualFriends,
      opensPage: false,
      onTap: _loading ? null : _load,
      trailing: _loading
          ? SizedBox.square(
              dimension: tt.iconSize,
              child: const CircularProgressIndicator.adaptive(strokeWidth: 2),
            )
          : null,
    );
  }
}
