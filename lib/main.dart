import 'package:flutter/material.dart';

import 'screens/trip_list_screen.dart';

void main() {
  runApp(const TripInventoryApp());
}

class TripInventoryApp extends StatelessWidget {
  const TripInventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trip Inventory Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D6B),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D6B),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const TripListScreen(),
    );
  }
}
