import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'highlights_screen.dart';
import 'app_state.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => ExploreScreenState();
}

class ExploreScreenState extends State<ExploreScreen> {
  final supabase = Supabase.instance.client;

  Map<String, dynamic>? selectedComplex;
  Map<String, dynamic>? selectedCourt;
  DateTime selectedDate = DateTime.now();

  void resetFilters() {
    setState(() {
      selectedComplex = null;
      selectedCourt = null;
      selectedDate = DateTime.now();
    });
  }

  Widget _buildClubCard() {
    final complex = selectedComplex;
    if (complex == null) return const SizedBox.shrink();

    final id = complex['id'].toString();
    final imageUrl = complex['image_url'] ?? 'https://images.unsplash.com/photo-1626224583764-f87db24ac4ea?w=150&q=80';
    final name = complex['name'] ?? '';
    final location = complex['location'] ?? 'Sin dirección';

    return ListenableBuilder(
      listenable: AppState(),
      builder: (context, child) {
        final isFav = AppState().isFavoriteComplex(id);
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E20),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isFav ? const Color(0xFF00FF88).withOpacity(0.3) : Colors.white10,
              width: 1.5,
            ),
            image: DecorationImage(
              image: NetworkImage(imageUrl),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                Colors.black.withOpacity(0.65),
                BlendMode.darken,
              ),
            ),
            boxShadow: [
              if (isFav)
                BoxShadow(
                  color: const Color(0xFF00FF88).withOpacity(0.1),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00FF88).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.sports_tennis,
                        color: Color(0xFF00FF88),
                        size: 20,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      name.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: Color(0xFF00FF88),
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isFav ? const Color(0xFF00FF88).withOpacity(0.2) : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isFav ? 'FAVORITO' : 'AÑADIR FAVORITO',
                        style: TextStyle(
                          color: isFav ? const Color(0xFF00FF88) : Colors.white60,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      AppState().toggleFavoriteComplex(id);
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isFav ? Icons.star : Icons.star_border,
                        color: isFav ? const Color(0xFF00FF88) : Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  // Mostrar Bottom Sheet para seleccionar Complejo
  void _showComplexPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E20),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Selecciona el Complejo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: supabase.from('complexes').select(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF00FF88),
                        ),
                      );
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(
                        child: Text('No hay complejos disponibles'),
                      );
                    }

                    final complexes = List<Map<String, dynamic>>.from(snapshot.data!);
                    // Ordenar por favoritos primero
                    complexes.sort((a, b) {
                      final aFav = AppState().isFavoriteComplex(a['id'].toString());
                      final bFav = AppState().isFavoriteComplex(b['id'].toString());
                      if (aFav && !bFav) return -1;
                      if (!aFav && bFav) return 1;
                      // Si ambos son favoritos o ninguno, mantener orden alfabético por nombre
                      return (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString());
                    });

                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: complexes.length,
                      itemBuilder: (context, index) {
                        final complex = complexes[index];
                        final isSelected =
                            selectedComplex?['id'] == complex['id'];
                        final isFav = AppState().isFavoriteComplex(complex['id'].toString());

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: Row(
                            children: [
                              Text(
                                complex['name'],
                                style: TextStyle(
                                  color: isSelected
                                      ? const Color(0xFF00FF88)
                                      : Colors.white,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              if (isFav) ...[
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.star,
                                  color: Color(0xFF00FF88),
                                  size: 16,
                                ),
                              ],
                            ],
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF00FF88),
                                )
                              : null,
                          onTap: () {
                            setState(() {
                              selectedComplex = complex;
                              selectedCourt =
                                  null; // Reiniciar cancha al cambiar complejo
                            });
                            Navigator.pop(context);
                            // Abrir automáticamente el de cancha si hay canchas
                            _showCourtPicker();
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Mostrar Bottom Sheet para seleccionar Cancha
  void _showCourtPicker() {
    if (selectedComplex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero selecciona un complejo')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E20),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Canchas en ${selectedComplex!['name']}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: supabase
                      .from('courts')
                      .select()
                      .eq('complex_id', selectedComplex!['id']),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF00FF88),
                        ),
                      );
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(
                        child: Text(
                          'No hay canchas disponibles para este complejo',
                        ),
                      );
                    }

                    final courts = snapshot.data!;
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: courts.length,
                      itemBuilder: (context, index) {
                        final court = courts[index];
                        final isSelected = selectedCourt?['id'] == court['id'];

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: Text(
                            court['name'],
                            style: TextStyle(
                              color: isSelected
                                  ? const Color(0xFF00FF88)
                                  : Colors.white,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF00FF88),
                                )
                              : null,
                          onTap: () {
                            setState(() {
                              selectedCourt = court;
                            });
                            Navigator.pop(context);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Selector de Fecha Nativo
  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00FF88),
              onPrimary: Colors.black,
              surface: Color(0xFF1E1E20),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('dd MMM').format(selectedDate);

    return Scaffold(
      backgroundColor: const Color(0xFF121214),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'EXPLORAR JUGADAS',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Banner Horizontal de Filtros
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1C),
              border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Filtro Complejo
                  _buildFilterChip(
                    label: selectedComplex != null
                        ? selectedComplex!['name']
                        : 'Complejo',
                    isActive: selectedComplex != null,
                    onTap: _showComplexPicker,
                  ),
                  const SizedBox(width: 8),

                  // Filtro Cancha
                  _buildFilterChip(
                    label: selectedCourt != null
                        ? selectedCourt!['name']
                        : 'Cancha',
                    isActive: selectedCourt != null,
                    onTap: _showCourtPicker,
                    isEnabled: selectedComplex != null,
                  ),
                  const SizedBox(width: 8),

                  // Filtro Fecha
                  _buildFilterChip(
                    label: formattedDate,
                    isActive: true,
                    onTap: _selectDate,
                  ),
                ],
              ),
            ),
          ),

          // Contenido Principal
          Expanded(
            child: selectedCourt == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.sports_tennis_rounded,
                            size: 64,
                            color: Colors.grey[700],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            selectedComplex == null
                                ? 'Selecciona un complejo para ver las jugadas'
                                : 'Selecciona una cancha',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: selectedComplex == null
                                ? _showComplexPicker
                                : _showCourtPicker,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00FF88),
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                            child: Text(
                              selectedComplex == null
                                  ? 'Elegir Complejo'
                                  : 'Elegir Cancha',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : _buildFilteredHighlights(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    bool isEnabled = true,
  }) {
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF00FF88).withOpacity(0.15)
                : const Color(0xFF262628),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: isActive ? const Color(0xFF00FF88) : Colors.white10,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isActive ? const Color(0xFF00FF88) : Colors.white70,
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: isActive ? const Color(0xFF00FF88) : Colors.white38,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilteredHighlights() {
    // Convertir inicio y fin del día LOCAL a UTC para comparar correctamente
    // con el created_at de Supabase (que está en UTC)
    final startOfDay = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    ).toUtc().toIso8601String();
    final endOfDay = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      23,
      59,
      59,
    ).toUtc().toIso8601String();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: supabase
          .from('highlights')
          .select()
          .eq('court_id', selectedCourt!['id'])
          .gte('created_at', startOfDay)
          .lte('created_at', endOfDay)
          .order('created_at', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00FF88)),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        final items = snapshot.data!;

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 9 / 16,
          ),
          itemCount: items.isEmpty ? 2 : items.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildClubCard();
            }
            if (items.isEmpty && index == 1) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.05),
                    width: 1,
                  ),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.video_camera_back_outlined,
                      size: 32,
                      color: Colors.grey[700],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Sin jugadas\neste día',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            }
            final itemIndex = index - 1;
            return HighlightCard(
              item: items[itemIndex],
              autoPreload: itemIndex < 3,
            );
          },
        );
      },
    );
  }
}
