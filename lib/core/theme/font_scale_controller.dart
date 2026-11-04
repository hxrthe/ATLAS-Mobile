import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists and broadcasts app text scale for accessibility.
class FontScaleController extends ChangeNotifier {
  static const _prefsKey = 'atlas_font_scale';

  static const double defaultScale = 1.0;
  static const double largeScale = 1.2;
  static const double extraLargeScale = 1.35;

  static const List<double> allowedScales = [
    defaultScale,
    largeScale,
    extraLargeScale,
  ];

  double _scale = defaultScale;

  double get scale => _scale;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getDouble(_prefsKey);
    _scale = _nearestAllowed(raw ?? defaultScale);
    notifyListeners();
  }

  Future<void> setScale(double scale) async {
    final next = _nearestAllowed(scale);
    if (_scale == next) return;
    _scale = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefsKey, next);
  }

  static double _nearestAllowed(double value) {
    var best = allowedScales.first;
    var bestDelta = (value - best).abs();
    for (final s in allowedScales.skip(1)) {
      final d = (value - s).abs();
      if (d < bestDelta) {
        best = s;
        bestDelta = d;
      }
    }
    return best;
  }
}

/// App-wide font scale controller (loaded in main before runApp).
final FontScaleController fontScaleController = FontScaleController();
