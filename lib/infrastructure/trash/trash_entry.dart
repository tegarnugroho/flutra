import 'package:equatable/equatable.dart';

/// A soft-deleted folder kept in a trash area for a limited time so the user
/// can restore it.
class TrashEntry extends Equatable {
  const TrashEntry({
    required this.id,
    required this.label,
    required this.originalPath,
    required this.trashPath,
    required this.deletedAt,
  });

  final String id;

  /// Human label (e.g. "Flutter SDK").
  final String label;

  /// Where it was before deletion (restore target).
  final String originalPath;

  /// Where it currently lives in the trash.
  final String trashPath;

  final DateTime deletedAt;

  factory TrashEntry.fromJson(Map<String, dynamic> json) => TrashEntry(
        id: json['id'] as String,
        label: json['label'] as String? ?? '',
        originalPath: json['originalPath'] as String,
        trashPath: json['trashPath'] as String,
        deletedAt: DateTime.parse(json['deletedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'originalPath': originalPath,
        'trashPath': trashPath,
        'deletedAt': deletedAt.toIso8601String(),
      };

  @override
  List<Object?> get props => [id, originalPath, trashPath, deletedAt];
}
