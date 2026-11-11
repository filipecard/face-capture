import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // O laboratório trabalha apenas em retrato: simplifica rotação e
  // espelhamento das coordenadas da câmera.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const FaceCaptureLabApp());
}

class FaceCaptureLabApp extends StatelessWidget {
  const FaceCaptureLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Capture Lab',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1565C0),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF1565C0),
      ),
      home: const HomePage(),
    );
  }
}
