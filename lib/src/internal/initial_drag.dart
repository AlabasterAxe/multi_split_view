import 'package:meta/meta.dart';

import 'area_geometry.dart';

@internal
class InitialDrag {
  InitialDrag(
      {required this.initialDragPos,
      required this.initialChild1Geometry,
      required this.initialChild2Geometry,
      required this.child1Start,
      required this.child2End,
      required this.posLimitStart,
      required this.posLimitEnd});

  final double initialDragPos;
  final AreaGeometry initialChild1Geometry;
  final AreaGeometry initialChild2Geometry;
  final double child1Start;
  final double child2End;
  final double posLimitStart;
  final double posLimitEnd;
  bool posBeforeMinimalChild1 = false;
  bool posAfterMinimalChild2 = false;
  double get sumMinimals =>
      (initialChild1Geometry.minSize ?? 0) +
      (initialChild2Geometry.minSize ?? 0);
  double get sumSizes =>
      initialChild1Geometry.size + initialChild2Geometry.size;
}
