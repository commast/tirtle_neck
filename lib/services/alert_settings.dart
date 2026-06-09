import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/neck_risk.dart';

/// 사용자에게 자세 주의/위험을 진동·소리로 알리는 설정.
/// - 주의(caution) / 경고(risk) 각각의 진동·소리 ON-OFF 분리
/// - 진동·소리 세기(0.0~1.0)는 공유 (단일 슬라이더)
/// SharedPreferences 에 영속화.
class AlertSettings extends ChangeNotifier {
  AlertSettings._();
  static final AlertSettings instance = AlertSettings._();

  // 경고 누적 정책 상수 — main_screen과 profile_tab이 함께 참조
  static const int riskWindowMinutes = 30; // 주의 누적 측정 윈도우
  static const int riskCautionCount  = 3;  // 경고 트리거에 필요한 주의 횟수

  // v2 키: 주의·경고 분리. 기존 v1 키는 마이그레이션 후 무시.
  static const _kCautionVib = 'alert_caution_vib_v2';
  static const _kCautionSnd = 'alert_caution_snd_v2';
  static const _kRiskVib    = 'alert_risk_vib_v2';
  static const _kRiskSnd    = 'alert_risk_snd_v2';
  // 마이그레이션용 v1 키 (단일 토글)
  static const _kVibLegacy  = 'alert_vibration_v1';
  static const _kSndLegacy  = 'alert_sound_v1';

  static const _kVibLvl = 'alert_vib_level_v1';
  static const _kSndLvl = 'alert_snd_level_v1';
  static const _kRiskCd = 'alert_risk_cooldown_min_v1';

  bool   _cautionVibration = true;
  bool   _cautionSound     = true;
  bool   _riskVibration    = true;
  bool   _riskSound        = true;
  double _vibrationLevel   = 0.7; // 0.0~1.0
  double _soundLevel       = 0.7; // 0.0~1.0
  int    _riskCooldownMinutes = 15; // 1~60

  bool   get cautionVibration => _cautionVibration;
  bool   get cautionSound     => _cautionSound;
  bool   get riskVibration    => _riskVibration;
  bool   get riskSound        => _riskSound;
  double get vibrationLevel   => _vibrationLevel;
  double get soundLevel       => _soundLevel;
  int    get riskCooldownMinutes => _riskCooldownMinutes;

  /// 슬라이더 enable 판정용 — 둘 중 하나라도 켜져있으면 세기 조절 가능.
  bool get anyVibrationOn => _cautionVibration || _riskVibration;
  bool get anySoundOn     => _cautionSound     || _riskSound;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 마이그레이션: v1 단일 토글이 있고 v2 가 없으면 v1 값을 양쪽 레벨에 복제.
      final hasV2 = prefs.containsKey(_kCautionVib);
      if (!hasV2) {
        final legacyVib = prefs.getBool(_kVibLegacy) ?? true;
        final legacySnd = prefs.getBool(_kSndLegacy) ?? true;
        _cautionVibration = legacyVib;
        _riskVibration    = legacyVib;
        _cautionSound     = legacySnd;
        _riskSound        = legacySnd;
      } else {
        _cautionVibration = prefs.getBool(_kCautionVib) ?? true;
        _cautionSound     = prefs.getBool(_kCautionSnd) ?? true;
        _riskVibration    = prefs.getBool(_kRiskVib)    ?? true;
        _riskSound        = prefs.getBool(_kRiskSnd)    ?? true;
      }
      _vibrationLevel = prefs.getDouble(_kVibLvl) ?? 0.7;
      _soundLevel     = prefs.getDouble(_kSndLvl) ?? 0.7;
      _riskCooldownMinutes = (prefs.getInt(_kRiskCd) ?? 15).clamp(1, 60);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setCautionVibration(bool v) async {
    if (_cautionVibration == v) return;
    _cautionVibration = v;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kCautionVib, v);
    } catch (_) {}
  }

  Future<void> setCautionSound(bool v) async {
    if (_cautionSound == v) return;
    _cautionSound = v;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kCautionSnd, v);
    } catch (_) {}
  }

  Future<void> setRiskVibration(bool v) async {
    if (_riskVibration == v) return;
    _riskVibration = v;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kRiskVib, v);
    } catch (_) {}
  }

  Future<void> setRiskSound(bool v) async {
    if (_riskSound == v) return;
    _riskSound = v;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kRiskSnd, v);
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

  Future<void> setRiskCooldownMinutes(int v) async {
    v = v.clamp(1, 60);
    if (_riskCooldownMinutes == v) return;
    _riskCooldownMinutes = v;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kRiskCd, v);
    } catch (_) {}
  }

  /// 위험 단계 진입 시 호출. 레벨별로 분리된 진동·소리 설정에 따라 알림.
  void triggerAlert(NeckRiskLevel level) {
    if (level == NeckRiskLevel.normal) return;
    final isRisk = level == NeckRiskLevel.risk;
    final vibOn = isRisk ? _riskVibration : _cautionVibration;
    final sndOn = isRisk ? _riskSound     : _cautionSound;
    if (vibOn) _playHaptic();
    if (sndOn) _playSound();
  }

  /// 설정 화면 슬라이더 조정 시 미리듣기 — 토글 OFF여도 강제로 재생.
  void previewVibration() => _playHaptic();
  void previewSound() => _playSound();

  void _playHaptic() {
    // HapticFeedback.vibrate() — 일반 진동 패턴, light/medium/heavy 보다 길고 확실함.
    // 게임/영상 풀스크린에서도 손에 잡힘.
    try {
      HapticFeedback.vibrate();
    } catch (e) {
      debugPrint('[Alert] 진동 실패: $e');
    }
  }

  void _playSound() {
    // play() 의 asAlarm: true 로 알람 스트림 사용 → 거의 모든 상황에서 들림.
    try {
      FlutterRingtonePlayer().play(
        android: AndroidSounds.notification,
        ios: IosSounds.glass,
        looping: false,
        volume: _soundLevel,
        asAlarm: true,
      );
    } catch (e) {
      debugPrint('[Alert] 알림음 재생 실패: $e');
      SystemSound.play(SystemSoundType.click);
    }
  }
}
