import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/song.dart';

/// Importar listas: un enlace de lista pública de YouTube (solo los
/// datos, no se descarga audio) o texto/CSV con «Artista - Canción» por
/// línea (por ejemplo, exportado de Spotify con TuneMyMusic).
class ImportService {
  ImportService._();

  static String? _playlistId(String text) {
    final m = RegExp(r'[?&]list=([A-Za-z0-9_-]+)').firstMatch(text);
    return m?.group(1);
  }

  static bool isYoutube(String text) => _playlistId(text) != null;

  /// Separador de un CSV (;, coma o tab) o null si no es CSV.
  static String? _sepOf(String line) {
    for (final c in const ['\t', ';', ',']) {
      if (line.contains(c) && !RegExp(r'\s[-–—]\s').hasMatch(line.split(c).first)) {
        return c;
      }
    }
    return null;
  }

  /// Lee una línea CSV respetando comillas («"Hello, Goodbye",The Beatles»).
  static List<String> _csv(String line, String sep) {
    final out = <String>[];
    final b = StringBuffer();
    var q = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (q && i + 1 < line.length && line[i + 1] == '"') {
          b.write('"');
          i++;
        } else {
          q = !q;
        }
      } else if (ch == sep && !q) {
        out.add(b.toString().trim());
        b.clear();
      } else {
        b.write(ch);
      }
    }
    out.add(b.toString().trim());
    return out;
  }

  /// (nombre sugerido, canciones)
  static Future<(String, List<Song>)> parse(String text) async {
    final id = _playlistId(text);
    if (id != null) {
      final yt = YoutubeExplode();
      try {
        final pl = await yt.playlists.get(id);
        final out = <Song>[];
        await for (final v in yt.playlists.getVideos(id)) {
          out.add(Song.fromYoutube(
            title: v.title,
            channel: v.author,
            image: v.thumbnails.mediumResUrl,
            videoId: v.id.value,
          ));
          if (out.length >= 500) break;
        }
        return (pl.title, out);
      } finally {
        yt.close();
      }
    }
    final out = <Song>[];
    final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return ('Lista importada', out);
    // Separador por mayoría en las primeras líneas (no solo la primera).
    final votes = <String, int>{};
    for (final l in lines.take(6)) {
      final c = _sepOf(l);
      if (c != null) votes[c] = (votes[c] ?? 0) + 1;
    }
    final sep = votes.isEmpty
        ? null
        : (votes.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    // CSV con encabezado (Exportify, TuneMyMusic…): columnas por nombre.
    int ti = -1, ai = -1;
    if (sep != null) {
      final head = [for (final h in _csv(lines.first, sep)) h.toLowerCase()];
      ti = head.indexWhere((h) => h == 'track name' || h == 'title' || h == 'name' || h == 'nombre' || h == 'canción' || h == 'cancion' || h == 'song');
      ai = head.indexWhere((h) => h.startsWith('artist name') || h == 'artist' || h == 'artists' || h == 'artista');
    }
    final hasHeader = ti >= 0 && ai >= 0;
    for (var k = hasHeader ? 1 : 0; k < lines.length; k++) {
      final line = lines[k].trim();
      String a = '', t = '';
      if (hasHeader) {
        final cols = _csv(line, sep!);
        if (cols.length <= ti || cols.length <= ai) continue;
        t = cols[ti];
        // Exportify: «Artista 1, Artista 2» → el primero.
        a = cols[ai].split(RegExp(r'[,;]')).first;
      } else {
        final dash = RegExp(r'^(.+?)\s+[-–—]\s+(.+)$').firstMatch(line);
        if (dash != null) {
          a = dash.group(1)!;
          t = dash.group(2)!;
        } else if (sep != null) {
          // Sin encabezado: «Artista;Canción» o «Artista,Canción».
          final cols = _csv(line, sep);
          if (cols.length < 2) continue;
          a = cols[0];
          t = cols[1];
        } else {
          continue;
        }
      }
      a = a.replaceAll('"', '').trim();
      t = t.replaceAll('"', '').trim();
      if (a.isEmpty || t.isEmpty || t.startsWith('spotify:')) continue;
      out.add(Song(title: t, artist: a, query: '$a $t'));
    }
    return ('Lista importada', out);
  }
}
