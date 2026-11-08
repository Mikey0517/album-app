class Paged<T> {
  final List<T> items;
  final String? nextCursor;

  const Paged({required this.items, required this.nextCursor});

  factory Paged.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) itemParser,
  ) {
    final raw = json['items'] as List<dynamic>? ?? const [];
    return Paged(
      items: raw
          .whereType<Map<String, dynamic>>()
          .map(itemParser)
          .toList(growable: false),
      nextCursor: json['next_cursor'] as String?,
    );
  }
}
