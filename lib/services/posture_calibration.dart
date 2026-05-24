import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/detected_context.dart';

/// 모드별 baseline tilt 저장.
/// 사용자가 영상/게임/소셜/학습 모드에서 각각 "편한 자세" 측정하면
/// 그 모드에서만 baseline 으로 사용한다.
///
/// 저장 키 패턴:
///   `posture_calibration_tilt_{modeName}`   (double, 도)
///   `posture_calibration_setAt_{modeName}`  (int, millis)
class PostureCalibration extends ChangeNotifier {
  static const _kTiltPrefix  = 'posture_calibration_tilt_';
  static const _kSetAtPrefix = 'posture_calibration_setAt_';

  final Map<DetectedContext, double>   _byMode = {};
  final Map<DetectedContext, DateTime> _setAt  = {};
  bool _loaded = false;

  bool get loaded => _loaded;

  /// 해당 모드의 baseline (없으면 null).
  double?   baselineFor(DetectedContext mode) => _byMode[mode];
  DateTime? setAtFor(DetectedContext mode)    => _setAt[mode];
  bool      isCalibratedFor(DetectedContext mode) => _byMode.containsKey(mode);

  /// 캘리브레이션된 모드 목록 (디버그/UI 용).
  Iterable<DetectedContext> get calibratedModes => _byMode.keys;

  /// 어떤 모드에서 측정 가능한가 (의미있는 컨텍스트만).
  /// onPhoneCall / normal 등은 제외.
  static bool isCalibratableMode(DetectedContext mode) {
    return mode == DetectedContext.watchingVideo ||
           mode == DetectedContext.gaming        ||
           mode == DetectedContext.social        ||
           mode == DetectedContext.studying      ||
           mode == DetectedContext.desk;
  }

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      for (final m in DetectedContext.values) {
        final tilt = p.getDouble('$_kTiltPrefix${m.name}');
        final ms   = p.getInt('$_kSetAtPrefix${m.name}');
        if (tilt != null) _byMode[m] = tilt;
        if (ms   != null) _setAt[m]  = DateTime.fromMillisecondsSinceEpoch(ms);
      }
    } catch (_) {/* ignore */}
    _loaded = true;
    notifyListeners();
  }

  Future<void> saveFor(DetectedContext mode, double tiltDeg) async {
    _byMode[mode] = tiltDeg;
    _setAt[mode]  = DateTime.now();
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setDouble('$_kTiltPrefix${mode.name}', tiltDeg);
    await p.setInt('$_kSetAtPrefix${mode.name}',
        _setAt[mode]!.millisecondsSinceEpoch);
  }

  Future<void> resetFor(DetectedContext mode) async {
    _byMode.remove(mode);
    _setAt.remove(mode);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.remove('$_kTiltPrefix${mode.name}');
    await p.remove('$_kSetAtPrefix${mode.name}');
  }

  Future<void> resetAll() async {
    final modes = _byMode.keys.toList();
    _byMode.clear();
    _setAt.clear();
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    for (final m in modes) {
      await p.remove('$_kTiltPrefix${m.name}');
      await p.remove('$_kSetAtPrefix${m.name}');
    }
  }
}
