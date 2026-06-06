import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'app_state.dart';
import 'highlights_screen.dart';
import 'explore_screen.dart';
import 'qr_scanner_screen.dart';
import 'settings_screen.dart';

class NavScreen extends StatefulWidget {
  const NavScreen({super.key});

  @override
  State<NavScreen> createState() => _NavScreenState();
}

class _NavScreenState extends State<NavScreen> {
  @override
  void initState() {
    super.initState();
    AppState().addListener(_onStateChanged);
  }

  @override
  void dispose() {
    AppState().removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    // Si se acaba de activar una cancha y estamos en la pestaña de QR (1),
    // nos movemos automáticamente a Explorar (0)
    if (AppState().hasActiveSession && _selectedIndex == 1) {
      setState(() => _selectedIndex = 0);
    } else {
      // Solo actualizamos la UI para mostrar/quitar el banner
      setState(() {});
    }
  }

  int _selectedIndex = 0;

  // IP corregida según tu terminal
  String edgeNodeIp = "192.168.0.15";

  final List<Widget> _screens = [
    const ExploreScreen(),
    const QrScannerScreen(),
    const HighlightsScreen(),
    const SettingsScreen(),
  ];

  Future<void> _triggerHighlight() async {
    debugPrint('>>> BOTÓN REPLAY PRESIONADO <<<');
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final court = AppState().activeCourt;

    if (court == null) {
      debugPrint('>>> ERROR: Sin cancha activa <<<');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escanea primero el QR de tu cancha'),
          backgroundColor: Colors.orange,
        ),
      );
      setState(() => _selectedIndex = 1); // Lo llevamos al escáner
      return;
    }

    final courtId = court['id'];
    String nodeAddress = AppState().edgeNodeIp.trim();
    
    // Si no tiene esquema, asumimos http y puerto 8000 si no tiene puerto
    if (!nodeAddress.startsWith('http')) {
      nodeAddress = 'http://$nodeAddress';
    }
    if (!nodeAddress.contains(':', 6)) { // 6 para saltar http://
      nodeAddress = '$nodeAddress:8000';
    }

    final url = '$nodeAddress/trigger?user_id=$userId&court_id=$courtId';
    debugPrint('>>> Llamando a: $url');

    try {
      final response = await http.post(Uri.parse(url)).timeout(const Duration(seconds: 5));
      debugPrint('>>> Respuesta del PC: ${response.statusCode}');
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚽ ¡Grabando en ${court['name']}!'),
            backgroundColor: const Color(0xFF00FF88),
          ),
        );
      } else {
        throw Exception('Status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('>>> ERROR de conexión: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: No se pudo conectar al Nodo ($e). Revisa la dirección en Ajustes.'),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeCourt = AppState().activeCourt;

    return Scaffold(
      body: Column(
        children: [
          if (activeCourt != null)
            Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                bottom: 8,
                left: 16,
                right: 16,
              ),
              color: const Color(0xFF00FF88).withOpacity(0.1),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    color: Color(0xFF00FF88),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Jugando en: ${activeCourt['complexes']['name']} - ${activeCourt['name']}',
                      style: const TextStyle(
                        color: Color(0xFF00FF88),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => AppState().clearSession(),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white54,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: _screens[_selectedIndex]),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(0, Icons.explore_outlined, 'Explorar'),
            _buildNavItem(1, Icons.qr_code_scanner, 'Escanear'),
            const SizedBox(width: 48), // Espacio para el botón central
            _buildNavItem(2, Icons.person_outline, 'Mis Play'),
            _buildNavItem(3, Icons.settings_outlined, 'Ajustes'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _triggerHighlight,
        backgroundColor: const Color(0xFF00FF88),
        elevation: 4,
        child: const Icon(Icons.videocam, color: Colors.black, size: 30),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isSelected ? const Color(0xFF00FF88) : Colors.grey),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isSelected ? const Color(0xFF00FF88) : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
