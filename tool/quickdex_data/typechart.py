import logging

from .csvdb import CsvDb, SchemaError

log = logging.getLogger("quickdex.typechart")

TYPE_ORDER = [
    "normal", "fire", "water", "electric", "grass", "ice", "fighting", "poison", "ground",
    "flying", "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy",
]


def build_chart(db: CsvDb) -> dict[str, dict[str, float]]:
    ident = {t["id"]: t["identifier"] for t in db.rows("types", ("id", "identifier"))
             if t["identifier"] in TYPE_ORDER}
    if len(ident) != 18:
        raise SchemaError(f"expected 18 battle types, found {sorted(ident.values())}")
    chart: dict[str, dict[str, float]] = {t: {} for t in TYPE_ORDER}
    for r in db.rows("type_efficacy", ("damage_type_id", "target_type_id", "damage_factor")):
        a, d = ident.get(r["damage_type_id"]), ident.get(r["target_type_id"])
        if a is None or d is None:
            log.debug("typechart.build.skip_non_battle_type %s->%s",
                      r["damage_type_id"], r["target_type_id"])
            continue
        chart[a][d] = int(r["damage_factor"]) / 100
    for a, row in chart.items():
        if set(row) != set(TYPE_ORDER):
            raise SchemaError(f"type_efficacy incomplete for attacker {a}")
    return {a: {d: chart[a][d] for d in TYPE_ORDER} for a in TYPE_ORDER}
