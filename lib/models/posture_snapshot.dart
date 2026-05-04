class PostureSnapshot {
  final DateTime time;
  final int      score;
  final double   pitchDeg; // 목 각도 (도)

  const PostureSnapshot({
    required this.time,
    required this.score,
    required this.pitchDeg,
  });
}
