class AreaGeometry {
  double size;
  final double? minSize;
  final double? maxSize;
  final double? collapseSize;

  AreaGeometry({
    required this.size,
    this.minSize,
    this.maxSize,
    this.collapseSize,
  });

  AreaGeometry clone() =>
      AreaGeometry(size: size, minSize: minSize, maxSize: maxSize);

  AreaGeometry operator +(AreaGeometry other) {
    return AreaGeometry(
      size: size + other.size,
      minSize: minSize != null && other.minSize != null
          ? minSize! + other.minSize!
          : null,
      maxSize: maxSize != null && other.maxSize != null
          ? maxSize! + other.maxSize!
          : null,
    );
  }
}
