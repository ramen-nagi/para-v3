import 'package:flutter/material.dart';
import 'package:para_v3/module/profile_long_text.dart';

class ProfilePageTermsOfService extends StatelessWidget {
  const ProfilePageTermsOfService({super.key});

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
  );

  Widget _paragraph(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text),
  );

  @override
  Widget build(BuildContext context) => ProfileLongTextPage(
    title: 'Terms of Service',
    sections: [
      const Text('Last updated: September 2, 2026', style: TextStyle(fontStyle: FontStyle.italic)),
      _paragraph('These Terms of Service govern your use of Para, a Metro Manila commute-planning application. By using Para, you agree to these Terms. If you do not agree, please do not use the app.'),
      _heading('Using Para'),
      _paragraph('Para provides transit information, route suggestions, map features, estimated fares, address search, and commute-planning tools. Information may be incomplete, delayed, estimated, or inaccurate.'),
      _paragraph('You are responsible for checking signs, schedules, fares, traffic conditions, service availability, and local conditions before and during your trip. Use appropriate care when walking, crossing roads, boarding vehicles, or using your device while travelling.'),
      _heading('Accounts'),
      _paragraph('Some features require an account. You are responsible for providing accurate information, protecting your sign-in credentials, and notifying us if you believe your account has been used without authorization.'),
      _heading('Your content'),
      _paragraph('You remain responsible for route suggestions, reports, descriptions, fare observations, coordinates, and other content you submit. You must have the right to provide that content.'),
      _paragraph('By submitting content, you grant Para permission to use, store, reproduce, adapt, and display it as reasonably necessary to operate, improve, and maintain the app and its transit information.'),
      _heading('Acceptable use'),
      _paragraph('You must not misuse Para, interfere with its operation, attempt unauthorized access, scrape or overload its services, circumvent usage limits, reverse engineer protected components, submit malicious code, or use the app unlawfully.'),
      _heading('Third-party services'),
      _paragraph('Para relies on Supabase, Google Places, and Mapbox. Their availability, data, terms, and policies may affect the app. Features provided by those services may also be subject to their respective terms and policies.'),
      _heading('Intellectual property'),
      _paragraph('The Para application, design, branding, software, and original content are owned by or licensed to Para. These Terms grant you a limited, personal, non-exclusive, non-transferable license to use the app for its intended purpose.'),
      _heading('Availability and changes'),
      _paragraph('Features, transit datasets, fares, maps, integrations, and availability may change or be discontinued. We may update the app and these Terms. Continued use after an update means you accept the revised Terms.'),
      _heading('Disclaimer and liability'),
      _paragraph('Para is provided on an â€œas availableâ€ basis. To the extent permitted by law, Para does not guarantee uninterrupted service or complete, current, error-free, or suitable route information. Estimated routes, durations, fares, traffic, and directions are not guarantees.'),
      _paragraph('To the extent permitted by law, Para and its contributors will not be responsible for indirect, incidental, special, consequential, or other losses arising from your use of, or inability to use, the app. Nothing here excludes rights or liability that cannot legally be excluded.'),
      _heading('Termination'),
      _paragraph('You may stop using Para at any time. Access may be suspended or terminated if you violate these Terms, misuse the app, or create a risk to the service or other users.'),
      _heading('Contact'),
      _paragraph('For questions about these Terms, use the support contact made available with your distribution of the Para app.'),
    ],
  );
}


