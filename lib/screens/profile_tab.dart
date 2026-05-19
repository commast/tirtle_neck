import 'package:flutter/material.dart';
import '../constants.dart';

class ProfileTab extends StatefulWidget {
  final String               serverIp;
  final ValueChanged<String>? onServerIpChanged; // null이면 Windows (숨김)
  final VoidCallback?        onOverlayStart;     // 오버레이 수동 시작

  const ProfileTab({
    super.key,
    required this.serverIp,
    this.onServerIpChanged,
    this.onOverlayStart,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  late final TextEditingController _ipCtrl;

  @override
  void initState() {
    super.initState();
    _ipCtrl = TextEditingController(text: widget.serverIp);
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
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
