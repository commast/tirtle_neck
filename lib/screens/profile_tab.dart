import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/detected_context.dart';
import '../services/camera_mode_settings.dart';
import '../services/posture_calibration.dart';
import '../services/alert_settings.dart';

class ProfileTab extends StatefulWidget {
  final VoidCallback?         onOverlayStart;    // 오버레이 수동 시작
  final CameraModeSettings?   cameraSettings;    // 모드별 카메라 옵트인 (Android)
  final PostureCalibration?   calibration;       // 모드별 baseline 자세

  const ProfileTab({
    super.key,
    this.onOverlayStart,
    this.cameraSettings,
    this.calibration,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(children: [
          const SizedBox(height: 24),
          CircleAvatar(
            radius: 48,
            backgroundColor: kGreen.withValues(alpha: 0.15),
            child: const Icon(Icons.person_rounded, size: 52, color: kGreen),
          ),
          const SizedBox(height: 14),
          const Text('사용자',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('postureguard@email.com',
              style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          const SizedBox(height: 24),

          // 오버레이 수동 시작 카드 (Android 전용)
          if (widget.onOverlayStart != null) ...[
            _overlayCard(),
            const SizedBox(height: 10),
          ],

          // 모드별 카메라 옵트인 (Android 전용)
          if (widget.cameraSettings != null) ...[
            _cameraModeCard(),
            const SizedBox(height: 10),
          ],

          // 하단 설정 리스트 (알람 설정은 펼침)
          _alarmExpandable(),
          const SizedBox(height: 10),
          if (widget.calibration != null) ...[
            _measurementExpandable(),
            const SizedBox(height: 10),
          ] else
            _plainListTile('측정 설정', Icons.tune_rounded, enabled: false),
          _plainListTile('도움말',    Icons.help_outline_rounded, enabled: false),
          _plainListTile('앱 정보',   Icons.info_outline_rounded, enabled: false),
          const SizedBox(height: 100),
        ]),
      ),
    );
  }

  // 측정 가능한 컨텍스트만 카드에 나열
  static const _calibratableModes = [
    DetectedContext.watchingVideo,
    DetectedContext.gaming,
    DetectedContext.social,
    DetectedContext.studying,
    DetectedContext.desk,
  ];

  Widget _measurementExpandable() {
    final cal = widget.calibration!;
    return AnimatedBuilder(
      animation: cal,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04), blurRadius: 6,
              ),
            ],
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              leading: const Icon(Icons.tune_rounded, color: kGreen),
              title: const Text('측정 설정', style: TextStyle(fontSize: 14)),
              subtitle: Text(
                '모드별 자세 기준 (${cal.calibratedModes.length}/${_calibratableModes.length} 측정됨)',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              children: [
                Text(
                  '각 모드에서 오버레이의 "🎯 측정" 버튼을 눌러 평상시 자세를 등록하세요.\n'
                  '등록된 모드에선 그 자세 기준으로 거북목을 판정합니다.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                const SizedBox(height: 6),
                for (final m in _calibratableModes) _modeRow(cal, m),
                if (cal.calibratedModes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => cal.resetAll(),
                      icon: const Icon(Icons.delete_outline, size: 14),
                      label: const Text('전체 초기화',
                          style: TextStyle(fontSize: 11)),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey[600],
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _modeRow(PostureCalibration cal, DetectedContext mode) {
    final tilt = cal.baselineFor(mode);
    final done = tilt != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: Color(int.parse(mode.modeColorHex.substring(1), radix: 16) | 0xFF000000),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(mode.label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        if (done) ...[
          Text('${tilt.toStringAsFixed(1)}°',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey[700],
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => cal.resetFor(mode),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close, size: 14, color: Colors.grey[500]),
            ),
          ),
        ] else
          Text('미측정',
              style: TextStyle(fontSize: 11, color: Colors.grey[400])),
      ]),
    );
  }

