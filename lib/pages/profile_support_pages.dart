import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Help & support')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const _InfoCard(
          icon: Icons.route_outlined,
          title: 'Planning a commute',
          body:
              'Choose an origin and destination, then compare the available '
              'journeys and follow the suggested legs and transfers.',
        ),
        const _InfoCard(
          icon: Icons.bookmark_border_rounded,
          title: 'Saved routes and places',
          body:
              'Tap the star beside a route to save it. Add Home, Work, or '
              'another place from your profile for faster planning.',
        ),
        const _InfoCard(
          icon: Icons.location_on_outlined,
          title: 'Location problems',
          body:
              'Check Profile > Location access. If access is blocked, open '
              'your device settings and allow location while using Para.',
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('support.para@gmail.com'),
            subtitle: const Text('Tap to copy the support email'),
            onTap: () async {
              await Clipboard.setData(
                const ClipboardData(text: 'support.para@gmail.com'),
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Support email copied.')),
              );
            },
          ),
        ),
      ],
    ),
  );
}

enum LegalDocument { terms, privacy }

class LegalPage extends StatelessWidget {
  final LegalDocument document;

  const LegalPage({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    final privacy = document == LegalDocument.privacy;
    return Scaffold(
      appBar: AppBar(
        title: Text(privacy ? 'Privacy policy' : 'Terms of service'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: privacy ? _privacySections : _termsSections,
      ),
    );
  }
}

class ReportIssuePage extends StatefulWidget {
  const ReportIssuePage({super.key});

  @override
  State<ReportIssuePage> createState() => _ReportIssuePageState();
}

class _ReportIssuePageState extends State<ReportIssuePage> {
  final _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _copyReport() async {
    final details = _details.text.trim();
    if (details.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Describe the issue first.')),
      );
      return;
    }
    await Clipboard.setData(
      ClipboardData(
        text:
            'To: support.para@gmail.com\nSubject: Para issue report\n\n$details',
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Report copied. Paste it into your email app.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Report an issue')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Tell us what happened, what you expected, and which route or place '
          'was involved.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _details,
          minLines: 7,
          maxLines: 12,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Issue details',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _copyReport,
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copy report for email'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Reports are not uploaded automatically. Send the copied report to '
          'support.para@gmail.com.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style:
                      Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(body),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _legalSection(String title, String body) => Padding(
  padding: const EdgeInsets.only(bottom: 24),
  child: Builder(
    builder: (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(body),
      ],
    ),
  ),
);

final _termsSections = <Widget>[
  _legalSection(
    'Using Para',
    'Para provides journey-planning information to help you compare public '
        'transport options. Routes, walking estimates, availability, and other '
        'results may change and should be checked against current conditions.',
  ),
  _legalSection(
    'Your responsibility',
    'Use safe judgment while traveling, follow local laws and operator '
        'instructions, and do not interact with the app when doing so would be '
        'unsafe.',
  ),
  _legalSection(
    'Accounts and local data',
    'Keep your account credentials private. Saved places and travel preferences '
        'currently remain on the device unless a synchronization feature '
        'explicitly says otherwise.',
  ),
  _legalSection(
    'Contact',
    'Questions about these terms can be sent to support.para@gmail.com.',
  ),
];

final _privacySections = <Widget>[
  _legalSection(
    'Information you provide',
    'Para stores account information through Supabase Authentication. Saved '
        'places, favorite routes, and travel preferences remain on your device '
        'and sync to your account when cloud profiles are available.',
  ),
  _legalSection(
    'Location',
    'Location access is used to show your position and help plan a journey. You '
        'can manage this permission in your device settings.',
  ),
  _legalSection(
    'Service providers',
    'Para uses external map, place-search, route-data, and authentication '
        'services. Requests sent to those services are subject to their own '
        'privacy practices.',
  ),
  _legalSection(
    'Your choices',
    'You can remove local profile data from Profile, clear permissions in device '
        'settings, and contact support.para@gmail.com about account data.',
  ),
];
