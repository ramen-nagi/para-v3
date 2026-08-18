import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:para_v3/pages/auth_page.dart';
import 'package:para_v3/pages/commute_page.dart';
import 'package:para_v3/pages/commute_history_page.dart';
import 'package:para_v3/pages/profile_place_picker.dart';
import 'package:para_v3/pages/profile_support_pages.dart';
import 'package:para_v3/pages/routes_page_map.dart';
import 'package:para_v3/services/gtfs_network_service.dart';
import 'package:para_v3/services/location_permission_service.dart';
import 'package:para_v3/services/profile_store.dart';

/// The original Para brand blue, retained here for the profile identity area.
const _profileBlue = Color(0xFF2563EB);
const _profileInk = Color(0xFF111111);
const _profileMuted = Color(0xFF666666);
const _profileDivider = Color(0x14000000);
const _profileSurface = Color(0xFFFFFFFF);

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with WidgetsBindingObserver {
  final _store = ProfileStore();
  final _locationService = const LocationPermissionService();
  User? _user;
  StreamSubscription<AuthState>? _authSubscription;

  LocationPermissionState? _locationPermission;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isCheckingLocation = false;
  String? _loadWarning;
  ProfileData get _profile => _store.profile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _user = Supabase.instance.client.auth.currentUser;
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (event) {
        if (mounted) setState(() => _user = event.session?.user);
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Authentication state error: $error');
      },
    );
    _store.addListener(_onSharedUpdate);
    GtfsNetworkService.instance.addListener(_onSharedUpdate);
    _loadProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.removeListener(_onSharedUpdate);
    GtfsNetworkService.instance.removeListener(_onSharedUpdate);
    _authSubscription?.cancel();
    super.dispose();
  }

  void _onSharedUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshLocationPermission();
    }
  }

  Future<void> _loadProfile() async {
    String? warning;

    try {
      await _store.load();
    } catch (_) {
      warning = 'Some profile settings could not be loaded.';
    }

    if (!mounted) return;
    setState(() {
      _loadWarning = warning;
      _isLoading = false;
    });

    try {
      final permission = await _locationService.checkPermission();
      if (!mounted) return;
      setState(() => _locationPermission = permission);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _loadWarning ??= 'Location access could not be checked.',
      );
    }
  }

  Future<LocationPermissionState?> _refreshLocationPermission() async {
    try {
      final permission = await _locationService.checkPermission();
      if (!mounted) return null;
      setState(() => _locationPermission = permission);
      return permission;
    } catch (_) {
      _showMessage('Could not check location access.');
      return null;
    }
  }

  Future<bool> _save(ProfileData Function(ProfileData current) update) async {
    if (_isSaving) return false;
    setState(() => _isSaving = true);
    try {
      final wasSaved = await _store.update(update);
      if (!mounted) return false;
      if (!wasSaved) {
        _showMessage('Your change could not be saved. Please try again.');
        return false;
      }
      return true;
    } catch (_) {
      if (mounted) {
        _showMessage('Your change could not be saved. Please try again.');
      }
      return false;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  SavedPlace? _placeFor(SavedPlaceKind kind) {
    for (final place in _profile.savedPlaces) {
      if (place.kind == kind) return place;
    }
    return null;
  }

  List<SavedPlace> get _customPlaces => _profile.savedPlaces
      .where((place) => place.kind == SavedPlaceKind.custom)
      .toList();

  Future<void> _pickPlace(
    SavedPlaceKind kind, {
    SavedPlace? existingPlace,
  }) async {
    if (_isSaving) return;
    final title = switch (kind) {
      SavedPlaceKind.home => 'Set your home',
      SavedPlaceKind.work => 'Set your work',
      SavedPlaceKind.custom =>
        existingPlace == null ? 'Save a place' : 'Change saved place',
    };
    final place = await showModalBottomSheet<SavedPlace>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: ProfilePlacePicker(
            title: title,
            kind: kind,
            existingPlace: existingPlace,
          ),
        ),
      ),
    );
    if (!mounted || place == null) return;

    final normalizedAddress = place.address.trim().toLowerCase();
    final isDuplicate =
        kind == SavedPlaceKind.custom &&
        _profile.savedPlaces.any(
          (savedPlace) =>
              savedPlace.kind == SavedPlaceKind.custom &&
              savedPlace.id != existingPlace?.id &&
              savedPlace.address.trim().toLowerCase() == normalizedAddress,
        );
    if (isDuplicate) {
      _showMessage('${place.label} is already saved.');
      return;
    }

    if (await _save((profile) {
      final places = List<SavedPlace>.of(profile.savedPlaces);
      if (kind == SavedPlaceKind.custom) {
        final index = places.indexWhere((saved) => saved.id == place.id);
        index < 0 ? places.add(place) : places[index] = place;
      } else {
        final index = places.indexWhere((saved) => saved.kind == kind);
        places.removeWhere((saved) => saved.kind == kind);
        places.insert(
          index < 0 || index > places.length ? places.length : index,
          place,
        );
      }
      return profile.copyWith(savedPlaces: places);
    })) {
      _showMessage('${place.label} saved on this device.');
    }
  }

  Future<void> _removePlace(SavedPlace place) async {
    final confirmed = await _confirm(
      title: 'Remove ${place.label}?',
      message: 'You can save this place again at any time.',
      actionLabel: 'Remove',
    );
    if (!confirmed || !mounted) return;
    if (await _save(
      (profile) => profile.copyWith(
        savedPlaces: profile.savedPlaces
            .where((saved) => saved.id != place.id)
            .toList(),
      ),
    )) {
      _showMessage('${place.label} removed.');
    }
  }

  Future<void> _handleLocationAccess() async {
    if (_isCheckingLocation) return;
    setState(() => _isCheckingLocation = true);
    try {
      var permission = _locationPermission;
      if (permission == null) {
        permission = await _refreshLocationPermission();
        if (permission == null) return;
      }
      if (permission == LocationPermissionState.denied) {
        final updatedPermission = await _locationService.requestPermission();
        if (mounted) {
          setState(() => _locationPermission = updatedPermission);
        }
      } else {
        final opened = await _locationService.openSettings();
        if (!opened && mounted) {
          _showMessage('Could not open device settings.');
        }
      }
    } catch (_) {
      _showMessage('Could not update location access.');
    } finally {
      if (mounted) setState(() => _isCheckingLocation = false);
    }
  }

  Future<void> _resetProfile() async {
    if (_isSaving) return;
    final confirmed = await _confirm(
      title: 'Reset profile?',
      message:
          'Saved places, favorites, and travel preferences '
          'will return to their defaults. Recent searches are kept.',
      actionLabel: 'Reset',
    );
    if (!confirmed || !mounted) return;
    setState(() => _isSaving = true);
    try {
      final wasReset = await _store.reset();
      if (!mounted) return;
      if (!wasReset) {
        _showMessage('Could not reset your profile.');
        return;
      }
      _showMessage('Profile reset.');
    } catch (_) {
      _showMessage('Could not reset your profile.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String actionLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'Para',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.directions_transit_rounded, size: 40),
      applicationLegalese: 'Built for Metro Manila commuters.',
      children: const [
        Text(
          'Para helps commuters discover public-transport routes and plan '
          'multimodal journeys with less guesswork.',
        ),
      ],
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openAuth(AuthMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => AuthPage(initialMode: mode)),
    );
  }

  String? _accountName(User? user) {
    final value = user?.userMetadata?['username'];
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  bool _isValidEmail(String value) => RegExp(
    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
  ).hasMatch(value);

  Future<void> _editAccountName() async {
    final user = _user;
    if (user == null) return;
    final currentName = _accountName(user) ?? '';
    final controller = TextEditingController(text: currentName);
    String? errorText;
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void saveName() {
            final normalized = controller.text.trim();
            if (normalized.isEmpty) {
              setDialogState(() => errorText = 'Enter a name to continue.');
              return;
            }
            Navigator.of(dialogContext).pop(normalized);
          }

          return AlertDialog(
            title: const Text('Account name'),
            content: TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Name',
                border: const OutlineInputBorder(),
                errorText: errorText,
              ),
              onChanged: (_) {
                if (errorText != null) setDialogState(() => errorText = null);
              },
              onSubmitted: (_) => saveName(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(onPressed: saveName, child: const Text('Save')),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (!mounted || name == null) return;
    try {
      final response = await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'username': name.trim()}),
      );
      if (!mounted) return;
      setState(() => _user = response.user);
      _showMessage('Account name updated.');
    } on AuthException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Could not update your account name.');
    }
  }

  Future<void> _changeEmail() async {
    final user = _user;
    if (user == null) return;
    final controller = TextEditingController(text: user.email ?? '');
    String? errorText;
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void continueWithEmail() {
            final normalized = controller.text.trim();
            final validationMessage = normalized.isEmpty
                ? 'Enter an email address.'
                : !_isValidEmail(normalized)
                ? 'Enter a valid email address.'
                : normalized == user.email
                ? 'This is already your current email.'
                : null;
            if (validationMessage != null) {
              setDialogState(() => errorText = validationMessage);
              return;
            }
            Navigator.of(dialogContext).pop(normalized);
          }

          return AlertDialog(
            title: const Text('Change email'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: 'New email',
                border: const OutlineInputBorder(),
                errorText: errorText,
              ),
              onChanged: (_) {
                if (errorText != null) setDialogState(() => errorText = null);
              },
              onSubmitted: (_) => continueWithEmail(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: continueWithEmail,
                child: const Text('Continue'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (!mounted || email == null) return;
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(email: email),
        emailRedirectTo: paraAuthCallbackUrl,
      );
      _showMessage('Check your email to confirm the change.');
    } on AuthException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Could not update your email. Please try again.');
    }
  }

  void _changePassword() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const UpdatePasswordPage()),
    );
  }

  Future<void> _signOut() async {
    if (!await _confirm(
      title: 'Sign out?',
      message:
          'Places and preferences from this account will be removed from '
          'this device.',
      actionLabel: 'Sign out',
    )) {
      return;
    }
    try {
      await Supabase.instance.client.auth.signOut();
      _showMessage('Signed out.');
    } on AuthException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Could not sign out. Please try again.');
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await _confirm(
      title: 'Delete account permanently?',
      message:
          'This permanently deletes your Para account and resets places, '
          'favorites, and preferences saved on this device. This cannot be '
          'undone.',
      actionLabel: 'Delete account',
    );
    if (!confirmed || !mounted) return;
    setState(() => _isSaving = true);
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'delete-account',
      );
      if (response.status != 200) {
        throw Exception('Account deletion failed');
      }
      await Supabase.instance.client.auth.signOut();
      await _store.reset();
      _showMessage('Your account was deleted.');
    } on FunctionException catch (error) {
      _showMessage(
        error.status == 404
            ? 'Account deletion is not configured on the server yet.'
            : 'Could not delete your account. Please try again.',
      );
    } catch (_) {
      _showMessage('Could not delete your account. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _openCommute({
    CommuteEndpoint? origin,
    CommuteEndpoint? destination,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Plan commute')),
          body: CommutePage(
            initialOrigin: origin,
            initialDestination: destination,
          ),
        ),
      ),
    );
  }

  void _planFromPlace(SavedPlace place, bool startHere) {
    final endpoint = CommuteEndpoint.fromSavedPlace(place);
    _openCommute(
      origin: startHere ? endpoint : null,
      destination: startHere ? null : endpoint,
    );
  }

  Future<void> _removeFavorite(FavoriteRoute favorite) async {
    await _save(
      (profile) => profile.copyWith(
        favoriteRoutes: profile.favoriteRoutes
            .where((route) => route.routeId != favorite.routeId)
            .toList(),
      ),
    );
  }

  String get _locationStatus => switch (_locationPermission) {
    LocationPermissionState.granted => 'Allowed - tap to manage',
    LocationPermissionState.permanentlyDenied =>
      'Blocked - tap to open settings',
    LocationPermissionState.denied => 'Not allowed - tap to allow',
    null => 'Status unavailable - tap to check',
  };

  void _openPage(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => page));
  }

  Widget _placeTile(
    String label,
    IconData icon,
    SavedPlaceKind kind, [
    SavedPlace? place,
  ]) => ListTile(
    minTileHeight: 72,
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, size: 20, color: _profileMuted),
    title: Text(label),
    subtitle: Text(
      place?.address ?? 'Not set',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: place == null
        ? const Icon(Icons.chevron_right_rounded)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<bool>(
                tooltip: 'Directions',
                icon: const Icon(Icons.directions_rounded),
                onSelected: (startHere) => _planFromPlace(place, startHere),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: true, child: Text('Start here')),
                  PopupMenuItem(value: false, child: Text('Go here')),
                ],
              ),
              IconButton(
                tooltip: 'Remove $label',
                onPressed: _isSaving ? null : () => _removePlace(place),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
    onTap: _isSaving ? null : () => _pickPlace(kind, existingPlace: place),
  );

  Widget _tile(
    IconData icon,
    String title,
    String? subtitle,
    VoidCallback? onTap, {
    Color? color,
    bool showChevron = true,
    Widget? trailing,
  }) => ListTile(
    minTileHeight: 72,
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, size: 20, color: color ?? _profileMuted),
    title: Text(title, style: color == null ? null : TextStyle(color: color)),
    subtitle: subtitle == null ? null : Text(subtitle),
    trailing:
        trailing ??
        (showChevron
            ? const Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: _profileMuted,
              )
            : null),
    onTap: onTap,
  );

  Widget _section(
    String title,
    Iterable<Widget> tiles, {
    String? note,
  }) {
    final items = tiles.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: _profileMuted,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 24),
          Text(
            note,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _profileMuted),
          ),
        ],
        const SizedBox(height: 24),
        const Divider(height: 1, thickness: 1, color: _profileDivider),
        for (var index = 0; index < items.length; index++) ...[
          items[index],
          const Divider(height: 1, thickness: 1, color: _profileDivider),
        ],
      ],
    );
  }

  Widget _header({required bool desktop}) {
    final user = _user;
    final name = _accountName(user);
    final emailName = user?.email?.split('@').first;
    final displayName = name?.trim().isNotEmpty == true
        ? name!.trim()
        : user == null
        ? 'Guest'
        : emailName?.isNotEmpty == true
        ? emailName!
        : 'Para user';
    final subtitle =
        user?.email ?? 'Places and preferences saved on this device.';
    return Padding(
      padding: EdgeInsets.symmetric(vertical: desktop ? 72 : 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PARA / PROFILE',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              color: Colors.white,
              fontSize: desktop ? 52 : 38,
              height: 1.05,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.6,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white70,
              height: 1.5,
              fontWeight: FontWeight.w400,
            ),
          ),
          if (user == null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                border: Border.fromBorderSide(
                  BorderSide(color: Color(0x52FFFFFF)),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    size: 16,
                    color: Colors.white70,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'GUEST MODE',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _account() {
    final user = _user;
    if (user == null) {
      return _section(
        'Account',
        [
          _tile(
            Icons.login_rounded,
            'Sign in',
            'Access your Para account',
            () => _openAuth(AuthMode.signIn),
            color: _profileBlue,
          ),
          _tile(
            Icons.person_add_alt_1_rounded,
            'Create account',
            'New to Para',
            () => _openAuth(AuthMode.createAccount),
          ),
        ],
        note: 'You can keep using commute tools without an account.',
      );
    }
    return _section('Account', [
      _tile(
        Icons.person_outline_rounded,
        'Account name',
        _accountName(user) ?? 'Add your name',
        _editAccountName,
      ),
      _tile(
        Icons.email_outlined,
        'Email',
        user.email ?? 'No email available',
        _changeEmail,
      ),
      _tile(
        Icons.password_rounded,
        'Change password',
        'Update your sign-in password',
        _changePassword,
      ),
      _tile(
        Icons.logout_rounded,
        'Sign out',
        'Remove this account\'s data from this device',
        _signOut,
        color: _profileInk,
        showChevron: false,
      ),
      _tile(
        Icons.delete_forever_outlined,
        'Delete account',
        'Permanently remove your Para account',
        _isSaving ? null : _deleteAccount,
        color: _profileInk,
        showChevron: false,
      ),
    ]);
  }

  Widget _savedPlaces() => _section('Saved places', [
    _placeTile(
      'Home',
      Icons.home_rounded,
      SavedPlaceKind.home,
      _placeFor(SavedPlaceKind.home),
    ),
    _placeTile(
      'Work',
      Icons.work_rounded,
      SavedPlaceKind.work,
      _placeFor(SavedPlaceKind.work),
    ),
    ..._customPlaces.map(
      (place) => _placeTile(
        place.label,
        Icons.place_rounded,
        SavedPlaceKind.custom,
        place,
      ),
    ),
    _tile(
      Icons.add_location_alt_outlined,
      'Add another place',
      null,
      _isSaving ? null : () => _pickPlace(SavedPlaceKind.custom),
    ),
  ]);

  IconData _modeIcon(TransportMode mode) => switch (mode) {
    TransportMode.train => Icons.train_rounded,
    TransportMode.bus => Icons.directions_bus_rounded,
    TransportMode.jeep => Icons.airport_shuttle_rounded,
    TransportMode.uvExpress => Icons.directions_car_rounded,
    TransportMode.tricycle => Icons.moped_rounded,
  };

  Widget _commute() => _section('Commute', [
    if (_profile.favoriteRoutes.isEmpty)
      _tile(
        Icons.star_border_rounded,
        'No favorite routes yet',
        'Save a route from the Routes tab',
        null,
        showChevron: false,
      ),
    for (final favorite in _profile.favoriteRoutes)
      Builder(
        builder: (context) {
          final route = GtfsNetworkService.instance.routesMap[favorite.routeId];
          final unavailable =
              GtfsNetworkService.instance.isLoaded && route == null;
          return ListTile(
            leading: Icon(_modeIcon(favorite.vehicleType)),
            title: Text(favorite.displayName),
            subtitle: Text(
              unavailable
                  ? 'Unavailable in the current dataset'
                  : route == null
                  ? 'Checking availability…'
                  : favorite.vehicleType.name,
            ),
            onTap: route == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => RoutesPageMap(route: route),
                    ),
                  ),
            trailing: IconButton(
              tooltip: 'Remove favorite',
              onPressed: _isSaving ? null : () => _removeFavorite(favorite),
              icon: const Icon(Icons.star_rounded),
            ),
          );
        },
      ),
    _tile(
      Icons.history_rounded,
      'Commute history',
      'Journeys completed on this device',
      () => _openPage(const CommuteHistoryPage()),
    ),
  ]);

  Widget _appSettings() => _section(
    'App',
    [
      _tile(
        Icons.my_location_rounded,
        'Location access',
        _locationStatus,
        _handleLocationAccess,
        trailing: _isCheckingLocation
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
      ),
      _tile(
        Icons.restart_alt_rounded,
        'Reset profile',
        'Remove places, favorites, and preferences',
        _isSaving ? null : _resetProfile,
        color: _profileInk,
        showChevron: false,
      ),
      _tile(
        Icons.info_outline_rounded,
        'About Para',
        'Built for Metro Manila commuters',
        _showAbout,
      ),
    ],
  );

  Widget _supportAndLegal() => _section('Support & legal', [
    _tile(
      Icons.help_outline_rounded,
      'Help & support',
      'Guides and contact information',
      () => _openPage(const HelpSupportPage()),
    ),
    _tile(
      Icons.flag_outlined,
      'Report an issue',
      'Prepare a report for the Para team',
      () => _openPage(const ReportIssuePage()),
      color: _profileInk,
    ),
    _tile(
      Icons.description_outlined,
      'Terms of service',
      null,
      () => _openPage(const LegalPage(document: LegalDocument.terms)),
    ),
    _tile(
      Icons.privacy_tip_outlined,
      'Privacy policy',
      null,
      () => _openPage(const LegalPage(document: LegalDocument.privacy)),
    ),
  ]);

  Widget _content() => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 960;
      final outerGutter = desktop ? 80.0 : 24.0;
      final gridWidth = constraints.maxWidth - (outerGutter * 2);
      final columnWidth = desktop ? gridWidth / 12 : 0.0;
      final left = desktop ? outerGutter + columnWidth : outerGutter;
      final right = desktop
          ? constraints.maxWidth - left - (columnWidth * 7)
          : outerGutter;

      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 72),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: _profileBlue,
              padding: EdgeInsets.only(left: left, right: right),
              child: _header(desktop: desktop),
            ),
            Padding(
              padding: EdgeInsets.only(left: left, right: right),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_loadWarning != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      decoration: const BoxDecoration(
                        border: Border.fromBorderSide(
                          BorderSide(color: _profileDivider),
                        ),
                      ),
                      child: ListTile(
                        minTileHeight: 72,
                        leading: const Icon(
                          Icons.info_outline_rounded,
                          size: 20,
                        ),
                        title: Text(_loadWarning!),
                        trailing: TextButton(
                          onPressed: () {
                            setState(() => _isLoading = true);
                            _loadProfile();
                          },
                          child: const Text('Retry'),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _account(),
                  const SizedBox(height: 24),
                  _savedPlaces(),
                  const SizedBox(height: 24),
                  _commute(),
                  const SizedBox(height: 24),
                  _appSettings(),
                  const SizedBox(height: 24),
                  _supportAndLegal(),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final profileTheme = Theme.of(context).copyWith(
      scaffoldBackgroundColor: _profileSurface,
      colorScheme: colors.copyWith(primary: _profileBlue),
      textTheme: Theme.of(context).textTheme.apply(
        fontFamily: 'Arial',
        bodyColor: _profileInk,
        displayColor: _profileInk,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _profileBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(
        color: _profileDivider,
        thickness: 1,
        space: 1,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
    );
    return Theme(
      data: profileTheme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(
              height: 1,
              thickness: 1,
              color: Color(0x29FFFFFF),
            ),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (_isSaving || _isCheckingLocation)
                    const LinearProgressIndicator(
                      color: _profileBlue,
                      minHeight: 2,
                    ),
                  Expanded(child: _content()),
                ],
              ),
      ),
    );
  }
}
