import 'dart:math' show max;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:multi_split_view/src/area.dart';

import '../../multi_split_view.dart';
import 'area_geometry.dart';

abstract class WidgetDescriptor {}

class ContentWidgetDescriptor extends WidgetDescriptor {
  ContentWidgetDescriptor({
    required this.widget,
    required this.childStart,
    required this.childEnd,
    required this.area,
  });
  final Widget widget;
  final double childStart;
  final double childEnd;
  final AdjacentArea area;
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

abstract class AdjacentArea {}

class KeyedArea extends AdjacentArea {
  KeyedArea({required this.key});
  final Key key;
  @override
  String toString() => 'KeyedArea(key: $key)';
}

class PositionalArea extends AdjacentArea {
  PositionalArea({required this.index});
  final int index;
  String toString() => 'PositionalArea (index: $index)';
}

@internal
class Boundary {
  Boundary({required this.prevArea, required this.nextArea});
  final AdjacentArea prevArea;
  final AdjacentArea nextArea;
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
    List<AreaGeometry> geometries = [];
    Map<Key, AreaGeometry> keyedGeometries = {};

    // the amount of space that is not occupied by fixed-size children
    final double flexSize = childrenSize -
        areas
            .where((area) => !area.flex)
            .fold<double>(0, (acc, area) => acc + (area.size ?? 0));
    for (Area area in areas) {
      final geometry = AreaGeometry(
        size: area.flex ? area.weight! * flexSize : area.size!,
        minSize: area.minimalWeight != null
            ? area.minimalWeight! * childrenSize
            : area.minimalSize ?? 0,
        collapseSize: area.collapseSize,
      );

      if (area.key != null) {
        keyedGeometries[area.key!] = geometry;
      } else {
        geometries.add(geometry);
      }
    }
    return SizesCache._(
      childrenCount: areas.length,
      fullSize: fullSize,
      childrenSize: childrenSize,
      dividerThickness: dividerThickness,
      geometries: geometries,
      keyedGeometries: keyedGeometries,
    );
  }

  SizesCache._({
    required this.childrenCount,
    required this.fullSize,
    required this.childrenSize,
    required this.dividerThickness,
    required List<AreaGeometry> geometries,
    required Map<Key, AreaGeometry> keyedGeometries,
  })  : _geometries = geometries,
        _keyedGeometries = keyedGeometries;

  final double dividerThickness;
  final int childrenCount;
  final double fullSize;
  final double childrenSize;
  List<AreaGeometry> _geometries;
  Map<Key, AreaGeometry> _keyedGeometries;
  List<Boundary> boundaries = [];

