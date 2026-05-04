import 'package:flutter/material.dart';
import 'constants.dart';
import 'screens/main_screen.dart';

void main() => runApp(const TirtleApp());

class TirtleApp extends StatelessWidget {
  const TirtleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '포스처가드',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kGreen,
          brightness: Brightness.light,
        ),
      ),
      home: const MainScreen(),
    );
  }
}
