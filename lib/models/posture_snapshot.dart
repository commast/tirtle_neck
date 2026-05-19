class PostureSnapshot {
  final DateTime time;
  final int      score;
  final double   pitchDeg;

  const PostureSnapshot({
    required this.time,
    required this.score,
    required this.pitchDeg,
  });

  Map<String, dynamic> toJson() => {
    'time':     time.toIso8601String(),
    'score':    score,
    'pitchDeg': pitchDeg,
  };

  factory PostureSnapshot.fromJson(Map<String, dynamic> json) => PostureSnapshot(
    time:     DateTime.parse(json['time'] as String),
    score:    json['score'] as int,
    pitchDeg: (json['pitchDeg'] as num).toDouble(),
  );
}
