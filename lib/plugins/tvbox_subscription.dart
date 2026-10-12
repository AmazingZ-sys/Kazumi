/// A locally saved configuration and the last successfully installed rules.
/// Rule snapshots distinguish a user's edits/deletions from upstream updates.
class TvBoxSubscription {
  TvBoxSubscription({
    required this.id,
    required this.name,
    required this.input,
    required this.snapshot,
    required this.updatedAt,
    Map<String, String> ruleSnapshots = const {},
    List<String> excludedSiteKeys = const [],
  }) : ruleSnapshots = Map.unmodifiable(ruleSnapshots),
       excludedSiteKeys = List.unmodifiable(excludedSiteKeys);

  final String id;
  final String name;
  final String input;
  final String snapshot;
  final DateTime updatedAt;
  final Map<String, String> ruleSnapshots;
  final List<String> excludedSiteKeys;

  factory TvBoxSubscription.fromJson(Map<String, dynamic> json) =>
      TvBoxSubscription(
        id: json['id'] as String,
        name: json['name'] as String,
        input: json['input'] as String,
        snapshot: json['snapshot'] as String,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        ruleSnapshots: Map<String, String>.from(
          json['ruleSnapshots'] as Map? ?? {},
        ),
        excludedSiteKeys: List<String>.from(
          json['excludedSiteKeys'] as List? ?? [],
        ),
      );

  TvBoxSubscription copyWith({
    String? name,
    String? input,
    String? snapshot,
    DateTime? updatedAt,
    Map<String, String>? ruleSnapshots,
    List<String>? excludedSiteKeys,
  }) => TvBoxSubscription(
    id: id,
    name: name ?? this.name,
    input: input ?? this.input,
    snapshot: snapshot ?? this.snapshot,
    updatedAt: updatedAt ?? this.updatedAt,
    ruleSnapshots: ruleSnapshots ?? this.ruleSnapshots,
    excludedSiteKeys: excludedSiteKeys ?? this.excludedSiteKeys,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'input': input,
    'snapshot': snapshot,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'ruleSnapshots': ruleSnapshots,
    'excludedSiteKeys': excludedSiteKeys,
  };
}
