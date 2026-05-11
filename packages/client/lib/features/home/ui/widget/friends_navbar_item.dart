import 'package:flutter/material.dart';

class FriendsNavbarItem extends StatelessWidget {
  const FriendsNavbarItem({super.key, this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) =>
      Icon(selected ? Icons.people : Icons.people_outline);
}
