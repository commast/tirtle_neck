import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/detected_context.dart';
import '../models/sensor_posture.dart';
import 'app_category_classifier.dart';
import 'foreground_app_channel.dart';
import 'phone_state_channel.dart';

/// 컨텍스트 감지 결과 + 디버그 정보.
class ContextSnapshot {
  final DetectedContext context;
  final String? foregroundPackage;
  final String? foregroundLabel;
  final AppCategory appCategory;
  final bool screenOn;
  final bool inCall;
  final SensorPosture sensorPosture;

  const ContextSnapshot({
    required this.context,
    required this.foregroundPackage,
    required this.foregroundLabel,
    required this.appCategory,
    required this.screenOn,
    required this.inCall,
    required this.sensorPosture,
  });

  static const initial = ContextSnapshot(
    context: DetectedContext.normal,
    foregroundPackage: null,
    foregroundLabel: null,
    appCategory: AppCategory.other,
    screenOn: true,
    inCall: false,
    sensorPosture: SensorPosture.normal,
  );
}

class ContextDetector {
  final ForegroundAppChannel _fgApp;
  final PhoneStateChannel    _phone;

  StreamSubscription<ForegroundAppEvent>?  _fgSub;
  StreamSubscription<PhoneState>?          _phoneSub;

  // 상태
  SensorPosture _sensorPosture = SensorPosture.normal;
  bool _screenOn = true;
  bool _inCall   = false;
  String? _fgPkg;
  String? _fgLabel;
  AppCategory _fgCategory = AppCategory.other;

  /// 현재 컨텍스트만 노출.
  final ValueNotifier<DetectedContext> context =
      ValueNotifier(DetectedContext.normal);

  /// 디버그용 통합 스냅샷 — ProfileTab 등에서 구독.
  final ValueNotifier<ContextSnapshot> snapshot =
      ValueNotifier(ContextSnapshot.initial);

  ContextDetector({
    ForegroundAppChannel? foregroundAppChannel,
    PhoneStateChannel?    phoneStateChannel,
  })  : _fgApp = foregroundAppChannel ?? ForegroundAppChannel(),
        _phone = phoneStateChannel    ?? PhoneStateChannel();

  ForegroundAppChannel get foregroundAppChannel => _fgApp;

  Future<void> start() async {
    // ── ForegroundApp ───────────────────────────────────────
    try {
      _fgSub = _fgApp.stream.listen(
        _onForegroundApp,
        onError: (e) => debugPrint('[Context] FgApp 오류: $e'),
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[Context] FgApp 구독 실패: $e');
    }

    // ── PhoneState (화면 ON/OFF + 통화) ───────────────────────
    try {
      _phoneSub = _phone.stream.listen(
        _onPhoneState,
        onError: (e) => debugPrint('[Context] Phone 오류: $e'),
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[Context] Phone 구독 실패: $e');
    }
  }

  void updateSensorPosture(SensorPosture posture) {
    if (_sensorPosture == posture) return;
    _sensorPosture = posture;
    _resolve();
  }

  void _onForegroundApp(ForegroundAppEvent ev) {
    _fgPkg      = ev.package;
    _fgLabel    = ev.label;
    _fgCategory = AppCategoryClassifier.classify(
      ev.package,
      systemCategory: ev.systemCategory,
    );
    debugPrint('[Context] 포그라운드: ${ev.label} (${ev.package}) '
        'sys=${ev.systemCategory} → ${_fgCategory.name}');
    _resolve();
  }

  void _onPhoneState(PhoneState st) {
    _screenOn = st.screenOn;
    _inCall   = st.inCall;
    _resolve();
  }

  DetectedContext _resolveInternal() {
    if (_inCall) return DetectedContext.onPhoneCall;
    if (_screenOn) {
      switch (_fgCategory) {
        case AppCategory.video:  return DetectedContext.watchingVideo;
        case AppCategory.game:   return DetectedContext.gaming;
        case AppCategory.social: return DetectedContext.social;
        case AppCategory.study:  return DetectedContext.studying;
        case AppCategory.other:  break;
      }
    }
    if (_sensorPosture == SensorPosture.desk) return DetectedContext.desk;
    return DetectedContext.normal;
  }

  void _resolve() {
    final next = _resolveInternal();

    snapshot.value = ContextSnapshot(
      context: next,
      foregroundPackage: _fgPkg,
      foregroundLabel:   _fgLabel,
      appCategory:       _fgCategory,
      screenOn:          _screenOn,
      inCall:            _inCall,
      sensorPosture:     _sensorPosture,
    );

    if (context.value != next) {
      debugPrint('[Context] ${context.value.label} → ${next.label}  '
          '(pitch임계=${next.pitchThreshold}°)');
      context.value = next;
    }
  }

  void dispose() {
    _fgSub?.cancel();
    _phoneSub?.cancel();
    context.dispose();
    snapshot.dispose();
  }
}
