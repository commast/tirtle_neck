import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/detected_context.dart';
import '../models/sensor_posture.dart';
import '../services/context_detector.dart';
import '../services/camera_mode_settings.dart';
import '../services/posture_calibration.dart';
import '../services/headphone_head_tracker.dart';

class ProfileTab extends StatefulWidget {
  final String                serverIp;
  final ValueChanged<String>? onServerIpChanged; // null이면 Windows (숨김)
  final VoidCallback?         onOverlayStart;    // 오버레이 수동 시작
  final ContextDetector?      contextDetector;   // 컨텍스트 디버그용 (Android)
  final CameraModeSettings?   cameraSettings;    // 모드별 카메라 옵트인 (Android)
  final PostureCalibration?    calibration;       // 모드별 baseline 자세
  final HeadphoneHeadTracker?  headphoneTracker;  // 실험: 이어폰 헤드 트래커

  const ProfileTab({
    super.key,
    required this.serverIp,
    this.onServerIpChanged,
    this.onOverlayStart,
    this.contextDetector,
    this.cameraSettings,
    this.calibration,
    this.headphoneTracker,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  late final TextEditingController _ipCtrl;
  bool _usageStatsGranted = false;

  @override
  void initState() {
    super.initState();
    _ipCtrl = TextEditingController(text: widget.serverIp);
    _refreshUsageStatsPermission();
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshUsageStatsPermission() async {
    final det = widget.contextDetector;
    if (det == null) return;
    final granted = await det.foregroundAppChannel.hasPermission();
    if (mounted) setState(() => _usageStatsGranted = granted);
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
          Row(children: [
            Expanded(child: _statCard('총 측정일', '14일')),
            const SizedBox(width: 10),
            Expanded(child: _statCard('평균 점수', '78점')),
            const SizedBox(width: 10),
            Expanded(child: _statCard('총 토큰', '5개')),
          ]),
          const SizedBox(height: 20),

          // 모바일에서만 서버 IP 설정 표시
          if (widget.onServerIpChanged != null) ...[
            _serverIpCard(),
            const SizedBox(height: 10),
          ],

          // 오버레이 수동 시작 카드 (Android 전용)
          if (widget.onOverlayStart != null) ...[
            _overlayCard(),
            const SizedBox(height: 10),
          ],

          // 개인 자세 캘리브레이션 (Android 전용)
          if (widget.calibration != null) ...[
            _calibrationCard(),
            const SizedBox(height: 10),
          ],

          // 모드별 카메라 옵트인 (Android 전용)
          if (widget.cameraSettings != null) ...[
            _cameraModeCard(),
            const SizedBox(height: 10),
          ],

          // 컨텍스트 디버그 카드 (Android 전용)
          if (widget.contextDetector != null) ...[
            _contextDebugCard(),
            const SizedBox(height: 10),
          ],

          // 실험: 이어폰 헤드 트래커 (Android 전용)
          // 자세한 동작 설명: docs/HEADPHONE_TRACKER.md
          if (widget.headphoneTracker != null) ...[
            _headphoneCard(),
            const SizedBox(height: 10),
          ],

          ..._settings.map((s) => Container(
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
              leading: Icon(s.icon, color: kGreen),
              title: Text(s.label),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () {},
            ),
          )),
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

  Widget _calibrationCard() {
    final cal = widget.calibration!;
    return AnimatedBuilder(
      animation: cal,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kGreen.withValues(alpha: 0.4)),
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.straighten_rounded, color: kGreen, size: 18),
              const SizedBox(width: 6),
              const Text('모드별 자세 기준',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ]),
            const SizedBox(height: 4),
            Text(
              '각 모드에서 오버레이의 "🎯 측정" 버튼을 눌러 평상시 자세를 등록하세요.\n'
              '등록된 모드에선 그 자세 기준으로 거북목을 판정합니다.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            const SizedBox(height: 10),
            for (final m in _calibratableModes) _modeRow(cal, m),
            if (cal.calibratedModes.isNotEmpty) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => cal.resetAll(),
                  icon: const Icon(Icons.delete_outline, size: 14),
                  label: const Text('전체 초기화', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.grey[600],
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
              ),
            ],
          ]),
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

