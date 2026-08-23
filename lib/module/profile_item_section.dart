import 'package:flutter/material.dart';

class ProfileTabs {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const ProfileTabs({
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing = const Icon(Icons.chevron_right),
    this.onTap,
  });
}

class ProfileSection extends StatelessWidget {
  final String title;
  final List<ProfileTabs> items;

  const ProfileSection({super.key, required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        for (final item in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(item.icon),
            title: Text(item.label),
            subtitle: item.subtitle == null ? null : Text(item.subtitle!),
            trailing: item.trailing,
            onTap: item.onTap,
          ),
        const Divider(),
      ],
    );
  }
}
