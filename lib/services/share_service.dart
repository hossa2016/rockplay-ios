import 'package:share_plus/share_plus.dart';

import '../models/song.dart';

/// Comparte una canción o una lista con el enlace de YouTube (WhatsApp y
/// demás apps muestran la portada sola a partir del enlace).
class ShareService {
  ShareService._();

  static String _link(Song s) => s.videoId.isNotEmpty
      ? 'https://youtu.be/${s.videoId}'
      : 'https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent('${s.artist} ${s.title}')}';

  static Future<void> song(Song s) async {
    final text = '🎸 ${s.title} — ${s.artist}\n${_link(s)}';
    try {
      await Share.share(text);
    } catch (_) {}
  }

  static Future<void> list(String title, List<Song> songs) async {
    final lines = [
      '🎸 $title (${songs.length} canciones)',
      for (final s in songs.take(15)) '• ${s.artist} - ${s.title}  ${_link(s)}',
      if (songs.length > 15) '…y ${songs.length - 15} más',
    ];
    try {
      await Share.share(lines.join('\n'));
    } catch (_) {}
  }
}
