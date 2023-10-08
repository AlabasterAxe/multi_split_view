import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:multi_split_view/src/area.dart';

/// Controller for [MultiSplitView].
///
/// It is not allowed to share this controller between [MultiSplitView]
/// instances.
class MultiSplitViewController extends ChangeNotifier {
  static const double _one_highPrecision = 1.0000000000001;

  /// Creates an [MultiSplitViewController].
  ///
  /// The sum of the [weights] cannot exceed 1.
  factory MultiSplitViewController({List<Area>? areas}) {
    final initialAreas = <Area>[];
    final keyedAreas = <Key, Area>{};
    if (areas != null) {
      for (final area in areas) {
        initialAreas.add(area);
        if (area.key != null) {
          keyedAreas[area.key!] = area;
        }
      }
    }
    return MultiSplitViewController._(initialAreas, keyedAreas);
  }

  MultiSplitViewController._(this._areas, this._keyedAreas);

  List<Area> _areas;
  final Map<Key, Area> _keyedAreas;

  UnmodifiableListView<Area> get areas => UnmodifiableListView(_areas);

  Object _areasUpdateHash = Object();

  /// Hash to identify [areas] setter usage.
  @internal
  Object get areasUpdateHash => _areasUpdateHash;

  set areas(List<Area> areas) {
    _areas = List.from(areas);
    _areasUpdateHash = Object();
    notifyListeners();
  }

  int get areasLength => _areas.length;

  /// Gets the area of a given widget index.
  Area getArea(int index) {
    return _areas[index];
  }

  /// Sum of all weights.
  double _weightSum() {
    double sum = 0;
    _areas.forEach((area) {
      sum += area.weight ?? 0;
    });
    return sum;
  }

  /// Adjusts the weights according to the number of children.
  /// New children will receive a percentage of current children.
  /// Excluded children will distribute their weights to the existing ones.
  @internal
  void fixWeights(
      {required List<Widget> children,
      required double fullSize,
      required double dividerThickness}) {
    final numChildren = children.length;

    final double totalDividerSize = (numChildren - 1) * dividerThickness;
    final double availableSize = fullSize - totalDividerSize;

    final newAreas = <Area>[];
    int existingAreaIndex = 0;

    // if a new flexible area is added:
    //  all non flexible area sizes are preserved, the newly added area is given 1/n of the available space where n is the number of flexible children
    //  the remaining flexible spaces are distributed according to their previous weight.
    // if a new flexible area is removed:
    //  all non flexible area sizes are preserved, the remaining flexible spaces are distributed according to their previous weight.
    for (final child in children) {
      final key = child.key;
      final keyedArea = _keyedAreas[key];

      if (keyedArea != null) {
        newAreas.add(keyedArea);
        continue;
      }

      Area? areaToAdd;
      while (existingAreaIndex < _areas.length && areaToAdd == null) {
        final area = _areas[existingAreaIndex++];
        if (area.key != null) {
          areaToAdd = area;
          break;
        }
      }

      // we've run out of positional areas, so we'll just add a new one
      if (areaToAdd == null) {
        // no more areas
        areaToAdd = Area();
      }

      newAreas.add(areaToAdd);
    }
    _areas = newAreas;

    final flexAreas = _areas.where((area) => area.flex).toList();

    int unsizedAreaCount =
        _areas.where((area) => area.weight == null && area.size == null).length;
    double weightSum = _weightSum();

    // fill null weights
    if (unsizedAreaCount > 0) {
      print('have unsized areas $unsizedAreaCount');
      double remainder =
          math.max(MultiSplitViewController._one_highPrecision - weightSum, 0) /
              unsizedAreaCount;

      // If there isn't already remaining space for the null areas
      // shrink the non null flexible areas to make space.
      if (remainder == 0) {
        flexAreas
            .where((area) => area.weight != null && area.flex)
            .forEach((area) {
          final double r = area.weight! / flexAreas.length;
          area.updateWeight(area.weight! - r);
          remainder += r / unsizedAreaCount;
        });
      }

      // updating the null weights
      _areas
          .where((area) => area.weight == null || area.size == null)
          .forEach((area) {
        if (area.flex) {
          area.updateWeight(remainder);
        } else {
          area.updateSize(remainder * availableSize);
        }
      });
      weightSum = _weightSum();
    }

    // _applyMinimal(availableSize: availableSize);
  }

