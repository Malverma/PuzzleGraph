#!/usr/bin/env python3
"""Generate sample piece sets for the Ribbon, Random, Octagon and Wavy cut styles.

Follows spec.md §5: every interior edge is one curve shared by both neighbours
(reversed for the second), outer borders are straight, and outlines are stored as
flattened polygons with bbox + home position. Each set is validated: outlines must
be simple polygons and their areas must sum to the puzzle area (no gaps/overlaps).

Usage: python3 tools/gen_cut_pieces.py [out_dir]
"""
import json
import math
import os
import random
import subprocess
import sys

SAMPLES = 16                    # points per cubic when flattening

# name -> grid, cell size, seed, look
STYLES = {
    "ribbon":  {"grid": (5, 4), "cell": (256, 240), "seed": 8734120934,
                "fill": "#F4F1EA", "stroke": "#6E6E6E", "stroke_w": 4},
    "random":  {"grid": (5, 4), "cell": (256, 240), "seed": 168,
                "fill": "#F4F1EA", "stroke": "#111111", "stroke_w": 3},
    # octagons on a 4 x 3 grid + diamonds at interior grid vertices = 18 pieces
    "octagon": {"grid": (4, 3), "cell": (256, 256), "seed": 4242,
                "fill": "#F4F1EA", "stroke": "#3D4F5C", "stroke_w": 3},
    "wavy":    {"grid": (5, 4), "cell": (256, 240), "seed": 77,
                "fill": "#E9D3B0", "stroke": "#3B2A1A", "stroke_w": 3},
}


# ---------- curve helpers ----------

def cubic(p0, p1, p2, p3, n=SAMPLES):
    out = []
    for i in range(1, n + 1):
        t = i / n
        u = 1 - t
        out.append((u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
                    u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1]))
    return out


def knob_profile(rng, flip, size=0.10, jitter=0.04):
    """Classic tab in local coords: (0,0)->(1,0), bulging toward +v if flip else -v.
    Returns flattened points excluding the start point."""
    j = lambda: rng.uniform(-jitter, jitter)
    a, b, c, d, e = j(), j(), j(), j(), j()
    t = size * rng.uniform(0.92, 1.08)
    s = 1 if flip else -1
    P = [(0, 0), (0.2, a), (0.5 + b + d, -t + c), (0.5 - t + b, t + c),
         (0.5 - 2 * t + b - d, 3 * t + c), (0.5 + 2 * t + b - d, 3 * t + c),
         (0.5 + t + b, t + c), (0.5 + b + d, -t + c), (0.8, e), (1, 0)]
    P = [(x, s * y) for x, y in P]
    return cubic(P[0], P[1], P[2], P[3]) + cubic(P[3], P[4], P[5], P[6]) + cubic(P[6], P[7], P[8], P[9])


def wave_fn(rng, amp, harmonics=2):
    """Low-amplitude noise v(u) on [0,1], zero at both ends."""
    ks = [(rng.uniform(-amp, amp) / (h + 1), rng.uniform(0, math.pi)) for h in range(harmonics)]
    return lambda u: math.sin(math.pi * u) * sum(k * math.sin((h + 1) * math.pi * u + (ph if h else 0))
                                                for h, (k, ph) in enumerate(ks))


def wavy_profile(rng, amp):
    f = wave_fn(rng, amp)
    n = SAMPLES * 2
    return [(i / n, f(i / n)) for i in range(1, n + 1)]


def to_world(local, p, q):
    """Map local (u,v) profile onto segment p->q (v scaled by segment length).
    For a clockwise cell (y down), +v points into the cell."""
    dx, dy = q[0] - p[0], q[1] - p[1]
    L = math.hypot(dx, dy)
    nx, ny = -dy / L, dx / L
    out = [(p[0] + dx * u + nx * v * L, p[1] + dy * u + ny * v * L) for u, v in local]
    out[-1] = q  # exact endpoint so neighbours meet
    return out


# ---------- shared tiling -> pieces ----------

def key(p):
    return (round(p[0], 3), round(p[1], 3))


