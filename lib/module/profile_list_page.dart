import 'package:flutter/material.dart';
import 'package:para_v3/module/appbar.dart';

class ProfileListPage extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final List<Widget>? actions;
  final bool loading;
  final bool isEmpty;
  final String emptyMessage;

  const ProfileListPage({
    super.key,
    required this.title,
    required this.children,
    this.actions,
    this.loading = false,
    this.isEmpty = false,
    this.emptyMessage = 'Nothing here yet.',
  });

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (isEmpty) {
      body = Center(child: Text(emptyMessage));
    } else {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: children,
      );
    }

    return Scaffold(
      appBar: ParaAppBar(title: title, actions: actions),
      body: body,
    );
  }
}
