import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/report_draft.dart';
import '../services/scope_api.dart';
import '../widgets/report_review_sheet.dart';

/// S11 — Location Tagging.
///
/// Interactive map with a current-location button, a draggable pin, premise
/// search and a reverse-geocoded address readout, so the reporter confirms
/// what was actually tagged rather than trusting an invisible coordinate.
///
/// The pin defaults to the position recorded at capture (S08). That is the
/// integrity control: it gives the report an evidentiary link between the
/// photograph and the place, and lets the backend flag a report tagged far
/// from where its evidence was taken.
///
/// If location permission is denied the screen degrades to search-only. A
/// denial must never block the report — the reporter can still name the
/// premise, and a report with a searched location is worth more than no
/// report at all.
class LocationTaggingScreen extends StatefulWidget {
  const LocationTaggingScreen({super.key});

  @override
  State<LocationTaggingScreen> createState() => _LocationTaggingScreenState();
}

/// Kuala Lumpur city centre — the fallback when there is neither a capture
/// position nor a device fix.
const LatLng _kualaLumpur = LatLng(3.1390, 101.6869);

class _LocationTaggingScreenState extends State<LocationTaggingScreen> {
  GoogleMapController? _map;
  LatLng _pin = _kualaLumpur;

  String? _addressText;
  String? _suggestedPremise;
  bool _resolvingAddress = false;
  bool _locating = false;
  bool _locationDenied = false;

  /// Guards against a slow reverse-geocode for an old pin overwriting the
  /// readout for a newer one.
  int _geocodeGeneration = 0;

  @override
  void initState() {
    super.initState();
    _seedInitialPin();
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  void _seedInitialPin() {
    final draft = context.read<ReportDraft>();
    final lat = draft.captureLatitude;
    final lng = draft.captureLongitude;

    if (lat != null && lng != null) {
      _pin = LatLng(lat, lng);
      _resolveAddress(_pin);
    } else {
      // No capture fix — try the device, falling back to KL centre.
      unawaited(_useCurrentLocation(silent: true));
    }
  }

  Future<void> _useCurrentLocation({bool silent = false}) async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const _LocationUnavailable('Location services are turned off.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const _LocationUnavailable('Location permission was declined.');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      final target = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _pin = target;
        _locationDenied = false;
      });
      await _map?.animateCamera(CameraUpdate.newLatLngZoom(target, 17));
      await _resolveAddress(target);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _locationDenied = true);
      if (!silent) {
        final message = e is _LocationUnavailable
            ? e.message
            : 'Could not get your location.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$message You can search for the place instead.')),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _resolveAddress(LatLng target) async {
    final generation = ++_geocodeGeneration;
    setState(() => _resolvingAddress = true);

    try {
      final result = await context.read<ScopeApi>().reverseGeocode(
            target.latitude,
            target.longitude,
          );
      if (!mounted || generation != _geocodeGeneration) return;
      setState(() {
        _addressText = result['address_text'];
        _suggestedPremise = result['premise_name'];
      });
    } on Object {
      if (!mounted || generation != _geocodeGeneration) return;
      // A geocoding failure is not fatal: the coordinates are what the report
      // actually needs, and the address is a confirmation aid.
      setState(() => _addressText = null);
    } finally {
      if (mounted && generation == _geocodeGeneration) {
        setState(() => _resolvingAddress = false);
      }
    }
  }

  void _movePin(LatLng target) {
    setState(() => _pin = target);
    _resolveAddress(target);
  }

  Future<void> _openSearch() async {
    final selection = await showModalBottomSheet<_PlaceSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _PlaceSearchSheet(),
    );
    if (selection == null || !mounted) return;

    final target = LatLng(selection.latitude, selection.longitude);
    setState(() {
      _pin = target;
      _addressText = selection.address;
      _suggestedPremise = selection.name;
    });
    await _map?.animateCamera(CameraUpdate.newLatLngZoom(target, 17));
  }

  void _reviewReport() {
    final draft = context.read<ReportDraft>();
    draft.setLocation(
      latitude: _pin.latitude,
      longitude: _pin.longitude,
      addressText: _addressText,
      suggestedPremiseName: _suggestedPremise,
    );
    showReportReviewSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tag the location'),
        actions: [
          IconButton(
            tooltip: 'Search for a premise',
            icon: const Icon(Icons.search_rounded),
            onPressed: _openSearch,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(target: _pin, zoom: 16),
                  onMapCreated: (controller) => _map = controller,
                  // The pin follows the map centre as well as being draggable,
                  // because dragging a small marker precisely is awkward
                  // one-handed — which is how this screen is actually used.
                  onCameraMove: (position) => _pin = position.target,
                  onCameraIdle: () => _movePin(_pin),
                  markers: {
                    Marker(
                      markerId: const MarkerId('violation'),
                      position: _pin,
                      draggable: true,
                      onDragEnd: _movePin,
                    ),
                  },
                  myLocationEnabled: !_locationDenied,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),
                Positioned(
                  right: Gap.md,
                  bottom: Gap.md,
                  child: FloatingActionButton(
                    heroTag: 'locate',
                    onPressed: _locating ? null : () => _useCurrentLocation(),
                    backgroundColor: Colors.white,
                    foregroundColor: ScopeTheme.primary,
                    child: _locating
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Icon(Icons.my_location_rounded),
                  ),
                ),
                if (_locationDenied)
                  Positioned(
                    left: Gap.md,
                    right: Gap.md,
                    top: Gap.md,
                    child: _SearchOnlyBanner(onSearch: _openSearch),
                  ),
              ],
            ),
          ),
          _buildReadout(),
        ],
      ),
    );
  }

  Widget _buildReadout() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        Gap.md,
        Gap.md,
        Gap.md,
        MediaQuery.of(context).padding.bottom + Gap.md,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: ScopeTheme.lineSoft)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.place_outlined,
                    size: 20, color: ScopeTheme.primary),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_resolvingAddress)
                      const Text(
                        'Finding this address…',
                        style: TextStyle(color: ScopeTheme.inkMuted),
                      )
                    else
                      Text(
                        _addressText ?? 'Address unavailable for this point',
                        style: TextStyle(
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: _addressText == null
                              ? ScopeTheme.inkMuted
                              : ScopeTheme.ink,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      '${_pin.latitude.toStringAsFixed(5)}, '
                      '${_pin.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: ScopeTheme.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          FilledButton(
            // Always enabled: the pin always holds a coordinate, seeded from
            // the capture position or KL centre, so there is no state in which
            // the reporter is stuck without a location to submit.
            onPressed: _reviewReport,
            child: const Text('Review report'),
          ),
        ],
      ),
    );
  }
}

