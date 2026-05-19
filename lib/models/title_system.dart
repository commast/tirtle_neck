import 'package:flutter/material.dart';
import 'posture_snapshot.dart';

class PostureTitle {
  final String   name;
  final String   emoji;
  final Color    color;
  final String   description;
  final int      minScore;

  const PostureTitle({
    required this.name,
    required this.emoji,
    required this.color,
    required this.description,
    required this.minScore,
  });
}

// ── 칭호 테이블 ──────────────────────────────────────────────────
const _titles = [
  PostureTitle(
    name: '자세의 달인',   emoji: '🏆',
    color: Color(0xFFFFB300),
    description: '완벽에 가까운 자세를 유지하고 있습니다!',
    minScore: 90,
  ),
  PostureTitle(
    name: '건강한 척추',   emoji: '💪',
    color: Color(0xFF00C896),
    description: '자세 관리를 잘 하고 있습니다.',
    minScore: 80,
  ),
  PostureTitle(
    name: '노력하는 중',   emoji: '😊',
    color: Color(0xFF2196F3),
    description: '꾸준한 노력이 필요합니다.',
    minScore: 70,
  ),
  PostureTitle(
    name: '주의 필요',    emoji: '⚠️',
    color: Color(0xFFFF9800),
    description: '자세 교정에 신경 써보세요.',
    minScore: 60,
  ),
  PostureTitle(
    name: '거북목 위험',  emoji: '🐢',
    color: Color(0xFFF44336),
    description: '즉각적인 자세 개선이 필요합니다!',
    minScore: 0,
  ),
];

PostureTitle titleFromScore(int score) {
  for (final t in _titles) {
    if (score >= t.minScore) return t;
  }
  return _titles.last;
}

// ── 기간별 평균 계산 ─────────────────────────────────────────────
class ScoreAverages {
  final int daily;
  final int weekly;
  final int monthly;
  final int overall;

  const ScoreAverages({
    required this.daily,
    required this.weekly,
    required this.monthly,
    required this.overall,
  });

  static ScoreAverages from(List<PostureSnapshot> snapshots) {
    if (snapshots.isEmpty) {
      return const ScoreAverages(daily: 0, weekly: 0, monthly: 0, overall: 0);
    }

    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart  = today.subtract(Duration(days: today.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);

    int avg(List<PostureSnapshot> list) {
      if (list.isEmpty) return 0;
      return (list.map((s) => s.score).reduce((a, b) => a + b) / list.length)
          .round();
    }

    return ScoreAverages(
      daily:   avg(snapshots.where((s) => !s.time.isBefore(today)).toList()),
      weekly:  avg(snapshots.where((s) => !s.time.isBefore(weekStart)).toList()),
      monthly: avg(snapshots.where((s) => !s.time.isBefore(monthStart)).toList()),
      overall: avg(snapshots),
    );
  }
}
