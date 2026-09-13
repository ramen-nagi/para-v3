import 'package:flutter/material.dart';
import 'package:para_v3/module/appbar.dart';

class ProfilePageAbout extends StatelessWidget {
  final String title;

  const ProfilePageAbout({
    super.key,
    required this.title,
  });

  Widget _section(
    BuildContext context, {
    required String heading,
    required String text,
    required IconData icon,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    heading,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(text),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpAndSupport(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'How can we help?',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Use these guides when you need help using Para or reporting a problem.',
        ),
        const SizedBox(height: 16),
        _section(
          context,
          heading: 'Plan a commute',
          text:
              'Open Commute, select your starting location and destination, '
              'then choose one of the suggested journeys. Review its vehicle '
              'types, stops, estimated time, distance, and fare before tapping '
              'Start commute.',
          icon: Icons.route_outlined,
        ),
        _section(
          context,
          heading: 'Location and internet access',
          text:
              'Turn on your device location and allow Para to use it while the '
              'app is open. An internet connection is required for address '
              'search, maps, route information, and updated journey estimates.',
          icon: Icons.location_on_outlined,
        ),
        _section(
          context,
          heading: 'Discounted fare estimates',
          text:
              'Open Profile, find Commute Settings, and turn on Discounted Fare. '
              'Plan the journey again so Para can calculate a discounted fare '
              'estimate when supported fare data is available.',
          icon: Icons.confirmation_number_outlined,
        ),
        _section(
          context,
          heading: 'Report incorrect information',
          text:
              'Go to Profile > Report to send details about an incorrect route, '
              'stop, or fare. During an active commute, you can also use the '
              'report button beside the journey details.',
          icon: Icons.report_problem_outlined,
        ),
        _section(
          context,
          heading: 'Suggest a missing route',
          text:
              'Go to Profile > Suggest a Route. Add the route name, vehicle '
              'type, endpoints, and any useful notes before submitting it.',
          icon: Icons.alt_route,
        ),
        _section(
          context,
          heading: 'Estimates and safety',
          text:
              'Routes, fares, traffic conditions, and travel times are estimates '
              'and may change. Check official signs and local conditions. Stay '
              'aware of your surroundings and avoid using your phone while '
              'crossing roads or boarding a vehicle.',
          icon: Icons.health_and_safety_outlined,
        ),
        _section(
          context,
          heading: 'Contact us',
          text:
              'For questions or problems that cannot be submitted through the '
              'app, email support.para@gmail.com.',
          icon: Icons.email_outlined,
        ),
      ],
    );
  }

  Widget _buildParaLore(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Built by commuters, for commuters',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        _section(
          context,
          heading: 'Where our journey started',
          text:
              'Para was created by four students who commute regularly. Like '
              'many commuters, we have experienced going somewhere unfamiliar '
              'without knowing which vehicle to ride, where to get on or off, '
              'how much the fare might be, or where to transfer.',
          icon: Icons.groups_outlined,
        ),
        _section(
          context,
          heading: 'The problem we experienced',
          text:
              'We often searched online or posted questions asking other people '
              'for directions. Helpful answers did not always arrive immediately, '
              'especially when the people who knew the route had not seen the '
              'post yet. Commuters usually need an answer before the trip starts, '
              'not hours later.',
          icon: Icons.question_answer_outlined,
        ),
        _section(
          context,
          heading: 'Why we created Para',
          text:
              'We created Para to make useful commuting information easier to '
              'find in one place. The app helps commuters explore possible '
              'routes, public transportation options, stops, transfers, fare '
              'estimates, travel conditions, and other journeys toward their '
              'chosen destination.',
          icon: Icons.directions_transit_outlined,
        ),
        _section(
          context,
          heading: 'Our goal',
          text:
              'Para is for commuters like us who may not know a route yet. Our '
              'goal is to reduce uncertainty and help people prepare for a safer, '
              'clearer, and more confident commute around Metro Manila.',
          icon: Icons.flag_outlined,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ParaAppBar(title: title),
      body: title == 'Help and Support'
          ? _buildHelpAndSupport(context)
          : _buildParaLore(context),
    );
  }
}
