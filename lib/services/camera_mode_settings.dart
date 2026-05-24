import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/detected_context.dart';

/// 게임/영상 모드에서 카메라 사용을 옵트인할지 저장. 기본 false (꺼짐).
class CameraModeSettings extends ChangeNotifier {
  static const _kGame  = 'camera_in_gaming';
  static const _kVideo = 'camera_in_video';

  bool _inGame  = false;
  bool _inVideo = false;
  bool _loaded  = false;

  bool get inGame  => _inGame;
  bool get inVideo => _inVideo;
  bool get loaded  => _loaded;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _inGame  = p.getBool(_kGame)  ?? false;
      _inVideo = p.getBool(_kVideo) ?? false;
      _loaded  = true;
      notifyListeners();
    } catch (_) {
      _loaded = true;
    }
  }

  Future<void> setInGame(bool v) async {
    _inGame = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kGame, v);
  }

  Future<void> setInVideo(bool v) async {
    _inVideo = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kVideo, v);
  }

  /// 주어진 컨텍스트에서 카메라 캡처가 허용되는지 판정.
  /// 게임/영상 컨텍스트에서 사용자가 옵트인한 경우에만 true.
  bool isCameraAllowedIn(DetectedContext ctx) {
    if (ctx == DetectedContext.gaming)        return _inGame;
    if (ctx == DetectedContext.watchingVideo) return _inVideo;
    return false; // 그 외 모드는 카메라 사용 안 함 (정책)
  }
}
