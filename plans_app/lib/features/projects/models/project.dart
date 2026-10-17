class Project {
  final String id;
  final String name;
  final int colorIndex;
  final DateTime updatedAt;

  Project({
    required this.id,
    required this.name,
    this.colorIndex = 0,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  Project copyWith({
    String? id,
    String? name,
    int? colorIndex,
    DateTime? updatedAt,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      colorIndex: colorIndex ?? this.colorIndex,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
