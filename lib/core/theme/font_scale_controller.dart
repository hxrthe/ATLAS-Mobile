import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists and broadcasts app text scale for accessibility.
///
/// Ladder: Small (0.9) / Default (1.0) / Large (1.35).
/// Fresh installs default to Small.
class FontScaleController extends ChangeNotifier {
  static const _prefsKey = 'atlas_font_scale_v2';
  static const _legacyPrefsKey = 'atlas_font_scale';

  static const double smallScale = 0.9;
  static const double defaultScale = 1.0;
  static const double largeScale = 1.35;

  /// New installs and unset prefs land on Small.
  static const double initialScale = smallScale;

  static const List<double> allowedScales = [
    smallScale,
    defaultScale,
    largeScale,
  ];

  static const List<(double, String)> labeledScales = [
    (smallScale, 'Small'),
    (defaultScale, 'Default'),
    (largeScale, 'Large'),
  ];

  double _scale = initialScale;

  double get scale => _scale;

  int get scaleIndex {
    final i = allowedScales.indexOf(_scale);
    return i < 0 ? allowedScales.indexOf(initialScale) : i;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getDouble(_prefsKey);
    if (raw != null) {
      _scale = _nearestAllowed(raw);
    } else {
      final legacy = prefs.getDouble(_legacyPrefsKey);
      if (legacy != null) {
        _scale = _migrateLegacy(legacy);
        await prefs.setDouble(_prefsKey, _scale);
        await prefs.remove(_legacyPrefsKey);
      } else {
        _scale = initialScale;
      }
    }
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

  Future<void> setScaleIndex(int index) async {
    if (index < 0 || index >= allowedScales.length) return;
    await setScale(allowedScales[index]);
  }

  /// Old ladder: 1.0 Default, 1.2 Large, 1.35 Extra large.
  static double _migrateLegacy(double value) {
    if ((value - 1.35).abs() < 0.05) return largeScale;
    if ((value - 1.0).abs() < 0.05) return defaultScale;
    if ((value - 1.2).abs() < 0.05) return defaultScale;
    return _nearestAllowed(value);
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
