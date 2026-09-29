import 'package:flutter/material.dart';

/// Responsive design constants for different screen sizes
/// Supports all common desktop resolutions from 1280x600 to 1920x1080
class ResponsiveSize {
  ResponsiveSize(this.context);
  final BuildContext context;

  /// Screen dimensions
  late final width = MediaQuery.of(context).size.width;
  late final height = MediaQuery.of(context).size.height;

  /// Device type detection
  bool get isMobile => width < 900;
  bool get isTablet => width >= 900 && width < 1366;
  bool get isDesktop => width >= 1366;
  bool get isLargeDesktop => width >= 1920;

  /// Responsive font sizes
  double get heading1 {
    if (isLargeDesktop) return 36;
    if (isDesktop) return 28;
    if (isTablet) return 24;
    return 20;
  }

  double get heading2 {
    if (isLargeDesktop) return 28;
    if (isDesktop) return 24;
    if (isTablet) return 20;
    return 16;
  }

  double get heading3 {
    if (isLargeDesktop) return 22;
    if (isDesktop) return 18;
    if (isTablet) return 16;
    return 14;
  }

  double get bodyLarge {
    if (isLargeDesktop) return 18;
    if (isDesktop) return 16;
    if (isTablet) return 14;
    return 12;
  }

  double get bodyMedium {
    if (isLargeDesktop) return 16;
    if (isDesktop) return 14;
    if (isTablet) return 13;
    return 11;
  }

  double get bodySmall {
    if (isLargeDesktop) return 14;
    if (isDesktop) return 12;
    if (isTablet) return 11;
    return 10;
  }

  double get bodyTiny {
    if (isLargeDesktop) return 12;
    if (isDesktop) return 10;
    if (isTablet) return 9;
    return 8;
  }

  /// Responsive spacing
  double get paddingXSmall => isMobile ? 4 : 6;
  double get paddingSmall => isMobile ? 8 : 12;
  double get paddingMedium => isMobile ? 12 : 16;
  double get paddingLarge => isMobile ? 16 : 24;
  double get paddingXLarge => isMobile ? 24 : 32;

  /// Responsive grid columns
  int get productGridColumns {
    if (isLargeDesktop) return 6;
    if (isDesktop) return 5;
    if (isTablet) return 4;
    if (isMobile) return 2;
    return 3;
  }

  int get categoryGridColumns {
    if (isLargeDesktop) return 8;
    if (isDesktop) return 6;
    if (isTablet) return 5;
    if (isMobile) return 3;
    return 4;
  }

  /// Icon sizes
  double get iconSmall {
    if (isLargeDesktop) return 24;
    if (isDesktop) return 20;
    if (isTablet) return 18;
    return 16;
  }

  double get iconMedium {
    if (isLargeDesktop) return 32;
    if (isDesktop) return 28;
    if (isTablet) return 24;
    return 20;
  }

  double get iconLarge {
    if (isLargeDesktop) return 48;
    if (isDesktop) return 40;
    if (isTablet) return 36;
    return 28;
  }

  /// Button heights
  double get buttonHeightSmall {
    if (isLargeDesktop) return 44;
    if (isDesktop) return 40;
    if (isTablet) return 36;
    return 32;
  }

  double get buttonHeightMedium {
    if (isLargeDesktop) return 50;
    if (isDesktop) return 44;
    if (isTablet) return 40;
    return 36;
  }

  /// Flex ratios for responsive layouts
  int get productListFlex {
    if (isTablet) return 3;
    return 3;
  }

  int get cartFlex {
    if (isTablet) return 2;
    return 2;
  }

  /// Border radius
  double get radiusSmall => 8;
  double get radiusMedium => 12;
  double get radiusLarge => 16;

  /// Search box constraints
  double get searchBoxHeight {
    if (isLargeDesktop) return 50;
    if (isDesktop) return 44;
    if (isTablet) return 40;
    return 36;
  }
}

/// Extension for easy access to responsive sizes
extension ResponsiveBuildContext on BuildContext {
  ResponsiveSize get responsive => ResponsiveSize(this);
}
