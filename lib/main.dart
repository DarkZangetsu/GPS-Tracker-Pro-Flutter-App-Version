import 'package:flutter/material.dart';
import 'package:gps_tracker_pro/components/location_tracker.dart';
import 'package:gps_tracker_pro/screens/home_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'your-supabase-url',
    anonKey: 'yours-supabase-key',
  );

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GPS Tracker Pro',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: GPSTrackerHomePage(),
    );
  }
}

class GPSTrackerHomePage extends StatefulWidget {
  @override
  _GPSTrackerHomePageState createState() => _GPSTrackerHomePageState();
}

class _GPSTrackerHomePageState extends State<GPSTrackerHomePage> {
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    _checkAndRequestPermissions();
  }

  Future<void> _checkAndRequestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.locationAlways,
    ].request();

    if (statuses[Permission.locationAlways] == PermissionStatus.granted) {
      setState(() {
        _permissionsGranted = true;
      });
    } else {
      _showPermissionDeniedDialog();
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Location Permission Required'),
        content: Text(
            'This app needs location permissions to function properly. Please grant the permissions in the app settings.'),
        actions: <Widget>[
          TextButton(
            child: Text('Open Settings'),
            onPressed: () {
              openAppSettings();
              Navigator.of(context).pop();
            },
          ),
          TextButton(
            child: Text('Cancel'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          HomeScreen(),
          if (_permissionsGranted)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: LocationTracker(),
            ),
        ],
      ),
    );
  }
}
