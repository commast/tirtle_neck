import 'package:flutter/material.dart';
import '../constants.dart';

enum SensorPosture { inactive, normal, turtleNeck, desk, sideLying, lying }

extension SensorPostureExt on SensorPosture {
  // TFLite 모델 출력 인덱스(0~4) → SensorPosture
  static SensorPosture fromIndex(int i) {
    const map = [
      SensorPosture.normal,
      SensorPosture.turtleNeck,
      SensorPosture.desk,
      SensorPosture.sideLying,
      SensorPosture.lying,
    ];
    return map[i.clamp(0, map.length - 1)];
  }

  String get label => switch (this) {
    SensorPosture.inactive   => '사용안함',
    SensorPosture.normal     => '정상',
    SensorPosture.turtleNeck => '거북목',
    SensorPosture.desk       => '책상 자세',
    SensorPosture.sideLying  => '옆으로 누움',
    SensorPosture.lying      => '누움',
  };

  Color get color => switch (this) {
    SensorPosture.inactive   => Colors.grey,
    SensorPosture.normal     => kGreen,
    SensorPosture.turtleNeck => Colors.orange,
    SensorPosture.desk       => Colors.blue,
    SensorPosture.sideLying  => Colors.cyan.shade700,
    SensorPosture.lying      => Colors.purple,
  };

  IconData get icon => switch (this) {
    SensorPosture.inactive   => Icons.sensors_off_rounded,
    SensorPosture.normal     => Icons.sentiment_satisfied_rounded,
    SensorPosture.turtleNeck => Icons.warning_amber_rounded,
    SensorPosture.desk       => Icons.laptop_rounded,
    SensorPosture.sideLying  => Icons.screen_rotation_rounded,
    SensorPosture.lying      => Icons.bed_rounded,
  };

  bool get isAlert => this == SensorPosture.turtleNeck;
}
