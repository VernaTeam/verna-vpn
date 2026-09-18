import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/palette.dart';
import '../data/world_shapes.dart';

/// Where the map's camera is looking: a point, and how close.
@immutable
class MapCamera {
  const MapCamera({
    required this.lon,
    required this.lat,
    required this.zoom,
  });

  /// The whole world, which is what the map shows with nothing selected.
  ///
  /// The centre of the design's frame: longitude 7, and the latitude whose
  /// Mercator y sits halfway between -56 and 78, which is 31.4 rather than the
  /// 11 an unprojected average would give.
  static const MapCamera world = MapCamera(lon: 7, lat: 31.4, zoom: 1);

  final double lon;
  final double lat;
  final double zoom;

  static MapCamera lerp(MapCamera a, MapCamera b, double t) => MapCamera(
        lon: a.lon + (b.lon - a.lon) * t,
        lat: a.lat + (b.lat - a.lat) * t,
        // Zoom interpolates geometrically. Linearly, a flight from the world
        // (1×) to Luxembourg (14×) spends its first half already halfway
        // zoomed in and the rest crawling.
        zoom: a.zoom * math.pow(b.zoom / a.zoom, t).toDouble(),
      );

  /// Frames [shape] in a viewport of [size], leaving a margin so the outline
  /// never touches the edge.
  ///
  /// The design hand-authored a zoom per country (DE 5.2, US 2.9, …). That
  /// does not survive a pool which can exit through any of two hundred
  /// countries, so the zoom is derived from the country's own bounding box and
  /// Russia and Luxembourg come out of the same rule.
  factory MapCamera.framing(CountryShape shape, Size size) {
    final spanX =
        (_lonRad(shape.maxLon) - _lonRad(shape.minLon)).abs().clamp(0.004, _spanX);
    final spanY =
        (_mercatorY(shape.maxLat) - _mercatorY(shape.minLat)).abs().clamp(0.004, _spanY);
    final fit = math.min(size.width / spanX, size.height / spanY);
    // Against the whole-world scale, so `zoom` means the same thing the
    // design's numbers mean. The 0.62 leaves the coastline and the neighbours
    // that make a country recognisable; the ceiling stops Luxembourg from
    // filling the card with one green field.
    final zoom = (fit / _baseScale(size)) * 0.62;
    return MapCamera(
      lon: shape.centreLon,
      lat: shape.centreLat,
      zoom: zoom.clamp(1.0, 6.0),
    );
  }
}

/// Mercator, in radians, with one scale for both axes.
///
/// This is the whole reason the outlines are the right shape. An earlier
/// version normalised longitude and latitude into a unit square and then
/// multiplied both by the same number -- which stretches every country
/// horizontally by the ratio of the two spans, and made Germany look like
/// Kazakhstan.
///
/// The frame is the design's: longitudes -172…186 and latitudes -56…78.
/// Antarctica and the empty northern ocean are dead weight on a 158 px map.
const double _minLon = -172;
const double _maxLon = 186;
const double _minLat = -56;
const double _maxLat = 78;

double _lonRad(double lon) => lon * math.pi / 180;

double _mercatorY(double lat) {
  final clamped = lat.clamp(-85.0, 85.0);
  final radians = clamped * math.pi / 180;
  return math.log(math.tan(math.pi / 4 + radians / 2));
}

/// How wide and tall the frame is in projected units.
final double _spanX = _lonRad(_maxLon) - _lonRad(_minLon);
final double _spanY = _mercatorY(_maxLat) - _mercatorY(_minLat);

/// The scale at which the whole frame is exactly as wide as the viewport --
/// `zoom: 1`. Taller than the viewport, so the world is cropped top and
/// bottom rather than letterboxed, which is what the design's fitExtent does.
double _baseScale(Size size) => size.width / _spanX;

