import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'gps_tracker_channel',
    'GPS Tracker Service',
    description: 'This channel is used for GPS tracking notifications',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'gps_tracker_channel',
      initialNotificationTitle: 'GPS Tracker Service',
      initialNotificationContent: 'Running',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );

  service.startService();
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  Timer.periodic(Duration(minutes: 15), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        service.setForegroundNotificationInfo(
          title: "GPS Tracker Service",
          content: "Running",
        );
      }
    }

    await updateAndSendLocation();

    service.invoke(
      'update',
      {
        "current_date": DateTime.now().toIso8601String(),
      },
    );
  });
}

Future<void> updateAndSendLocation() async {
  try {
    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('deviceId');
    String? deviceName = prefs.getString('deviceName');

    Map<String, dynamic> locationData = {
      'device_id': deviceId,
      'device_name': deviceName,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'altitude': position.altitude,
      'accuracy': position.accuracy,
      'speed': position.speed,
      'timestamp': position.timestamp.toIso8601String(),
    };

    await storeLocationLocally(locationData);
    await sendLocationToSupabase();
  } catch (e) {
    print('Error in updateAndSendLocation: $e');
  }
}

Future<void> storeLocationLocally(Map<String, dynamic> locationData) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  List<String> storedLocations = prefs.getStringList('offlineLocations') ?? [];

  storedLocations.add(json.encode(locationData));
  await prefs.setStringList('offlineLocations', storedLocations);
}

Future<void> sendLocationToSupabase() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  List<String> storedLocations = prefs.getStringList('offlineLocations') ?? [];

  if (storedLocations.isEmpty) return;

  List locations = storedLocations.map((loc) => json.decode(loc)).toList();

  try {
    final supabase = Supabase.instance.client;
    await supabase.from('locations').insert(locations);
    await prefs.remove('offlineLocations');
  } catch (e) {
    print('Failed to send locations to Supabase: $e');
  }
}
