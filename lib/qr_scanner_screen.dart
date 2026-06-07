import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_state.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  bool _isProcessing = false;

  Future<void> _handleDetection(String code) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final supabase = Supabase.instance.client;
      
      // Buscamos la cancha por su qr_code_data
      final response = await supabase
          .from('courts')
          .select('*, complexes(name)')
          .eq('qr_code_data', code)
          .maybeSingle();

      if (response != null) {
        // Registrar check-in en la base de datos de Supabase
        final userId = supabase.auth.currentUser?.id;
        if (userId != null) {
          try {
            await supabase.from('check_ins').insert({
              'user_id': userId,
              'court_id': response['id'],
            });
            debugPrint('Check-in registrado exitosamente en la DB para el usuario $userId');
          } catch (dbError) {
            debugPrint('Error al registrar check-in en la DB: $dbError');
          }
        }
        AppState().setActiveCourt(response);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('¡Ubicación fijada: ${response['complexes']['name']} - ${response['name']}!'),
              backgroundColor: const Color(0xFF00FF88),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Código QR no reconocido'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint('Error en escaneo: $e');
    } finally {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _isProcessing = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ESCANEAR CANCHA')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  _handleDetection(barcode.rawValue!);
                }
              }
            },
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _isProcessing ? Colors.orange : const Color(0xFF00FF88), 
                  width: 4
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: _isProcessing ? const Center(child: CircularProgressIndicator(color: Colors.orange)) : null,
            ),
          ),
          const Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Text(
              'Apunta al QR de la cancha',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
