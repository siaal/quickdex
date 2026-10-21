import 'dart:convert';

import 'package:flutter/services.dart';

import '../search/searchable.dart';
import '../trace.dart';
import 'game.dart';

/// An item in the loaded game's bag (`assets/data/<game>/items.json`, built by
/// tool/quickdex_data/items.py).
class Item implements Searchable {
  const Item({
    required this.id,
    required this.key,
    required this.name,
    required this.category,
    required this.effect,
    required this.text,
    required this.sprite,
    this.badges,
    this.note,
  });

  factory Item.fromJson(Map<String, dynamic> j) => Item(
    id: j['id'] as int,
    key: j['key'] as String,
    name: j['name'] as String,
    category: j['cat'] as String?,
    effect: j['effect'] as String?,
    text: j['text'] as String?,
    sprite: j['sprite'] as bool,
    badges: j['badges'] as int?,
    note: j['note'] as String?,
  );

  /// PokéAPI's item id.
  @override
  final int id;

  /// PokéAPI identifier, e.g. `choice-band`.
  final String key;
  @override
  final String name;

  /// E.g. "Held items"; null when PokéAPI has none worth showing.
  final String? category;

  /// What it does (PokéAPI's prose, else Showdown's); may describe today's games.
  final String? effect;

  /// In-game text (the loaded game's when it has one).
  final String? text;

  /// Whether `assets/art/items/<id>.webp` exists.
  final bool sprite;

  /// Scrambled Scarlet: badges needed before Delibird Presents sells it.
  final int? badges;

  /// Scrambled Scarlet: how the hack changed it.
  final String? note;

  @override
  List<int> get numbers => const [];
}

class ItemDex {
  ItemDex(this.items, [this.game = GameInfo.scarlet])
    : byId = {for (final i in items) i.id: i};

  factory ItemDex.parse(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    return ItemDex([
      for (final i in j['items'] as List)
        Item.fromJson(i as Map<String, dynamic>),
    ], GameInfo.fromJson(j['game'] as Map<String, dynamic>));
  }

  final GameInfo game;

  /// Sorted by name.
  final List<Item> items;
  final Map<int, Item> byId;

  void assertInvariants() {
    assert(byId.length == items.length, 'duplicate item ids');
    assert(
      items.every(
        (i) => i.name.isNotEmpty && (i.effect != null || i.text != null),
      ),
      'item without a name or any text',
    );
  }
}

Future<ItemDex> loadItems(
  AssetBundle bundle, [
  GameInfo game = GameInfo.scarlet,
]) async {
  final sw = Stopwatch()..start();
  final items = ItemDex.parse(
    await bundle.loadString('${game.dataDir}/items.json'),
  );
  items.assertInvariants();
  assert(items.game == game, 'loaded ${items.game} for $game');
  trace('startup.items.done', {
    'game': game.key,
    'ms': sw.elapsedMilliseconds,
    'items': items.items.length,
  });
  return items;
}
