import 'dart:io';
import 'package:flutter/services.dart';
import '../models/detected_context.dart';
import '../models/neck_risk.dart';

/// 네이티브 Android OverlayService 와 통신하는 채널.
/// 분할 레이아웃: [모드 칩] [위험 칩(정상이면 숨김)]
class OverlayChannel {
  static const _ch       = MethodChannel('com.example.tirtle_ml/overlay');
  static const _cameraCh = MethodChannel('com.example.tirtle_ml/camera_bg');

  /// 백그라운드 카메라 서비스 시작 (startCapture 시 호출)
  static Future<void> startCameraService() async {
    if (!Platform.isAndroid) return;
    try { await _cameraCh.invokeMethod('start'); } catch (_) {}
  }

  /// 백그라운드 카메라 서비스 중지 (stopCapture 시 호출)
  static Future<void> stopCameraService() async {
    if (!Platform.isAndroid) return;
    try { await _cameraCh.invokeMethod('stop'); } catch (_) {}
  }

  static Future<void> start() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('start');
    } catch (_) {}
  }

  /// 측정 버튼 탭 콜백 등록 (Kotlin → Flutter).
  /// [main_screen]에서 한 번만 등록.
  static void setCalibrateTappedHandler(void Function() handler) {
    if (!Platform.isAndroid) return;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'onCalibrateTapped') {
        handler();
      }
    });
  }

  /// 모드 + 위험 레벨로 오버레이 갱신.
  /// - 모드 칩: 컨텍스트별 색 + 라벨 (영상/게임/소셜/학습/...)
  /// - 위험 칩: 정상이면 숨김, 주의=주황, 위험=빨강
  /// - 측정 버튼: [showCalibrateBtn]=true 면 표시. 캘리브레이션 중이면
  ///   [calibrateBtnText]로 카운트다운 등 표시 가능 ("측정 중 3" 등).
  static Future<void> updateSplit({
    required DetectedContext mode,
    required NeckRiskLevel risk,
    String? appLabel,
    int? score,
    bool   showCalibrateBtn = false,
    String? calibrateBtnText,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      final modeText = _buildModeText(mode, appLabel);
      final riskText = risk == NeckRiskLevel.normal
          ? null
          : (score != null ? '${risk.label} $score점' : risk.label);
      await _ch.invokeMethod('updateSplit', {
        'modeLabel': modeText,
        'modeColor': mode.modeColorHex,
        'riskLabel': riskText,
        'riskColor': risk == NeckRiskLevel.normal ? null : risk.colorHex,
        'showCalibrateBtn': showCalibrateBtn,
        'calibrateBtnText': calibrateBtnText,
      });
    } catch (_) {}
  }

  static String _buildModeText(DetectedContext mode, String? appLabel) {
    final base = mode.overlayLabel ?? '대기';
    if (appLabel == null || appLabel.isEmpty) return base;
    final trimmed = appLabel.length > 10 ? '${appLabel.substring(0, 10)}…' : appLabel;
    return '$base · $trimmed';
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
  }
}
