import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'mix_service.dart';

/// Catálogo del modo «Todos los géneros» (Pulso): géneros, ánimos y
/// artistas semilla. El modo rock usa el de [MixService] y artist_pools.
class GeneralCatalog {
  GeneralCatalog._();

  static List<MixDef> get genre => [
        MixDef('Pop', 'Éxitos', Icons.star_rounded, AppPalettes.fire,
            const ['Taylor Swift', 'Dua Lipa', 'Ed Sheeran', 'The Weeknd', 'Bruno Mars', 'Adele', 'Harry Styles', 'Billie Eilish']),
        MixDef('Pop latino', 'Para cantar', Icons.favorite_rounded, AppPalettes.wine,
            const ['Shakira', 'Carlos Vives', 'Juanes', 'Camilo', 'Sebastián Yatra', 'Morat', 'Luis Fonsi', 'Ricky Martin']),
        MixDef('Salsa', 'A bailar', Icons.nightlife_rounded, AppPalettes.rust,
            const ['Grupo Niche', 'Marc Anthony', 'Joe Arroyo', 'Héctor Lavoe', 'Celia Cruz', 'Willie Colón', 'Rubén Blades', 'Guayacán Orquesta']),
        MixDef('Reguetón', 'Urbano', Icons.bolt_rounded, AppPalettes.amber,
            const ['Bad Bunny', 'Karol G', 'J Balvin', 'Daddy Yankee', 'Feid', 'Maluma', 'Ozuna', 'Rauw Alejandro']),
        MixDef('Vallenato', 'Acordeón', Icons.music_note_rounded, AppPalettes.graphite,
            const ['Diomedes Díaz', 'Silvestre Dangond', 'Jorge Celedón', 'Binomio de Oro de América', 'Los Diablitos', 'Peter Manjarrés', 'Iván Villazón', 'Los Hermanos Zuleta']),
        MixDef('Rock', 'Guitarras', Icons.album_rounded, AppPalettes.steel,
            const ['Queen', 'Soda Stereo', 'Linkin Park', 'Coldplay', 'Guns N\' Roses', 'Maná', 'Nirvana', 'Arctic Monkeys']),
        MixDef('Electrónica', 'Beats', Icons.graphic_eq_rounded, AppPalettes.burgundy,
            const ['Calvin Harris', 'David Guetta', 'Avicii', 'Daft Punk', 'Martin Garrix', 'Kygo', 'Swedish House Mafia', 'Tiësto']),
        MixDef('Jazz', 'Con calma', Icons.piano_rounded, AppPalettes.brass,
            const ['Miles Davis', 'John Coltrane', 'Ella Fitzgerald', 'Louis Armstrong', 'Norah Jones', 'Chet Baker', 'Diana Krall', 'Herbie Hancock']),
        MixDef('Clásica', 'Orquesta y piano', Icons.queue_music_rounded, AppPalettes.graphite,
            const ['Ludwig van Beethoven', 'Wolfgang Amadeus Mozart', 'Johann Sebastian Bach', 'Frédéric Chopin', 'Antonio Vivaldi', 'Pyotr Ilyich Tchaikovsky', 'Claude Debussy', 'Ludovico Einaudi']),
        MixDef('Baladas', 'Románticas', Icons.nightlight_round, AppPalettes.wine,
            const ['Luis Miguel', 'Ricardo Arjona', 'Alejandro Sanz', 'Laura Pausini', 'Franco De Vita', 'Ricardo Montaner', 'Cristian Castro', 'Marco Antonio Solís']),
      ];

  static List<MixDef> get mood => [
        MixDef('Energía', 'Sube el volumen', Icons.bolt_rounded, AppPalettes.fire,
            const ['Bad Bunny', 'Dua Lipa', 'Imagine Dragons', 'Calvin Harris', 'Karol G', 'Pitbull', 'Daddy Yankee', 'David Guetta']),
        MixDef('Para entrenar', 'Sin pausa', Icons.fitness_center_rounded, AppPalettes.rust,
            const ['Eminem', 'Imagine Dragons', 'Feid', 'Martin Garrix', 'Daddy Yankee', 'Kanye West', 'Avicii', 'Linkin Park']),
        MixDef('Para manejar', 'Carretera', Icons.directions_car_rounded, AppPalettes.steel,
            const ['Carlos Vives', 'Coldplay', 'Juanes', 'The Weeknd', 'Morat', 'Bruno Mars', 'Fonseca', 'Queen']),
        MixDef('Tranquilo', 'Bajando revoluciones', Icons.nightlight_round, AppPalettes.graphite,
            const ['Norah Jones', 'Ludovico Einaudi', 'Ed Sheeran', 'Natalia Lafourcade', 'Jorge Drexler', 'Adele', 'Billie Eilish', 'Bon Iver']),
        MixDef('Nostalgia', 'Los de siempre', Icons.history_rounded, AppPalettes.amber,
            const ['Michael Jackson', 'Madonna', 'Luis Miguel', 'Joe Arroyo', 'Juan Gabriel', 'Whitney Houston', 'Diomedes Díaz', 'ABBA']),
        MixDef('Fiesta', 'Para la rumba', Icons.celebration_rounded, AppPalettes.burgundy,
            const ['Grupo Niche', 'Bad Bunny', 'Carlos Vives', 'Juan Luis Guerra', 'Silvestre Dangond', 'J Balvin', 'Marc Anthony', 'Shakira']),
      ];