  Widget _headphoneCard() {
    final tracker = widget.headphoneTracker!;
    return AnimatedBuilder(
      animation: tracker,
      builder: (context, _) {
        final s = tracker.state;
        final isTracking = s.status == HeadphoneTrackerStatus.tracking;
        final isUnsupported = s.status == HeadphoneTrackerStatus.earphoneUnsupported;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('🎧', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              const Text('이어폰 헤드 트래커',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('실험',
                    style: TextStyle(
                      fontSize: 9,
                      color: Color(0xFF8B6914),
                      fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              '대부분의 이어폰은 헤드 트래커 데이터를 제공하지 않습니다.\n본인 기기 지원 확인용입니다.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            const SizedBox(height: 10),
            _kv('연결',
                s.deviceName ?? '이어폰 미연결'),
            _kv('상태', _statusLabel(s.status)),
            if (isTracking && s.pitchDeg != null)
              _kv('머리 pitch', '${s.pitchDeg!.toStringAsFixed(1)}°'),
            if (s.lastEventAt != null)
              _kv('마지막 이벤트',
                  '${DateTime.now().difference(s.lastEventAt!).inSeconds}s 전'),
            if (isUnsupported) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(child: Text(
                  '이 이어폰은 헤드 트래커 데이터를 외부 앱에 공개하지 않습니다.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]))),
              ]),
            ],
          ]),
        );
      },
    );
  }

  String _statusLabel(HeadphoneTrackerStatus st) => switch (st) {
    HeadphoneTrackerStatus.tracking            => '✅ tracking',
    HeadphoneTrackerStatus.earphoneUnsupported => '❌ 지원 안 됨',
    HeadphoneTrackerStatus.noEarphone          => '— 이어폰 미연결',
    HeadphoneTrackerStatus.unknown             => '⏳ 초기화 중',
  };

  Widget _contextDebugCard() {
    final det = widget.contextDetector!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.bug_report_rounded, color: Colors.blueGrey, size: 18),
          SizedBox(width: 6),
          Text('컨텍스트 상태 (디버그)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ]),
        const SizedBox(height: 4),
        Text('포그라운드 앱이 제대로 감지되는지 확인할 수 있어요.',
            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        const SizedBox(height: 12),

        // 권한 상태 줄
        Row(children: [
          Icon(_usageStatsGranted ? Icons.check_circle : Icons.error_outline,
              color: _usageStatsGranted ? kGreen : Colors.orange, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text('사용 정보 접근 ${_usageStatsGranted ? "허용됨" : "필요"}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          if (!_usageStatsGranted)
            TextButton(
              onPressed: () async {
                await det.foregroundAppChannel.openSettings();
                // 사용자가 돌아온 뒤 재확인
                await Future.delayed(const Duration(milliseconds: 500));
                await _refreshUsageStatsPermission();
              },
              child: const Text('설정 열기'),
            ),
        ]),
        const Divider(height: 18),

        // 실시간 상태 — ContextDetector.snapshot 구독
        ValueListenableBuilder<ContextSnapshot>(
          valueListenable: det.snapshot,
          builder: (context, snap, _) {
            final pitch = snap.context.pitchThreshold;
            final pitchStr = pitch.isFinite ? '${pitch.toStringAsFixed(0)}°' : '감지 끔';
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _kv('현재 앱',  snap.foregroundLabel ?? '—'),
              _kv('패키지',  snap.foregroundPackage ?? '—', mono: true),
              _kv('분류',    snap.appCategory.name),
              _kv('컨텍스트', snap.context.label),
              _kv('pitch 임계', pitchStr),
              const Divider(height: 14),
              _kv('화면',    snap.screenOn ? 'ON' : 'OFF'),
              _kv('통화',    snap.inCall ? '통화 중' : '아님'),
              _kv('자세',    snap.sensorPosture.label),
              _kv('위험 가중치', '×${snap.context.riskWeight}'),
            ]);
          },
        ),
      ]),
    );
  }

  Widget _kv(String k, String v, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 78, child: Text(k,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
        Expanded(
          child: Text(v,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: mono ? 'monospace' : null,
              ),
              overflow: TextOverflow.ellipsis),
        ),
      ]),
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

  Widget _serverIpCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kGreen.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04), blurRadius: 6,
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.wifi_rounded, color: kGreen, size: 18),
          const SizedBox(width: 6),
          const Text('서버 IP 설정',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const Spacer(),
          Text('포트: $kServerPort',
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ]),
        const SizedBox(height: 4),
        Text('PC와 같은 WiFi에 연결 후 PC의 IP를 입력하세요.',
            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ipCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: '예: 192.168.0.10',
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: kGreen),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: () {
              widget.onServerIpChanged?.call(_ipCtrl.text.trim());
              FocusScope.of(context).unfocus();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${_ipCtrl.text.trim()}:$kServerPort 에 연결 중...'),
                  backgroundColor: kGreen,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('연결'),
          ),
        ]),
      ]),
    );
  }

  Widget _statCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04), blurRadius: 6,
          ),
        ],
      ),
      child: Column(children: [
        Text(value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ]),
    );
  }

  static const _settings = [
    _SettingItem('알림 설정', Icons.notifications_outlined),
    _SettingItem('측정 설정', Icons.tune_rounded),
    _SettingItem('도움말',    Icons.help_outline_rounded),
    _SettingItem('앱 정보',   Icons.info_outline_rounded),
  ];
}

class _SettingItem {
  final String   label;
  final IconData icon;
  const _SettingItem(this.label, this.icon);
}
