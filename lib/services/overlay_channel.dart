import 'dart:io';
import 'package:flutter/services.dart';
import '../models/sensor_posture.dart';

/// 네이티브 Android OverlayService 와 통신하는 채널
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
    } catch (e) {
      // ignore
    }
  }

  static Future<void> update(SensorPosture posture) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('update', {
        'label': posture.label,
        'color': _colorHex(posture),
      });
    } catch (e) {
      // ignore
    }
  }

  /// 사진 촬영 결과를 오버레이에 표시 (자세 + 점수)
  static Future<void> updateWithScore(SensorPosture posture, int score) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('update', {
        'label': '${posture.label} $score점',
        'color': _colorHex(posture),
      });
    } catch (e) {
      // ignore
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('stop');
    } catch (e) {
      // ignore
    }
  }

  static String _colorHex(SensorPosture p) => switch (p) {
    SensorPosture.inactive   => '#9E9E9E',
    SensorPosture.normal     => '#00C896',
    SensorPosture.turtleNeck => '#FF9800',
    SensorPosture.desk       => '#2196F3',
    SensorPosture.sideLying  => '#00838F',
    SensorPosture.lying      => '#9C27B0',
  };
}
