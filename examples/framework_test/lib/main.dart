import 'dart:ui';
import 'package:flutter/material.dart';

void main() {
  double dy = 300.0;

  PlatformDispatcher.instance.onDrawFrame = () {
    final PictureRecorder pictureRecorder = PictureRecorder();
    drawLine(pictureRecorder, dy);
    if (dy < 800) {
      dy++;
    }

    final Picture picture = pictureRecorder.endRecording();

    final SceneBuilder sceneBuilder = SceneBuilder();
    sceneBuilder.addPicture(Offset.zero, picture);
    final Scene scene = sceneBuilder.build();

    // 不断刷新界面
    window.render(scene);
    PlatformDispatcher.instance.scheduleFrame();
  };

  PlatformDispatcher.instance.scheduleFrame();
}

void drawLine(PictureRecorder recorder, double dy) {
  final Canvas canvas = Canvas(recorder);

  final Paint paint = Paint()
    ..color = Colors.white
    ..strokeWidth = 10;

  canvas.drawLine(Offset(300, dy), Offset(800, dy), paint);
}
