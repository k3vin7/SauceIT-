#!/usr/bin/env python3
"""Build the Haapsalu RealGuide meshes from Maa-amet open data.

The script intentionally uses only Python's standard library plus Pillow, which
is already available in the project environment.  It reads the official LoD2
OBJ and 1 m DTM GeoTIFF, crops the festival-map comparison area, translates it
to a metre-scale local origin at Karja/Kalda, and writes Godot-importable GLB.
"""

from __future__ import annotations

import json
import math
import struct
import zipfile
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets" / "real_guide" / "source"
DERIVED = ROOT / "assets" / "real_guide" / "derived"

BUILDINGS_ZIP = SOURCE / "hooned_lod2-Haapsalu_linn-obj.zip"
DTM_TIF = SOURCE / "62371_dtm_1m.tif"
OSM_XML = SOURCE / "haapsalu_festival_area_osm.xml"

# Karja/Kalda centre-line intersection.  The festival map and StreetMap both
# use this southern end of the represented Karja section as their start.
ORIGIN_LON_LAT = (23.5362231, 58.9465648)

# Godot horizontal crop in metres: X east, Z south.  It covers the complete
# festival diagram, including Ehte's western arm, the Lossiplats/Karja
# north-east arm, and a background-building margin.  Sheet 62371 spans local
# X -3304.7..1695.3 and Z -744.1..4255.9, so this still fits one DTM tile.
CROP_X = (-190.0, 235.0)
CROP_Z = (-320.0, 80.0)

# OSM ways used only as measurement/reference centrelines.  Terrain and
# buildings remain the official Maa-amet datasets.  The IDs are preserved in
# the metrics so a regenerated guide can be audited against the saved XML.
ROUTE_SPECS = {
    "karja": [(1077409051, False)],
    "rootsiturg_loop": [
        (78515554, False),
        (294591644, False),
        (294591655, False),
        (294591647, False),
        (294591650, False),
        (78515531, False),
    ],
    # The supplied festival scope starts at the west edge of Rootsiturg, not at
    # the far western end of Ehte outside the event route.
    "ehte_west": [(27468217, False)],
    "ehte_east": [(78515450, True)],
    "northeast_branch": [
        (4728079, False),
        (78515585, False),
        (313806203, True),
    ],
}

ROUTE_OUTPUTS = {
    "karja": ("route_karja.glb", "Karja", (1.0, 0.18, 0.78, 0.86)),
    "rootsiturg_loop": (
        "route_rootsiturg_loop.glb",
        "RootsiturgLoop",
        (1.0, 0.76, 0.10, 0.90),
    ),
    "ehte_west": ("route_ehte_west.glb", "EhteWest", (0.16, 0.78, 1.0, 0.86)),
    "ehte_east": ("route_ehte_east.glb", "EhteEast", (0.16, 0.78, 1.0, 0.86)),
    "northeast_branch": (
        "route_northeast_branch.glb",
        "NortheastBranch",
        (0.78, 0.38, 1.0, 0.86),
    ),
}

LAVA_PLAZA_WAY = 1467386804
SCALE_REPORT = 2.27

# Existing StreetMap centre-line abstraction, reconstructed without touching
# scripts/street_map.gd.  CELL is 1.28 * 3.6 metres in the source.
CELL = 1.28 * 3.6
VIRTUAL_ROUTE_XZ = [
    (0.0, 0.0),
    (0.0, -25.0 * CELL),
    (-2.0 * CELL, -33.0 * CELL),
    (-2.0 * CELL, -52.5 * CELL),
    (2.5 * CELL, -61.5 * CELL),
]


