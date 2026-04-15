import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 构建根节点
  final PipelineOwner pipelineOwner = PipelineOwner();
  final RenderView renderView =
  RenderView(configuration: const ViewConfiguration(), view: window);
  pipelineOwner.rootNode = renderView;
  // 初始化
  renderView.prepareInitialFrame();

  final RenderFlex flex = RenderFlex(textDirection: TextDirection.ltr);

  // 从 301 开始移动到 500 一共绘制了 200 次
  double dy = 301;

  // 创建两个叶子节点
  final MyRenderNode node1 = MyRenderNode(dy, Colors.white);
  final MyRenderNode node2 = MyRenderNode(dy, Colors.blue);

  renderView.child = flex;
  // 注意这里是往前插入
  flex.insert(node1);
  flex.insert(node2);

  window.onDrawFrame = () {
    callFlush(pipelineOwner);
    renderView.compositeFrame();
    if (dy < 500) {
      node1.dy = ++dy;
      window.scheduleFrame();
    } else {
      print('node1 paint count: ${node1.paintCount}');
      print('node2 paint count: ${node2.paintCount}');
    }
  };

  window.scheduleFrame();
}

void callFlush(PipelineOwner pipelineOwner) {
  pipelineOwner.flushLayout();
  pipelineOwner.flushCompositingBits();
  pipelineOwner.flushPaint();
}

class MyRenderNode extends RenderBox {
  MyRenderNode(this._dy, Color color) {
    _paint = Paint()
      ..color = color
      ..strokeWidth = 10;
  }

  double _dy;
  int paintCount = 0;

  set dy(double dy) {
    _dy = dy;
    markNeedsLayout();
  }

  double get dy => _dy;

  late Paint _paint;

  void _drawLines(Canvas canvas, double dy) {
    canvas.drawLine(Offset(300, dy), Offset(800, dy), _paint);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _drawLines(context.canvas, dy);
    paintCount++;
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return constraints.smallest;
  }
}

