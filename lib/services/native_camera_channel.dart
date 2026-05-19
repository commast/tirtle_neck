import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Activity lifecycle과 무관한 Kotlin Camera2 직접 캡처 채널.
/// 백그라운드에서도 CameraBackgroundService(camera type)가 실행 중이면 동작한다.
class NativeCameraChannel {
  static const _ch = MethodChannel('com.example.tirtle_ml/native_camera');

  /// 사진 촬영 → JPEG bytes 반환. 실패 시 null.
  static Future<List<int>?> captureImage() async {
    if (!Platform.isAndroid) return null;
    try {
      final bytes = await _ch.invokeMethod<Uint8List>('captureImage');
      if (bytes == null) return null;
      debugPrint('[NativeCam] 캡처 성공 (${bytes.length} bytes)');
      return bytes;
    } catch (e) {
      debugPrint('[NativeCam] 캡처 오류: $e');
      return null;
    }
  }
}
