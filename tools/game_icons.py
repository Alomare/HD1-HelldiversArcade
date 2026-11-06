"""Takes the game's own icons that some upgrades show (a stratagem's, a perk's) out of the installed game,
as white images for tools/build_art.py: tools/icons/<upgrade>.png.

Usage: python tools/game_icons.py [path to Helldivers/contents]

A stratagem icon is a light symbol on a coloured square: whatever is brighter than the square becomes
white. A perk icon is a wide strip of grey shapes, so only its main shape is kept (CROPS). Needs Pillow
and numpy.
"""
import io
import struct
import sys
import zlib
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tools" / "icons"
CONTENTS = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"C:\Program Files (x86)\Steam\steamapps\common\Helldivers\contents")

# upgrade id -> the game's image name, by kind.
STRATAGEMS = {
    "guard_dog": "stratagem_drone_defensive",
    "angel": "stratagem_drone_heal",
    "shield_generator_pack": "stratagem_shield_generator_pack",
    "suitable_replacement": "stratagem_turret",
}
# upgrade id -> (image name, (left, top, right, bottom) of its main shape in the image's pixels[, whole]).
# Only the shape joined to the box's middle is kept, unless `whole` (a shape in pieces, as stars are).
# Stratagem Priority and Precision Call-in are stars joined to wing bars in the game's images, so they
# are drawn as SVGs in tools/icons instead.
CROPS = {
    "autoinjector": ("perk_adrenaline_01", (100, 0, 300, 92)),
    "all_terrain_boots": ("perk_all_terrain_boots", (50, 0, 132, 92)),
    "incendiary_grenades": ("perk_grenade_incendiary_01", (230, 0, 325, 92)),
    "smoke_grenades": ("perk_grenade_smoke_01", (225, 0, 345, 92), True),
    "stun_grenades": ("perk_grenade_stun_01", (228, 0, 356, 92), True),
    "heavy_armor": ("perk_heavy_armor_01", (125, 0, 230, 92)),
    "pyro": ("perk_pistol_flamer", (15, 0, 160, 92)),
    "singe": ("perk_pistol_plasma", (5, 0, 140, 92)),
    "gunslinger": ("perk_pistol_revolver", (10, 0, 195, 92)),
    "strong_arm": ("perk_strong_arm_01", (95, 0, 230, 92)),
    "displacement_field": ("perk_teleport_shield_01", (195, 0, 336, 92), True),
}

SIZE = 192
DIFFUSE_MAP = 0x3aa8b87e


def murmur64(data, seed=0):
    m, r, mask = 0xc6a4a7935bd1e995, 47, (1 << 64) - 1
    h = (seed ^ (len(data) * m)) & mask
    tail = len(data) & ~7
    for (k,) in struct.iter_unpack("<Q", data[:tail]):
        k = (k * m) & mask
        k ^= k >> r
        k = (k * m) & mask
        h = ((h ^ k) * m) & mask
    rest = data[tail:]
    if rest:
        h = ((h ^ int.from_bytes(rest, "little")) * m) & mask
    h ^= h >> r
    h = (h * m) & mask
    return h ^ (h >> r)


def bundle_entries(path):
    """A bundle's resources: (type, name, data of the first variant)."""
    data = path.read_bytes()
    if len(data) < 12 or struct.unpack_from("<I", data, 0)[0] != 0xF0000004:
        return
    total = struct.unpack_from("<I", data, 4)[0]
    raw, pos = bytearray(), 12
    while pos < len(data) and len(raw) < total:
        (size,) = struct.unpack_from("<I", data, pos)
        pos += 4
        chunk = data[pos:pos + size]
        pos += size
        raw += chunk if size == 0x10000 else zlib.decompress(chunk)
    (count,) = struct.unpack_from("<I", raw, 0)
    pos = 260 + count * 16
    for _ in range(count):
        kind, name, variants, _ = struct.unpack_from("<QQII", raw, pos)
        pos += 24
        heads = [struct.unpack_from("<III", raw, pos + 12 * i) for i in range(variants)]
        pos += 12 * variants
        first = None
        for _, size, _ in heads:
            if first is None:
                first = bytes(raw[pos:pos + size])
            pos += size
        yield kind, name, first