def lest97(lon_deg: float, lat_deg: float) -> tuple[float, float]:
    """EUREF-EST97 geographic to EPSG:3301 (GRS80 Lambert 2SP)."""
    a = 6378137.0
    inv_f = 298.257222101
    eccentricity = math.sqrt(2.0 / inv_f - 1.0 / (inv_f * inv_f))

    def m(phi: float) -> float:
        return math.cos(phi) / math.sqrt(
            1.0 - eccentricity * eccentricity * math.sin(phi) ** 2
        )

    def t(phi: float) -> float:
        ratio = (1.0 - eccentricity * math.sin(phi)) / (
            1.0 + eccentricity * math.sin(phi)
        )
        return math.tan(math.pi / 4.0 - phi / 2.0) / ratio ** (eccentricity / 2.0)

    phi0 = math.radians(57.51755393055556)
    phi1 = math.radians(59.33333333333334)
    phi2 = math.radians(58.0)
    lam0 = math.radians(24.0)
    phi = math.radians(lat_deg)
    lam = math.radians(lon_deg)
    n = (math.log(m(phi1)) - math.log(m(phi2))) / (
        math.log(t(phi1)) - math.log(t(phi2))
    )
    f_const = m(phi1) / (n * t(phi1) ** n)
    rho = a * f_const * t(phi) ** n
    rho0 = a * f_const * t(phi0) ** n
    theta = n * (lam - lam0)
    return (
        500000.0 + rho * math.sin(theta),
        6375000.0 + rho0 - rho * math.cos(theta),
    )


def sample_dtm(image: Image.Image, east: float, north: float) -> float:
    """Bilinear DTM sample using the GeoTIFF's 1 m pixel-centre convention."""
    u = east - 470000.0 - 0.5
    v = 6535000.0 - north - 0.5
    x0 = max(0, min(image.width - 2, math.floor(u)))
    y0 = max(0, min(image.height - 2, math.floor(v)))
    fx = u - x0
    fy = v - y0
    h00 = float(image.getpixel((x0, y0)))
    h10 = float(image.getpixel((x0 + 1, y0)))
    h01 = float(image.getpixel((x0, y0 + 1)))
    h11 = float(image.getpixel((x0 + 1, y0 + 1)))
    return (
        h00 * (1.0 - fx) * (1.0 - fy)
        + h10 * fx * (1.0 - fy)
        + h01 * (1.0 - fx) * fy
        + h11 * fx * fy
    )


def normalize(v: tuple[float, float, float]) -> tuple[float, float, float]:
    length = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    if length <= 1.0e-12:
        return (0.0, 1.0, 0.0)
    return (v[0] / length, v[1] / length, v[2] / length)


def triangle_normal(
    a: tuple[float, float, float],
    b: tuple[float, float, float],
    c: tuple[float, float, float],
) -> tuple[float, float, float]:
    ab = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
    ac = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
    return normalize(
        (
            ab[1] * ac[2] - ab[2] * ac[1],
            ab[2] * ac[0] - ab[0] * ac[2],
            ab[0] * ac[1] - ab[1] * ac[0],
        )
    )


