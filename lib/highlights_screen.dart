import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';

class HighlightsScreen extends StatefulWidget {
  const HighlightsScreen({super.key});

  @override
  State<HighlightsScreen> createState() => _HighlightsScreenState();
}

class _HighlightsScreenState extends State<HighlightsScreen> {
  final supabase = Supabase.instance.client;

  late Stream<List<Map<String, dynamic>>> _highlightsStream;

  @override
  void initState() {
    super.initState();
    final userId = supabase.auth.currentUser?.id;

    // Escuchar solo los highlights del usuario actual
    _highlightsStream = supabase
        .from('highlights')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId ?? '')
        .order('created_at', ascending: false);
  }

  Future<void> _logout() async {
    await supabase.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = supabase.auth.currentUser?.email ?? 'Usuario';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text(
              'PADEL SNAP',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              userEmail,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.logout, size: 20),
          onPressed: _logout,
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _highlightsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Center(child: Text('Error: ${snapshot.error}'));
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          final highlights = snapshot.data!;
          if (highlights.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.video_library_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No hay jugadas aún.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: highlights.length,
            itemBuilder: (context, index) {
              final item = highlights[index];
              return HighlightCard(item: item, autoPreload: index < 2);
            },
          );
        },
      ),
    );
  }
}

class HighlightCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final bool autoPreload;
  const HighlightCard({
    super.key,
    required this.item,
    this.autoPreload = false,
  });

  @override
  State<HighlightCard> createState() => _HighlightCardState();
}

class _HighlightCardState extends State<HighlightCard> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _showVideo = false;
  bool _isSharing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoPreload) {
      _initializeVideo(autoPlay: false);
    }
  }

  Future<String?> _downloadVideo() async {
    final videoUrl = widget.item['video_url_vertical'] as String?;
    if (videoUrl == null) return null;

    final response = await http.get(Uri.parse(videoUrl));
    if (response.statusCode != 200) {
      throw Exception('Error al descargar video');
    }

    final bytes = response.bodyBytes;

    final temp = await getTemporaryDirectory();
    final directoryPath = '${temp.path}/highlights';
    await Directory(directoryPath).create(recursive: true);

    final filePath = '$directoryPath/replay_${widget.item['id']}.mp4';
    final file = File(filePath);

    await file.writeAsBytes(bytes, flush: true);
    return filePath;
  }

  Future<void> _saveToGallery() async {
    setState(() => _isSaving = true);
    try {
      // Pedir permisos si es necesario y guardar
      final filePath = await _downloadVideo();
      if (filePath != null && await File(filePath).exists()) {
        await Gal.putVideo(filePath, album: 'Padel Snap');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Video guardado en la galería!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('El archivo no se pudo crear');
      }
    } catch (e) {
      debugPrint('Error al guardar en galería: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo guardar el video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _shareVideo() async {
    final videoUrl = widget.item['video_url_vertical'] as String?;
    if (videoUrl == null) return;

    setState(() => _isSharing = true);
    try {
      final filePath = await _downloadVideo();

      if (filePath != null && await File(filePath).exists()) {
        await Share.shareXFiles([
          XFile(filePath),
        ], text: '¡Mira mi jugada en Padel Snap! ⚽🔥');
      } else {
        throw Exception('El archivo no se pudo crear');
      }
    } catch (e) {
      debugPrint('Error al compartir: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo compartir el video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  void _initializeVideo({bool autoPlay = true}) {
    // Si ya está inicializado y solo queremos mostrarlo
    if (_initialized && autoPlay) {
      setState(() => _showVideo = true);
      _controller?.play();
      return;
    }

    // Si ya se está cargando, no hacer nada más
    if (_controller != null && !_initialized) return;

    final videoUrl = widget.item['video_url_vertical'] as String?;
    debugPrint(' Intentando reproducir: $videoUrl');

    if (videoUrl != null) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));

      _controller!
          .initialize()
          .then((_) {
            debugPrint(' Video inicializado correctamente');
            if (mounted) {
              setState(() {
                _initialized = true;
                if (autoPlay) _showVideo = true;
              });
              if (autoPlay) _controller!.play();
            }
          })
          .catchError((error) {
            debugPrint(' Error al inicializar VideoPlayer: $error');
          });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Área de Video / Placeholder
          AspectRatio(
            aspectRatio: 9 / 16,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: _showVideo && _initialized
                  ? InkWell(
                      onTap: () {
                        setState(() {
                          _controller!.value.isPlaying
                              ? _controller!.pause()
                              : _controller!.play();
                        });
                      },
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          VideoPlayer(_controller!),
                          if (!_controller!.value.isPlaying)
                            const Icon(
                              Icons.play_circle_fill,
                              size: 60,
                              color: Colors.white70,
                            ),
                        ],
                      ),
                    )
                  : Container(
                      color: Colors.black26,
                      child: Center(
                        child: _showVideo
                            ? const CircularProgressIndicator()
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.play_circle_outline,
                                    size: 80,
                                    color: Color(0xFF00FF88),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: _initializeVideo,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF00FF88),
                                      foregroundColor: Colors.black,
                                    ),
                                    child: const Text('VER HIGHLIGHT'),
                                  ),
                                ],
                              ),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Jugada #${widget.item['id'].toString().substring(0, 4)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Grabado: ${DateTime.parse(widget.item['created_at']).toLocal().toString().split('.')[0]}',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ),
                Row(
                  children: [
                    _isSaving
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00FF88)),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(
                              Icons.download_rounded,
                              color: Color(0xFF00FF88),
                            ),
                            onPressed: _saveToGallery,
                            tooltip: 'Guardar en galería',
                          ),
                    const SizedBox(width: 8),
                    _isSharing
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00FF88)),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(
                              Icons.ios_share,
                              color: Color(0xFF00FF88),
                            ),
                            onPressed: _shareVideo,
                            tooltip: 'Compartir',
                          ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
