import 'package:flutter/material.dart';
import 'package:para_v3/pages/route_suggestion_page.dart';

class RouteSuggestionButton extends StatelessWidget {
  const RouteSuggestionButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.alt_route),
        title: const Text('Route not in Para?'),
        subtitle: const Text('Suggest a route'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RouteSuggestionPage()),
        ),
      ),
    );
  }
}
