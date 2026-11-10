"""Builds Helldivers Arcade's art: one white atlas that the game tints when it draws, its material,
and the table of where each image sits.

Usage: python tools/build_art.py

The upgrades' and the elites' icons are game-icons.net's SVGs (tools/icons, credited in CREDITS.md) and, for upgrades that
stand for a stratagem or a perk, the game's own icon as a white PNG (tools/game_icons.py takes them out of
the game). Every other image is drawn here from shapes. Writes res/art.texture, res/art.material and src/atlas.lua, and internal/art_preview.png to look at.
Needs Pillow, numpy and resvg-py.
"""
import math
import struct
from pathlib import Path

import io

import numpy as np
import resvg_py
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RES, SRC, INTERNAL = ROOT / "res", ROOT / "src", ROOT / "internal"
ICON_DIR = ROOT / "tools" / "icons"

ATLAS_W, ATLAS_H = 2048, 2048
PAD = 4
RESOURCE_BASE = "arcade/art"
MATERIAL_NAME = "arcade_art"
MATERIAL_VERSION = 10
# The game's font material: the shader multiplies a white texture's alpha by the vertex color.
TEMPLATE, DIFFUSE_MAP, VARIABLE = 0xba25de35, 0x3aa8b87e, 0x46f80ade

ICON = 192
# Drawn four times larger, then scaled down, for smooth edges.
SS = 4


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


class Pen:
    """A square canvas in units of 0 to 100, y down, drawn large and scaled to `size` at the end."""

    def __init__(self, size=ICON):
        self.size = size
        self.image = Image.new("L", (size * SS, size * SS), 0)
        self.d = ImageDraw.Draw(self.image)
        self.s = size * SS / 100

    def p(self, points):
        return [(x * self.s, y * self.s) for x, y in points]

    def poly(self, points, fill=255):
        self.d.polygon(self.p(points), fill=fill)

    def rect(self, x0, y0, x1, y1, fill=255):
        self.d.rectangle(self.p([(x0, y0), (x1, y1)]), fill=fill)

    def circle(self, cx, cy, r, fill=255):
        self.d.ellipse(self.p([(cx - r, cy - r), (cx + r, cy + r)]), fill=fill)

    def ring(self, cx, cy, r, width, fill=255):
        self.circle(cx, cy, r, fill)
        self.circle(cx, cy, r - width, 0)

    def pie(self, cx, cy, r, start, end, fill=255):
        """Degrees clockwise from three o'clock, as Pillow counts them."""
        self.d.pieslice(self.p([(cx - r, cy - r), (cx + r, cy + r)]), start, end, fill=fill)

    def arc(self, cx, cy, r, width, start, end, fill=255):
        """A band `width` thick inside radius r, degrees clockwise from three o'clock."""
        self.d.arc(self.p([(cx - r, cy - r), (cx + r, cy + r)]), start, end, fill=fill, width=max(1, round(width * self.s)))

    def line(self, ax, ay, bx, by, width, fill=255):
        dx, dy = bx - ax, by - ay
        n = math.hypot(dx, dy)
        nx, ny = -dy / n * width / 2, dx / n * width / 2
        self.poly([(ax + nx, ay + ny), (bx + nx, by + ny), (bx - nx, by - ny), (ax - nx, ay - ny)], fill)

    def done(self):
        return self.image.resize((self.size, self.size), Image.Resampling.LANCZOS)


def hex_points(cx, cy, r, pointy=True):
    start = -90 if pointy else 0
    return [(cx + r * math.cos(math.radians(start + 60 * i)), cy + r * math.sin(math.radians(start + 60 * i))) for i in range(6)]


# The upgrades' icons, one each: an SVG of tools/icons drawn large, or the game's icon as a PNG, its
# coverage kept as the white image.

