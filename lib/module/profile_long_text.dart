import 'package:flutter/material.dart';
import 'package:para_v3/module/profile_list_page.dart';

class ProfileLongTextPage extends StatelessWidget {
  final String title;
  final List<Widget> sections;

  const ProfileLongTextPage({
    super.key,
    required this.title,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return ProfileListPage(
      title: title,
      children: sections,
    );
  }
}
