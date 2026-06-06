import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'highlights_screen.dart'; // Reutilizaremos el card de highlight

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final supabase = Supabase.instance.client;
  
  Map<String, dynamic>? selectedComplex;
  Map<String, dynamic>? selectedCourt;
  DateTime selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EXPLORAR')),
      body: Column(
        children: [
          // 1. Selector de Complejo
          _buildSectionTitle('1. Selecciona el Complejo'),
          _buildComplexSelector(),
          
          if (selectedComplex != null) ...[
            // 2. Selector de Cancha
            _buildSectionTitle('2. Selecciona la Cancha'),
            _buildCourtSelector(),
          ],

          if (selectedCourt != null) ...[
            // 3. Selector de Fecha
            _buildSectionTitle('3. Selecciona el Día'),
            _buildDateSelector(),
            
            // 4. Lista de Videos filtrados
            Expanded(child: _buildFilteredHighlights()),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00FF88))),
    );
  }

  Widget _buildComplexSelector() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: supabase.from('complexes').select(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();
        final complexes = snapshot.data!;
        return SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: complexes.length,
            itemBuilder: (context, index) {
              final complex = complexes[index];
              final isSelected = selectedComplex?['id'] == complex['id'];
              return GestureDetector(
                onTap: () => setState(() {
                  selectedComplex = complex;
                  selectedCourt = null;
                }),
                child: Container(
                  width: 150,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF00FF88) : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isSelected ? Colors.white : Colors.transparent),
                  ),
                  child: Center(
                    child: Text(
                      complex['name'],
                      style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildCourtSelector() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: supabase.from('courts').select().eq('complex_id', selectedComplex!['id']),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        final courts = snapshot.data!;
        return SizedBox(
          height: 50,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: courts.length,
            itemBuilder: (context, index) {
              final court = courts[index];
              final isSelected = selectedCourt?['id'] == court['id'];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(court['name']),
                  selected: isSelected,
                  onSelected: (val) => setState(() => selectedCourt = court),
                  selectedColor: const Color(0xFF00FF88),
                  labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDateSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListTile(
        tileColor: Colors.white.withOpacity(0.05),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Fecha: ${selectedDate.toString().split(' ')[0]}'),
        trailing: const Icon(Icons.calendar_month, color: Color(0xFF00FF88)),
        onTap: () async {
          final date = await showDatePicker(
            context: context,
            initialDate: selectedDate,
            firstDate: DateTime(2024),
            lastDate: DateTime.now(),
          );
          if (date != null) setState(() => selectedDate = date);
        },
      ),
    );
  }

  Widget _buildFilteredHighlights() {
    final startOfDay = DateTime(selectedDate.year, selectedDate.month, selectedDate.day).toIso8601String();
    final endOfDay = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, 23, 59, 59).toIso8601String();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: supabase
          .from('highlights')
          .select()
          .eq('court_id', selectedCourt!['id'])
          .gte('created_at', startOfDay)
          .lte('created_at', endOfDay)
          .order('created_at', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        
        final items = snapshot.data!;
        if (items.isEmpty) return const Center(child: Text('No hay jugadas este día.'));
        
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) => HighlightCard(item: items[index]),
        );
      },
    );
  }
}
