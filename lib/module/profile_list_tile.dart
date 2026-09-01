import 'package:flutter/material.dart';

class ProfileListTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const ProfileListTile({super.key, this.leading, required this.title, this.subtitle, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: leading,
    title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: subtitle == null ? null : Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: trailing,
    onTap: onTap,
  );
}
