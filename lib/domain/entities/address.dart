import 'package:equatable/equatable.dart';

/// A user address from the settings API.
class Address extends Equatable {
  const Address({
    required this.id,
    required this.label,
    required this.line1,
    this.line2,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.country,
    required this.type,
    required this.isDefault,
  });

  final String id;
  final String label;
  final String line1;
  final String? line2;
  final String city;
  final String state;
  final String postalCode;
  final String country;

  /// e.g. "shipping", "billing".
  final String type;
  final bool isDefault;

  factory Address.fromJson(Map<String, dynamic> json) => Address(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        line1: json['line1'] as String? ?? '',
        line2: json['line2'] as String?,
        city: json['city'] as String? ?? '',
        state: json['state'] as String? ?? '',
        postalCode: json['postal_code'] as String? ?? '',
        country: json['country'] as String? ?? '',
        type: json['type'] as String? ?? '',
        isDefault: json['is_default'] as bool? ?? false,
      );

  /// Single-line formatted address.
  String get formatted {
    final parts = [
      line1,
      if (line2 != null && line2!.isNotEmpty) line2,
      city,
      state,
      postalCode,
      country,
    ].where((e) => e != null && e.isNotEmpty);
    return parts.join(', ');
  }

  @override
  List<Object?> get props => [id, label, line1, line2, city, state, postalCode];
}