/// The map on the connect screen.
///
/// Real country outlines from a bundled Natural Earth extract, a camera that
/// flies to the country the tunnel exits through, and a pin that pulses on it.
/// Not a bitmap of the world and not hand-traced shapes -- at any zoom the
/// borders are the real ones.
class WorldMap extends StatefulWidget {
  const WorldMap({
    super.key,
    required this.countryCode,
    required this.highlight,
    this.pinVisible = true,
    this.dimPin = false,
  });

  /// The country to fly to, or null for the whole world.
  final String? countryCode;

  /// What the highlight and the pin mean right now.
  final MapHighlight highlight;

  /// Hidden while a handshake is in flight, as the design has it: a pin on a
  /// country the app has not reached yet is a claim it cannot make.
  final bool pinVisible;

  final bool dimPin;

  @override
  State<WorldMap> createState() => _WorldMapState();
}

/// Cyan only ever means protected. Amber is "chosen, not proven"; rose is a
/// country that was tried and failed.
enum MapHighlight { idle, pending, connected, failed }

class _WorldMapState extends State<WorldMap>
    with TickerProviderStateMixin {
  WorldShapes? _shapes;
  _WorldPaths? _paths;

  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  MapCamera _from = MapCamera.world;
  MapCamera _to = MapCamera.world;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    WorldShapes.load().then((shapes) {
      if (!mounted) return;
      setState(() {
        _shapes = shapes;
        _paths = _WorldPaths.build(shapes);
        _retarget(animate: false);
      });
    });
  }

  @override
  void didUpdateWidget(WorldMap old) {
    super.didUpdateWidget(old);
    if (old.countryCode != widget.countryCode) _retarget(animate: true);
  }

  @override
  void dispose() {
    _fly.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _retarget({required bool animate}) {
    final shapes = _shapes;
    if (shapes == null || _size.isEmpty) return;
    final shape = shapes[widget.countryCode];
    final point = WorldShapes.pointFor(widget.countryCode);
    final next = shape != null
        ? MapCamera.framing(shape, _size)
        : point != null
            // No outline at this scale, but the place is real: fly to it and
            // let the pin say where it is.
            ? MapCamera(lon: point.lon, lat: point.lat, zoom: 5)
            : MapCamera.world;
    _from = animate ? _current : next;
    _to = next;
    if (animate) {
      _fly.forward(from: 0);
    } else {
      _fly.value = 1;
      setState(() {});
    }
  }

  MapCamera get _current => MapCamera.lerp(
        _from,
        _to,
        Curves.easeOutCubic.transform(_fly.value),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.verna;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size != _size) {
          _size = size;
          // After the first layout, not during it: _retarget calls setState.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _retarget(animate: false);
          });
        }

        final paths = _paths;
        if (paths == null) {
          // The parse takes a few milliseconds, but a flash of nothing still
          // reads as breakage. The sea is the map's own background, so this is
          // the map, minus its countries.
          return ColoredBox(color: c.mapSea, child: const SizedBox.expand());
        }

        return AnimatedBuilder(
          animation: Listenable.merge([_fly, _pulse]),
          builder: (context, _) {
            final camera = _current;
            return CustomPaint(
              size: size,
              painter: _MapPainter(
                paths: paths,
                camera: camera,
                highlightCode: widget.countryCode,
                highlight: widget.highlight,
                pulse: _pulse.value,
                showPin: widget.pinVisible && widget.countryCode != null,
                dimPin: widget.dimPin,
                sea: c.mapSea,
                land: c.mapLand,
                stroke: c.mapStroke,
                highlightColour: switch (widget.highlight) {
                  MapHighlight.connected => c.mapHighlight,
                  MapHighlight.failed => c.danger,
                  MapHighlight.pending => c.warn,
                  MapHighlight.idle => c.mapLand,
                },
              ),
            );
          },
        );
      },
    );
  }
}

/// Country outlines as [Path]s in unit space, built once.
///
/// Rebuilding 10 500 points into paths on every frame of a 1.15 s flight is
/// the difference between a map that glides and one that stutters on a J7.
class _WorldPaths {
  const _WorldPaths(this.byCountry);

