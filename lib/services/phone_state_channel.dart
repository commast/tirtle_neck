import 'dart:io';
import 'package:flutter/services.dart';

class PhoneState {
  final bool screenOn;
  final bool inCall;
  const PhoneState({required this.screenOn, required this.inCall});

  static const initial = PhoneState(screenOn: true, inCall: false);
}

class PhoneStateChannel {
  static const _events = EventChannel('com.example.tirtle_ml/phone_state_events');

  Stream<PhoneState>? _stream;

  Stream<PhoneState> get stream {
    if (!Platform.isAndroid) return const Stream.empty();
    _stream ??= _events.receiveBroadcastStream().map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      return PhoneState(
        screenOn: (m['screenOn'] as bool?) ?? true,
        inCall:   (m['inCall']   as bool?) ?? false,
      );
    });
    return _stream!;
  }
}
