import 'package:equatable/equatable.dart';

/// A hardware device profile from `avdmanager list device`, used as the `-d`
/// argument when creating an AVD.
class DeviceDefinition extends Equatable {
  const DeviceDefinition({
    required this.id,
    required this.name,
    this.oem,
  });

  /// avdmanager device id (e.g. "pixel_6") or numeric index as a string.
  final String id;

  /// Display name, e.g. "Pixel 6".
  final String name;

  /// Manufacturer, e.g. "Google".
  final String? oem;

  /// Rough form-factor bucket inferred from the name, used for wizard grouping.
  DeviceCategory get category {
    final n = name.toLowerCase();
    if (n.contains('wear')) return DeviceCategory.wear;
    if (n.contains('tv')) return DeviceCategory.tv;
    if (n.contains('fold')) return DeviceCategory.foldable;
    if (n.contains('tablet') || n.contains('pad')) return DeviceCategory.tablet;
    if (n.contains('automotive') || n.contains('car')) {
      return DeviceCategory.automotive;
    }
    return DeviceCategory.phone;
  }

  @override
  List<Object?> get props => [id, name, oem];
}

enum DeviceCategory { phone, tablet, foldable, wear, tv, automotive }

extension DeviceCategoryLabel on DeviceCategory {
  String get label => switch (this) {
        DeviceCategory.phone => 'Phone',
        DeviceCategory.tablet => 'Tablet',
        DeviceCategory.foldable => 'Foldable',
        DeviceCategory.wear => 'Wear',
        DeviceCategory.tv => 'TV',
        DeviceCategory.automotive => 'Automotive',
      };
}
