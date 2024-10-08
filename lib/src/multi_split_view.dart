import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:multi_split_view/src/area.dart';
import 'package:multi_split_view/src/controller.dart';
import 'package:multi_split_view/src/divider_tap_typedefs.dart';
import 'package:multi_split_view/src/divider_widget.dart';
import 'package:multi_split_view/src/internal/initial_drag.dart';
import 'package:multi_split_view/src/internal/sizes_cache.dart';
import 'package:multi_split_view/src/theme_data.dart';
import 'package:multi_split_view/src/theme_widget.dart';
import 'package:multi_split_view/src/typedefs.dart';

import 'internal/area_geometry.dart';

/// A widget to provides horizontal or vertical multiple split view.
class MultiSplitView extends StatefulWidget {
  static const Axis defaultAxis = Axis.horizontal;

  /// Creates an [MultiSplitView].
  ///
  /// The default value for [axis] argument is [Axis.horizontal].
  /// The [children] argument is required.
  /// The sum of the [initialWeights] cannot exceed 1.
  /// The [initialWeights] parameter will be ignored if the [controller]
  /// has been provided.
  MultiSplitView(
      {Key? key,
      this.axis = MultiSplitView.defaultAxis,
      required this.children,
      this.controller,
      this.dividerBuilder,
      this.onWeightChange,
      this.onDividerTap,
      this.onDividerDoubleTap,
      this.resizable = true,
      this.antiAliasingWorkaround = true,
      this.debugRendering = false,
      List<Area>? initialAreas})
      : this.initialAreas =
            initialAreas != null ? List.from(initialAreas) : null,
        super(key: key);

  final Axis axis;
  final List<Widget> children;
  final MultiSplitViewController? controller;
  final List<Area>? initialAreas;

  /// Signature for when a divider tap has occurred.
  final DividerTapCallback? onDividerTap;

  /// Signature for when a divider double tap has occurred.
  final DividerTapCallback? onDividerDoubleTap;

  /// Defines a builder of dividers. Overrides the default divider
  /// created by the theme.
  final DividerBuilder? dividerBuilder;

  /// Indicates whether it is resizable. The default value is [TRUE].
  final bool resizable;

  /// Function to listen children weight change.
  /// The listener will run on the parent's resize or
  /// on the dragging end of the divisor.
  final OnWeightChange? onWeightChange;

  /// Enables a workaround for https://github.com/flutter/flutter/issues/14288
  final bool antiAliasingWorkaround;

  /// Renders debug information over the dividers and areas.
  final bool debugRendering;

  @override
  State createState() => _MultiSplitViewState();
}

/// State for [MultiSplitView]
class _MultiSplitViewState extends State<MultiSplitView> {
  late MultiSplitViewController _controller;
  InitialDrag? _initialDrag;

  int? _draggingDividerIndex;
  int? _hoverDividerIndex;
  SizesCache? _sizesCache;
  int? _weightsHashCode;