def game_images(names):
    """The named images of the gui materials, as RGBA images."""
    material, texture = murmur64(b"material"), murmur64(b"texture")
    wanted = {murmur64(n.encode()) >> 32: n for n in names}
    where, textures = {}, {}
    for path in sorted(CONTENTS.iterdir()):
        if not path.is_file() or len(path.name) != 16 or "." in path.name:
            continue
        for kind, name, data in bundle_entries(path):
            if kind == material:
                words = struct.unpack_from("<%dI" % (len(data) // 4), data, 0)
                for i, w in enumerate(words[:-8]):
                    if w in wanted and words[i + 5] == DIFFUSE_MAP:
                        where.setdefault(wanted[w], words[i + 6] | (words[i + 7] << 32))
            elif kind == texture:
                textures[name] = data
    out = {}
    for n in names:
        data = textures.get(where.get(n))
        if data is None:
            raise SystemExit(f"no image {n} in {CONTENTS}")
        out[n] = Image.open(io.BytesIO(data)).convert("RGBA")
    return out


def fit(alpha):
    """Coverage centred on a square of SIZE, with a margin, as the SVG icons are drawn."""
    box = alpha.getbbox()
    if box:
        alpha = alpha.crop(box)
    w, h = alpha.size
    scale = SIZE * 0.86 / max(w, h)
    alpha = alpha.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.Resampling.LANCZOS)
    out = Image.new("L", (SIZE, SIZE), 0)
    out.paste(alpha, ((SIZE - alpha.size[0]) // 2, (SIZE - alpha.size[1]) // 2))
    return out


def stratagem_symbol(image):
    """The light symbol off its coloured square, its border trimmed."""
    a = np.asarray(image, dtype=np.float32)[3:-3, 3:-3, :3]
    low = a.min(axis=2)
    back = np.median(low)
    cover = np.clip((low - back - 25) / (230 - back - 25), 0, 1)
    # Some symbols are light grey: the brightest part is white, the shading between parts kept.
    cover = np.clip(cover / max(np.percentile(cover, 99.5), 0.05), 0, 1)
    return Image.fromarray((cover * 255).astype(np.uint8), "L")


def grow(region, mask):
    """region spread through mask, one pixel at a time, until it stops."""
    while True:
        wider = region.copy()
        wider[1:, :] |= region[:-1, :]
        wider[:-1, :] |= region[1:, :]
        wider[:, 1:] |= region[:, :-1]
        wider[:, :-1] |= region[:, 1:]
        wider &= mask
        if (wider == region).all():
            return region
        region = wider


def perk_shape(image, box, whole=False):
    """The grey shape at the middle of the box, brightness kept as shading. Shapes beside it in the strip
    (a second figure, a trail, wings) don't touch it, so only what's joined to the middle stays."""
    a = np.asarray(image.crop(box), dtype=np.float32)
    cover = a[:, :, 3] / 255 * np.clip(a[:, :, :3].max(axis=2) / 235, 0, 1)
    if whole:
        return Image.fromarray((cover * 255).astype(np.uint8), "L")
    solid = cover > 0.35
    h, w = solid.shape
    seed = np.zeros_like(solid)
    seed[h * 2 // 5:h * 3 // 5, w * 2 // 5:w * 3 // 5] = True
    region = grow(seed & solid, solid)
    # A pixel's soft edge stays with it.
    near = region.copy()
    for _ in range(2):
        near[1:, :] |= near[:-1, :].copy()
        near[:-1, :] |= near[1:, :].copy()
        near[:, 1:] |= near[:, :-1].copy()
        near[:, :-1] |= near[:, 1:].copy()
    cover = np.where(near, cover, 0)
    return Image.fromarray((cover * 255).astype(np.uint8), "L")


def main():
    images = game_images(sorted(set(STRATAGEMS.values()) | {v[0] for v in CROPS.values()}))
    for upgrade, name in STRATAGEMS.items():
        white = fit(stratagem_symbol(images[name]))
        Image.merge("LA", (Image.new("L", white.size, 255), white)).save(OUT / f"{upgrade}.png")
        print(upgrade, "from", name)
    for upgrade, (name, box, *whole) in CROPS.items():
        white = fit(perk_shape(images[name], box, bool(whole and whole[0])))
        Image.merge("LA", (Image.new("L", white.size, 255), white)).save(OUT / f"{upgrade}.png")
        print(upgrade, "from", name)


if __name__ == "__main__":
    main()