def build_pieces(cells, W, H, profile_fn):
    """cells: list of dicts with clockwise 'poly'. profile_fn(i, j, p, q) returns a local
    profile for the edge p->q as traversed by cell i (i < j)."""
    owners = {}
    for i, c in enumerate(cells):
        poly = c["poly"]
        for k in range(len(poly)):
            p, q = poly[k], poly[(k + 1) % len(poly)]
            owners.setdefault(frozenset((key(p), key(q))), []).append((i, p, q))
    curves = {}
    for ek, own in owners.items():
        if len(own) == 1:
            i, p, q = own[0]
            on_border = (abs(p[0] - q[0]) < 1e-6 and min(abs(p[0]), abs(p[0] - W)) < 1e-6) or \
                        (abs(p[1] - q[1]) < 1e-6 and min(abs(p[1]), abs(p[1] - H)) < 1e-6)
            assert on_border, f"unmatched interior edge {p}->{q}"
            continue
        assert len(own) == 2, f"edge shared by {len(own)} cells"
        (i, p, q), (j, _, _) = sorted(own)
        curves[ek] = (i, p, to_world(profile_fn(i, j, p, q), p, q))

    pieces = []
    for i, c in enumerate(cells):
        poly, pts = c["poly"], []
        for k in range(len(poly)):
            p, q = poly[k], poly[(k + 1) % len(poly)]
            pts.append(p)
            ek = frozenset((key(p), key(q)))
            if ek not in curves:
                continue
            owner, start, cur = curves[ek]
            if owner == i:
                pts += cur[:-1]
            else:
                pts += list(reversed([start] + cur[:-1]))[:-1]
        pc = {k: v for k, v in c.items() if k != "poly"}
        pc["outline"] = pts
        pieces.append(pc)
    return pieces


def area(pts):
    return sum(pts[k][0] * pts[(k + 1) % len(pts)][1] - pts[(k + 1) % len(pts)][0] * pts[k][1]
               for k in range(len(pts))) / 2


