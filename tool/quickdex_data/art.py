import logging
import shutil
import subprocess
from pathlib import Path

from .entries import Entry

log = logging.getLogger("quickdex.art")

SIZES = ((256, "full"), (128, "thumb"))


def convert_art(entries: list[Entry], src_dir: Path, out_dir: Path,
                art_overrides: dict[str, int]) -> list[str]:
    for _, sub in SIZES:
        (out_dir / sub).mkdir(parents=True, exist_ok=True)
    gaps: list[str] = []
    wanted = {f"{e.id}.webp" for e in entries}
    for e in entries:
        src_id = art_overrides.get(str(e.id), e.id)
        if src_id != e.id:
            log.debug("art.convert.override %s -> %s", e.id, src_id)
        src = src_dir / f"{src_id}.png"
        if not src.is_file():
            log.debug("art.convert.missing %s", e.id)
            gaps.append(f"artwork missing for {e.id} ({e.name}); "
                        f"add tool/overrides.json art[\"{e.id}\"]")
            continue
        for size, sub in SIZES:
            dst = out_dir / sub / f"{e.id}.webp"
            if dst.is_file() and dst.stat().st_mtime >= src.stat().st_mtime:
                continue
            subprocess.run(["cwebp", "-quiet", "-q", "80", "-alpha_q", "100",
                            "-resize", str(size), str(size), str(src), "-o", str(dst)],
                           check=True)
    for _, sub in SIZES:
        for stale in (out_dir / sub).glob("*.webp"):
            if stale.name not in wanted:
                log.debug("art.convert.remove_stale %s", stale)
                stale.unlink()
    return gaps


def copy_type_icons(type_idents: dict[str, str], src_dir: Path, out_dir: Path) -> list[str]:
    """Copy Scarlet/Violet type icons (`<type id>.png`) to `out_dir/<identifier>.png`."""
    out_dir.mkdir(parents=True, exist_ok=True)
    gaps = []
    for tid, ident in type_idents.items():
        src = src_dir / f"{tid}.png"
        if not src.is_file():
            log.debug("art.type_icon.missing %s %s", tid, ident)
            gaps.append(f"type icon {tid} ({ident}) missing from the sprites repo")
            continue
        shutil.copyfile(src, out_dir / f"{ident}.png")
    return gaps
