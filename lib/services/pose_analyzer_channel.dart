import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/posture_state.dart';

/// 온디바이스 MediaPipe 자세 분석 채널.
/// 서버 없이 폰 안에서 직접 분석한다.
class PoseAnalyzerChannel {
  static const _ch = MethodChannel('com.example.tirtle_ml/pose_analyzer');
  static bool _initialized = false;

  /// 모델 로드 (앱 시작 시 1회 호출)
  static Future<bool> initialize() async {
    if (!Platform.isAndroid) return false;
    if (_initialized) return true;
    try {
      await _ch.invokeMethod('initialize');
      _initialized = true;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// JPEG 바이트 → 자세 분석 결과 반환
  /// 서버 응답과 동일한 PostureState 구조
  static Future<PostureState?> analyze(List<int> jpegBytes) async {
    if (!Platform.isAndroid || !_initialized) return null;
    try {
      final result = await _ch.invokeMethod<Map>('analyze', {
        'imageData': Uint8List.fromList(jpegBytes),
      });
      if (result == null) return null;
      // MethodChannel의 중첩 Map은 Map<Object?,Object?> 타입으로 옴 → 재귀 변환 필요
      return PostureState.fromJson(_deepConvert(result));
    } catch (e) {
      debugPrint('[PoseAnalyzer] analyze 오류: $e');
      return null;
    }
  }

  /// MethodChannel Map을 재귀적으로 Map[String,dynamic]으로 변환
  static Map<String, dynamic> _deepConvert(Map map) {
    return map.map((k, v) => MapEntry(
      k.toString(),
      v is Map ? _deepConvert(v) : v,
    ));
  }

  /// 리소스 해제
  static Future<void> close() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('close');
      _initialized = false;
    } catch (_) {}
  }
}
