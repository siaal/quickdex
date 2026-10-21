"""The games QuickDex can show. Each gets its own data bundle (see build_data.py)."""
from dataclasses import dataclass

from .csvdb import CsvDb


@dataclass(frozen=True)
class Game:
    key: str  # bundle directory and prefs suffix
    name: str  # shown in the app, e.g. "Not in Emerald"
    generation: int
    version_group: str  # version_groups.csv id
    # In-game regional dexes (pokedexes.csv id, label), in display preference.
    dexes: tuple[tuple[str, str], ...]
    # Learnset fallbacks for Pokémon the game itself lacks (version group id -> label),
    # most preferred first.
    fallback_games: tuple[tuple[str, str], ...] = ()
    friendship: int = 220  # Gen 8 lowered it to 160
    # Moves seen in the game without any Pokémon learning them there.
    extra_moves: frozenset[str] = frozenset()
    # A romhack read from the Doozdex sheet (scrambled.py) rather than PokéAPI.
    doozdex: bool = False
    # The game's bag (items.py): PKHeX (file, array) lists of in-game item indices,
    # arrays to subtract, and PKHeX's English item names by index.
    item_lists: tuple[tuple[str, str], ...] = ()
    item_exclusions: tuple[tuple[str, str], ...] = ()
    item_names: str = ""


# Every pocket except TMs (move pages cover those); Unreleased are in the bag data
# but can't be obtained.
SV_ITEMS = {
    "item_lists": tuple(("ItemStorage9SV.cs", a) for a in (
        "Medicine", "Balls", "Battle", "Berry", "Other", "Treasure", "Picnic", "Event",
        "Material")),
    "item_exclusions": (("ItemStorage9SV.cs", "Unreleased"),),
    "item_names": "text_Items_en.txt",
}

SCARLET = Game(
    key="scarlet", name="Scarlet", generation=9, version_group="25",
    dexes=(("31", "Paldea"), ("32", "Kitakami"), ("33", "Blueberry")),
    # Sword/Shield's learnsets are what Scarlet's derive from, BDSP keeps Gen 4 ones.
    # Legends games and Champions are left out: their move systems differ.
    fallback_games=(("20", "Sword/Shield"), ("23", "Brilliant Diamond/Shining Pearl"),
                    ("18", "Ultra Sun/Ultra Moon"), ("17", "Sun/Moon"),
                    ("19", "Let's Go")),
    friendship=160,
    extra_moves=frozenset({"struggle", "behemoth-blade", "behemoth-bash",
                           "blazing-torque", "wicked-torque", "noxious-torque",
                           "combat-torque", "magical-torque"}),
    **SV_ITEMS,
)

EMERALD = Game(
    key="emerald", name="Emerald", generation=3, version_group="6",
    dexes=(("4", "Hoenn"),),
    fallback_games=(("7", "FireRed/LeafGreen"), ("5", "Ruby/Sapphire")),
    extra_moves=frozenset({"struggle"}),
    # PKHeX's Gen 3 "Unreleased" (Safari Ball, Berry Juice) only can't sit in the
    # bag; both are in Emerald, so nothing is subtracted.
    item_lists=(*(("ItemStorage3RS.cs", a) for a in ("General", "Berry", "Balls")),
                ("ItemStorage3E.cs", "Key")),
    item_names="text_ItemsG3_en.txt",
)

# The Scrambled Scarlet romhack: Scarlet with the Doozdex's changes (scrambled.py).
SCRAMBLED = Game(
    key="scrambled", name="Scrambled Scarlet", generation=9, version_group="25",
    dexes=SCARLET.dexes, friendship=160, doozdex=True, **SV_ITEMS,
)

GAMES = (SCARLET, EMERALD, SCRAMBLED)


class Eras:
    """Version-group and generation lookups for "as of this game" questions."""

    def __init__(self, db: CsvDb, game: Game):
        rows = db.rows("version_groups", ("id", "generation_id", "order"))
        self.order = {r["id"]: int(r["order"]) for r in rows}
        self.vg_generation = {r["id"]: int(r["generation_id"]) for r in rows}
        self.game = game
        self.game_order = self.order[game.version_group]
        assert self.vg_generation[game.version_group] == game.generation, game

    def after_game(self, vg: str) -> bool:
        """True if version group `vg` came out after the game (its changes don't apply)."""
        return self.order[vg] > self.game_order

    def past_applies(self, generation: int) -> bool:
        """`*_past` rows hold until and including their generation."""
        return generation >= self.game.generation
