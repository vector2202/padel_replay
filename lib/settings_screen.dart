import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _ipController;

  @override
  void initState() {
    super.initState();
    // En una versión futura usaríamos SharedPreferences para que persista al cerrar la app
    // Por ahora lo leemos de una variable estática que vamos a crear en NavScreen o AppState
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('AJUSTES')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const CircleAvatar(
            radius: 40,
            backgroundColor: Color(0xFF00FF88),
            child: Icon(Icons.person, size: 40, color: Colors.black),
          ),
          const SizedBox(height: 16),
          Text(
            user?.email ?? 'Usuario',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),

          const Text(
            'CONFIGURACIÓN DEL NODO',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // ESTO ES LO QUE BUSCÁBAMOS:
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: const Icon(Icons.lan, color: Color(0xFF00FF88)),
              title: const Text('Dirección del Edge Node'),
              subtitle: const Text('IP Local, Pública o Hostname'),
              trailing: const Icon(Icons.edit, size: 18),
              onTap: () => _showIpDialog(context),
            ),
          ),

          const SizedBox(height: 32),
          const Divider(color: Colors.white10),

          ListTile(
            leading: const Icon(Icons.help_outline, color: Color(0xFF00FF88)),
            title: const Text('Ayuda y Soporte'),
            onTap: () {},
          ),

          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Supabase.instance.client.auth.signOut(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.withOpacity(0.1),
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
            ),
            child: const Text('CERRAR SESIÓN'),
          ),
        ],
      ),
    );
  }

  void _showIpDialog(BuildContext context) {
    final controller = TextEditingController(text: AppState().edgeNodeIp);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configurar Nodo (IP o URL)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Si estás fuera de tu casa, usa tu IP Pública o URL de túnel (ngrok/tailscale).',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: "Ej: 192.168.0.15 o mi-node.ngrok.io",
                labelText: 'Dirección del Nodo',
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              AppState().setEdgeNodeIp(controller.text);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('IP actualizada correctamente')),
              );
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
