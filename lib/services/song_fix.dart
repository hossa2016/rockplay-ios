import '../models/song.dart';
import 'deezer_service.dart';

/// Confirma con Deezer el título y el artista de las canciones dudosas antes
/// de guardarlas en el historial y en Tus números:
/// - título que es un número («1993» de «Killing In The Name»): si
///   «Killing In The Name - 1993» no existe pero «Killing In The Name» sí,
///   se corrige a esa canción con su artista real. «2112» de Rush se queda.
/// - artista que no parece artista (canal, «OP», «type beat»): se busca el
///   artista real por el título.
class SongFix {
  SongFix._();

  static final Map<String, Song> _cache = {};
  static final RegExp _num = RegExp(r'^\d{1,4}$');

  static bool doubtful(Song s) =>
      _num.hasMatch(s.title.trim()) ||
      !SongMeta.isPlausibleArtist(s.artist) ||
      // «Shakira · No»: artista corto y título de una o dos palabras.
      (s.artist.trim().length <= 3 &&
          s.title.trim().split(RegExp(r'\s+')).length <= 2 &&
          SongMeta.isPlausibleArtist(s.title)) ||
      RegExp(r'[♫♪]|\blyrics?\b|subtitulad', caseSensitive: false).hasMatch(s.title);

  static Future<Song> verify(Song s) async {
    if (s.isRadio || !doubtful(s)) return s;
    final key = '${s.artist}|${s.title}';
    final hit = _cache[key];
    if (hit != null) return hit;
    var out = s;
    // Primero se vuelve a separar con las reglas actuales: «The Verve .
    // Sonnet♫Lyrics» de «LyricsTime» → Sonnet · The Verve.
    final re = SongMeta.split(s.title, s.artist);
    if (re.title != s.title || re.artist != s.artist) {
      out = s.withMeta(title: re.title, artist: re.artist);
      if (!doubtful(out)) {
        _cache[key] = out;
        return out;
      }
      s = out;
    }
    try {
      final d = DeezerService();
      // «Shakira · No» guardada al revés («No» de Shakira): se voltea si
      // Deezer la conoce así y no al derecho.
      if (s.artist.trim().length <= 3) {
        // «U2 · One» está bien: se deja como está.
        if (await d.trackExists(s.artist, s.title)) {
          _cache[key] = s;
          return s;
        }
        if (await d.trackExists(s.title, s.artist)) {
          out = s.withMeta(title: s.artist, artist: s.title);
          _cache[key] = out;
          return out;
        }
      }
      if (_num.hasMatch(s.title.trim())) {
        if (!await d.trackExists(s.artist, s.title)) {
          final a = await d.artistForTitle(s.artist);
          if (a != null) out = s.withMeta(title: s.artist, artist: a);
        }
      } else {
        final a = await d.artistForTitle(s.title);
        if (a != null) out = s.withMeta(artist: a);
      }
    } catch (_) {}
    _cache[key] = out;
    return out;
  }
}
