import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/artist_info_service.dart';
import '../services/music_mode.dart';
import '../theme/app_theme.dart';
import '../widgets/state_views.dart';
import '../widgets/cover_art.dart';
import '../widgets/player_route.dart';
import '../widgets/section_header.dart';
import 'song_list_screen.dart';
import '../services/radar_service.dart';
import '../services/concert_service.dart';

/// Ficha de artista: foto, biografía, lo más escuchado y discos.
class ArtistScreen extends StatefulWidget {
  final String name;
  const ArtistScreen({super.key, required this.name});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  final ArtistInfoService _svc = ArtistInfoService.instance;
  ArtistInfo? _artist;
  List<AlbumInfo> _albums = [];
  String? _bio;
  bool _loading = true;
  bool _notFound = false;
  bool _bioOpen = false;
  bool _following = false;

  @override
  void initState() {
    super.initState();
    RadarService.instance.isFollowed(widget.name).then((v) {
      if (mounted) setState(() => _following = v);
    });
    _load();
  }

  Future<void> _load() async {
    final a = await _svc.artist(widget.name);
    if (!mounted) return;
    if (a == null) {
      setState(() {
        _loading = false;
        _notFound = true;
      });
      return;
    }
    setState(() {
      _artist = a;
      _loading = false;
    });
    _svc.bio(a.name).then((b) {
      if (mounted) setState(() => _bio = b);
    });
    try {
      final al = await _svc.albums(a.id);
      if (mounted) setState(() => _albums = al);
    } catch (_) {}
  }

  Future<void> _playTop() async {
    final a = _artist;
    if (a == null) return;
    try {
      final l = await _svc.topTracks(a.id, a.name);
      if (!mounted || l.isEmpty) return;
      playSongs(context, l..shuffle(), 0);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No pude cargar las canciones.')));
    }
  }

  void _openLive() {
    final a = _artist!;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SongListScreen(
        title: 'En vivo',
        subtitle: a.name,
        stream: _svc.liveSongs(a.name).asStream(),
        emptyMessage: 'No encontré presentaciones en vivo.',
      ),
    ));
  }

  void _openAlbum(AlbumInfo al) {
    final a = _artist!;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SongListScreen(
        title: al.title,
        subtitle: [a.name, if (al.year != null) '${al.year}'].join(' · '),
        stream: _svc.albumTracks(al, a.name).asStream(),
        emptyMessage: 'No pude cargar este disco.',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final a = _artist;
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const SkeletonList()
            : _notFound || a == null
                ? StateMessage(
                    icon: Icons.person_search_rounded,
                    title: 'Artista no encontrado',
                    message: 'No encontré información de este artista.',
                    actionLabel: 'Volver',
                    onAction: () => Navigator.of(context).pop(),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 32),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                        child: Row(children: [
                          IconButton(
                            tooltip: 'Volver',
                            icon: const Icon(Icons.arrow_back_rounded),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ]),
                      ),
                      Center(
                        child: ClipOval(
                          child: SizedBox(
                            width: 150,
                            height: 150,
                            child: a.picture.isEmpty
                                ? ColoredBox(color: AppColors.surfaceWarm)
                                : Image.network(a.picture, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          MusicModeService.general ? a.name : a.name.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      if (a.fans > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('${_fmt(a.fans)} seguidores en Deezer',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: AppColors.textDim, fontSize: AppType.label)),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: FilledButton.icon(
                          onPressed: _playTop,
                          icon: const Icon(Icons.shuffle_rounded),
                          label: const Text('Escuchar lo más popular'),
                        ),
                      ),
                      // «Toca pronto en…» si está en Conciertos.
                      Builder(builder: (context) {
                        final cs = ConcertService.instance.state.value.items
                            .where((c) =>
                                RadarService.matchBand(c, [a.name]) != null &&
                                (c.date == null ||
                                    !c.date!.isBefore(DateTime(DateTime.now().year,
                                        DateTime.now().month, DateTime.now().day))))
                            .toList();
                        if (cs.isEmpty) return const SizedBox.shrink();
                        final c = cs.first;
                        final d = c.date;
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.confirmation_number_rounded,
                                  size: 18, color: AppColors.amber),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                    'Toca pronto en ${c.city.isEmpty ? 'Colombia' : c.city}${d == null ? '' : ' · ${d.day}/${d.month}/${d.year}'}',
                                    style: TextStyle(
                                        color: AppColors.amber,
                                        fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ),
                        );
                      }),
                      // Seguir: el Radar avisa si viene a Colombia.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final v = await RadarService.instance.toggleFollow(widget.name);
                            if (!mounted) return;
                            setState(() => _following = v);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(v
                                    ? 'Te aviso si ${a.name} anuncia concierto en Colombia.'
                                    : 'Ya no sigues a ${a.name}.')));
                          },
                          icon: Icon(_following
                              ? Icons.notifications_active_rounded
                              : Icons.notifications_none_rounded),
                          label: Text(_following ? 'Siguiendo' : 'Seguir'),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        child: OutlinedButton.icon(
                          onPressed: _openLive,
                          icon: const Icon(Icons.mic_external_on_rounded),
                          label: const Text('Presentaciones en vivo'),
                        ),
                      ),
                      if (_bio != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                          child: GestureDetector(
                            onTap: () => setState(() => _bioOpen = !_bioOpen),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _bio!,
                                  maxLines: _bioOpen ? null : 5,
                                  overflow: _bioOpen
                                      ? TextOverflow.visible
                                      : TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      height: 1.45, color: AppColors.textBody),
                                ),
                                const SizedBox(height: 4),
                                Text(_bioOpen ? 'Ver menos' : 'Leer más',
                                    style: TextStyle(
                                        color: AppColors.amber, fontSize: AppType.label)),
                                const SizedBox(height: 2),
                                Text('Fuente: Wikipedia',
                                    style: TextStyle(
                                        color: AppColors.textFaint,
                                        fontSize: AppType.caption)),
                              ],
                            ),
                          ),
                        ),
                      if (_albums.isNotEmpty) ...[
                        const SectionTitle('Discos'),
                        SizedBox(
                          height: 210,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _albums.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, i) {
                              final al = _albums[i];
                              return GestureDetector(
                                onTap: () => _openAlbum(al),
                                child: SizedBox(
                                  width: 140,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      CoverArt(
                                          url: al.cover, size: 140, radius: 12),
                                      const SizedBox(height: 8),
                                      Text(al.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: AppType.label)),
                                      if (al.year != null)
                                        Text('${al.year}',
                                            style: TextStyle(
                                                color: AppColors.textDim,
                                                fontSize: AppType.caption)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
      ),
    );
  }

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)} M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)} mil';
    return '$n';
  }
}