  /// Más artistas por mix (se elige al azar entre todos cada vez).
  static const Map<String, List<String>> pools = {
    'Pop': ['Ariana Grande', 'Olivia Rodrigo', 'Katy Perry', 'Lady Gaga', 'Rihanna', 'Justin Bieber', 'Sia', 'Sam Smith', 'Miley Cyrus', 'Shawn Mendes', 'Lizzo', 'Charlie Puth', 'Sabrina Carpenter', 'Doja Cat', 'Coldplay', 'Maroon 5', 'OneRepublic', 'Imagine Dragons', 'Lewis Capaldi', 'Michael Jackson', 'Madonna', 'Beyoncé'],
    'Pop latino': ['Fonseca', 'Jesse & Joy', 'Reik', 'Natalia Lafourcade', 'Enrique Iglesias', 'Alejandro Sanz', 'Carlos Rivera', 'Kany García', 'Pablo Alborán', 'Mau y Ricky', 'Manuel Turizo', 'Piso 21', 'Andrés Cepeda', 'Jorge Drexler', 'Julieta Venegas', 'Paulina Rubio', 'Thalía', 'Chayanne', 'Aitana', 'Danny Ocean'],
    'Salsa': ['Oscar D\'León', 'Fruko y sus Tesos', 'Gilberto Santa Rosa', 'Victor Manuelle', 'El Gran Combo de Puerto Rico', 'Frankie Ruiz', 'Eddie Santiago', 'Jerry Rivera', 'La India', 'Tito Nieves', 'Ismael Rivera', 'Cheo Feliciano', 'Hector Tricoche', 'Orquesta Platino', 'Galy Galiano', 'Yuri Buenaventura', 'Sonora Ponceña', 'Richie Ray & Bobby Cruz', 'Maelo Ruiz', 'Tony Vega'],
    'Reguetón': ['Wisin & Yandel', 'Don Omar', 'Nicky Jam', 'Anuel AA', 'Myke Towers', 'Sech', 'Farruko', 'Blessd', 'Ryan Castro', 'Young Miko', 'Jhayco', 'Arcángel', 'Tego Calderón', 'Zion & Lennox', 'Plan B', 'Manuel Turizo', 'Lunay', 'Mora', 'Tainy', 'Quevedo'],
    'Vallenato': ['Carlos Vives', 'Poncho Zuleta', 'Rafael Orozco', 'Kaleth Morales', 'Martín Elías', 'Jean Carlos Centeno', 'Felipe Peláez', 'Alejandro Palacio', 'Otto Serge', 'Los Inquietos del Vallenato', 'Miguel Morales', 'Jorge Oñate', 'Beto Zabaleta', 'Nelson Velásquez', 'Iván Villazón', 'Rafael Santos', 'Elder Dayán', 'Churo Díaz', 'Mono Zabaleta', 'Fabián Corrales'],
    'Rock': ['Foo Fighters', 'Red Hot Chili Peppers', 'The Killers', 'Bon Jovi', 'AC/DC', 'Metallica', 'Aerosmith', 'Pink Floyd', 'The Beatles', 'Los Prisioneros', 'Enanitos Verdes', 'Héroes del Silencio', 'Zoé', 'Café Tacvba', 'Muse', 'Green Day', 'Pearl Jam', 'Oasis', 'Radiohead', 'U2'],
    'Electrónica': ['Marshmello', 'Alan Walker', 'Zedd', 'Skrillex', 'Deadmau5', 'Armin van Buuren', 'Hardwell', 'The Chainsmokers', 'Major Lazer', 'Diplo', 'Fred again..', 'Disclosure', 'Robin Schulz', 'Alesso', 'Afrojack', 'Bob Sinclar', 'Fisher', 'Peggy Gou', 'Rüfüs Du Sol', 'Odesza'],
    'Jazz': ['Billie Holiday', 'Nina Simone', 'Duke Ellington', 'Dave Brubeck', 'Bill Evans', 'Thelonious Monk', 'Charlie Parker', 'Sarah Vaughan', 'Frank Sinatra', 'Tony Bennett', 'Michael Bublé', 'Gregory Porter', 'Pat Metheny', 'Chick Corea', 'Stan Getz', 'Wes Montgomery', 'Esperanza Spalding', 'Kamasi Washington', 'Snarky Puppy', 'Melody Gardot'],
    'Clásica': ['Johannes Brahms', 'Franz Schubert', 'Sergei Rachmaninoff', 'Edvard Grieg', 'Erik Satie', 'Antonín Dvořák', 'Gustav Mahler', 'Felix Mendelssohn', 'Giuseppe Verdi', 'Giacomo Puccini', 'Richard Wagner', 'George Frideric Handel', 'Joseph Haydn', 'Maurice Ravel', 'Camille Saint-Saëns', 'Max Richter', 'Yiruma', 'Hans Zimmer', 'Lang Lang', 'André Rieu'],
    'Baladas': ['Rocío Dúrcal', 'José José', 'Camilo Sesto', 'Juan Gabriel', 'Ana Gabriel', 'Myriam Hernández', 'Chayanne', 'Enrique Iglesias', 'Alejandro Fernández', 'Pablo Alborán', 'Reik', 'Ha*Ash', 'Jesse & Joy', 'Sin Bandera', 'Kalimba', 'Eros Ramazzotti', 'Raphael', 'Julio Iglesias', 'Roberto Carlos', 'Yuridia'],
    'Energía': ['Pitbull', 'Black Eyed Peas', 'LMFAO', 'Major Lazer', 'Marshmello', 'Anuel AA', 'Nicky Jam', 'Wisin & Yandel', 'Lady Gaga', 'Rihanna', 'Shakira', 'Maluma', 'Avicii', 'Martin Garrix', 'Queen', 'Foo Fighters'],
    'Para entrenar': ['Dr. Dre', '50 Cent', 'Kendrick Lamar', 'Travis Scott', 'Drake', 'The Prodigy', 'Skrillex', 'Anuel AA', 'Myke Towers', 'Ozuna', 'Rammstein', 'AC/DC', 'Dua Lipa', 'Calvin Harris', 'David Guetta', 'Major Lazer'],
    'Para manejar': ['Fleetwood Mac', 'Tom Petty', 'Bon Jovi', 'Shakira', 'Camilo', 'Sebastián Yatra', 'Maná', 'Soda Stereo', 'Dua Lipa', 'Harry Styles', 'Ed Sheeran', 'Silvestre Dangond', 'Bad Bunny', 'Morat', 'Reik', 'Coldplay'],
    'Tranquilo': ['Diana Krall', 'Chet Baker', 'Jack Johnson', 'John Mayer', 'Kany García', 'Jesse & Joy', 'Sin Bandera', 'Coldplay', 'Max Richter', 'Yiruma', 'Frédéric Chopin', 'Claude Debussy', 'Erik Satie', 'Lana Del Rey', 'Lewis Capaldi', 'Sam Smith'],
    'Nostalgia': ['Rocío Dúrcal', 'José José', 'Queen', 'Bee Gees', 'Earth, Wind & Fire', 'Celia Cruz', 'Héctor Lavoe', 'Soda Stereo', 'Los Prisioneros', 'Cyndi Lauper', 'Prince', 'Elton John', 'Rafael Orozco', 'Juan Luis Guerra', 'Wilfrido Vargas', 'Bon Jovi'],
    'Fiesta': ['Wilfrido Vargas', 'Elvis Crespo', 'Proyecto Uno', 'Los Hermanos Rosario', 'Fruko y sus Tesos', 'Joe Arroyo', 'Guayacán Orquesta', 'Daddy Yankee', 'Don Omar', 'Karol G', 'Feid', 'Peter Manjarrés', 'Jorge Celedón', 'Pitbull', 'Ricky Martin', 'Gente de Zona'],
  };

  static const Map<String, List<String>> neighbors = {
    'Pop': ['Pop latino', 'Electrónica', 'Baladas'],
    'Pop latino': ['Pop', 'Baladas', 'Reguetón'],
    'Salsa': ['Fiesta', 'Vallenato'],
    'Reguetón': ['Pop latino', 'Fiesta', 'Energía'],
    'Vallenato': ['Fiesta', 'Salsa'],
    'Rock': ['Pop', 'Para manejar'],
    'Electrónica': ['Pop', 'Energía', 'Para entrenar'],
    'Jazz': ['Tranquilo', 'Clásica'],
    'Clásica': ['Jazz', 'Tranquilo'],
    'Baladas': ['Pop latino', 'Tranquilo', 'Nostalgia'],
    'Energía': ['Reguetón', 'Electrónica', 'Para entrenar'],
    'Para entrenar': ['Energía', 'Electrónica', 'Reguetón'],
    'Para manejar': ['Pop', 'Pop latino', 'Rock'],
    'Tranquilo': ['Jazz', 'Baladas', 'Clásica'],
    'Nostalgia': ['Baladas', 'Salsa', 'Rock'],
    'Fiesta': ['Salsa', 'Reguetón', 'Vallenato'],
  };
}