  final List<({String code, Path path})> byCountry;

  factory _WorldPaths.build(WorldShapes shapes) {
    final built = <({String code, Path path})>[];
    for (final country in shapes.countries) {
      final path = Path();
      for (final ring in country.rings) {
        for (var i = 0; i < ring.length; i += 2) {
          final x = _lonRad(ring[i]);
          // Negated: Mercator y grows northward, the canvas grows downward.
          final y = -_mercatorY(ring[i + 1]);
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
      }
      built.add((code: country.code, path: path));
    }
    return _WorldPaths(built);
  }
}

class _MapPainter extends CustomPainter {
  const _MapPainter({
    required this.paths,
    required this.camera,
    required this.highlightCode,
    required this.highlight,
    required this.pulse,
    required this.showPin,
    required this.dimPin,
    required this.sea,
    required this.land,
    required this.stroke,
    required this.highlightColour,
  });

  final _WorldPaths paths;
  final MapCamera camera;
  final String? highlightCode;
  final MapHighlight highlight;
  final double pulse;
  final bool showPin;
  final bool dimPin;
  final Color sea;
  final Color land;
  final Color stroke;
  final Color highlightColour;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = sea);

    // One transform for the whole world: the camera is a scale about the
    // target point, exactly like the design's `translate scale translate`.
    // One `scale` for both axes, because the paths are already in projected
    // units -- that is what keeps the outlines the right shape.
    final scale = _baseScale(size) * camera.zoom;
    final focus = Offset(_lonRad(camera.lon), -_mercatorY(camera.lat));

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-focus.dx, -focus.dy);

    final landPaint = Paint()..color = land;
    final highlightPaint = Paint()..color = highlightColour;
    final strokePaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      // Divided by the scale so the hairline stays a hairline at any zoom --
      // the same thing `vector-effect:non-scaling-stroke` does in the
      // prototype.
      ..strokeWidth = 0.9 / scale;

    final code = highlightCode?.toUpperCase();
    for (final country in paths.byCountry) {
      final isTarget = code != null && country.code == code;
      canvas.drawPath(country.path, isTarget ? highlightPaint : landPaint);
      canvas.drawPath(country.path, strokePaint);
    }
    canvas.restore();

    if (!showPin) return;
    final pin = Offset(size.width / 2, size.height / 2);
    _paintPin(canvas, pin);
  }

  void _paintPin(Canvas canvas, Offset centre) {
    final colour = switch (highlight) {
      MapHighlight.connected => highlightColour,
      MapHighlight.failed => highlightColour,
      MapHighlight.pending => highlightColour,
      MapHighlight.idle => highlightColour,
    };
    final alpha = dimPin ? 0.35 : 1.0;

    // `.pin::after`: a 32 px ring scaling .55 → 1.9 over two seconds while it
    // fades from .9 to nothing.
    final ringScale = 0.55 + pulse * 1.35;
    canvas.drawCircle(
      centre,
      16 * ringScale,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = colour.withValues(alpha: (1 - pulse) * 0.9 * alpha),
    );
    // `.pin`: a 16 px dot with a 5 px halo around it. The halo is drawn in the
    // sea colour rather than in the pin's own: the pin sits on the country it
    // points at, which is filled with that very colour, and an amber dot on an
    // amber country is not a dot at all.
    canvas.drawCircle(
      centre,
      13,
      Paint()..color = sea.withValues(alpha: 0.85 * alpha),
    );
    canvas.drawCircle(
      centre,
      8,
      Paint()..color = colour.withValues(alpha: alpha),
    );
    canvas.drawCircle(
      centre,
      8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = sea.withValues(alpha: 0.9 * alpha),
    );
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.camera.lon != camera.lon ||
      old.camera.lat != camera.lat ||
      old.camera.zoom != camera.zoom ||
      old.highlightCode != highlightCode ||
      old.highlight != highlight ||
      old.pulse != pulse ||
      old.showPin != showPin ||
      old.dimPin != dimPin ||
      old.land != land;
}
