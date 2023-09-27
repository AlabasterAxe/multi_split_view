import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:multi_split_view/src/area.dart';

import '../../multi_split_view.dart';

abstract class WidgetDescriptor {}

class ContentWidgetDescriptor extends WidgetDescriptor {
  ContentWidgetDescriptor(
      {required this.widget, required this.childStart, required this.childEnd});
  final Widget widget;
  final double childStart;
  final double childEnd;
}

class DividerWidgetDescriptor extends WidgetDescriptor {
  DividerWidgetDescriptor(
      {required this.widget,
      required this.dividerStart,
      required this.dividerEnd,
      required this.index});
  final Widget widget;
  final double dividerStart;
  final double dividerEnd;
  final int index;
}

@internal
class SizesCache {
  factory SizesCache(
      {required List<Area> areas,
      required double fullSize,
      required double dividerThickness}) {
    final int childrenCount = areas.length;
    final double totalDividerSize = (childrenCount - 1) * dividerThickness;
    final double childrenSize = fullSize - totalDividerSize;
    List<double> sizes = [];
    List<double> minimalSizes = [];
    Map<Key, double> keyedSizes = {};
    Map<Key, double> keyedMinimalSizes = {};
    for (Area area in areas) {
      double size = area.weight! * childrenSize;
      if (area.key != null) {
        keyedSizes[area.key!] = size;
      } else {
        sizes.add(size);
      }
      double minimalSize = area.minimalSize ?? 0;
      if (area.minimalWeight != null) {
        minimalSize = area.minimalWeight! * childrenSize;
      }
      if (area.key != null) {
        keyedMinimalSizes[area.key!] = minimalSize;
      } else {
        minimalSizes.add(minimalSize);
      }
    }
    return SizesCache._(
      childrenCount: areas.length,
      fullSize: fullSize,
      childrenSize: childrenSize,
      sizes: sizes,
      minimalSizes: minimalSizes,
      dividerThickness: dividerThickness,
      keyedSizes: keyedSizes,
      keyedMinimalSizes: keyedMinimalSizes,
    );
  }

  SizesCache._({
    required this.childrenCount,
    required this.fullSize,
    required this.childrenSize,
    required this.sizes,
    required this.minimalSizes,
    required this.dividerThickness,
    required this.keyedSizes,
    required this.keyedMinimalSizes,
  });

  final double dividerThickness;
  final int childrenCount;
  final double fullSize;
  final double childrenSize;
  List<double> sizes;
  List<double> minimalSizes;
  final Map<Key, double> keyedSizes;
  final Map<Key, double> keyedMinimalSizes;

  void iterate({required CacheIterator child, required CacheIterator divider}) {
    double childStart = 0, childEnd = 0, dividerStart = 0, dividerEnd = 0;
    for (int childIndex = 0; childIndex < childrenCount; childIndex++) {
      final double childSize = sizes[childIndex];
      childEnd = fullSize - childSize - childStart;
      child(childIndex, childStart, childEnd);
      if (childIndex < childrenCount - 1) {
        dividerStart = childStart + childSize;
        dividerEnd = childEnd - dividerThickness;
        divider(childIndex, dividerStart, dividerEnd);
        childStart = dividerStart + dividerThickness;
      }
    }
  }

  List<WidgetDescriptor> build(List<Widget> children) {
    final result = <WidgetDescriptor>[];

    double childStart = 0, childEnd = 0, dividerStart = 0, dividerEnd = 0;
    int positionIndex = 0;
    int childIndex = 0;
    for (final child in children) {
      final double childSize = keyedSizes[child.key] != null
          ? keyedSizes[child.key]!
          : sizes[positionIndex++];
      childEnd = fullSize - childSize - childStart;
      result.add(ContentWidgetDescriptor(
          widget: child, childStart: childStart, childEnd: childEnd));
      if (childIndex < children.length - 1) {
        dividerStart = childStart + childSize;
        dividerEnd = childEnd - dividerThickness;
        result.add(DividerWidgetDescriptor(
            widget: child,
            dividerStart: dividerStart,
            dividerEnd: dividerEnd,
            index: childIndex));
        childStart = dividerStart + dividerThickness;
      }
      childIndex++;
    }

    return result;
  }
}

typedef CacheIterator = void Function(int index, double start, double end);
