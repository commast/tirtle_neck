class PostureState {
  final String  status;
  final int     score;
  final int     countdown;
  final bool    isFhp;
  final Map<String, double> scores;
  final String  frame;

  const PostureState({
    required this.status,
    required this.score,
    required this.countdown,
    required this.isFhp,
    required this.scores,
    required this.frame,
  });

  factory PostureState.fromJson(Map<String, dynamic> json) {
    final raw = json['scores'] as Map<String, dynamic>? ?? {};
    return PostureState(
      status:    json['status']    as String? ?? 'starting',
      score:     json['score']     as int?    ?? 0,
      countdown: json['countdown'] as int?    ?? 5,
      isFhp:     json['is_fhp']   as bool?   ?? false,
      scores:    raw.map((k, v) => MapEntry(k, (v as num).toDouble())),
      frame:     json['frame']     as String? ?? '',
    );
  }

  static const PostureState initial = PostureState(
    status: 'starting', score: 0, countdown: 5, isFhp: false,
    scores: {'pitch': 1.0, 'eye': 1.0, 'vis': 1.0, 'z': 1.0},
    frame: '',
  );
}
