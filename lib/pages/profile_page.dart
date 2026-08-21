import 'package:flutter/material.dart';
import 'package:para_v3/module/route_suggestion_button.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Center(
            child: Text(
              'Profile Page',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(height: 24),
          RouteSuggestionButton(),
        ],
      ),
    );
  }
}
