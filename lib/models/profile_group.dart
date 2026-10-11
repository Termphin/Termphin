import 'dart:convert';

class ProfileGroup {
  const ProfileGroup({required this.name, this.colorHex});

  final String name;

  /// Null means "no colour picked" -> neutral dot.
  final String? colorHex;

  ProfileGroup copyWith({
    String? name,
    String? colorHex,
    bool clearColor = false,
  }) {
    return ProfileGroup(
      name: name ?? this.name,
      colorHex: clearColor ? null : (colorHex ?? this.colorHex),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'colorHex': colorHex};

  factory ProfileGroup.fromJson(Map<String, dynamic> json) {
    return ProfileGroup(
      name: json['name'] as String,
      colorHex: json['colorHex'] as String?,
    );
  }

  String encode() => jsonEncode(toJson());

  static ProfileGroup decode(String raw) {
    return ProfileGroup.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileGroup &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          colorHex == other.colorHex;

  @override
  int get hashCode => Object.hash(name, colorHex);

  @override
  String toString() => 'ProfileGroup(name: $name, colorHex: $colorHex)';
}
