class Song {
  final String title;
  final String artist;
  final String album;
  final String image;
  final String url;
  final String videoId;
  final String query;

  /// Duración conocida (0 = aún no se sabe). Se guarda con la cola para
  /// que al reabrir la app se vea «3:42» y no «--:--».
  final int durationMs;

  Song({
    required this.title,
    required this.artist,
    this.videoId = '',
    this.album = '',
    this.image = '',
    this.url = '',
    this.query = '',
    this.durationMs = 0,
  });

  Song withDuration(Duration d) => Song(
        title: title,
        artist: artist,
        album: album,
        image: image,
        url: url,
        videoId: videoId,
        query: query,
        durationMs: d.inMilliseconds,
      );

  /// Emisora de radio en vivo (la dirección de la transmisión va en [url]).
  bool get isRadio => query.startsWith('radio:');

  Song withVideoId(String id) => Song(
        title: title,
        artist: artist,
        album: album,
        image: image,
        url: 'https://www.youtube.com/watch?v=$id',
        videoId: id,
        query: query,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'artist': artist,
        'album': album,
        'image': image,
        'url': url,
        'videoId': videoId,
        'query': query,
        if (durationMs > 0) 'ms': durationMs,
      };

  factory Song.fromJson(Map<String, dynamic> j) {
    final s = Song(
      title: (j['title'] ?? '') as String,
      artist: (j['artist'] ?? '') as String,
      album: (j['album'] ?? '') as String,
      image: (j['image'] ?? '') as String,
      url: (j['url'] ?? '') as String,
      videoId: (j['videoId'] ?? '') as String,
      query: (j['query'] ?? '') as String,
      durationMs: (j['ms'] as num?)?.toInt() ?? 0,
    );
    // Lo guardado antes venía con el nombre del canal: se limpia al leer.
    return s.query.isEmpty && s.videoId.isNotEmpty ? s.cleaned() : s;
  }

  /// Canción salida de YouTube: separa «Artista - Canción» del título, quita
  /// «(Official Video)», «[Lyrics]», etc. y limpia el nombre del canal.
  factory Song.fromYoutube({
    required String title,
    required String channel,
    required String videoId,
    String image = '',
  }) =>
      Song(
        title: title,
        artist: channel,
        image: image,
        url: 'https://www.youtube.com/watch?v=$videoId',
        videoId: videoId,
      ).cleaned();

  Song withMeta({String? title, String? artist}) => Song(
        title: title ?? this.title,
        artist: artist ?? this.artist,
        album: album,
        image: image,
        url: url,
        videoId: videoId,
        query: query,
        durationMs: durationMs,
      );

  Song cleaned() {
    final m = SongMeta.split(title, artist);
    if (m.title == title && m.artist == artist) return this;
    return Song(
      title: m.title,
      artist: m.artist,
      album: album,
      image: image,
      url: url,
      videoId: videoId,
      query: query,
      durationMs: durationMs,
    );
  }
}

/// Limpieza de títulos y nombres de artista que vienen de YouTube.
class SongMeta {
  SongMeta._();

  static final RegExp _bracketJunk = RegExp(
      r'\s*[\(\[\{][^\)\]\}]*\b(official|oficial|video|vídeo|audio|lyrics?|letra|visuali[sz]er|hd|hq|4k|remaster(ed)?|videoclip|clip|mv|subtitulad[oa]|sub español|traducid[oa])\b[^\)\]\}]*[\)\]\}]',
      caseSensitive: false);
  static final RegExp _tailJunk = RegExp(
      r'\s*[-|–—]\s*(official\s+)?(music\s+)?(video|audio|lyrics?|lyric video|video oficial|audio oficial|hd|4k)\s*$',
      caseSensitive: false);
  /// «Artista - Canción», «Artista | Canción», «Artista . Canción»,
  /// «Artista ♫ Canción», «Artista // Canción».
  static final RegExp _sep = RegExp(r'\s+[-–—|.·•~]\s+|(?<=[^\s\-–—])[-–—]\s+(?=\S)|\s*(?:[♫♪]|\u{1F3B5})\s*|\s+//\s+', unicode: true);

