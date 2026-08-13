import 'package:flutter/material.dart';

import 'theme/tiza_theme.dart';
import 'ui/capture_screen.dart';

void main() {
  // flutter_secure_storage habla por MethodChannel, y el binding tiene que estar
  // listo antes de la primera lectura de la key.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TizaApp());
}

class TizaApp extends StatelessWidget {
  const TizaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tiza',
      debugShowCheckedModeBanner: false,
      theme: tizaTheme(Brightness.light),
      darkTheme: tizaTheme(Brightness.dark),
      home: const CaptureScreen(),
    );
  }
}
