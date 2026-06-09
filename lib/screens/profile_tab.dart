import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../constants.dart';
import '../models/detected_context.dart';
import '../services/posture_calibration.dart';
import '../services/alert_settings.dart';
import '../services/foreground_app_channel.dart';

class ProfileTab extends StatefulWidget {
  final VoidCallback?         onOverlayStart;    // 오버레이 수동 시작
  final PostureCalibration?   calibration;       // 모드별 baseline 자세

  const ProfileTab({
    super.key,
    this.onOverlayStart,
    this.calibration,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> with WidgetsBindingObserver {
  bool _usageGranted = false;
  bool _overlayGranted = false;
  final _fgApp = ForegroundAppChannel();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 설정 화면에서 권한 켜고 돌아오면 자동 재확인
    if (state == AppLifecycleState.resumed) _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final usage = await _fgApp.hasPermission();
    final overlay = await Permission.systemAlertWindow.isGranted;
    if (!mounted) return;
    setState(() {
      _usageGranted = usage;
      _overlayGranted = overlay;
    });
  }

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

          // 권한 상태 카드 (Android 전용)
          if (widget.onOverlayStart != null) ...[
            _permissionsCard(),
            const SizedBox(height: 10),
            _overlayCard(),
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

  Widget _permissionsCard() {
    final allGranted = _usageGranted && _overlayGranted;
    final color = allGranted ? kGreen : Colors.orange;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(allGranted ? Icons.verified_rounded : Icons.warning_amber_rounded,
              color: color, size: 18),
          const SizedBox(width: 6),
          const Text('권한 상태',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const Spacer(),
          IconButton(
            tooltip: '새로고침',
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: _refreshPermissions,
            icon: const Icon(Icons.refresh_rounded, color: Colors.grey),
          ),
        ]),
        const SizedBox(height: 4),
        Text('두 권한 모두 허용되어야 다른 앱 사용 중에 자세 감지가 작동합니다.',
            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        const SizedBox(height: 10),
        _permRow(
          label: '앱 사용 정보 접근',
          desc: '포그라운드 앱(영상/게임/SNS/학습) 감지',
          granted: _usageGranted,
          onGrant: () async {
            await _fgApp.openSettings();
            await Future.delayed(const Duration(milliseconds: 400));
            await _refreshPermissions();
          },
        ),
        const SizedBox(height: 8),
        _permRow(
          label: '다른 앱 위에 표시',
          desc: '오버레이 칩 표시',
          granted: _overlayGranted,
          onGrant: () async {
            await Permission.systemAlertWindow.request();
            await _refreshPermissions();
          },
        ),
      ]),
    );
  }

  Widget _permRow({
    required String label,
    required String desc,
    required bool granted,
    required VoidCallback onGrant,
  }) {
    return Row(children: [
      Icon(granted ? Icons.check_circle : Icons.cancel,
          color: granted ? kGreen : Colors.redAccent, size: 16),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          Text(desc,
              style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ]),
      ),
      if (!granted)
        TextButton(
          onPressed: onGrant,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: const Text('허용', style: TextStyle(fontSize: 12)),
        ),
    ]);
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
                _alarmSubtitle(s),
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              children: [
                Text(
                  '주의/위험 자세가 감지되면 진동이나 소리로 알려드립니다.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                // ── 주의 (caution) ─────────────────────────────
                _sectionLabel('주의 (1~2회 누적)', Colors.orange),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('진동', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('주의 발생 시 폰 진동',
                      style: TextStyle(fontSize: 11)),
                  value: s.cautionVibration,
                  onChanged: s.setCautionVibration,
                  activeThumbColor: Colors.orange,
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('소리', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('주의 발생 시 알림음',
                      style: TextStyle(fontSize: 11)),
                  value: s.cautionSound,
                  onChanged: s.setCautionSound,
                  activeThumbColor: Colors.orange,
                ),
                const SizedBox(height: 4),
                // ── 경고 (risk) ────────────────────────────────
                _sectionLabel('경고 (3회 누적 시 발사)', Colors.red),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('진동', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('경고 발생 시 폰 진동',
                      style: TextStyle(fontSize: 11)),
                  value: s.riskVibration,
                  onChanged: s.setRiskVibration,
                  activeThumbColor: Colors.red,
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('소리', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('경고 발생 시 알림음',
                      style: TextStyle(fontSize: 11)),
                  value: s.riskSound,
                  onChanged: s.setRiskSound,
                  activeThumbColor: Colors.red,
                ),
                const Divider(height: 16),
                // ── 공용 세기 슬라이더 ─────────────────────────
                _levelSlider(
                  label: '진동 세기',
                  value: s.vibrationLevel,
                  enabled: s.anyVibrationOn,
                  onChanged: s.setVibrationLevel,
                  onChangeEnd: (_) => s.previewVibration(),
                ),
                _levelSlider(
                  label: '소리 크기',
                  value: s.soundLevel,
                  enabled: s.anySoundOn,
                  onChanged: s.setSoundLevel,
                  onChangeEnd: (_) => s.previewSound(),
                ),
                const Divider(height: 16),
                Text(
                  '경고 쿨다운 — ${AlertSettings.riskWindowMinutes}분 내 주의 ${AlertSettings.riskCautionCount}회 누적 시 경고가 울리며, 이후 ${s.riskCooldownMinutes}분 동안은 재경고하지 않습니다.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                _intSlider(
                  label: '경고 쿨다운',
                  value: s.riskCooldownMinutes.toDouble(),
                  min: 1, max: 60,
                  onChanged: (v) => s.setRiskCooldownMinutes(v.round()),
                  suffix: '분',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _intSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required String suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 4, bottom: 4),
      child: Row(children: [
        SizedBox(
          width: 80,
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
              value: value.clamp(min, max),
              min: min, max: max,
              divisions: (max - min).round(),
              activeColor: kGreen,
              inactiveColor: Colors.grey[300],
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text('${value.round()}$suffix',
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ),
      ]),
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

  String _alarmSubtitle(AlertSettings s) {
    final caution = _summary(s.cautionVibration, s.cautionSound);
    final risk    = _summary(s.riskVibration,    s.riskSound);
    if (caution == risk) return '주의·경고 $caution';
    return '주의 $caution · 경고 $risk';
  }

  String _summary(bool vib, bool snd) {
    if (vib && snd) return '진동·소리';
    if (vib) return '진동만';
    if (snd) return '소리만';
    return '꺼짐';
  }

  Widget _sectionLabel(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(children: [
        Container(width: 4, height: 12, color: color),
        const SizedBox(width: 6),
        Text(text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            )),
      ]),
    );
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
