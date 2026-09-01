import 'package:flutter/material.dart';
import 'package:para_v3/module/profile_long_text.dart';

class ProfilePrivacyPolicyPage extends StatelessWidget {
  const ProfilePrivacyPolicyPage({super.key});

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
  );

  Widget _paragraph(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text),
  );

  @override
  Widget build(BuildContext context) {
    return ProfileLongTextPage(
      title: 'Privacy Policy',
      sections: [
        const Text('Last updated: September 2, 2026', style: TextStyle(fontStyle: FontStyle.italic)),
        _paragraph('Para is a Metro Manila commute-planning application. This Privacy Policy explains what information Para processes, where it is stored, and how it is used when you use the app.'),
        _heading('Information you provide'),
        _paragraph('If you create an account, Para processes your email address and authentication information through Supabase. If you submit a route suggestion or report, Para processes the information you enter, including route details, stop information, fare information, descriptions, and any coordinates or other context included in the submission.'),
        _heading('Location and address information'),
        _paragraph('When you use address search, the text you enter is sent to Google Places to provide autocomplete suggestions and geocoding. Para limits guest autocomplete searches to 25 requests per local day. Searches are restricted by the app to the Metro Manila area.'),
        _paragraph('When you use your current location, the app obtains your device location to set a commute endpoint or to show your position on the map and track progress during an active commute. Para does not require live location access merely to browse the app.'),
        _heading('Information stored on your device'),
        _paragraph('Para stores address-search history, saved places such as Home, School, and Work, custom saved places, and favorite route IDs in a local SQLite database. Fare preferences, commute-mode preferences, the cached GTFS dataset version, and the guest autocomplete request count are stored locally as well.'),
        _paragraph('Local information remains on the device until you delete it through the app, clear the app data, or uninstall the app. Address-search history and saved addresses can be managed from the corresponding Profile pages.'),
        _heading('Transit and map services'),
        _paragraph('Para downloads transit schedule and route data from Supabase and caches the active GTFS dataset on the device. Map display, walking directions, road matching, traffic information, and map tiles are provided through Mapbox. These services may receive the coordinates needed to provide the requested map or routing feature.'),
        _heading('How information is used'),
        _paragraph('Para uses information to provide commute planning, autocomplete, geocoding, route display, fare estimates, live commute progress, saved-address features, authentication, user reports, and route suggestions. Para does not sell your personal information.'),
        _heading('Sharing and service providers'),
        _paragraph('Para shares information with service providers only as needed to operate the requested feature, including Supabase for authentication, database operations, storage, reports, and route suggestions; Google Places for address autocomplete and geocoding; and Mapbox for maps, directions, matching, and traffic services. Their own privacy policies and terms may also apply.'),
        _heading('Retention and deletion'),
        _paragraph('You can delete locally stored address history and saved addresses through the app. Account-linked submissions and authentication data may remain in the relevant service until deleted or removed according to the service configuration and applicable requirements. To request account or server-side data deletion, contact the Para app team through the support channel provided with your distribution of the app.'),
        _heading('Security'),
        _paragraph('Para uses the security mechanisms provided by Flutter, the operating system, Supabase, Google, and Mapbox. No method of electronic storage or transmission is completely secure, so Para cannot guarantee absolute security.'),
        _heading('Children’s privacy'),
        _paragraph('Para is not directed to children under 13. We do not knowingly collect personal information from children under 13.'),
        _heading('Changes to this policy'),
        _paragraph('This policy may be updated when the app’s features, services, or data practices change. The updated policy will be made available in the app with a revised “Last updated” date.'),
      ],
    );
  }
}