  /// Fills equally the missing weights
  void _fillWeightsEqually(int childrenCount, double weightSum) {
    if (weightSum < 1) {
      double availableWeight = 1 - weightSum;
      if (availableWeight > 0) {
        double w = availableWeight / childrenCount;
        for (int i = 0; i < _areas.length; i++) {
          final Area area = _areas[i];
          area.updateWeight(area.weight! + w);
        }
      }
    }
  }

  /// Fix the weights to the minimal size/weight.
  void _applyMinimal({required double availableSize}) {
    double totalNonMinimalWeight = 0;
    double totalMinimalWeight = 0;
    int minimalCount = 0;
    for (int i = 0; i < _areas.length; i++) {
      Area area = _areas[i];
      if (area.minimalSize != null) {
        double minimalWeight = area.minimalSize! / availableSize;
        totalMinimalWeight += minimalWeight;
        minimalCount++;
      } else if (area.minimalWeight != null) {
        totalMinimalWeight += area.minimalWeight!;
        minimalCount++;
      } else {
        totalNonMinimalWeight += area.weight!;
      }
    }
    if (totalMinimalWeight > 0) {
      double reducerMinimalWeight = 0;
      if (totalMinimalWeight > 1) {
        reducerMinimalWeight = ((totalMinimalWeight - 1) / minimalCount);
        totalMinimalWeight = 1;
      }
      double totalReducerNonMinimalWeight = 0;
      if (totalMinimalWeight + totalNonMinimalWeight > 1) {
        totalReducerNonMinimalWeight =
            (totalMinimalWeight + totalNonMinimalWeight - 1);
      }
      for (int i = 0; i < _areas.length; i++) {
        final Area area = _areas[i];
        if (area.minimalSize != null) {
          double minimalWeight = math.max(
              0, (area.minimalSize! / availableSize) - reducerMinimalWeight);
          if (area.weight! < minimalWeight) {
            area.updateWeight(minimalWeight);
          }
        } else if (area.minimalWeight != null) {
          double minimalWeight =
              math.max(0, area.minimalWeight! - reducerMinimalWeight);
          if (area.weight! < minimalWeight) {
            area.updateWeight(minimalWeight);
          }
        } else if (totalReducerNonMinimalWeight > 0) {
          double reducer = totalReducerNonMinimalWeight *
              area.weight! /
              totalNonMinimalWeight;
          double newWeight = math.max(0, area.weight! - reducer);
          area.updateWeight(newWeight);
        }
      }
    }
  }

  /// Stores the hashCode of the state to identify if a controller instance
  /// is being shared by multiple [MultiSplitView]. The application must not
  /// manipulate this attribute, it is for the internal use of the package.
  @internal
  int? stateHashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MultiSplitViewController &&
          runtimeType == other.runtimeType &&
          _areas == other._areas;

  @override
  int get hashCode => _areas.hashCode;

  int get weightsHashCode => Object.hashAll(_WeightIterable(areas));
}

class _WeightIterable extends Iterable<double?> {
  _WeightIterable(this.areas);

  final List<Area> areas;

  @override
  Iterator<double?> get iterator => _WeightIterator(areas);
}

class _WeightIterator extends Iterator<double?> {
  _WeightIterator(this.areas);

  final List<Area> areas;
  int _index = -1;

  @override
  double? get current => areas[_index].weight;

  @override
  bool moveNext() {
    _index++;
    return _index > -1 && _index < areas.length;
  }
}
