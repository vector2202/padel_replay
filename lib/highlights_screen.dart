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
      backgroundColor: const Color(0xFF121214),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          children: [
            const Text(
              'MIS PLAYS',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              userEmail,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.logout, size: 20, color: Colors.white70),
          onPressed: _logout,
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _highlightsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF00FF88)),
            );
          }

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

          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 9 / 16,
            ),
            itemCount: highlights.length,
            itemBuilder: (context, index) {
              final item = highlights[index];
              // Pre-cargar el primer frame de manera nativa solo para los primeros 4 videos (visibles al entrar)
              return HighlightCard(item: item, autoPreload: index < 4);
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
  bool _isSharing = false;
  bool _isSaving = false;

  bool _isFavorited = false;
  bool _checkingFavorite = true;
  String? _favoriteRecordId;
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _checkIfFavorited();
    if (widget.autoPreload) {
      _initializeVideo();
    }
  }

  // Inicializar controlador para el primer frame silenciosamente
  void _initializeVideo() {
    if (_controller != null) return;

    final videoUrl = widget.item['video_url_vertical'] as String?;
    if (videoUrl != null) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      _controller!
          .initialize()
          .then((_) {
            if (mounted) {
              setState(() {
                _initialized = true;
              });
            }
          })
          .catchError((error) {
            debugPrint('Error al inicializar previsualización: $error');
          });
    }
  }

  Future<void> _checkIfFavorited() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _checkingFavorite = false);
      return;
    }

    // Si la jugada ya pertenece al usuario logueado en la base de datos
    if (widget.item['user_id'] == userId) {
      if (mounted) {
        setState(() {
          _isFavorited = true;
          _checkingFavorite = false;
        });
      }
      return;
    }

    try {
      final response = await _supabase
          .from('highlights')
          .select('id')
          .eq('video_url_vertical', widget.item['video_url_vertical'] ?? '')
          .eq('user_id', userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _isFavorited = response != null;
          _favoriteRecordId = response?['id']?.toString();
          _checkingFavorite = false;
        });
      }
    } catch (e) {
      debugPrint('Error al verificar favorito: $e');
      if (mounted) setState(() => _checkingFavorite = false);
    }
  }

  Future<void> _toggleFavorite() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _checkingFavorite = true);

    try {
      if (_isFavorited) {
        // Quitar de favoritos (Borrar registro duplicado)
        final recordIdToDelete = _favoriteRecordId ?? 
            (widget.item['user_id'] == userId ? widget.item['id']?.toString() : null);

        if (recordIdToDelete != null) {
          await _supabase.from('highlights').delete().eq('id', recordIdToDelete);
        } else {
          await _supabase
              .from('highlights')
              .delete()
              .eq('video_url_vertical', widget.item['video_url_vertical'] ?? '')
              .eq('user_id', userId);
        }

        if (mounted) {
          setState(() {
            _isFavorited = false;
            _favoriteRecordId = null;
          });
        }
      } else {
        // Añadir a favoritos (Crear copia de la fila)
        final response = await _supabase.from('highlights').insert({
          'video_url_vertical': widget.item['video_url_vertical'],
          'duration_seconds': widget.item['duration_seconds'],
          'user_id': userId,
          'court_id': widget.item['court_id'],
          'status': widget.item['status'],
        }).select('id').single();

        if (mounted) {
          setState(() {
            _isFavorited = true;
            _favoriteRecordId = response['id']?.toString();
          });
        }
      }
    } catch (e) {
      debugPrint('Error al cambiar estado de favorito: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar jugada: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingFavorite = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
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

  void _openFullScreen() {
    final videoUrl = widget.item['video_url_vertical'] as String?;
    if (videoUrl == null) return;

    // Si no está inicializado, lo inicializamos para cuando vuelva
    _initializeVideo();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenVideoPlayer(
          videoUrl: videoUrl,
          title: 'Jugada #${widget.item['id'].toString().substring(0, 4)}',
          dateString:
              'Grabado: ${DateTime.parse(widget.item['created_at']).toLocal().toString().split('.')[0]}',
          onShare: _shareVideo,
          onSave: _saveToGallery,
          isSharing: _isSharing,
          isSaving: _isSaving,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Si no está inicializado pero el widget entra en pantalla, lo inicializamos de forma perezosa
    if (!_initialized && _controller == null) {
      _initializeVideo();
    }

    final dateString = DateTime.parse(
      widget.item['created_at'],
    ).toLocal().toString().split(' ')[0];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Preview / Video renderizado (primer frame estático)
            Positioned.fill(
              child: _initialized && _controller != null
                  ? AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    )
                  : Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF1E1E22), Color(0xFF101012)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.sports_tennis_rounded,
                          color: const Color(0xFF00FF88).withOpacity(0.15),
                          size: 40,
                        ),
                      ),
                    ),
            ),

            // Sombra oscura inferior para leer textos y controles
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black54,
                      Colors.transparent,
                      Colors.black87,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.4, 1.0],
                  ),
                ),
              ),
            ),

            // Botón de Play gigante en medio (abre pantalla completa)
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _openFullScreen,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Color(0xFF00FF88),
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Textos descriptivos (Inferior izquierdo)
            Positioned(
              left: 10,
              bottom: 44,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Jugada #${widget.item['id'].toString().substring(0, 4)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateString,
                    style: TextStyle(color: Colors.grey[400], fontSize: 10),
                  ),
                ],
              ),
            ),

            // Botones de acción inferiores (Descargar, Compartir)
            Positioned(
              left: 6,
              bottom: 4,
              right: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _isSaving
                      ? const SizedBox(
                          width: 28,
                          height: 28,
                          child: Padding(
                            padding: EdgeInsets.all(6),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF00FF88),
                            ),
                          ),
                        )
                      : IconButton(
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(
                            Icons.download_rounded,
                            color: Color(0xFF00FF88),
                          ),
                          onPressed: _saveToGallery,
                          tooltip: 'Guardar',
                        ),
                  _isSharing
                      ? const SizedBox(
                          width: 28,
                          height: 28,
                          child: Padding(
                            padding: EdgeInsets.all(6),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF00FF88),
                            ),
                          ),
                        )
                      : IconButton(
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(
                            Icons.ios_share,
                            color: Color(0xFF00FF88),
                          ),
                          onPressed: _shareVideo,
                          tooltip: 'Compartir',
                        ),
                ],
              ),
            ),

            // Botón de estrella flotante (favoritos)
            Positioned(
              top: 10,
              right: 10,
              child: _checkingFavorite
                  ? Container(
                      padding: const EdgeInsets.all(6),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00FF88)),
                      ),
                    )
                  : GestureDetector(
                      onTap: _toggleFavorite,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          _isFavorited ? Icons.star_rounded : Icons.star_border_rounded,
                          color: _isFavorited ? const Color(0xFF00FF88) : Colors.white70,
                          size: 20,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
//  Full-Screen Video Player
// ──────────────────────────────────────────────
class FullScreenVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String dateString;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final bool isSharing;
  final bool isSaving;

  const FullScreenVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.title,
    required this.dateString,
    required this.onShare,
    required this.onSave,
    this.isSharing = false,
    this.isSaving = false,
  });

  @override
  State<FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<FullScreenVideoPlayer> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _controller.initialize().then((_) {
      if (mounted) {
        setState(() => _initialized = true);
        _controller.play();
      }
    });
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleControls() => setState(() => _controlsVisible = !_controlsVisible);

  void _togglePlayPause() {
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Video ──
            Center(
              child: _initialized
                  ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    )
                  : const CircularProgressIndicator(
                      color: Color(0xFF00FF88),
                    ),
            ),

            // ── Overlay Controls ──
            if (_controlsVisible) ...[
              // Top bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 8,
                    bottom: 16,
                    left: 8,
                    right: 16,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black87, Colors.transparent],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              widget.dateString,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Center Play/Pause button
              Center(
                child: GestureDetector(
                  onTap: _togglePlayPause,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _controller.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: const Color(0xFF00FF88),
                      size: 48,
                    ),
                  ),
                ),
              ),

              // Bottom bar — progress + actions
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 16,
                    top: 24,
                    left: 16,
                    right: 16,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Colors.black87],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Progress slider
                      if (_initialized)
                        Row(
                          children: [
                            Text(
                              _formatDuration(_controller.value.position),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                            Expanded(
                              child: Slider(
                                activeColor: const Color(0xFF00FF88),
                                inactiveColor: Colors.white24,
                                value: _controller.value.position.inMilliseconds
                                    .toDouble()
                                    .clamp(
                                      0,
                                      _controller.value.duration.inMilliseconds
                                          .toDouble(),
                                    ),
                                min: 0,
                                max: _controller.value.duration.inMilliseconds
                                    .toDouble()
                                    .clamp(1, double.infinity),
                                onChanged: (v) => _controller.seekTo(
                                  Duration(milliseconds: v.toInt()),
                                ),
                              ),
                            ),
                            Text(
                              _formatDuration(_controller.value.duration),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),

                      // Action buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Save to gallery
                          widget.isSaving
                              ? const SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Padding(
                                    padding: EdgeInsets.all(10),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF00FF88),
                                    ),
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(
                                    Icons.download_rounded,
                                    color: Color(0xFF00FF88),
                                    size: 26,
                                  ),
                                  tooltip: 'Guardar en galería',
                                  onPressed: widget.onSave,
                                ),

                          const SizedBox(width: 24),

                          // Share
                          widget.isSharing
                              ? const SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Padding(
                                    padding: EdgeInsets.all(10),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF00FF88),
                                    ),
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(
                                    Icons.ios_share,
                                    color: Color(0xFF00FF88),
                                    size: 26,
                                  ),
                                  tooltip: 'Compartir',
                                  onPressed: widget.onShare,
                                ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
