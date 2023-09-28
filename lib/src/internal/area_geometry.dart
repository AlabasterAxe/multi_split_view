class AreaGeometry {
  double size;
  final double? minSize;
  final double? maxSize;

  AreaGeometry({
    required this.size,
    this.minSize,
    this.maxSize,
  });

  AreaGeometry clone() =>
      AreaGeometry(size: size, minSize: minSize, maxSize: maxSize);

  @override
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
