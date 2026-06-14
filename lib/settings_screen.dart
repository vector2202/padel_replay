import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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

          const SizedBox(height: 24),
          const Text(
            'MIS CLUBES FAVORITOS',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ListenableBuilder(
            listenable: AppState(),
            builder: (context, child) {
              return FutureBuilder<List<Map<String, dynamic>>>(
                future: Supabase.instance.client.from('complexes').select(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(
                          color: Color(0xFF00FF88),
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No hay clubes disponibles'),
                    );
                  }
                  final complexes = snapshot.data!;
                  final favoriteComplexes = complexes.where((c) => AppState().isFavoriteComplex(c['id'].toString())).toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (favoriteComplexes.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Aún no tienes clubes favoritos.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: favoriteComplexes.length,
                          itemBuilder: (context, index) {
                            final complex = favoriteComplexes[index];
                            final id = complex['id'].toString();
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              color: Colors.white.withOpacity(0.05),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        complex['image_url'] ??
                                            'https://images.unsplash.com/photo-1626224583764-f87db24ac4ea?w=150&q=80',
                                        width: 50,
                                        height: 50,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) =>
                                            Container(
                                          width: 50,
                                          height: 50,
                                          color: Colors.white10,
                                          child: const Icon(
                                            Icons.sports_tennis,
                                            color: Color(0xFF00FF88),
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            complex['name'] ?? '',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.location_on,
                                                size: 12,
                                                color: Colors.grey,
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  complex['location'] ??
                                                      'Dirección no especificada',
                                                  style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 11,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.star,
                                        color: Color(0xFF00FF88),
                                      ),
                                      onPressed: () {
                                        AppState().toggleFavoriteComplex(id);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _showManageFavoritesDialog(context, complexes),
                        icon: const Icon(Icons.star_border, size: 18),
                        label: const Text('Gestionar Clubes'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF00FF88),
                          side: const BorderSide(color: Color(0xFF00FF88)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
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

  void _showManageFavoritesDialog(BuildContext context, List<Map<String, dynamic>> complexes) {
    showDialog(
      context: context,
      builder: (context) {
        return ListenableBuilder(
          listenable: AppState(),
          builder: (context, child) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E20),
              title: const Text('Gestionar Clubes'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: complexes.length,
                  separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (context, index) {
                    final complex = complexes[index];
                    final id = complex['id'].toString();
                    final name = complex['name'] ?? '';
                    final isFav = AppState().isFavoriteComplex(id);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(name, style: const TextStyle(color: Colors.white)),
                      subtitle: Text(complex['location'] ?? 'Sin dirección', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                      trailing: IconButton(
                        icon: Icon(
                          isFav ? Icons.star : Icons.star_border,
                          color: isFav ? const Color(0xFF00FF88) : Colors.white30,
                        ),
                        onPressed: () {
                          AppState().toggleFavoriteComplex(id);
                        },
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Aceptar', style: TextStyle(color: Color(0xFF00FF88))),
                ),
              ],
            );
          },
        );
      },
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