  /// Colas de canales de letras sin guion: «Sonnet♫Lyrics», «… Letra»,
  /// «… Subtitulado al Español», «… (Traducida)».
  static final RegExp _lyricTail = RegExp(
      r'\s*(?:[-–—♫♪|/]|\u{1F3B5})*\s*(lyrics?( video)?|letra( y traducción| en español)?|sub(titulad[oa]|s)?( al| en)? español|traducid[oa]( al español)?|traducción)\s*$',
      caseSensitive: false, unicode: true);

  /// «Rammstein Official», «PearlJamVEVO», «Korn - Topic» → nombre del artista.
  static final RegExp _uploader = RegExp(
      r'(^the\s+\S+(\s+\S+)+\s+show$|\b(tonight|late|daily) show$|podcast|productions?\b|\bstudios?$|\bentertainment$|uploader|vault|records\b|recordings|music\s*(channel|tv)?$|heartbeats|lyrics|letras|hits|classics|mix(es)?$|channel$|^\w+chef$|\btv$|archive|collection)',
      caseSensitive: false);

  /// ¿El «artista» parece un canal que sube música de otros?
  static bool looksLikeUploader(String a) => _uploader.hasMatch(a.trim());

  static const _noArtist = {
    'op', 'ed', 'hd', 'hq', 'amv', 'ost', 'lyrics', 'letra', 'audio', 'video',
    'official', 'oficial', 'live', 'en vivo', 'cover', 'subtitulado',
    'subtitulado en español', 'traducido', 'traducida', 'sub español',
    'letras', 'karaoke', 'instrumental', 'remix',
  };

  /// ¿Sirve como nombre de artista? Descarta «OP», «[FREE] … Type Beat»,
  /// «Kaelia Ash: "Self Destruction», canales que suben música ajena, etc.
  static bool isPlausibleArtist(String a) {
    final t = a.trim();
    if (t.length < 2 || t.length > 40) return false;
    final l = t.toLowerCase();
    if (_noArtist.contains(l)) return false;
    if (RegExp(r'["“”:\[\]♫♪]|type ?beat|\bprod\.? by\b|\[free\]|\(free\)|\s[x×]\s|subtitulad|traducid|en español|\blyrics?\b|\bletras?\b')
        .hasMatch(l)) return false;
    if (RegExp(r'^\d+$').hasMatch(l)) return false;
    return !looksLikeUploader(t);
  }

  /// Etiquetas que nunca son título (a diferencia de «1979» o «2112»).
  static final RegExp _tagOnly = RegExp(
      r'^(live|en vivo|directo|remaster(ed)?( \d{4})?|demo|hd|hq|4k|lyrics?|letra)$',
      caseSensitive: false);

  /// Lado derecho que no es un título: un año, un número o una etiqueta.
  static final RegExp _notTitle = RegExp(
      r'^((19|20)\d{2}|\d+|live|en vivo|directo|remaster(ed)?( \d{4})?|demo|version|versión|hd|hq|4k|lyrics?|letra)$',
      caseSensitive: false);

  static String cleanChannel(String a) => a
      .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*vevo$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\(?official\)?\s*(channel)?$', caseSensitive: false), '')
      .replaceAll(RegExp(r'^official\s+', caseSensitive: false), '')
      .trim();

  /// Clave para comparar artistas: «The Strokes», «Strokes» y «STROKES»
  /// son el mismo; «Café Tacvba» = «Cafe Tacuba» no, pero sí sin tildes.
  static String artistKey(String a) {
    var s = a.toLowerCase().trim();
    const from = 'áàäâéèëêíìïîóòöôúùüûñ';
    const to = 'aaaaeeeeiiiioooouuuun';
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    s = s.replaceAll(RegExp(r'^the\s+'), '').replaceAll('&', 'and');
    return s.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9áéíóúñü]'), '');

