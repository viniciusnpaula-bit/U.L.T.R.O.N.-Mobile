import 'package:flutter/material.dart';
import 'ui/screens/core_screen.dart';

void main() => runApp(const UltronApp());

class UltronApp extends StatelessWidget {
  const UltronApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'U.L.T.R.O.N.', debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: const Color(0xFF08090C), colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB51224), brightness: Brightness.dark), useMaterial3: true),
    home: const CoreScreen(),
  );
}