class _LocationUnavailable implements Exception {
  const _LocationUnavailable(this.message);
  final String message;
}

class _SearchOnlyBanner extends StatelessWidget {
  const _SearchOnlyBanner({required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(12),
      color: Colors.white,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(Gap.sm),
        child: Row(
          children: [
            const Icon(Icons.location_off_outlined,
                size: 20, color: ScopeTheme.warning),
            const SizedBox(width: Gap.sm),
            const Expanded(
              child: Text(
                'Location is off. Search for the premise or drag the pin.',
                style: TextStyle(fontSize: 13, height: 1.3),
              ),
            ),
            TextButton(onPressed: onSearch, child: const Text('Search')),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Premise search
// ---------------------------------------------------------------------------

class _PlaceSelection {
  const _PlaceSelection({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String? address;
  final double latitude;
  final double longitude;
}

/// Search by premise name.
///
/// Queries are proxied through the SCOPE backend rather than calling Google
/// directly, so the Places key stays on the server and never ships in the APK.
class _PlaceSearchSheet extends StatefulWidget {
  const _PlaceSearchSheet();

  @override
  State<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<_PlaceSearchSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Map<String, String?>> _results = const [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }
    // Debounced so a query is not issued per keystroke — Places is billed per
    // request.
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
  }

  Future<void> _search(String query) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final api = context.read<ScopeApi>();
      final suggestions = await api.searchPlaces(query.trim());
      if (!mounted) return;
      setState(() => _results = suggestions);
    } on Object {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _error = 'Search is unavailable. Drag the pin on the map instead.';
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _select(Map<String, String?> suggestion) async {
    final placeId = suggestion['place_id'];
    if (placeId == null || placeId.isEmpty) return;

    setState(() => _searching = true);
    try {
      final detail = await context.read<ScopeApi>().placeDetail(placeId);
      if (!mounted) return;
      Navigator.of(context).pop(
        _PlaceSelection(
          name: detail.name,
          address: detail.address,
          latitude: detail.latitude,
          longitude: detail.longitude,
        ),
      );
    } on Object {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = 'Could not open that place. Try another result.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: 'Search premise or place name',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          ),
                        )
                      : null,
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                child: Text(
                  _error!,
                  style: const TextStyle(color: ScopeTheme.warning),
                ),
              ),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: _results.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _results[index];
                  return ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(item['main_text'] ?? item['description'] ?? ''),
                    subtitle: item['secondary_text'] == null
                        ? null
                        : Text(item['secondary_text']!),
                    onTap: () => _select(item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
