import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_gate.dart';
import 'app_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Asegúrate de usar tu clave real aquí
  await Supabase.initialize(
    url: 'https://cwubftnikhgbspndecoc.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN3dWJmdG5pa2hnYnNwbmRlY29jIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxMzM2NjksImV4cCI6MjA5MjcwOTY2OX0.Iej5JNLUipE2TYd1-3FRd0r1XdgBN2XIXIqgYtggptw',
  );

  await AppState().init();

  runApp(const PadelSnapApp());
}

class PadelSnapApp extends StatelessWidget {
  const PadelSnapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Padel Snap',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00FF88), 
          brightness: Brightness.dark,
          surface: const Color(0xFF0A0A0B),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0B),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00FF88))),
        ),
      ),
      home: const AuthGate(),
    );
  }
}
