import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// The world, as the connect screen draws it.
///
/// Loaded from `assets/geo/world_110m.bin`: Natural Earth's 110m country
/// outlines, quantised to int16 degrees by `build_map_asset.py`. That file is
/// 45 KB and parses in a couple of milliseconds; the same data as GeoJSON is
/// roughly 600 KB of text that would have to be decoded on the frame the map
/// first appears.
///
/// Bundled rather than fetched. This app is used on networks that block or
/// throttle half the internet, and a map that arrives late -- or never -- is
/// worse than one that is simply there.
class WorldShapes {
  const WorldShapes._(this.countries, this._byCode);

  final List<CountryShape> countries;
  final Map<String, CountryShape> _byCode;

  /// The outline for an ISO 3166-1 alpha-2 code, or null when the map does not
  /// carry that country (small island states mostly, which are invisible at
  /// this scale anyway).
  CountryShape? operator [](String? code) =>
      code == null ? null : _byCode[code.toUpperCase()];

  /// Where to point when a country has no outline at this scale.
  ///
  /// Natural Earth's 110m file has no polygon for a city state or a small
  /// island -- Hong Kong, Singapore, Malta and seven others in this app's list
  /// simply are not drawable at that resolution. Reported from the phone: the
  /// map stayed on the whole world when those were chosen. The camera flies to
  /// the point instead and the pin carries the meaning, which is honest: the
  /// place is there, the outline is below the map's resolution.
  static const Map<String, ({double lon, double lat})> _points = {
    'AD': (lon: 1.52, lat: 42.51),
    'BH': (lon: 50.55, lat: 26.07),
    'CW': (lon: -68.99, lat: 12.17),
    'HK': (lon: 114.17, lat: 22.32),
    'LI': (lon: 9.55, lat: 47.17),
    'MO': (lon: 113.55, lat: 22.20),
    'MT': (lon: 14.51, lat: 35.90),
    'SC': (lon: 55.49, lat: -4.68),
    'SG': (lon: 103.82, lat: 1.35),
    'VG': (lon: -64.62, lat: 18.42),
  };

  /// The fallback point for [code], or null when the map does have a shape for
  /// it (or has never heard of it).
  static ({double lon, double lat})? pointFor(String? code) =>
      code == null ? null : _points[code.toUpperCase()];

  static WorldShapes? _cached;
  static Future<WorldShapes>? _loading;

  /// Parsed once per process and kept: the map is rebuilt on every frame of a
  /// camera flight, and re-parsing 10 000 points each time would be visible.
  static Future<WorldShapes> load() {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    return _loading ??= _parse().then((shapes) {
      _cached = shapes;
      _loading = null;
      return shapes;
    });
  }

  static Future<WorldShapes> _parse() async {
    final data = await rootBundle.load('assets/geo/world_110m.bin');
    final bytes = data.buffer.asByteData(data.offsetInBytes, data.lengthInBytes);
    var at = 0;

    int u8() => bytes.getUint8(at++);
    int u16() {
      final v = bytes.getUint16(at, Endian.little);
      at += 2;
      return v;
    }

    double deg(double scale) {
      final v = bytes.getInt16(at, Endian.little);
      at += 2;
      return v * scale / 32767;
    }

    if (bytes.getUint8(0) != 0x56 ||
        bytes.getUint8(1) != 0x4D ||
        bytes.getUint8(2) != 0x41 ||
        bytes.getUint8(3) != 0x50) {
      throw const FormatException('world_110m.bin: not a VMAP file');
    }
    at = 4;
    final version = u8();
    if (version != 2) {
      throw FormatException('world_110m.bin: version $version, expected 2');
    }

    final count = u16();
    final countries = <CountryShape>[];
    final byCode = <String, CountryShape>{};

    for (var i = 0; i < count; i++) {
      final codeA = u8();
      final codeB = u8();
      final code = codeA == 0 ? '' : String.fromCharCodes([codeA, codeB]);
      final nameLength = u8();
      final name = String.fromCharCodes(
        Uint8List.view(bytes.buffer, bytes.offsetInBytes + at, nameLength),
      );
      at += nameLength;

      final centreLon = deg(180);
      final centreLat = deg(90);
      final minLon = deg(180);
      final minLat = deg(90);
      final maxLon = deg(180);
      final maxLat = deg(90);

      final ringCount = u16();
      final rings = <Float32List>[];
      for (var r = 0; r < ringCount; r++) {
        final points = u16();
        // Flat [lon, lat, lon, lat, …]: half the allocations of a list of
        // Offsets, and the painter walks it in the same order.
        final ring = Float32List(points * 2);
        for (var p = 0; p < points; p++) {
          ring[p * 2] = deg(180);
          ring[p * 2 + 1] = deg(90);
        }
        rings.add(ring);
      }

      final shape = CountryShape(
        code: code,
        name: name,
        centreLon: centreLon,
        centreLat: centreLat,
        minLon: minLon,
        minLat: minLat,
        maxLon: maxLon,
        maxLat: maxLat,
        rings: rings,
      );
      countries.add(shape);
      if (code.isNotEmpty) byCode[code] = shape;
    }

    return WorldShapes._(countries, byCode);
  }
}

/// One country: its outline rings, and where a camera should sit to frame it.
class CountryShape {
  const CountryShape({
    required this.code,
    required this.name,
    required this.centreLon,
    required this.centreLat,
    required this.minLon,
    required this.minLat,
    required this.maxLon,
    required this.maxLat,
    required this.rings,
  });

  /// ISO 3166-1 alpha-2, or empty when the build could not name it.
  final String code;

  /// Natural Earth's English name. Only used for diagnostics -- the app shows
  /// its own names, so this one never reaches a user.
  final String name;

  final double centreLon;
  final double centreLat;
  final double minLon;
  final double minLat;
  final double maxLon;
  final double maxLat;

  /// Outer rings only. Holes (Lesotho inside South Africa, the Vatican inside
  /// Italy) are a pixel wide at this scale and cost bytes to carry.
  final List<Float32List> rings;

  /// How much of the viewport this country covers, as a fraction of the world.
  ///
  /// Used to pick a zoom: the design hand-authored one per country, which does
  /// not survive a pool that can exit through any of two hundred. Russia and
  /// Luxembourg get different numbers from the same rule.
  double get spanLon => (maxLon - minLon).abs().clamp(0.5, 360);
  double get spanLat => (maxLat - minLat).abs().clamp(0.5, 180);
}
