import 'package:flutter/material.dart';
import '../constants.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

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
