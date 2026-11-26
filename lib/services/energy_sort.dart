import '../models/song.dart';
import 'deezer_service.dart';

/// «Ordenar por energía»: con el BPM de Deezer arma una curva que sube y
/// luego baja. Las canciones sin BPM conservan su lugar.
class EnergySort {
  EnergySort._();

  /// Null si menos de 3 canciones tienen BPM (no se puede ordenar).
  static Future<List<Song>?> sort(List<Song> songs,
      {void Function(int done, int total)? progress}) async {
    final d = DeezerService();
    final take = songs.length > 150 ? 150 : songs.length;
    final bpm = List<double>.filled(songs.length, 0);
    var done = 0;
    // De a 3 a la vez.
    for (var i = 0; i < take; i += 3) {
      await Future.wait([
        for (var j = i; j < i + 3 && j < take; j++)
          d.bpm(songs[j].artist, songs[j].title).then((v) => bpm[j] = v),
      ]);
      done = (i + 3).clamp(0, take);
      progress?.call(done, take);
    }
    final slots = [for (var i = 0; i < songs.length; i++) if (bpm[i] > 0) i];
    if (slots.length < 3) return null;
    final sorted = List<int>.of(slots)..sort((a, b) => bpm[a].compareTo(bpm[b]));
    // Curva: los pares suben, los impares bajan.
    final wave = [
      for (var k = 0; k < sorted.length; k += 2) sorted[k],
      for (var k = sorted.length.isOdd ? sorted.length - 2 : sorted.length - 1;
          k >= 1;
          k -= 2)
        sorted[k],
    ];
    final out = List<Song>.of(songs);
    for (var k = 0; k < slots.length; k++) {
      out[slots[k]] = songs[wave[k]];
    }
    return out;
  }
}
