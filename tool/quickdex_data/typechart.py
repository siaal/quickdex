import logging

from .csvdb import CsvDb, SchemaError
from .games import Eras, Game

log = logging.getLogger("quickdex.typechart")

# Alphabetical (user choice): the conventional chart order can't be scanned without
# memorising it. Drives the Focus tiles, both Grid axes and the defence table.
TYPE_ORDER = [
    "bug", "dark", "dragon", "electric", "fairy", "fighting", "fire", "flying", "ghost",
    "grass", "ground", "ice", "normal", "poison", "psychic", "rock", "steel", "water",
]


def build_chart(db: CsvDb, game: Game) -> tuple[list[str], dict[str, dict[str, float]]]:
    """The game's battle types (TYPE_ORDER, minus later ones) and its chart."""
    eras = Eras(db, game)
    rows = db.rows("types", ("id", "identifier", "generation_id"))
    battle = {t["id"]: t for t in rows if t["identifier"] in TYPE_ORDER}
    if len(battle) != 18:
        raise SchemaError(f"expected 18 battle types, found {sorted(battle)}")
    ident = {i: t["identifier"] for i, t in battle.items()
             if int(t["generation_id"]) <= game.generation}
    order = [t for t in TYPE_ORDER if t in ident.values()]
    chart: dict[str, dict[str, float]] = {t: {} for t in order}
    for r in db.rows("type_efficacy", ("damage_type_id", "target_type_id", "damage_factor")):
        a, d = ident.get(r["damage_type_id"]), ident.get(r["target_type_id"])
        if a is None or d is None:
            continue
        chart[a][d] = int(r["damage_factor"]) / 100
    # The nearest past row at or after the game's generation wins.
    past: dict[tuple[str, str], tuple[int, float]] = {}
    for r in db.rows("type_efficacy_past", ("damage_type_id", "target_type_id",
                                            "damage_factor", "generation_id")):
        a, d = ident.get(r["damage_type_id"]), ident.get(r["target_type_id"])
        gen = int(r["generation_id"])
        if a is None or d is None or not eras.past_applies(gen):
            continue
        if (a, d) not in past or gen < past[(a, d)][0]:
            past[(a, d)] = (gen, int(r["damage_factor"]) / 100)
    for (a, d), (gen, factor) in past.items():
        log.debug("typechart.build.past %s %s->%s %s (gen %d)", game.key, a, d, factor, gen)
        chart[a][d] = factor
    for a, row in chart.items():
        if set(row) != set(order):
            raise SchemaError(f"type_efficacy incomplete for attacker {a}")
    return order, {a: {d: chart[a][d] for d in order} for a in order}