  static ({String artist, String title}) split(String rawTitle, String rawArtist) {
    var t = rawTitle.replaceAll(_bracketJunk, '').replaceAll(_tailJunk, '');
    // Dos pasadas: «Sonnet♫Lyrics - Subtitulado» pierde ambas colas.
    t = t.replaceAll(_lyricTail, '').replaceAll(_lyricTail, '');
    t = t
        .replaceAll(RegExp(r'\s+(hd|hq|4k)$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (t.isEmpty) t = rawTitle.trim();
    final channel = cleanChannel(rawArtist);
    var artist = channel.isEmpty ? rawArtist.trim() : channel;
    // «Demon Slayer OP - "Gurenge" by LiSA» → Gurenge · LiSA.
    final by = RegExp(r'["“]([^"”]+)["”]\s+by\s+(.+)$', caseSensitive: false)
        .firstMatch(t);
    if (by != null) {
      final a = by.group(2)!.trim();
      if (a.isNotEmpty && a.length <= 40) {
        return (artist: a, title: by.group(1)!.trim());
      }
    }
    // «Counting Crows "Round Here"» (subido por un programa de TV o radio).
    final q = RegExp(r'^([^"“”]{2,40}?)\s*[:\-–]?\s*["“]([^"”]+)["”]\s*(.*)$').firstMatch(t);
    // Solo si el canal no es el artista: «Smells Like Teen Spirit "Live"»
    // subido por Nirvana no es «Live» de «Smells Like Teen Spirit».
    final channelIsArtist = channel.isNotEmpty &&
        !looksLikeUploader(channel) &&
        isPlausibleArtist(channel);
    if (q != null && !channelIsArtist && _sep.firstMatch(q.group(1)!) == null) {
      final a = q.group(1)!.trim(), ti = q.group(2)!.trim();
      if (isPlausibleArtist(a) && ti.isNotEmpty && !_notTitle.hasMatch(ti)) {
        return (artist: a, title: ti);
      }
    }
    // «Self- Destruction» (una palabra antes del guion sin espacio) no es
    // «Artista - Canción»; «Bring Me The Horizon- Dig It» sí.
    RegExpMatch? m;
    for (final x in _sep.allMatches(t)) {
      final glued = x.start > 0 && '-–—'.contains(t[x.start]);
      if (glued && !t.substring(0, x.start).trim().contains(' ')) continue;
      m = x;
      break;
    }
    if (m != null) {
      final left = t.substring(0, m.start).trim().replaceAll(RegExp(r'^["“]|["”]$'), '');
      final right = t.substring(m.end).trim().replaceAll(RegExp(r'^["“]|["”]$'), '');
      if (left.isNotEmpty && right.isNotEmpty && left.length <= 60) {
        final nc = _norm(channel), nl = _norm(left), nr = _norm(right);
        final leftIsChannel = nc.isNotEmpty && nl.contains(nc);
        final tag = _tagOnly.hasMatch(right);
        final channelArtist =
            channel.isNotEmpty && !looksLikeUploader(channel) && !leftIsChannel;
        if (tag || (_notTitle.hasMatch(right) && channelArtist)) {
          // «Du Hast - Live» o «Killing In The Name - 1993» subido por el
          // artista: la derecha no es título. Con «Smashing Pumpkins - 1979»
          // (izquierda = canal) o un canal ajeno se deja «Artista - Canción»
          // y lo dudoso se confirma con Deezer al sonar (SongFix).
          t = left;
          if (channelArtist) artist = channel;
        } else if (nc.isNotEmpty && nr.contains(nc) && !nl.contains(nc)) {
          // «Canción - Artista»
          artist = right;
          t = left;
        } else {
          artist = left;
          t = right;
        }
      }
    } else if (channel.isNotEmpty) {
      // «Rammstein Du Hast» con canal Rammstein → «Du Hast».
      final lower = t.toLowerCase(), lc = channel.toLowerCase();
      if (lower.startsWith('$lc ') && t.length > channel.length + 2) {
        t = t.substring(channel.length).trim();
      }
    }
    return (artist: artist, title: t);
  }
}
