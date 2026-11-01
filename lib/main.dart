import 'package:flutter/material.dart';

void main() => runApp(const UltronApp());

class UltronApp extends StatelessWidget {
  const UltronApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'U.L.T.R.O.N.',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF08090C),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFB51224),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const CoreScreen(),
      );
}

class CoreScreen extends StatelessWidget {
  const CoreScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.blur_circular, size: 112, color: Color(0xFFB51224)),
                const SizedBox(height: 20),
                Text('U.L.T.R.O.N.',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          letterSpacing: 5,
                          fontWeight: FontWeight.w300,
                        )),
                const SizedBox(height: 8),
                const Text('MOBILE • INITIAL CORE'),
                const SizedBox(height: 32),
                const Text('Sistema pronto para configuração'),
              ],
            ),
          ),
        ),
      );
}
