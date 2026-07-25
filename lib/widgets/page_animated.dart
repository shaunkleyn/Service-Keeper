import 'package:flutter/material.dart';

Widget PageAnimated(
    Widget child, int pageIndex, PageController _pageController) {
  return AnimatedBuilder(
    animation: _pageController,
    builder: (context, w) {
      final page = _pageController.hasClients ? (_pageController.page ?? 0.0) : 0.0;
      final progress = (1.0 - (page - pageIndex).abs()).clamp(0.0, 1.0);
      return Opacity(
        opacity: progress,
        child: ClipRect(
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: progress,
            child: w,
          ),
        ),
    );
    },
    child: child,
  );
}
