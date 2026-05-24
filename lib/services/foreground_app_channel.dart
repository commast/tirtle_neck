import 'dart:io';
import 'package:flutter/services.dart';

class ForegroundAppEvent {
  final String package;
  final String label;
  /// Android ApplicationInfo.category — "game"/"video"/"audio"/"social"/
  /// "image"/"news"/"maps"/"productivity"/"undefined"
  final String systemCategory;
  const ForegroundAppEvent(this.package, this.label, this.systemCategory);
}

/// Kotlin ForegroundAppMonitor 와 통신하는 채널.
class ForegroundAppChannel {
  static const _events = EventChannel('com.example.tirtle_ml/foreground_app_events');
  static const _method = MethodChannel('com.example.tirtle_ml/foreground_app');

  Stream<ForegroundAppEvent>? _stream;

  Stream<ForegroundAppEvent> get stream {
    if (!Platform.isAndroid) return const Stream.empty();
    _stream ??= _events.receiveBroadcastStream().map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      return ForegroundAppEvent(
        (m['package']  as String?) ?? '',
        (m['label']    as String?) ?? '',
        (m['category'] as String?) ?? 'undefined',
      );
    });
    return _stream!;
  }

  Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      return (await _method.invokeMethod<bool>('hasPermission')) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openSettings() async {
    if (!Platform.isAndroid) return;
    try { await _method.invokeMethod('openSettings'); } catch (_) {}
  }
}
