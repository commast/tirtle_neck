import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/neck_risk.dart';

/// 사용자에게 자세 주의/위험을 진동·소리로 알리는 설정.
/// 진동/소리 ON-OFF + 각각의 세기(0.0~1.0). SharedPreferences 에 영속화.
class AlertSettings extends ChangeNotifier {
  AlertSettings._();
  static final AlertSettings instance = AlertSettings._();

  static const _kVib = 'alert_vibration_v1';
  static const _kSnd = 'alert_sound_v1';
  static const _kVibLvl = 'alert_vib_level_v1';
  static const _kSndLvl = 'alert_snd_level_v1';

  bool _vibration = true;
  bool _sound = true;
  double _vibrationLevel = 0.7; // 0.0~1.0
  double _soundLevel = 0.7;     // 0.0~1.0

  bool get vibration => _vibration;
  bool get sound => _sound;
  double get vibrationLevel => _vibrationLevel;
  double get soundLevel => _soundLevel;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _vibration = prefs.getBool(_kVib) ?? true;
      _sound = prefs.getBool(_kSnd) ?? true;
      _vibrationLevel = prefs.getDouble(_kVibLvl) ?? 0.7;
      _soundLevel = prefs.getDouble(_kSndLvl) ?? 0.7;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setVibration(bool v) async {
    if (_vibration == v) return;
    _vibration = v;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kVib, v);
    } catch (_) {}
  }

  Future<void> setSound(bool v) async {
    if (_sound == v) return;
    _sound = v;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSnd, v);
    } catch (_) {}
  }

  Future<void> setVibrationLevel(double v) async {
    v = v.clamp(0.0, 1.0);
    if ((_vibrationLevel - v).abs() < 0.005) return;
    _vibrationLevel = v;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kVibLvl, v);
    } catch (_) {}
  }

  Future<void> setSoundLevel(double v) async {
    v = v.clamp(0.0, 1.0);
    if ((_soundLevel - v).abs() < 0.005) return;
    _soundLevel = v;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kSndLvl, v);
    } catch (_) {}
  }

  /// 위험 단계 진입 시 호출. 진동/소리 설정에 따라 알림.
  void triggerAlert(NeckRiskLevel level) {
    if (level == NeckRiskLevel.normal) return;
    if (_vibration) _playHaptic();
    if (_sound) _playSound();
  }

  /// 설정 화면 슬라이더 조정 시 미리듣기 — 토글 OFF여도 강제로 재생.
  void previewVibration() => _playHaptic();
  void previewSound() => _playSound();

  void _playHaptic() {
    // 0.0~0.33 → light, 0.34~0.66 → medium, 0.67~1.0 → heavy.
    // HapticFeedback 자체가 3단계 외 미세 조정을 지원하지 않음.
    if (_vibrationLevel < 0.34) {
      HapticFeedback.lightImpact();
    } else if (_vibrationLevel < 0.67) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
  }

  void _playSound() {
    try {
      FlutterRingtonePlayer().playNotification(volume: _soundLevel);
    } catch (e) {
      debugPrint('[Alert] 알림음 재생 실패: $e');
      SystemSound.play(SystemSoundType.click);
    }
  }
}