  Object? _lastAreasUpdateHash;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller != null
        ? widget.controller!
        : MultiSplitViewController(areas: widget.initialAreas);
    _stateHashCodeValidation();
    _controller.stateHashCode = hashCode;
    _controller.addListener(_rebuild);
  }

  @override
  void dispose() {
    _controller.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    setState(() {
      _sizesCache = null;
    });
  }

  @override
  void deactivate() {
    _controller.stateHashCode = null;
    super.deactivate();
  }

  @override
  void didUpdateWidget(MultiSplitView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.controller != _controller) {
      List<Area> areas = _controller.areas;
      _controller.stateHashCode = null;
      _controller.removeListener(_rebuild);

      _controller = widget.controller != null
          ? widget.controller!
          : MultiSplitViewController(areas: areas);
      _stateHashCodeValidation();
      _controller.stateHashCode = hashCode;
      _controller.addListener(_rebuild);
    }
  }

  /// Checks a controller's [_stateHashCode] to identify if it is
  /// not being shared by another instance of [MultiSplitView].
  void _stateHashCodeValidation() {
    if (_controller.stateHashCode != null &&
        _controller.stateHashCode != hashCode) {
      throw StateError(
          'It is not allowed to share MultiSplitViewController between MultiSplitView instances.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_lastAreasUpdateHash != _controller.areasUpdateHash) {
      _draggingDividerIndex = null;
      _lastAreasUpdateHash = _controller.areasUpdateHash;
    }
    if (widget.children.length > 0) {
      MultiSplitViewThemeData themeData = MultiSplitViewTheme.of(context);

      return LayoutBuilder(builder: (context, constraints) {
        final double fullSize = widget.axis == Axis.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;

        _controller.fixWeights(
            children: widget.children,
            fullSize: fullSize,
            dividerThickness: themeData.dividerThickness);
        if (_sizesCache == null ||
            _sizesCache!.childrenCount != widget.children.length ||
            _sizesCache!.fullSize != fullSize) {
          _sizesCache = SizesCache(
              areas: _controller.areas,
              fullSize: fullSize,
              dividerThickness: themeData.dividerThickness);
        }

        List<Widget> children = [];

        final descriptors = _sizesCache!.build(widget.children);
        for (final descriptor in descriptors) {
          if (descriptor is ContentWidgetDescriptor) {
            children.add(_buildPositioned(
                start: descriptor.childStart,
                end: descriptor.childEnd,
                child: descriptor.widget));
            if (widget.debugRendering) {
              children.add(_buildDebugInfo(
                start: descriptor.childStart,
                area: descriptor.area,
              ));
            }
          } else if (descriptor is DividerWidgetDescriptor) {
            bool highlighted = (_draggingDividerIndex == descriptor.index ||
                (_draggingDividerIndex == null &&
                    _hoverDividerIndex == descriptor.index));
            Widget dividerWidget = widget.dividerBuilder != null
                ? widget.dividerBuilder!(
                    widget.axis == Axis.horizontal
                        ? Axis.vertical
                        : Axis.horizontal,
                    descriptor.index,
                    widget.resizable,
                    _draggingDividerIndex == descriptor.index,
                    highlighted,
                    themeData)
                : DividerWidget(
                    axis: widget.axis == Axis.horizontal
                        ? Axis.vertical
                        : Axis.horizontal,
                    index: descriptor.index,
                    themeData: themeData,
                    highlighted: highlighted,
                    resizable: widget.resizable,
                    dragging: _draggingDividerIndex == descriptor.index);
            if (widget.resizable) {
              dividerWidget = GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => _onDividerTap(descriptor.index),
                  onDoubleTap: () => _onDividerDoubleTap(descriptor.index),
                  onPanDown: (detail) {
                    setState(() {
                      _draggingDividerIndex = descriptor.index;
                    });
                    final pos = _position(context, detail.globalPosition);
                    _setInitialDrag(descriptor.index,
                        widget.axis == Axis.horizontal ? pos.dx : pos.dy);
                  },
                  onPanCancel: () => _onDragCancel(),
                  onPanEnd: (detail) => _onDragEnd(),
                  onPanUpdate: (detail) {
                    if (_draggingDividerIndex == null) {
                      return;
                    }
                    final pos = _position(context, detail.globalPosition);
                    double diff =
                        (widget.axis == Axis.horizontal ? pos.dx : pos.dy) -
                            _initialDrag!.initialDragPos;

                    _updateWeights(
                        dividerIndex: descriptor.index, diffPos: diff);
                  },
                  child: dividerWidget);
              dividerWidget = _mouseRegion(
                  index: descriptor.index,
                  axis: widget.axis == Axis.horizontal
                      ? Axis.vertical
                      : Axis.horizontal,
                  dividerWidget: dividerWidget,
                  themeData: themeData);
            }
            children.add(_buildPositioned(
                start: descriptor.dividerStart,
                end: descriptor.dividerEnd,
                child: dividerWidget));
          }
        }

        if (widget.onWeightChange != null) {
          int newWeightsHashCode = _controller.weightsHashCode;
          if (_weightsHashCode != null &&
              _weightsHashCode != newWeightsHashCode) {
            Future.microtask(widget.onWeightChange!);
          }
          _weightsHashCode = newWeightsHashCode;
        }

        return Stack(children: children);
      });
    }
    return Container();
  }

  /// Updates the hover divider index.
  void _updatesHoverDividerIndex(
      {int? index, required MultiSplitViewThemeData themeData}) {
    if (_hoverDividerIndex != index &&
        (themeData.dividerPainter != null || widget.dividerBuilder != null)) {
      setState(() {
        _hoverDividerIndex = index;
      });
    }
  }

  void _onDividerTap(int index) {
    if (widget.onDividerTap != null) {
      widget.onDividerTap!(index);
    }
  }

  void _onDividerDoubleTap(int index) {
    if (widget.onDividerDoubleTap != null) {
      widget.onDividerDoubleTap!(index);
    }
  }

  void _onDragCancel() {
    if (_draggingDividerIndex == null) {
      return;
    }
    setState(() {
      _draggingDividerIndex = null;
    });
  }

  void _onDragEnd() {
    if (_draggingDividerIndex == null) {
      return;
    }

    double totalFlexArea = 0;
    for (int i = 0; i < _controller.areasLength; i++) {
      final area = _controller.getArea(i);
      if (area.flex) {
        totalFlexArea += _sizesCache!.getGeomtryByPositionIndex(i).size;
      }
    }
    for (int i = 0; i < _controller.areasLength; i++) {
      final area = _controller.getArea(i);
      final size = _sizesCache!.getGeomtryByPositionIndex(i).size;
      if (area.flex) {
        area.updateWeight(size / totalFlexArea);
      } else {
        area.updateSize(size);
      }
    }
    setState(() {
      _draggingDividerIndex = null;
    });
  }

  /// Wraps the divider widget with a [MouseRegion].
  Widget _mouseRegion(
      {required int index,
      required Axis axis,
      required Widget dividerWidget,
      required MultiSplitViewThemeData themeData}) {
    MouseCursor cursor = axis == Axis.horizontal
        ? SystemMouseCursors.resizeRow
        : SystemMouseCursors.resizeColumn;
    return MouseRegion(
        cursor: cursor,
        onEnter: (event) =>
            _updatesHoverDividerIndex(index: index, themeData: themeData),
        onExit: (event) => _updatesHoverDividerIndex(themeData: themeData),
        child: dividerWidget);
  }

  void _setInitialDrag(int dividerIndex, double initialDragPos) {
    final AreaGeometry child1Geometry =
        _sizesCache!.getPrevAreaGeometry(dividerIndex);
    final AreaGeometry child2Geometry =
        _sizesCache!.getNextAreaGeometry(dividerIndex);

    double posLimitStart = 0;
    double posLimitEnd = 0;
    double child1Start = 0;
    double child2End = 0;
    for (int i = 0; i <= dividerIndex; i++) {
      final prevAreaGeometry = _sizesCache!.getPrevAreaGeometry(i);
      final nextAreaGeometry = _sizesCache!.getNextAreaGeometry(i);
      if (i < dividerIndex) {
        child1Start += prevAreaGeometry.size;
        child1Start += _sizesCache!.dividerThickness;
        child2End += prevAreaGeometry.size;
        child2End += _sizesCache!.dividerThickness;
        posLimitStart += prevAreaGeometry.size;
        posLimitStart += _sizesCache!.dividerThickness;
        posLimitEnd += prevAreaGeometry.size;
        posLimitEnd += _sizesCache!.dividerThickness;
      } else if (i == dividerIndex) {
        posLimitStart += prevAreaGeometry.minSize ?? 0;
        posLimitEnd += prevAreaGeometry.size;
        posLimitEnd += _sizesCache!.dividerThickness;
        posLimitEnd += nextAreaGeometry.size;
        child2End += prevAreaGeometry.size;
        child2End += _sizesCache!.dividerThickness;
        child2End += nextAreaGeometry.size;
        posLimitEnd = math.max(
            posLimitStart, posLimitEnd - (nextAreaGeometry.minSize ?? 0));
      }
    }

    _initialDrag = InitialDrag(
        initialDragPos: initialDragPos,
        initialChild1Geometry: child1Geometry.clone(),
        initialChild2Geometry: child2Geometry.clone(),
        child1Start: child1Start,
        child2End: child2End,
        posLimitStart: posLimitStart,
        posLimitEnd: posLimitEnd);
    _initialDrag!.posBeforeMinimalChild1 = initialDragPos < posLimitStart;
    _initialDrag!.posAfterMinimalChild2 = initialDragPos > posLimitEnd;
  }

  /// Calculates the new weights and sets if they are different from the current one.
  void _updateWeights({required int dividerIndex, required double diffPos}) {
    if (diffPos == 0) {
      return;
    }

    if (_initialDrag!.sumMinimals >= _initialDrag!.sumSizes) {
      // minimals already smaller than available space. Ignoring...
      return;
    }

    if (diffPos.isNegative && _initialDrag!.posBeforeMinimalChild1 ||
        diffPos > 0 && _initialDrag!.posAfterMinimalChild2) {
      return;
    }

    if (_sizesCache != null) {
      setState(() {
        final res = _sizesCache!.dragDivider(
            dividerIndex,
            diffPos,
            _initialDrag!.initialChild1Geometry.size,
            _initialDrag!.initialChild2Geometry.size,
            _initialDrag!.posAfterMinimalChild2,
            _initialDrag!.posBeforeMinimalChild1);

        _initialDrag!.posAfterMinimalChild2 = res[0];
        _initialDrag!.posBeforeMinimalChild1 = res[1];
      });
    }
  }

  /// Builds an [Offset] for cursor position.
  Offset _position(BuildContext context, Offset globalPosition) {
    final RenderBox container = context.findRenderObject() as RenderBox;
    return container.globalToLocal(globalPosition);
  }

  Positioned _buildPositioned(
      {required double start,
      required double end,
      required Widget child,
      bool last = false}) {
    Positioned positioned = Positioned(
        key: child.key,
        top: widget.axis == Axis.horizontal ? 0 : _convert(start, false),
        bottom: widget.axis == Axis.horizontal ? 0 : _convert(end, last),
        left: widget.axis == Axis.horizontal ? _convert(start, false) : 0,
        right: widget.axis == Axis.horizontal ? _convert(end, last) : 0,
        child: ClipRect(child: child));
    return positioned;
  }

  Positioned _buildDebugInfo({
    required double start,
    required AdjacentArea area,
  }) {
    Positioned positioned = Positioned(
        key: UniqueKey(),
        width: 200,
        top: widget.axis == Axis.horizontal ? 0 : _convert(start, false),
        left: widget.axis == Axis.horizontal ? _convert(start, false) : 0,
        // red container with white text that says "debug"
        child: Container(
            color: Colors.red,
            child: Text(area.toString(),
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold))));
    return positioned;
  }

  /// This is a workaround for https://github.com/flutter/flutter/issues/14288
  /// The problem minimizes by avoiding the use of coordinates with
  /// decimal values.
  double _convert(double value, bool last) {
    if (widget.antiAliasingWorkaround && !last) {
      return value.roundToDouble();
    }
    return value;
  }
}