def write_glb(
    output: Path,
    name: str,
    positions: list[tuple[float, float, float]],
    normals: list[tuple[float, float, float]],
    indices: list[int],
    color: tuple[float, float, float, float],
) -> None:
    """Write a compact, single-mesh glTF 2.0 binary."""
    if not positions or not indices:
        raise RuntimeError(f"Refusing to write empty mesh: {name}")

    pos_blob = b"".join(struct.pack("<3f", *p) for p in positions)
    normal_blob = b"".join(struct.pack("<3f", *n) for n in normals)
    index_blob = b"".join(struct.pack("<I", i) for i in indices)

    def pad4(blob: bytes) -> bytes:
        return blob + b"\0" * ((-len(blob)) % 4)

    pos_offset = 0
    normal_offset = len(pad4(pos_blob))
    index_offset = normal_offset + len(pad4(normal_blob))
    binary = pad4(pos_blob) + pad4(normal_blob) + pad4(index_blob)
    mins = [min(p[i] for p in positions) for i in range(3)]
    maxs = [max(p[i] for p in positions) for i in range(3)]

    document = {
        "asset": {"version": "2.0", "generator": "sauceit2 RealGuide builder"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": name, "mesh": 0}],
        "meshes": [
            {
                "name": name,
                "primitives": [
                    {
                        "attributes": {"POSITION": 0, "NORMAL": 1},
                        "indices": 2,
                        "material": 0,
                        "mode": 4,
                    }
                ],
            }
        ],
        "materials": [
            {
                "name": f"{name}Transparent",
                "pbrMetallicRoughness": {
                    "baseColorFactor": list(color),
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.92,
                },
                "alphaMode": "BLEND",
                "doubleSided": True,
            }
        ],
        "buffers": [{"byteLength": len(binary)}],
        "bufferViews": [
            {
                "buffer": 0,
                "byteOffset": pos_offset,
                "byteLength": len(pos_blob),
                "target": 34962,
            },
            {
                "buffer": 0,
                "byteOffset": normal_offset,
                "byteLength": len(normal_blob),
                "target": 34962,
            },
            {
                "buffer": 0,
                "byteOffset": index_offset,
                "byteLength": len(index_blob),
                "target": 34963,
            },
        ],
        "accessors": [
            {
                "bufferView": 0,
                "componentType": 5126,
                "count": len(positions),
                "type": "VEC3",
                "min": mins,
                "max": maxs,
            },
            {
                "bufferView": 1,
                "componentType": 5126,
                "count": len(normals),
                "type": "VEC3",
            },
            {
                "bufferView": 2,
                "componentType": 5125,
                "count": len(indices),
                "type": "SCALAR",
            },
        ],
    }
    json_blob = json.dumps(document, separators=(",", ":")).encode("utf-8")
    json_blob += b" " * ((-len(json_blob)) % 4)
    total = 12 + 8 + len(json_blob) + 8 + len(binary)
    glb = (
        struct.pack("<III", 0x46546C67, 2, total)
        + struct.pack("<II", len(json_blob), 0x4E4F534A)
        + json_blob
        + struct.pack("<II", len(binary), 0x004E4942)
        + binary
    )
    output.write_bytes(glb)


def read_obj_groups(
    archive: zipfile.ZipFile,
) -> tuple[list[tuple[float, float, float]], dict[str, list[tuple[int, int, int]]], tuple[float, float, float]]:
    fwt = archive.read("hooned_lod2-Haapsalu_linn.fwt").decode("ascii").splitlines()
    offset = tuple(float(line.split()[3]) for line in fwt[:3])
    vertices: list[tuple[float, float, float]] = []
    groups: dict[str, list[tuple[int, int, int]]] = defaultdict(list)
    material = "unassigned"
    text = archive.read("hooned_lod2-Haapsalu_linn.obj").decode("ascii")
    for line in text.splitlines():
        if line.startswith("v "):
            _, x, y, z = line.split()[:4]
            vertices.append((float(x), float(y), float(z)))
        elif line.startswith("usemtl "):
            material = line.split(maxsplit=1)[1]
        elif line.startswith("f "):
            refs = [int(token.split("/", 1)[0]) - 1 for token in line.split()[1:]]
            for i in range(1, len(refs) - 1):
                groups[material].append((refs[0], refs[i], refs[i + 1]))
    return vertices, groups, offset


def build_buildings(
    origin_e: float,
    origin_n: float,
    origin_h: float,
) -> tuple[list[tuple[tuple[float, float], tuple[float, float]]], int, int]:
    with zipfile.ZipFile(BUILDINGS_ZIP) as archive:
        vertices, groups, offset = read_obj_groups(archive)

    world = [
        (v[0] + offset[0], v[1] + offset[1], v[2] + offset[2]) for v in vertices
    ]
    kept: list[list[tuple[int, int, int]]] = []
    for faces in groups.values():
        used = {index for face in faces for index in face}
        xs = [world[i][0] - origin_e for i in used]
        zs = [origin_n - world[i][1] for i in used]
        if (
            max(xs) >= CROP_X[0]
            and min(xs) <= CROP_X[1]
            and max(zs) >= CROP_Z[0]
            and min(zs) <= CROP_Z[1]
        ):
            kept.append(faces)

    positions: list[tuple[float, float, float]] = []
    normals: list[tuple[float, float, float]] = []
    indices: list[int] = []
    plan_edges: set[tuple[tuple[float, float], tuple[float, float]]] = set()
    for faces in kept:
        for face in faces:
            tri = [
                (
                    world[i][0] - origin_e,
                    world[i][2] - origin_h,
                    origin_n - world[i][1],
                )
                for i in face
            ]
            n = triangle_normal(tri[0], tri[1], tri[2])
            base = len(positions)
            positions.extend(tri)
            normals.extend([n, n, n])
            indices.extend((base, base + 1, base + 2))
            for i in range(3):
                a = (round(tri[i][0], 4), round(tri[i][2], 4))
                b = (round(tri[(i + 1) % 3][0], 4), round(tri[(i + 1) % 3][2], 4))
                plan_edges.add((a, b) if a <= b else (b, a))

    write_glb(
        DERIVED / "haapsalu_lod2.glb",
        "HaapsaluLoD2",
        positions,
        normals,
        indices,
        (0.08, 0.68, 1.0, 0.34),
    )
    return list(plan_edges), len(kept), len(indices) // 3


def build_terrain(
    image: Image.Image,
    origin_e: float,
    origin_n: float,
    origin_h: float,
) -> tuple[int, int, int]:
    min_e = origin_e + CROP_X[0]
    max_e = origin_e + CROP_X[1]
    min_n = origin_n - CROP_Z[1]
    max_n = origin_n - CROP_Z[0]
    col0 = max(0, math.floor(min_e - 470000.0))
    col1 = min(image.width - 1, math.ceil(max_e - 470000.0))
    row0 = max(0, math.floor(6535000.0 - max_n))
    row1 = min(image.height - 1, math.ceil(6535000.0 - min_n))
    width = col1 - col0 + 1
    height = row1 - row0 + 1
    crop = image.crop((col0, row0, col1 + 1, row1 + 1))
    heights = [float(value) for value in crop.getdata()]

    def height_at(col: int, row: int) -> float:
        return heights[max(0, min(height - 1, row)) * width + max(0, min(width - 1, col))]

    positions: list[tuple[float, float, float]] = []
    normals: list[tuple[float, float, float]] = []
    for row in range(height):
        north = 6535000.0 - (row0 + row + 0.5)
        for col in range(width):
            east = 470000.0 + col0 + col + 0.5
            h = height_at(col, row)
            dh_dx = (height_at(col + 1, row) - height_at(col - 1, row)) * 0.5
            dh_dz = (height_at(col, row + 1) - height_at(col, row - 1)) * 0.5
            positions.append((east - origin_e, h - origin_h, origin_n - north))
            normals.append(normalize((-dh_dx, 1.0, -dh_dz)))

    indices: list[int] = []
    for row in range(height - 1):
        for col in range(width - 1):
            tl = row * width + col
            tr = tl + 1
            bl = tl + width
            br = bl + 1
            if min(heights[tl], heights[tr], heights[bl], heights[br]) <= -9990.0:
                continue
            indices.extend((tl, bl, tr, tr, bl, br))

    write_glb(
        DERIVED / "haapsalu_dtm_1m.glb",
        "HaapsaluDTM1m",
        positions,
        normals,
        indices,
        (0.20, 0.88, 0.50, 0.20),
    )
    return width, height, len(indices) // 3


def cumulative_lengths(points: list[tuple[float, float]]) -> list[float]:
    result = [0.0]
    for a, b in zip(points, points[1:]):
        result.append(result[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    return result


def point_at_distance(
    points: list[tuple[float, float]], lengths: list[float], distance: float
) -> tuple[tuple[float, float], tuple[float, float]]:
    distance = max(0.0, min(lengths[-1], distance))
    for i in range(len(points) - 1):
        if lengths[i + 1] >= distance:
            span = max(1.0e-9, lengths[i + 1] - lengths[i])
            t = (distance - lengths[i]) / span
            p = (
                points[i][0] + (points[i + 1][0] - points[i][0]) * t,
                points[i][1] + (points[i + 1][1] - points[i][1]) * t,
            )
            tangent = normalize(
                (
                    points[i + 1][0] - points[i][0],
                    0.0,
                    points[i + 1][1] - points[i][1],
                )
            )
            return p, (tangent[0], tangent[2])
    return points[-1], (0.0, -1.0)


def route_widths(
    route: list[tuple[float, float]],
    plan_edges: list[tuple[tuple[float, float], tuple[float, float]]],
) -> list[tuple[float, float]]:
    lengths = cumulative_lengths(route)
    result: list[tuple[float, float]] = []
    for station in range(10, int(lengths[-1]) - 5, 5):
        point, tangent = point_at_distance(route, lengths, float(station))
        normal = (-tangent[1], tangent[0])
        hits: list[float] = []
        for a, b in plan_edges:
            dx = b[0] - a[0]
            dz = b[1] - a[1]
            denominator = normal[0] * dz - normal[1] * dx
            if abs(denominator) < 1.0e-8:
                continue
            apx = a[0] - point[0]
            apz = a[1] - point[1]
            t = (apx * dz - apz * dx) / denominator
            u = (apx * normal[1] - apz * normal[0]) / denominator
            if -1.0e-7 <= u <= 1.0 + 1.0e-7 and abs(t) <= 45.0:
                hits.append(t)
        negative = [hit for hit in hits if hit < -1.0]
        positive = [hit for hit in hits if hit > 1.0]
        if negative and positive:
            width = min(positive) - max(negative)
            if 4.0 <= width <= 45.0:
                result.append((float(station), width))
    return result


def read_osm_geometry() -> dict[int, list[tuple[float, float]]]:
    """Read saved OSM ways as (lon, lat) point lists."""
    root = ET.parse(OSM_XML).getroot()
    nodes = {
        node.attrib["id"]: (float(node.attrib["lon"]), float(node.attrib["lat"]))
        for node in root.findall("node")
    }
    ways: dict[int, list[tuple[float, float]]] = {}
    for way in root.findall("way"):
        points = [
            nodes[ref.attrib["ref"]]
            for ref in way.findall("nd")
            if ref.attrib["ref"] in nodes
        ]
        ways[int(way.attrib["id"])] = points
    return ways


def stitch_way_points(
    ways: dict[int, list[tuple[float, float]]],
    spec: list[tuple[int, bool]],
) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    for way_id, reverse in spec:
        if way_id not in ways:
            raise RuntimeError(f"OSM way {way_id} is missing from {OSM_XML.name}")
        segment = list(reversed(ways[way_id])) if reverse else list(ways[way_id])
        if not segment:
            continue
        if points and math.hypot(
            points[-1][0] - segment[0][0], points[-1][1] - segment[0][1]
        ) > 1.0e-8:
            raise RuntimeError(f"OSM route is not contiguous before way {way_id}")
        points.extend(segment[1:] if points else segment)
    return points


def project_points(
    lon_lat: list[tuple[float, float]], origin_e: float, origin_n: float
) -> tuple[list[tuple[float, float]], list[tuple[float, float]]]:
    projected = [lest97(lon, lat) for lon, lat in lon_lat]
    local = [(east - origin_e, origin_n - north) for east, north in projected]
    return local, projected


def build_route_mesh(
    output_name: str,
    mesh_name: str,
    color: tuple[float, float, float, float],
    route: list[tuple[float, float]],
    projected: list[tuple[float, float]],
    image: Image.Image,
    origin_h: float,
    closed: bool = False,
) -> None:
    if closed and route[0] != route[-1]:
        route = route + [route[0]]
        projected = projected + [projected[0]]
    half_width = 0.62
    left: list[tuple[float, float, float]] = []
    right: list[tuple[float, float, float]] = []
    for i, ((x, z), (east, north)) in enumerate(zip(route, projected)):
        if closed:
            logical_count = len(route) - 1
            logical_i = i % logical_count
            before = route[(logical_i - 1) % logical_count]
            after = route[(logical_i + 1) % logical_count]
        else:
            before = route[max(0, i - 1)]
            after = route[min(len(route) - 1, i + 1)]
        tangent = normalize((after[0] - before[0], 0.0, after[1] - before[1]))
        nx, nz = -tangent[2], tangent[0]
        y = sample_dtm(image, east, north) - origin_h + 0.18
        left.append((x + nx * half_width, y, z + nz * half_width))
        right.append((x - nx * half_width, y, z - nz * half_width))

    positions: list[tuple[float, float, float]] = []
    normals: list[tuple[float, float, float]] = []
    for l, r in zip(left, right):
        positions.extend((l, r))
        normals.extend(((0.0, 1.0, 0.0), (0.0, 1.0, 0.0)))
    indices: list[int] = []
    for i in range(len(route) - 1):
        a = i * 2
        indices.extend((a, a + 2, a + 1, a + 1, a + 2, a + 3))
    write_glb(
        DERIVED / output_name,
        mesh_name,
        positions,
        normals,
        indices,
        color,
    )


def build_routes(
    image: Image.Image,
    origin_e: float,
    origin_n: float,
    origin_h: float,
    ways: dict[int, list[tuple[float, float]]],
) -> dict[str, list[tuple[float, float]]]:
    routes: dict[str, list[tuple[float, float]]] = {}
    for key, spec in ROUTE_SPECS.items():
        lon_lat = stitch_way_points(ways, spec)
        route, projected = project_points(lon_lat, origin_e, origin_n)
        output_name, mesh_name, color = ROUTE_OUTPUTS[key]
        closed = key == "rootsiturg_loop"
        build_route_mesh(
            output_name,
            mesh_name,
            color,
            route,
            projected,
            image,
            origin_h,
            closed=closed,
        )
        if closed and route[0] != route[-1]:
            route.append(route[0])
        routes[key] = route
    return routes


def polygon_area(points: list[tuple[float, float]]) -> float:
    if points and points[0] == points[-1]:
        points = points[:-1]
    return abs(
        sum(
            a[0] * b[1] - b[0] * a[1]
            for a, b in zip(points, points[1:] + points[:1])
        )
    ) * 0.5


def minimum_bounding_dimensions(
    points: list[tuple[float, float]],
) -> tuple[float, float]:
    """Return long/short sides of the minimum-area edge-aligned rectangle."""
    if points and points[0] == points[-1]:
        points = points[:-1]
    best: tuple[float, float, float] | None = None
    for a, b in zip(points, points[1:] + points[:1]):
        angle = math.atan2(b[1] - a[1], b[0] - a[0])
        cosine, sine = math.cos(angle), math.sin(angle)
        rotated = [
            (p[0] * cosine + p[1] * sine, -p[0] * sine + p[1] * cosine)
            for p in points
        ]
        width = max(p[0] for p in rotated) - min(p[0] for p in rotated)
        height = max(p[1] for p in rotated) - min(p[1] for p in rotated)
        candidate = (width * height, max(width, height), min(width, height))
        if best is None or candidate[0] < best[0]:
            best = candidate
    if best is None:
        return 0.0, 0.0
    return best[1], best[2]


def build_lava_plaza(
    image: Image.Image,
    origin_e: float,
    origin_n: float,
    origin_h: float,
    ways: dict[int, list[tuple[float, float]]],
) -> tuple[list[tuple[float, float]], float, float, float]:
    if LAVA_PLAZA_WAY not in ways:
        raise RuntimeError(f"OSM way {LAVA_PLAZA_WAY} is missing from {OSM_XML.name}")
    local, projected = project_points(ways[LAVA_PLAZA_WAY], origin_e, origin_n)
    if local[0] == local[-1]:
        local = local[:-1]
        projected = projected[:-1]
    positions = [
        (
            x,
            sample_dtm(image, east, north) - origin_h + 0.20,
            z,
        )
        for (x, z), (east, north) in zip(local, projected)
    ]
    normals = [(0.0, 1.0, 0.0)] * len(positions)
    indices: list[int] = []
    for i in range(1, len(positions) - 1):
        indices.extend((0, i, i + 1))
    write_glb(
        DERIVED / "lava_plaza.glb",
        "LavaPlaza",
        positions,
        normals,
        indices,
        (1.0, 0.34, 0.08, 0.42),
    )
    area = polygon_area(local)
    long_side, short_side = minimum_bounding_dimensions(local)
    return local, area, long_side, short_side


def percentile(values: list[float], q: float) -> float:
    if not values:
        return float("nan")
    ordered = sorted(values)
    index = (len(ordered) - 1) * q
    lo = math.floor(index)
    hi = math.ceil(index)
    if lo == hi:
        return ordered[lo]
    return ordered[lo] * (hi - index) + ordered[hi] * (index - lo)


def main() -> None:
    DERIVED.mkdir(parents=True, exist_ok=True)
    image = Image.open(DTM_TIF)
    if image.size != (5000, 5000) or image.mode != "F":
        raise RuntimeError(f"Unexpected DTM format: {image.size}, mode={image.mode}")

    origin_e, origin_n = lest97(*ORIGIN_LON_LAT)
    origin_h = sample_dtm(image, origin_e, origin_n)
    plan_edges, building_count, building_triangles = build_buildings(
        origin_e, origin_n, origin_h
    )
    terrain_width, terrain_height, terrain_triangles = build_terrain(
        image, origin_e, origin_n, origin_h
    )
    ways = read_osm_geometry()
    routes = build_routes(image, origin_e, origin_n, origin_h, ways)
    lava_points, lava_area, lava_long, lava_short = build_lava_plaza(
        image, origin_e, origin_n, origin_h, ways
    )

    route_lengths = {
        key: cumulative_lengths(points)[-1] for key, points in routes.items()
    }
    route_total = sum(route_lengths.values())
    comparison_lon_lat = stitch_way_points(
        ways,
        [(1077409051, False), (78515554, False), (294591644, False)],
    )
    comparison_route, _ = project_points(comparison_lon_lat, origin_e, origin_n)
    real_lengths = cumulative_lengths(comparison_route)
    virtual_lengths = cumulative_lengths(VIRTUAL_ROUTE_XZ)
    # Keep the documented 13.8 m figure comparable with the first guide: it is
    # measured on the 204 m Karja-to-Rootsiturg main axis, including its north
    # bend, rather than on the newly added branches or inside the plaza loop.
    widths = route_widths(comparison_route, plan_edges)
    width_values = [width for _, width in widths]

    real_saue = routes["karja"][5]
    virtual_saue, _ = point_at_distance(VIRTUAL_ROUTE_XZ, virtual_lengths, 0.5 * (25.0 + 33.0) * CELL)
    real_head = routes["karja"][-1]
    virtual_head = VIRTUAL_ROUTE_XZ[3]
    real_end = comparison_route[-1]
    virtual_end = VIRTUAL_ROUTE_XZ[-1]

    metrics = {
        "source": {
            "authority": "Maa- ja Ruumiamet (Estonian Land and Spatial Development Board)",
            "crs": "EPSG:3301 (L-EST97), metres",
            "lod2_format": "Wavefront OBJ + MTL + FWT + PRJ (ZIP)",
            "dtm_format": "GeoTIFF, float32, 1 m, map sheet 62371",
            "route_measurement_aid": "OpenStreetMap saved XML, fetched 2026-09-21",
            "route_way_ids": {
                key: [way_id for way_id, _ in spec]
                for key, spec in ROUTE_SPECS.items()
            },
        },
        "origin": {
            "description": "Karja/Kalda centre-line intersection",
            "longitude": ORIGIN_LON_LAT[0],
            "latitude": ORIGIN_LON_LAT[1],
            "epsg3301_easting_m": origin_e,
            "epsg3301_northing_m": origin_n,
            "dtm_height_m": origin_h,
            "godot_axis_mapping": "X=east-origin_e, Y=height-origin_h, Z=origin_n-north",
        },
        "crop_local_m": {"x": list(CROP_X), "z": list(CROP_Z)},
        "dtm_sheet_coverage": {
            "sheet": "62371",
            "epsg3301_easting_m": [470000.0, 475000.0],
            "epsg3301_northing_m": [6530000.0, 6535000.0],
            "additional_sheets_required": False,
        },
        "output": {
            "lod2_buildings": building_count,
            "lod2_triangles": building_triangles,
            "terrain_grid_vertices": terrain_width * terrain_height,
            "terrain_grid_size": [terrain_width, terrain_height],
            "terrain_triangles": terrain_triangles,
        },
        "festival_routes": {
            "scale": 1.0,
            "lengths_m": route_lengths,
            "total_m": route_total,
            "scaled_2_27": {
                "factor": SCALE_REPORT,
                "lengths_m": {
                    key: length * SCALE_REPORT
                    for key, length in route_lengths.items()
                },
                "total_m": route_total * SCALE_REPORT,
            },
        },
        "lava_plaza": {
            "basis": (
                "OSM way 1467386804 grass footprint at the LAVA position shown "
                "on the supplied festival diagram; reference overlay, not an "
                "official event production boundary"
            ),
            "local_outline_xz_m": [list(point) for point in lava_points],
            "minimum_bounding_rectangle_m": [lava_long, lava_short],
            "area_m2": lava_area,
            "scaled_2_27": {
                "dimensions_m": [lava_long * SCALE_REPORT, lava_short * SCALE_REPORT],
                "area_m2": lava_area * SCALE_REPORT * SCALE_REPORT,
            },
        },
        "width_measurement": {
            "street": "Karja-to-Rootsiturg 204 m comparison axis",
            "definition": (
                "nearest opposing Maa-amet LoD2 building-envelope intersections "
                "on a line perpendicular to the OSM centreline; includes carriageway "
                "and sidewalks/open frontage, not carriageway width"
            ),
            "sampling": "every 5 m from station 10 m; valid opposing hits 1..45 m from centreline",
            "valid_samples": len(width_values),
            "median_m": percentile(width_values, 0.5),
            "p10_m": percentile(width_values, 0.1),
            "p90_m": percentile(width_values, 0.9),
            "samples_m": [[station, width] for station, width in widths],
        },
        "comparison": {
            "real_route_length_m": real_lengths[-1],
            "existing_route_length_m": virtual_lengths[-1],
            "existing_to_real_length_ratio": virtual_lengths[-1] / real_lengths[-1],
            "width_samples": len(width_values),
            "real_facade_width_median_m": percentile(width_values, 0.5),
            "real_facade_width_p10_m": percentile(width_values, 0.1),
            "real_facade_width_p90_m": percentile(width_values, 0.9),
            "existing_uniform_width_m": 8.0 * CELL,
            "existing_minus_real_median_width_m": 8.0 * CELL - percentile(width_values, 0.5),
            "key_positions": {
                "saue_junction": {
                    "real_station_m": real_lengths[5],
                    "existing_station_m": 0.5 * (25.0 + 33.0) * CELL,
                    "station_difference_existing_minus_real_m": 0.5 * (25.0 + 33.0) * CELL - real_lengths[5],
                    "real_local_xz_m": list(real_saue),
                    "existing_local_xz_m": list(virtual_saue),
                },
                "rootsiturg_bend_entry": {
                    "real_station_m": real_lengths[10],
                    "existing_station_m": virtual_lengths[3],
                    "station_difference_existing_minus_real_m": virtual_lengths[3] - real_lengths[10],
                    "real_local_xz_m": list(real_head),
                    "existing_local_xz_m": list(virtual_head),
                },
                "route_end": {
                    "real_local_xz_m": list(real_end),
                    "existing_local_xz_m": list(virtual_end),
                    "plan_offset_m": math.hypot(real_end[0] - virtual_end[0], real_end[1] - virtual_end[1]),
                },
            },
            "width_station_samples_m": [[station, width] for station, width in widths],
        },
    }
    (DERIVED / "real_guide_metrics.json").write_text(
        json.dumps(metrics, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(json.dumps(metrics, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