def icon_from_svg(name):
    png = ICON_DIR / f"{name}.png"
    if png.exists():
        return Image.open(png).convert("LA").getchannel("A").resize((ICON, ICON), Image.Resampling.LANCZOS)
    svg = (ICON_DIR / f"{name}.svg").read_text(encoding="utf-8")
    png = bytes(resvg_py.svg_to_bytes(svg_string=svg, width=ICON * SS, height=ICON * SS))
    alpha = Image.open(io.BytesIO(png)).convert("RGBA").getchannel("A")
    return alpha.resize((ICON, ICON), Image.Resampling.LANCZOS)


ICONS = ["oxygenator", "panic", "analysis_field", "molecular_scan", "patch_up", "extended_mag", "steady_aim", "higher_calibre", "peak_physique", "arsenal_support", "rapid_fire", "quick_cycle", "shield_generator_pack", "meritocracy", "strategic_reserve", "fast_reflexes", "destroyer_support", "sweet_liberty", "absolute_freedom", "suitable_replacement", "broad_permit", "guard_dog", "angel",
         "autoinjector", "all_terrain_boots", "cardio_accelerator", "heavy_armor", "incendiary_grenades", "stun_grenades", "smoke_grenades", "stratagem_priority", "displacement_field", "strong_arm", "gunslinger", "pyro", "singe", "precision_call_in",
         "divers_resolve", "strike_back", "extra_padding", "elusive_tactics", "ignition_rounds", "needle_rounds", "warp_pack", "democracy_protects", "unstoppable_freedom", "exo_expert", "kinetic_battery", "cluster_grenade", "deep_pockets", "weight_training", "carpet_bombing", "napalm_needles", "dynamo", "iron_saint", "spiked_plating", "sample_siphon", "chain_reaction", "tank_hunter", "facetanker", "trailblazer", "quick_draw"]
# Images that aren't an upgrade's, by their file in tools/icons: the stat numbers' icons.
MARKS = ["stat_health", "stat_armor"]
# The elites' marks over their health bars (Better HUD's elite_mark), one for each kind, by their file
# in tools/icons.
ELITES = ["elite_fire", "elite_shock", "elite_noxious", "elite_bulwark", "elite_swift", "elite_brood"]


# The cards' and the orbs' parts.

def shape_hex(size, r=47):
    pen = Pen(size)
    pen.poly(hex_points(50, 50, r))
    return pen.done()


def shape_frame(size, kind):
    """A badge's frame, filled: a circle for common, a square for rare, a diamond for legendary. Each
    is sized to look as big as the others."""
    pen = Pen(size)
    if kind == "circle":
        pen.circle(50, 50, 47)
    elif kind == "square":
        pen.rect(9, 9, 91, 91)
    elif kind == "hex":
        pen.poly(hex_points(50, 50, 49, pointy=False))
    else:
        pen.poly([(50, 0), (100, 50), (50, 100), (0, 50)])
    return pen.done()


def shape_hex_ring(size, width):
    pen = Pen(size)
    pen.poly(hex_points(50, 50, 47))
    pen.poly(hex_points(50, 50, 47 - width), 0)
    return pen.done()


def shape_glow(size, power=2.2):
    y, x = np.mgrid[0:size, 0:size]
    d = np.hypot(x - size / 2 + 0.5, y - size / 2 + 0.5) / (size / 2)
    a = np.clip(1 - d, 0, 1) ** power
    return Image.fromarray((a * 255).astype(np.uint8), "L")


def shape_gem(size):
    """An XP shard: a long diamond with lit and shaded facets."""
    pen = Pen(size)
    pen.poly([(50, 4), (80, 44), (50, 96), (20, 44)], 150)
    pen.poly([(50, 4), (50, 96), (20, 44)], 255)
    pen.poly([(50, 4), (66, 44), (50, 60), (34, 44)], 220)
    return pen.done()


def shape_ramp(w, h):
    """Bright at the top, gone at the bottom."""
    a = np.tile(np.linspace(255, 0, h, dtype=np.float32)[:, None], (1, w))
    return Image.fromarray(a.astype(np.uint8), "L")


