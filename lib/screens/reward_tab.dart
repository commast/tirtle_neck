import 'package:flutter/material.dart';
import '../models/posture_snapshot.dart';
import '../models/title_system.dart';

class RewardTab extends StatelessWidget {
  final List<PostureSnapshot> snapshots;

  const RewardTab({super.key, required this.snapshots});

  @override
  Widget build(BuildContext context) {
    final avgs  = ScoreAverages.from(snapshots);
    final title = titleFromScore(avgs.overall);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(children: [
          const SizedBox(height: 24),

          // ── 현재 칭호 카드 ──────────────────────────────────────
          _titleCard(title, avgs.overall),
          const SizedBox(height: 20),

          // ── 기간별 평균 ─────────────────────────────────────────
          _periodCard(avgs),
          const SizedBox(height: 20),

          // ── 칭호 목록 ───────────────────────────────────────────
          _titleListCard(avgs.overall),
          const SizedBox(height: 100),
        ]),
      ),
    );
  }

  // ── 현재 칭호 카드 ────────────────────────────────────────────
  Widget _titleCard(PostureTitle title, int score) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [title.color, title.color.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: title.color.withValues(alpha: 0.35),
            blurRadius: 16, offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(children: [
        Text(title.emoji, style: const TextStyle(fontSize: 52)),
        const SizedBox(height: 10),
        Text(title.name,
            style: const TextStyle(
                color: Colors.white, fontSize: 24,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(title.description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            score == 0 ? '측정 데이터 없음' : '전체 평균 $score점',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold,
                fontSize: 14),
          ),
        ),
      ]),
    );
  }

  // ── 기간별 평균 카드 ─────────────────────────────────────────
  Widget _periodCard(ScoreAverages avgs) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('기간별 평균 점수',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _periodRow('오늘',   avgs.daily),
        const SizedBox(height: 12),
        _periodRow('이번 주', avgs.weekly),
        const SizedBox(height: 12),
        _periodRow('이번 달', avgs.monthly),
      ]),
    );
  }

  Widget _periodRow(String label, int score) {
    final title = titleFromScore(score);
    final ratio = score / 100.0;
    return Row(children: [
      SizedBox(
        width: 64,
        child: Text(label,
            style: TextStyle(fontSize: 13, color: Colors.grey[600])),
      ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            minHeight: 10,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(title.color),
          ),
        ),
      ),
      const SizedBox(width: 12),
      SizedBox(
        width: 42,
        child: Text(
          score == 0 ? '-' : '$score점',
          textAlign: TextAlign.right,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.bold,
              color: title.color),
        ),
      ),
      const SizedBox(width: 8),
      Text(score == 0 ? '' : title.emoji,
          style: const TextStyle(fontSize: 14)),
    ]);
  }

  // ── 칭호 목록 카드 ───────────────────────────────────────────
  Widget _titleListCard(int currentScore) {
    const allTitles = [
      PostureTitle(name: '자세의 달인', emoji: '🏆',
          color: Color(0xFFFFB300), description: '',  minScore: 90),
      PostureTitle(name: '건강한 척추', emoji: '💪',
          color: Color(0xFF00C896), description: '',  minScore: 80),
      PostureTitle(name: '노력하는 중', emoji: '😊',
          color: Color(0xFF2196F3), description: '',  minScore: 70),
      PostureTitle(name: '주의 필요',  emoji: '⚠️',
          color: Color(0xFFFF9800), description: '',  minScore: 60),
      PostureTitle(name: '거북목 위험', emoji: '🐢',
          color: Color(0xFFF44336), description: '',  minScore: 0),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('칭호 목록',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        ...allTitles.map((t) {
          final unlocked = currentScore >= t.minScore && currentScore > 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              Text(t.emoji,
                  style: TextStyle(
                      fontSize: 24,
                      color: unlocked ? null : Colors.grey[300])),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.name,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: unlocked ? t.color : Colors.grey[400])),
                  Text('${t.minScore}점 이상',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[400])),
                ],
              )),
              if (unlocked)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: t.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('달성',
                      style: TextStyle(
                          fontSize: 11, color: t.color,
                          fontWeight: FontWeight.bold)),
                )
              else
                Icon(Icons.lock_rounded, size: 18, color: Colors.grey[300]),
            ]),
          );
        }),
      ]),
    );
  }
}
