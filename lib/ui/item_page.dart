import 'package:flutter/material.dart';

import '../data/items.dart';
import '../frecency/frecency.dart';
import '../trace.dart';
import 'art.dart';
import 'game_scope.dart';

/// An item's sprite at [size]; a generic bag icon when it has none.
class ItemSprite extends StatelessWidget {
  const ItemSprite(this.item, {super.key, this.size = 32});
  final Item item;
  final double size;

  @override
  Widget build(BuildContext context) => item.sprite
      ? Image.asset(
          itemSpritePath(item.id),
          width: size,
          height: size,
          // Pixel art: keep it crisp when scaled up.
          filterQuality: FilterQuality.none,
          semanticLabel: item.name,
        )
      : Icon(Icons.backpack_outlined, size: size * 0.8);
}

/// "Shop: 3 badges" (Scrambled Scarlet's Delibird Presents unlock).
String shopLabel(int badges) =>
    'Shop: $badges ${badges == 1 ? 'badge' : 'badges'}';

/// List row for an item: sprite, name and category.
class ItemTile extends StatelessWidget {
  const ItemTile(this.item, {super.key, required this.onTap, this.onDetails});
  final Item item;
  final VoidCallback onTap;

  /// Long-press or right-click, e.g. to peek at the item's details.
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      leading: SizedBox(width: 48, child: Center(child: ItemSprite(item))),
      title: Text(item.name),
      subtitle: item.category == null ? null : Text(item.category!),
      trailing: item.badges == null
          ? null
          : Text(shopLabel(item.badges!), style: const TextStyle(fontSize: 14)),
      onTap: onTap,
      onLongPress: onDetails,
    );
    if (onDetails == null) return tile;
    return GestureDetector(onSecondaryTap: onDetails, child: tile);
  }
}

class ItemPage extends StatefulWidget {
  const ItemPage({super.key, required this.item, required this.frecency});
  final Item item;
  final FrecencyStore frecency;

  @override
  State<ItemPage> createState() => _ItemPageState();
}

class _ItemPageState extends State<ItemPage> {
  @override
  void initState() {
    super.initState();
    widget.frecency.visit(widget.item.id);
    trace('item.page.open', {'id': widget.item.id});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: ItemDetails(widget.item),
    ),
  );
}

/// Bottom sheet with an item's details, without crediting a visit.
Future<void> showItemDetails(BuildContext context, Item item) {
  trace('item.details.sheet', {'id': item.id});
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        key: const Key('item-details-sheet'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: ItemDetails(item),
      ),
    ),
  );
}

/// An item's sprite, name, shop unlock, category, the game's change and texts.
class ItemDetails extends StatelessWidget {
  const ItemDetails(this.item, {super.key});
  final Item item;

  @override
  Widget build(BuildContext context) {
    final i = item;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ItemSprite(i, key: const Key('item-sprite'), size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                i.name,
                key: const Key('item-name'),
                style: theme.textTheme.headlineSmall,
              ),
            ),
            if (i.badges case final b?)
              Text(
                shopLabel(b),
                key: const Key('item-shop'),
                style: theme.textTheme.titleMedium,
              ),
          ],
        ),
        if (i.category case final c?) ...[
          const SizedBox(height: 4),
          Text(
            c,
            key: const Key('item-category'),
            style: theme.textTheme.labelLarge,
          ),
        ],
        if (i.note case final note?) ...[
          const SizedBox(height: 16),
          Container(
            key: const Key('item-note'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'In ${GameScope.of(context).name}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                SelectableText(note),
              ],
            ),
          ),
        ],
        if (i.text case final text?) ...[
          const SizedBox(height: 16),
          Text(
            text,
            key: const Key('item-text'),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        if (i.effect case final effect?) ...[
          const SizedBox(height: 16),
          Text(effect, key: const Key('item-effect')),
        ],
      ],
    );
  }
}