def shape_stripes(w, h):
    image = Image.new("L", (w * SS, h * SS), 0)
    d = ImageDraw.Draw(image)
    step = h * SS
    for x in range(-step, w * SS + step, step):
        d.polygon([(x, h * SS), (x + step * 0.5, h * SS), (x + step, 0), (x + step * 0.5, 0)], fill=255)
    return image.resize((w, h), Image.Resampling.LANCZOS)


def shape_noise(size):
    """A soft cloud for the cards' faces. Seeded, so every build is the same."""
    rng = np.random.default_rng(97)
    out = np.zeros((size, size), dtype=np.float32)
    for octave in range(5):
        cells = 4 * 2 ** octave
        grid = rng.random((cells, cells), dtype=np.float32)
        tile = Image.fromarray((grid * 255).astype(np.uint8), "L").resize((size, size), Image.Resampling.BICUBIC)
        out += np.asarray(tile, dtype=np.float32) / 255 / 2 ** octave
    out = (out - out.min()) / (out.max() - out.min())
    return Image.fromarray((np.clip((out - 0.3) * 1.5, 0, 1) * 255).astype(np.uint8), "L")


def shape_corner(size):
    """A bracket for a card's corner, at its top left."""
    pen = Pen(size)
    pen.poly([(0, 0), (100, 0), (100, 16), (16, 16), (16, 100), (0, 100)])
    return pen.done()


def shapes():
    out = {f"icon_{name}": icon_from_svg(name) for name in ICONS}
    out.update({f"mark_{name}": icon_from_svg(name) for name in MARKS})
    out.update({name: icon_from_svg(name) for name in ELITES})
    out["hex"] = shape_hex(256)
    for kind in ("circle", "square", "diamond", "hex"):
        out[f"frame_{kind}"] = shape_frame(256, kind)
    out["hex_ring"] = shape_hex_ring(256, 5)
    # The thin ring round a partner's icon in a card's corner.
    pen = Pen(128)
    pen.ring(50, 50, 47, 6)
    out["ring"] = pen.done()
    out["glow"] = shape_glow(256)
    out["glow_soft"] = shape_glow(128, 1.2)
    out["gem"] = shape_gem(64)
    out["ramp"] = shape_ramp(16, 128)
    out["stripes"] = shape_stripes(128, 16)
    out["noise"] = shape_noise(256)
    out["corner"] = shape_corner(32)
    return out