  void iterate({required CacheIterator child, required CacheIterator divider}) {
    double childStart = 0, childEnd = 0, dividerStart = 0, dividerEnd = 0;
    for (int childIndex = 0; childIndex < childrenCount; childIndex++) {
      final double childSize = _geometries[childIndex].size;
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
    AdjacentArea? prevArea;
    final newBoundaries = <Boundary>[];
    for (final child in children) {
      final double childSize = _keyedGeometries[child.key] != null
          ? _keyedGeometries[child.key]!.size
          : _geometries[positionIndex].size;
      final thisArea = _keyedGeometries[child.key] != null
          ? KeyedArea(key: child.key!)
          : PositionalArea(index: positionIndex);
      if (prevArea != null) {
        newBoundaries.add(Boundary(prevArea: prevArea, nextArea: thisArea));
      }
      prevArea = thisArea;
      if (_keyedGeometries[child.key] == null) {
        positionIndex++;
      }
      childEnd = fullSize - childSize - childStart;
      result.add(ContentWidgetDescriptor(
          widget: child,
          childStart: childStart,
          childEnd: childEnd,
          area: thisArea));
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
    boundaries = newBoundaries;

    return result;
  }

  void _setSize(AdjacentArea area, double size) {
    if (area is KeyedArea) {
      _keyedGeometries[area.key]!.size = size;
    } else if (area is PositionalArea) {
      _geometries[area.index].size = size;
    }
  }

  AreaGeometry _getGeometry(AdjacentArea area) {
    if (area is KeyedArea) {
      return _keyedGeometries[area.key]!;
    } else if (area is PositionalArea) {
      return _geometries[area.index];
    }
    throw Exception('Unknown area type');
  }

  AreaGeometry getGeomtryByPositionIndex(int index) {
    if (index < 0 || index >= childrenCount) {
      throw Exception('Index out of range');
    }

    if (index == childrenCount - 1) {
      return getNextAreaGeometry(index - 1);
    }

    return getPrevAreaGeometry(index);
  }

  AreaGeometry getPrevAreaGeometry(int index) {
    return _getGeometry(boundaries[index].prevArea);
  }

  AreaGeometry getNextAreaGeometry(int index) {
    return _getGeometry(boundaries[index].nextArea);
  }

  void _updateSize(
      int dividerIndex, double newPrevAreaSize, double newNextAreaSize) {
    final boundary = boundaries[dividerIndex];
    _setSize(boundary.prevArea, newPrevAreaSize);
    _setSize(boundary.nextArea, newNextAreaSize);
  }

  List<bool> dragDivider(
      int dividerIndex,
      double delta,
      double initialPrevAreaSize,
      double initialNextAreaSize,
      bool posAfterNextChild,
      bool posBeforePrevChild) {
    if (delta == 0) {
      return [posAfterNextChild, posBeforePrevChild];
    }

    final boundary = boundaries[dividerIndex];

    double minimalPrevAreaSize = _getGeometry(boundary.prevArea).minSize ?? 0;
    double minimalNextAreaSize = _getGeometry(boundary.nextArea).minSize ?? 0;

    double collapsePrevAreaSize =
        _getGeometry(boundary.prevArea).collapseSize ?? 0;
    double collapseNextAreaSize =
        _getGeometry(boundary.nextArea).collapseSize ?? 0;

    double newPrevAreaSize;
    double newNextAreaSize;
    double sumSizes = initialNextAreaSize + initialPrevAreaSize;

    if (delta.isNegative) {
      final proposedPrevAreaSize = initialPrevAreaSize + delta;

      if (proposedPrevAreaSize < collapsePrevAreaSize) {
        newPrevAreaSize = 0;
      } else {
        newPrevAreaSize = max(minimalPrevAreaSize, proposedPrevAreaSize);
      }

      // divider moving on left/top from initial mouse position
      newNextAreaSize = sumSizes - newPrevAreaSize;

      // handle the case when the next area has been collapsed
      if (initialNextAreaSize == 0) {
        if (newNextAreaSize < collapseNextAreaSize) {
          newNextAreaSize = 0;
          newPrevAreaSize = sumSizes;
        } else if (newNextAreaSize < minimalNextAreaSize) {
          newNextAreaSize = minimalNextAreaSize;
          newPrevAreaSize = sumSizes - newNextAreaSize;
        }
      }

      if (posAfterNextChild) {
        if (newNextAreaSize > minimalNextAreaSize) {
          posAfterNextChild = false;
        }
      } else if (newNextAreaSize < minimalNextAreaSize) {
        double diff = minimalNextAreaSize - newNextAreaSize;
        newNextAreaSize += diff;
        newPrevAreaSize -= diff;
      }
    } else {
      final proposedNextAreaSize = initialNextAreaSize - delta;

      if (proposedNextAreaSize < collapseNextAreaSize) {
        newNextAreaSize = 0;
      } else {
        newNextAreaSize = max(minimalNextAreaSize, proposedNextAreaSize);
      }

      newPrevAreaSize = sumSizes - newNextAreaSize;

      // handle the case when the prev area has been collapsed
      if (initialPrevAreaSize == 0) {
        if (newPrevAreaSize < collapsePrevAreaSize) {
          newPrevAreaSize = 0;
          newNextAreaSize = sumSizes;
        } else if (newPrevAreaSize < minimalPrevAreaSize) {
          newPrevAreaSize = minimalPrevAreaSize;
          newNextAreaSize = sumSizes - newPrevAreaSize;
        }
      }

      if (posBeforePrevChild) {
        if (newPrevAreaSize > minimalPrevAreaSize) {
          posBeforePrevChild = false;
        }
      } else if (newPrevAreaSize < minimalPrevAreaSize) {
        double diff = minimalPrevAreaSize - newPrevAreaSize;
        newPrevAreaSize += diff;
        newNextAreaSize -= diff;
      }
    }
    _updateSize(dividerIndex, newPrevAreaSize, newNextAreaSize);

    return [posAfterNextChild, posBeforePrevChild];
  }
}

typedef CacheIterator = void Function(int index, double start, double end);
