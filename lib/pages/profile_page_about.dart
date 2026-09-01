import 'package:flutter/material.dart';
import 'package:para_v3/module/appbar.dart';

class ProfilePageAbout extends StatelessWidget {
  final String title;

  const ProfilePageAbout({
    super.key,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ParaAppBar(title: title),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'para is your new bestfriend- Luis Cordero the goat',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
