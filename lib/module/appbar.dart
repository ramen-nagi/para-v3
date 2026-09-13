import 'package:flutter/material.dart';

class ParaAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool? centerTitle;

  const ParaAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.centerTitle,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'Cubao',
          fontSize: 25
        ),
      ),
      backgroundColor: Colors.blue,
      foregroundColor: Colors.white,
      leadingWidth: 30,
      titleSpacing: 10,
      actions: actions,
      leading: leading,
      centerTitle: centerTitle,
    );
  }
}


