import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 이어폰 헤드 트래커 상태 (실험적 기능).
/// 자세한 동작 설명은 docs/HEADPHONE_TRACKER.md 참조.
enum HeadphoneTrackerStatus {
  unknown,             // 초기화 안 됨
  noEarphone,          // BT 오디오 미연결
  earphoneUnsupported, // 연결됐지만 헤드 트래커 미지원 (대부분의 케이스)
  tracking,            // 센서 데이터 들어오는 중
}

class HeadphoneTrackerState {
  final HeadphoneTrackerStatus status;
  final String?  deviceName;
  final double?  pitchDeg;
  final DateTime? lastEventAt;

  const HeadphoneTrackerState({
    required this.status,
    this.deviceName,
    this.pitchDeg,
    this.lastEventAt,
  });

  static const initial =
      HeadphoneTrackerState(status: HeadphoneTrackerStatus.unknown);
}

/// 네이티브 HeadphoneHeadTracker 와 통신하는 래퍼.
/// 상세 프로토콜은 docs/HEADPHONE_TRACKER.md 의 "채널 프로토콜" 섹션 참조.
class HeadphoneHeadTracker extends ChangeNotifier {
  static const _events =
      EventChannel('com.example.tirtle_ml/headphone_tracker');
  static const _method =
      MethodChannel('com.example.tirtle_ml/headphone_tracker_method');

  HeadphoneTrackerState _state = HeadphoneTrackerState.initial;
  HeadphoneTrackerState get state => _state;

  StreamSubscription? _sub;

  /// 스트림 구독 시작. 네이티브 측 BT 리시버도 자동으로 등록됨.
  Future<void> start() async {
    if (!Platform.isAndroid) return;
    if (_sub != null) return;
    _sub = _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (e) => debugPrint('[HeadphoneTracker] 스트림 오류: $e'),
      cancelOnError: false,
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    final m = Map<String, dynamic>.from(raw);
    final statusStr = (m['status'] as String?) ?? 'noEarphone';
    final status = switch (statusStr) {
      'tracking'            => HeadphoneTrackerStatus.tracking,
      'earphoneUnsupported' => HeadphoneTrackerStatus.earphoneUnsupported,
      'noEarphone'          => HeadphoneTrackerStatus.noEarphone,
      _                     => HeadphoneTrackerStatus.unknown,
    };
    final next = HeadphoneTrackerState(
      status:      status,
      deviceName:  m['device'] as String?,
      pitchDeg:    (m['pitchDeg'] as num?)?.toDouble(),
      lastEventAt: DateTime.now(),
    );
    _state = next;
    notifyListeners();
  }

  /// 디버그/진단 — 한 번 호출로 현재 환경 정보 받음.
  /// 반환: { androidSdk, headTrackerApiAvail, headTrackerSensor, device, btConnectPermission }
  Future<Map<String, dynamic>> checkSupport() async {
    if (!Platform.isAndroid) return {};
    try {
      final r = await _method.invokeMethod<Map<dynamic, dynamic>>('checkSupport');
      return r == null ? {} : Map<String, dynamic>.from(r);
    } catch (e) {
      debugPrint('[HeadphoneTracker] checkSupport 오류: $e');
      return {};
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
