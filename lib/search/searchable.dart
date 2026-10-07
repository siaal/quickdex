/// Anything the search screens can find: Pokémon entries and moves.
abstract interface class Searchable {
  /// Unique within its kind; also the frecency key.
  int get id;
  String get name;

  /// Matched by digit-only queries (the dex number); null if not numbered.
  int? get number;
}