def is_simple(pts):
    """Segment self-intersection test, bucketed on a coarse grid."""
    n, G = len(pts), 24.0
    segs = [(pts[k], pts[(k + 1) % n]) for k in range(n)]
    grid = {}
    for k, (a, b) in enumerate(segs):
        for gx in range(int(min(a[0], b[0]) // G), int(max(a[0], b[0]) // G) + 1):
            for gy in range(int(min(a[1], b[1]) // G), int(max(a[1], b[1]) // G) + 1):
                grid.setdefault((gx, gy), []).append(k)

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    for bucket in grid.values():
        for x in range(len(bucket)):
            for y in range(x + 1, len(bucket)):
                k, m = bucket[x], bucket[y]
                if abs(k - m) <= 1 or abs(k - m) == n - 1:
                    continue
                (a, b), (c, d) = segs[k], segs[m]
                if (cross(a, b, c) > 0) != (cross(a, b, d) > 0) and (cross(c, d, a) > 0) != (cross(c, d, b) > 0):
                    return False
    return True


def validate(pieces, W, H):
    total = sum(abs(area(p["outline"])) for p in pieces)
    return abs(total - W * H) < 0.5 and all(is_simple(p["outline"]) for p in pieces)


# ---------- tilings ----------

def grid_cells(cols, rows, cw, ch):
    cells = []
    for r in range(rows):
        for c in range(cols):
            x0, y0 = c * cw, r * ch
            cells.append({"row": r, "col": c, "type": "A" if (r + c) % 2 == 0 else "B",
                          "poly": [(x0, y0), (x0 + cw, y0), (x0 + cw, y0 + ch), (x0, y0 + ch)]})
    return cells


def clip(poly, a, b, c):
    """Keep the part of poly where a*x + b*y <= c."""
    out = []
    for i in range(len(poly)):
        p, q = poly[i], poly[(i + 1) % len(poly)]
        fp, fq = a * p[0] + b * p[1] - c, a * q[0] + b * q[1] - c
        if fp <= 1e-9:
            out.append(p)
        if (fp > 1e-9) != (fq > 1e-9):
            t = fp / (fp - fq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out


def voronoi_cells(rng, cols, rows, cw, ch, jitter=0.35):
    W, H = cols * cw, rows * ch
    seeds = [((c + 0.5 + rng.uniform(-jitter, jitter)) * cw, (r + 0.5 + rng.uniform(-jitter, jitter)) * ch)
             for r in range(rows) for c in range(cols)]
    cells = []
    for i, si in enumerate(seeds):
        poly = [(0, 0), (W, 0), (W, H), (0, H)]
        for j, sj in enumerate(seeds):
            if i != j:
                a, b = sj[0] - si[0], sj[1] - si[1]
                poly = clip(poly, a, b, (sj[0]**2 + sj[1]**2 - si[0]**2 - si[1]**2) / 2)
        dedup = [p for k, p in enumerate(poly) if key(p) != key(poly[k - 1])]
        cells.append({"row": i // cols, "col": i % cols, "seed_point": [round(v, 2) for v in si], "poly": dedup})
    return cells


def octagon_cells(rng, cols, rows, s, shift=0.07, size_var=0.25, turn=14):
    """Truncated-square tiling: octagons on the grid, diamonds at interior vertices.
    Each diamond is moved by up to shift*s, resized by up to +-size_var and turned by up to
    +-turn degrees; border vertices slide along the border. Corners touching the border stay
    square so the border is straight."""
    k0 = s / (2 + math.sqrt(2))   # corner cut leg -> regular octagon
    J = lambda a: rng.uniform(-a, a)
    dia = {}                      # (r, c) grid vertex -> N, E, S, W diamond corners
    for r in range(1, rows):
        for c in range(1, cols):
            x, y = c * s + J(shift * s), r * s + J(shift * s)
            k, a = k0 * (1 + J(size_var)), math.radians(J(turn))
            ca, sa = math.cos(a), math.sin(a)
            dia[r, c] = [(x + u * ca - v * sa, y + u * sa + v * ca) for u, v in ((0, -k), (k, 0), (0, k), (-k, 0))]
    top = {c: (c * s + J(shift * s), 0) for c in range(1, cols)}
    bot = {c: (c * s + J(shift * s), rows * s) for c in range(1, cols)}
    left = {r: (0, r * s + J(shift * s)) for r in range(1, rows)}
    right = {r: (cols * s, r * s + J(shift * s)) for r in range(1, rows)}

    def corner(r, c, first, second):
        """Grid vertex (r, c) seen from one octagon: border point, square corner or diamond side."""
        if (r in (0, rows)) and (c in (0, cols)):
            return [(c * s, r * s)]
        if r == 0:
            return [top[c]]
        if r == rows:
            return [bot[c]]
        if c == 0:
            return [left[r]]
        if c == cols:
            return [right[r]]
        N, E, S, W = dia[r, c]
        return [{"N": N, "E": E, "S": S, "W": W}[q] for q in (first, second)]

    cells = []
    for r in range(rows):
        for c in range(cols):
            poly = corner(r, c, "S", "E") + corner(r, c + 1, "W", "S") + \
                   corner(r + 1, c + 1, "N", "W") + corner(r + 1, c, "E", "N")
            cells.append({"row": r, "col": c, "type": "octagon", "poly": poly})
    for (r, c), pts in dia.items():
        cells.append({"row": r - 0.5, "col": c - 0.5, "type": "diamond", "poly": pts})
    return cells


# ---------- styles ----------

def ribbon(rng, cfg):
    (cols, rows), (cw, ch) = cfg["grid"], cfg["cell"]
    cells = grid_cells(cols, rows, cw, ch)

    # Checkerboard ribbon pattern: type A has knobs out left/right, sockets top/bottom;
    # type B is the opposite, so neighbours always mate.
    def prof(i, j, p, q):
        side_by_side = abs(p[0] - q[0]) < 1e-6        # vertical shared edge
        out_of_i = (cells[i]["type"] == "A") == side_by_side
        return knob_profile(rng, flip=not out_of_i)
    return build_pieces(cells, cols * cw, rows * ch, prof)


def random_cut(rng, cfg):
    (cols, rows), (cw, ch) = cfg["grid"], cfg["cell"]
    cells = voronoi_cells(rng, cols, rows, cw, ch)

    def prof(i, j, p, q):
        L = math.hypot(q[0] - p[0], q[1] - p[1])
        if L < 0.6 * cw:
            return wavy_profile(rng, 0.05)
        size = max(0.07, min(0.12, 0.095 * cw / L))  # consistent absolute knob size
        f = wave_fn(rng, 0.02)
        return [(u, v + f(u)) for u, v in knob_profile(rng, flip=rng.random() < 0.5, size=size)]
    return build_pieces(cells, cols * cw, rows * ch, prof)


def octagon(rng, cfg):
    (cols, rows), (s, _) = cfg["grid"], cfg["cell"]
    cells = octagon_cells(rng, cols, rows, s)

    def prof(i, j, p, q):
        # diamond tabs mostly push into the octagon (sometimes into the diamond);
        # octagon/octagon edges pick a side and long ones may carry two knobs
        L = math.hypot(q[0] - p[0], q[1] - p[1])
        bow = wave_fn(rng, 0.05)
        if cells[j]["type"] == "diamond":
            size = max(0.08, min(0.15, 0.055 * s / L)) * rng.uniform(0.8, 1.2)
            pts = knob_profile(rng, flip=rng.random() < 0.8, size=size, jitter=0.05)
        elif L > 0.65 * s and rng.random() < 0.35:
            flip, pts = rng.random() < 0.5, []
            for a in (0, 0.5):
                size = max(0.10, min(0.16, 0.06 * s / (L / 2))) * rng.uniform(0.85, 1.15)
                pts += [(a + u / 2, v / 2) for u, v in knob_profile(rng, flip=flip, size=size, jitter=0.05)]
                flip = not flip
        else:
            size = max(0.08, min(0.12, 0.055 * s / L)) * rng.uniform(0.8, 1.25)
            pts = knob_profile(rng, flip=rng.random() < 0.5, size=size, jitter=0.05)
        return [(u, v + bow(u)) for u, v in pts]
    return build_pieces(cells, cols * s, rows * s, prof)


def wavy(rng, cfg):
    (cols, rows), (cw, ch) = cfg["grid"], cfg["cell"]
    cells = voronoi_cells(rng, cols, rows, cw, ch, jitter=0.30)

    # Laser-cut look: meandering edge + 0-2 bulbous knobs, often in alternating directions.
    def prof(i, j, p, q):
        L = math.hypot(q[0] - p[0], q[1] - p[1])
        n = 3 if L > 1.4 * cw else 2 if L > 0.75 * cw else 1 if L > 0.3 * cw else 0
        meander = wave_fn(rng, 0.16, harmonics=3)
        if n == 0:
            return [(u, v + meander(u) * 0.5) for u, v in wavy_profile(rng, 0.08)]
        flip = rng.random() < 0.5
        pts = []
        for m in range(n):
            a, b = m / n, (m + 1) / n
            size = max(0.10, min(0.17, 0.065 * cw / (L / n)))
            for u, v in knob_profile(rng, flip=flip, size=size, jitter=0.07):
                pts.append((a + u * (b - a), v * (b - a)))
            flip = not flip if rng.random() < 0.75 else flip
        return [(u, v + meander(u)) for u, v in pts]
    return build_pieces(cells, cols * cw, rows * ch, prof)


BUILDERS = {"ribbon": ribbon, "random": random_cut, "octagon": octagon, "wavy": wavy}


# ---------- output ----------

def path_d(pts, ox=0, oy=0):
    return "M" + " L".join(f"{x - ox:.2f},{y - oy:.2f}" for x, y in pts) + " Z"


def bbox(pts):
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def write_style(name, cfg, pieces, seed, out_dir):
    (cols, rows), (cw, ch) = cfg["grid"], cfg["cell"]
    W, H = cols * cw, rows * ch
    d = os.path.join(out_dir, name)
    os.makedirs(d, exist_ok=True)
    for f in os.listdir(d):                      # drop stale files from older, smaller sets
        if f.startswith(f"{name}_piece_"):
            os.remove(os.path.join(d, f))
    pad = cfg["stroke_w"] + 2
    look = f'fill="{cfg["fill"]}" stroke="{cfg["stroke"]}" stroke-width="{cfg["stroke_w"]}" stroke-linejoin="round"'
    meta = {"style": name.upper(), "seed": seed, "grid": [cols, rows], "puzzle_size": [W, H], "pieces": []}
    for idx, pc in enumerate(pieces, 1):
        x0, y0, x1, y1 = bbox(pc["outline"])
        ox, oy = math.floor(x0) - pad, math.floor(y0) - pad
        w, h = math.ceil(x1) + pad - ox, math.ceil(y1) + pad - oy
        base = os.path.join(d, f"{name}_piece_{idx:02d}")
        with open(base + ".svg", "w") as f:
            f.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
                    f'<path d="{path_d(pc["outline"], ox, oy)}" {look}/></svg>\n')
        subprocess.run(["rsvg-convert", "-o", base + ".png", base + ".svg"], check=True)
        entry = {"id": idx - 1, "file": f"{name}_piece_{idx:02d}.png", "row": pc["row"], "col": pc["col"],
                 "home": [ox, oy], "size": [w, h],
                 "bbox": [round(x0, 2), round(y0, 2), round(x1, 2), round(y1, 2)],
                 "outline": [[round(x, 2), round(y, 2)] for x, y in pc["outline"]]}
        for k in ("type", "seed_point"):
            if k in pc:
                entry[k] = pc[k]
        meta["pieces"].append(entry)
    with open(os.path.join(d, f"{name}_pieces.json"), "w") as f:
        json.dump(meta, f, indent=1)

    # Assembled board + exploded sheet (pieces pushed apart from their home spots).
    m = 90
    paths = "".join(f'<path d="{path_d(p["outline"])}"/>' for p in pieces)
    with open(os.path.join(d, f"{name}_assembled.svg"), "w") as f:
        f.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W + 2 * m}" height="{H + 2 * m}" '
                f'viewBox="{-m} {-m} {W + 2 * m} {H + 2 * m}"><g {look}>{paths}</g></svg>\n')
    gap, spread, ext = 70, "", [math.inf, math.inf, -math.inf, -math.inf]
    for p in pieces:
        x0, y0, x1, y1 = bbox(p["outline"])
        tx, ty = gap * (0.5 + (x0 + x1) / 2 / cw), gap * (0.5 + (y0 + y1) / 2 / ch)
        ext = [min(ext[0], x0 + tx), min(ext[1], y0 + ty), max(ext[2], x1 + tx), max(ext[3], y1 + ty)]
        spread += f'<path transform="translate({tx:.1f},{ty:.1f})" d="{path_d(p["outline"])}"/>'
    vx, vy = ext[0] - 40, ext[1] - 40
    sw, sh = math.ceil(ext[2] - ext[0] + 80), math.ceil(ext[3] - ext[1] + 80)
    with open(os.path.join(d, f"{name}_sheet.svg"), "w") as f:
        f.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{sw}" height="{sh}" '
                f'viewBox="{vx:.1f} {vy:.1f} {sw} {sh}"><g {look}>{spread}</g></svg>\n')
    for n in ("assembled", "sheet"):
        subprocess.run(["rsvg-convert", "-o", os.path.join(d, f"{name}_{n}.png"),
                        os.path.join(d, f"{name}_{n}.svg")], check=True)
    return len(pieces), (sw, sh)


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "assets/pieces"
    for name, cfg in STYLES.items():
        (cols, rows), (cw, ch) = cfg["grid"], cfg["cell"]
        seed = cfg["seed"]
        # Retry with the next seed if a curve ever crosses another (keeps sets valid).
        for _ in range(50):
            pieces = BUILDERS[name](random.Random(seed), cfg)
            if validate(pieces, cols * cw, rows * ch):
                break
            seed += 1
        else:
            raise SystemExit(f"{name}: no valid layout found")
        n, size = write_style(name, cfg, pieces, seed, out_dir)
        print(f"{name}: {n} pieces, seed {seed}, sheet {size[0]}x{size[1]}")


if __name__ == "__main__":
    main()
