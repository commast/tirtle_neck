import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'constants.dart';
import 'screens/main_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 포그라운드 서비스 통신 포트 초기화 (앱 시작 시 한 번만)
  FlutterForegroundTask.initCommunicationPort();
  runApp(const TirtleApp());
}

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
