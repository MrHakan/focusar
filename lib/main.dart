import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FocusArApp());
}

class FocusArApp extends StatelessWidget {
  const FocusArApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF071427);
    const blue = Color(0xFF5B7CFF);

    return MaterialApp(
      title: 'FocusAR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: blue,
          brightness: Brightness.dark,
          surface: const Color(0xFF101F36),
        ),
        useMaterial3: true,
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: -2,
          ),
          headlineMedium: TextStyle(fontWeight: FontWeight.w700),
          titleLarge: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