def alpha_blocks(image):
    width, height = image.size
    pad_w, pad_h = (4 - width % 4) % 4, (4 - height % 4) % 4
    a = np.pad(np.asarray(image, dtype=np.int32), ((0, pad_h), (0, pad_w)), mode="edge")
    blocks = a.reshape(a.shape[0] // 4, 4, a.shape[1] // 4, 4).transpose(0, 2, 1, 3).reshape(-1, 16)
    high, low = blocks.max(axis=1), blocks.min(axis=1)
    steps = np.arange(1, 7)
    ramp = np.zeros((len(blocks), 8), dtype=np.int32)
    ramp[:, 0], ramp[:, 1] = high, low
    ramp[:, 2:] = ((7 - steps)[None, :] * high[:, None] + steps[None, :] * low[:, None]) // 7
    best = np.abs(blocks[:, :, None] - ramp[:, None, :]).argmin(axis=2).astype(np.uint64)
    best[high == low] = 0
    bits = np.zeros(len(blocks), dtype=np.uint64)
    for i in range(16):
        bits |= best[:, i] << np.uint64(3 * i)
    out = bytearray(len(blocks) * 16)
    colour = b"\xff\xff\xff\xff\0\0\0\0"
    for i, (h, l, b) in enumerate(zip(high.tolist(), low.tolist(), bits.tolist())):
        out[i * 16:i * 16 + 16] = bytes((h, l)) + b.to_bytes(6, "little") + colour
    return bytes(out)


def dds(image):
    """DXT5 with every mip, in the layout of the game's own atlases."""
    width, height = image.size
    mips = [image]
    while mips[-1].size != (1, 1):
        w, h = mips[-1].size
        mips.append(mips[-1].resize((max(1, w // 2), max(1, h // 2)), Image.Resampling.BOX))
    header = bytearray(128)
    header[:4] = b"DDS "
    struct.pack_into("<IIIIIII", header, 4, 124, 0x000a1007, height, width, width * height, 0, len(mips))
    header[60:64], header[68:72] = b"UVER", b"NVTT"
    struct.pack_into("<I", header, 72, 0x00020100)
    struct.pack_into("<II4s", header, 76, 32, 4, b"DXT5")
    struct.pack_into("<I", header, 108, 0x00401008)
    # Every texture resource ends with a four byte category, or the game stalls at boot.
    return bytes(header) + b"".join(alpha_blocks(m) for m in mips) + bytes(4)


def material():
    name = murmur64(MATERIAL_NAME.encode()) >> 32
    tex = murmur64(f"{RESOURCE_BASE}/atlas".encode())
    record = struct.pack("<13I", name, TEMPLATE, 0, 0, 1, DIFFUSE_MAP, tex & 0xffffffff, tex >> 32, 1, VARIABLE, 0, 0, 0)
    return struct.pack("<II", MATERIAL_VERSION, 1) + record


def pack(images):
    """Shelves, tallest first."""
    atlas = Image.new("L", (ATLAS_W, ATLAS_H), 0)
    x, y, row = PAD, PAD, 0
    table = {}
    for name, image in sorted(images.items(), key=lambda kv: (-kv[1].size[1], kv[0])):
        w, h = image.size
        if x + w + PAD > ATLAS_W:
            x, y, row = PAD, y + row + PAD, 0
        if y + h + PAD > ATLAS_H:
            raise SystemExit(f"atlas is full at {name}")
        atlas.paste(image, (x, y))
        table[name] = (x, y, w, h)
        x += w + PAD
        row = max(row, h)
    print(f"atlas used to y={y + row} of {ATLAS_H}")
    return atlas, table


RARITY = {"common": (190, 196, 204), "rare": (80, 170, 255), "perk": (95, 208, 104), "legendary": (255, 176, 40), "evolution": (255, 61, 61)}
RARITY_OF = {
    "oxygenator": "common", "panic": "common", "analysis_field": "common", "molecular_scan": "common", "patch_up": "common", "extended_mag": "common",
    "steady_aim": "common", "higher_calibre": "common", "peak_physique": "common", "arsenal_support": "rare", "rapid_fire": "rare", "quick_cycle": "rare",
    "shield_generator_pack": "rare", "meritocracy": "common", "strategic_reserve": "rare", "fast_reflexes": "rare", "destroyer_support": "legendary",
    "sweet_liberty": "legendary", "absolute_freedom": "legendary", "suitable_replacement": "legendary", "broad_permit": "legendary", "guard_dog": "rare",
    "angel": "rare",
    "divers_resolve": "common", "kinetic_battery": "common", "cluster_grenade": "common", "deep_pockets": "rare",
    "weight_training": "legendary",
    "tank_hunter": "common",
    "strike_back": "common",
    "extra_padding": "common",
    "exo_expert": "rare",
    "elusive_tactics": "common",
    "ignition_rounds": "rare",
    "needle_rounds": "rare",
    "facetanker": "rare",
    "trailblazer": "rare",
    "quick_draw": "legendary",
    "warp_pack": "legendary",
    "democracy_protects": "legendary",
    "unstoppable_freedom": "legendary",
    "autoinjector": "perk",
    "all_terrain_boots": "perk",
    "cardio_accelerator": "perk",
    "heavy_armor": "perk",
    "incendiary_grenades": "perk",
    "stun_grenades": "perk",
    "smoke_grenades": "perk",
    "stratagem_priority": "perk",
    "displacement_field": "perk",
    "strong_arm": "perk",
    "gunslinger": "perk",
    "pyro": "perk",
    "singe": "perk",
    "precision_call_in": "perk",
    "carpet_bombing": "evolution",
    "napalm_needles": "evolution",
    "dynamo": "evolution",
    "iron_saint": "evolution",
    "spiked_plating": "evolution",
    "sample_siphon": "evolution",
    "chain_reaction": "evolution",
}
FRAME_OF = {"common": "circle", "rare": "square", "perk": "square", "legendary": "diamond", "evolution": "hex"}
# The inside of a frame against its edge, as src/art.lua draws it: a diamond's edges run at 45 degrees,
# so it needs a smaller inside for the same width of edge.
INNER = {"circle": 0.9, "square": 0.9, "diamond": 0.86, "hex": 0.88}
# The icon against the frame, as src/art.lua sizes it: a diamond holds a smaller square.
ICON_SCALE = {"circle": 1.0, "square": 1.0, "diamond": 1.03 / 1.15, "hex": 1.08 / 1.15}
# How big each frame is drawn, as src/art.lua does it: a diamond is a square turned to fit the box, so it
# is drawn bigger to look as big as the others.
FRAME_SIZE = {"circle": 1.0, "square": 1.0, "diamond": 1.15, "hex": 1.1}


def preview(images):
    """The icons on their badges, tinted as the cards tint them."""
    names = list(ICONS)
    cell = 220
    cols = 7
    sheet = Image.new("RGB", (cell * cols, cell * ((len(names) + cols - 1) // cols)), (20, 21, 24))
    for i, name in enumerate(names):
        ox, oy = (i % cols) * cell, (i // cols) * cell
        color = RARITY[RARITY_OF[name]]
        kind = FRAME_OF[RARITY_OF[name]]
        outer = 0.8 * FRAME_SIZE[kind]
        for layer, tint, scale in ((f"frame_{kind}", color, outer), (f"frame_{kind}", (38, 39, 44), outer * INNER[kind])):
            mask = images[layer].resize((int(cell * scale), int(cell * scale)), Image.Resampling.LANCZOS)
            off = (ox + (cell - mask.size[0]) // 2, oy + (cell - mask.size[1]) // 2)
            sheet.paste(Image.new("RGB", mask.size, tint), off, mask)
        size = round(104 * ICON_SCALE[kind])
        mask = images[f"icon_{name}"].resize((size, size), Image.Resampling.LANCZOS)
        sheet.paste(Image.new("RGB", mask.size, (236, 232, 220)), (ox + (cell - size) // 2, oy + (cell - size) // 2), mask)
    return sheet


def main():
    images = shapes()
    atlas, table = pack(images)
    RES.mkdir(exist_ok=True)
    INTERNAL.mkdir(exist_ok=True)
    (RES / "art.texture").write_bytes(dds(atlas))
    (RES / "art.material").write_bytes(material())
    atlas.save(INTERNAL / "atlas_preview.png")
    preview(images).save(INTERNAL / "art_preview.png")
    lines = ["-- Written by tools/build_art.py. Where each image sits in the atlas, in pixels.", "return {",
             f"\tw = {ATLAS_W}, h = {ATLAS_H},", f'\tmaterial = "{MATERIAL_NAME}",', f'\tpath = "{RESOURCE_BASE}",', "\timages = {"]
    for name in sorted(table):
        x, y, w, h = table[name]
        lines.append(f"\t\t{name} = {{ {x}, {y}, {w}, {h} }},")
    lines += ["\t},", "}", ""]
    (SRC / "atlas.lua").write_text("\n".join(lines), newline="\n")
    print("texture", (RES / "art.texture").stat().st_size)


if __name__ == "__main__":
    main()
