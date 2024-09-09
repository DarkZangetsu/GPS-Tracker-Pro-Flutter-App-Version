import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';

class LocationTracker extends StatefulWidget {
  @override
  _LocationTrackerState createState() => _LocationTrackerState();
}

class _LocationTrackerState extends State<LocationTracker> {
  String _locationStatus = "Initializing...";
  String _deviceName = "Unknown Device";
  int _offlineCount = 0;
  Timer? _timer;
  Position? _lastKnownLocation;
  String? _deviceId;

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _setupLocationTracking();
  }

  String generateUUIDv4() {
    var random = Random.secure();
    var values = List<int>.generate(16, (i) => random.nextInt(256));

    values[6] = (values[6] & 0x0f) | 0x40; // Version 4
    values[8] = (values[8] & 0x3f) | 0x80; // Variant is 10

    var hex = values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  String generateDeterministicUUID(String input) {
    var bytes = utf8.encode(input);
    var digest = md5.convert(bytes);
    var hex = digest.toString();

    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-4${hex.substring(13, 16)}-'
        '${(int.parse(hex.substring(16, 18), radix: 16) & 0x3f | 0x80).toRadixString(16).padLeft(2, '0')}${hex.substring(18, 20)}-${hex.substring(20)}';
  }

  bool isValidUUID(String uuid) {
    RegExp uuidRegex = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false);
    return uuidRegex.hasMatch(uuid);
  }

  Future<void> _setupLocationTracking() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied');
      }

      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        throw Exception('Location permissions are not sufficient');
      }

      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      _deviceName = androidInfo.model;

      SharedPreferences prefs = await SharedPreferences.getInstance();
      _deviceId = prefs.getString('deviceId');
      if (_deviceId == null || !isValidUUID(_deviceId!)) {
        _deviceId = generateDeterministicUUID(_deviceName);
        await prefs.setString('deviceId', _deviceId!);
      }

      _updateAndSendLocation();

      _timer = Timer.periodic(
          Duration(hours: 1), (Timer t) => _updateAndSendLocation());

      Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
            if (result != ConnectivityResult.none) {
              _sendLocationToSupabase();
            }
          } as void Function(List<ConnectivityResult> event)?);
    } catch (e, stackTrace) {
      print('Error in _setupLocationTracking: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _locationStatus = 'Failed to start tracking: ${e.toString()}';
      });
    }
  }

  Future<void> _updateAndSendLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      _lastKnownLocation = position;
      setState(() {
        _locationStatus = "Location updated: ${DateTime.now().toLocal()}";
      });
      await _storeLocationLocally(position);
      await _sendLocationToSupabase();
    } catch (e, stackTrace) {
      print('Error in _updateAndSendLocation: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _locationStatus = 'Failed to update location: ${e.toString()}';
      });
    }
  }

  Future<void> _storeLocationLocally(Position position) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> storedLocations =
        prefs.getStringList('offlineLocations') ?? [];

    Map<String, dynamic> locationData = {
      'device_id': _deviceId,
      'device_name': _deviceName,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'altitude': position.altitude,
      'accuracy': position.accuracy,
      'speed': position.speed,
      'timestamp': position.timestamp?.toIso8601String(),
    };

    storedLocations.add(json.encode(locationData));
    await prefs.setStringList('offlineLocations', storedLocations);

    setState(() {
      _offlineCount = storedLocations.length;
    });
  }

  Future<void> _sendLocationToSupabase() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> storedLocations =
        prefs.getStringList('offlineLocations') ?? [];

    if (storedLocations.isEmpty) return;

    List locations = storedLocations.map((loc) => json.decode(loc)).toList();

    try {
      await supabase.from('locations').insert(locations);
      await prefs.remove('offlineLocations');
      setState(() {
        _offlineCount = 0;
      });
    } catch (e) {
      print('Failed to send locations to Supabase: ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Location Tracking Status',
                style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: 8),
            _buildInfoRow('Status:', _locationStatus),
            _buildInfoRow('Device:', _deviceName),
            _buildInfoRow('Offline Locations:', _offlineCount.toString()),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold)),
          Text(value, style: TextStyle(color: Colors.blue)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
