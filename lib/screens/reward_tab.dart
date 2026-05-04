import 'package:flutter/material.dart';
import '../constants.dart';

class RewardTab extends StatelessWidget {
  const RewardTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(children: [
          const SizedBox(height: 24),
          const Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 64),
          const SizedBox(height: 12),
          const Text('보상 센터',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('바른 자세로 토큰을 획득하세요',
              style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 28),
          _buildTokenCard(),
          const SizedBox(height: 20),
          _buildRewardCard(),
          const SizedBox(height: 100),
        ]),
      ),
    );
  }

  Widget _buildTokenCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12, offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.token_rounded, color: Colors.amber, size: 36),
          const SizedBox(width: 8),
          const Text('0',
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
          const Text(' / 10',
              style: TextStyle(fontSize: 22, color: Colors.grey)),
        ]),
        const SizedBox(height: 6),
        Text('오늘의 토큰',
            style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        const SizedBox(height: 18),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: 0.0,
            minHeight: 10,
            backgroundColor: Colors.grey[200],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: kGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: const Text('오늘의 토큰 획득하기',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }

  Widget _buildRewardCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B61FF), Color(0xFF5A45D6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B61FF).withValues(alpha: 0.35),
            blurRadius: 16, offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('랜덤 보상',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 8),
              const Text('건강 챌린지\n완료 보상',
                  style: TextStyle(
                      color: Colors.white, fontSize: 20,
                      fontWeight: FontWeight.bold, height: 1.3)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('10 토큰 보상',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        const Icon(Icons.card_giftcard_rounded,
            color: Colors.white30, size: 70),
      ]),
    );
  }
}