  Widget _cameraModeCard() {
    final s = widget.cameraSettings!;
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.3)),
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.camera_alt_rounded, color: Colors.deepOrange, size: 18),
              SizedBox(width: 6),
              Text('모드별 카메라 사용',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ]),
            const SizedBox(height: 4),
            Text(
              '센서가 거북목 위험을 감지했을 때, 게임/영상 모드에서만 카메라로 자세를 검증합니다.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            const SizedBox(height: 8),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('게임 모드에서 카메라 사용',
                  style: TextStyle(fontSize: 13)),
              subtitle: const Text('위험 단계 5초 지속 시 자세 촬영',
                  style: TextStyle(fontSize: 11)),
              value: s.inGame,
              onChanged: s.setInGame,
              activeThumbColor: Colors.deepOrange,
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('영상 모드에서 카메라 사용',
                  style: TextStyle(fontSize: 13)),
              subtitle: const Text('위험 단계 5초 지속 시 자세 촬영',
                  style: TextStyle(fontSize: 11)),
              value: s.inVideo,
              onChanged: s.setInVideo,
              activeThumbColor: Colors.deepOrange,
            ),
          ]),
        );
      },
    );
  }

  Widget _overlayCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: Colors.purple.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.picture_in_picture_rounded,
              color: Colors.purple, size: 20),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('자세 오버레이',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            Text('다른 앱 위에 센서 상태 표시',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
        ),
        ElevatedButton(
          onPressed: widget.onOverlayStart,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          child: const Text('시작', style: TextStyle(fontSize: 13)),
        ),
      ]),
    );
  }

  /// 하단 ListTile 형 알람 설정 — 탭하면 진동/소리 토글 펼침
  Widget _alarmExpandable() {
    final s = AlertSettings.instance;
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        return Container(
          margin: const EdgeInsets.only(bottom: 0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04), blurRadius: 6,
              ),
            ],
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
            ),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              leading: const Icon(Icons.notifications_active_rounded, color: kGreen),
              title: const Text('알람 설정', style: TextStyle(fontSize: 14)),
              subtitle: Text(
                _alarmSubtitle(s.vibration, s.sound),
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              children: [
                Text(
                  '주의/위험 자세가 감지되면 진동이나 소리로 알려드립니다.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('진동 알림', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('주의 단계 진입 시 폰 진동',
                      style: TextStyle(fontSize: 11)),
                  value: s.vibration,
                  onChanged: s.setVibration,
                  activeThumbColor: kGreen,
                ),
                _levelSlider(
                  label: '진동 세기',
                  value: s.vibrationLevel,
                  enabled: s.vibration,
                  onChanged: s.setVibrationLevel,
                  onChangeEnd: (_) => s.previewVibration(),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('소리 알림', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('시스템 알림음 재생',
                      style: TextStyle(fontSize: 11)),
                  value: s.sound,
                  onChanged: s.setSound,
                  activeThumbColor: kGreen,
                ),
                _levelSlider(
                  label: '소리 크기',
                  value: s.soundLevel,
                  enabled: s.sound,
                  onChanged: s.setSoundLevel,
                  onChangeEnd: (_) => s.previewSound(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _levelSlider({
    required String label,
    required double value,
    required bool enabled,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    final color = enabled ? kGreen : Colors.grey;
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 4, bottom: 4),
      child: Row(children: [
        SizedBox(
          width: 60,
          child: Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value,
              activeColor: color,
              inactiveColor: Colors.grey[300],
              onChanged: enabled ? onChanged : null,
              onChangeEnd: enabled ? onChangeEnd : null,
            ),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text('${(value * 100).round()}',
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ),
      ]),
    );
  }

  String _alarmSubtitle(bool vib, bool snd) {
    if (vib && snd) return '진동·소리 모두 켜짐';
    if (vib) return '진동만 켜짐';
    if (snd) return '소리만 켜짐';
    return '모두 꺼짐';
  }

  Widget _plainListTile(String label, IconData icon, {bool enabled = true}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04), blurRadius: 6,
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(icon, color: enabled ? kGreen : Colors.grey[400]),
        title: Text(label,
            style: TextStyle(color: enabled ? null : Colors.grey[500])),
        trailing: Icon(Icons.chevron_right,
            color: enabled ? Colors.grey : Colors.grey[300]),
        enabled: enabled,
        onTap: enabled ? () {} : null,
      ),
    );
  }

}
