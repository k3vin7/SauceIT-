#!/usr/bin/env python3
"""Build isolated 45 m corridor assets for the two scale-test scenes.

The wide RealGuide assets are deliberately not touched.  Buildings are kept as
individual glTF nodes so Godot can reclassify them when the exported corridor
distance changes.  The node name stores the exact minimum plan distance to the
selected Karja + Rootsiturg centreline network.
"""

from __future__ import annotations

import importlib.util
import json
import math
import struct
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE_PATH = ROOT / "tools" / "real_guide" / "build_real_guide.py"
SPEC = importlib.util.spec_from_file_location("real_guide_base", BASE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Cannot load {BASE_PATH}")
base = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(base)

OUTPUT = ROOT / "assets" / "scale_tests"
DEFAULT_CORRIDOR_M = 45.0
SELECTED_KEYS = ("karja", "rootsiturg_loop")


def pad4(blob: bytes) -> bytes:
    return blob + b"\0" * ((-len(blob)) % 4)


def point_segment_distance(
    point: tuple[float, float],
    a: tuple[float, float],
    b: tuple[float, float],
) -> float:
    vx, vz = b[0] - a[0], b[1] - a[1]
    wx, wz = point[0] - a[0], point[1] - a[1]
    denominator = vx * vx + vz * vz
    t = 0.0 if denominator <= 1.0e-12 else (wx * vx + wz * vz) / denominator
    t = max(0.0, min(1.0, t))
    return math.hypot(point[0] - (a[0] + vx * t), point[1] - (a[1] + vz * t))


def cross(
    a: tuple[float, float],
    b: tuple[float, float],
    c: tuple[float, float],
) -> float:
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def segments_intersect(
    a: tuple[float, float],
    b: tuple[float, float],
    c: tuple[float, float],
    d: tuple[float, float],
) -> bool:
    ab_c, ab_d = cross(a, b, c), cross(a, b, d)
    cd_a, cd_b = cross(c, d, a), cross(c, d, b)
    return (
        min(ab_c, ab_d) <= 1.0e-9 <= max(ab_c, ab_d)
        and min(cd_a, cd_b) <= 1.0e-9 <= max(cd_a, cd_b)
    )


def segment_distance(
    a: tuple[float, float],
    b: tuple[float, float],
    c: tuple[float, float],
    d: tuple[float, float],
) -> float:
    if segments_intersect(a, b, c, d):
        return 0.0
    return min(
        point_segment_distance(a, c, d),
        point_segment_distance(b, c, d),
        point_segment_distance(c, a, b),
        point_segment_distance(d, a, b),
    )


def route_segments(
    routes: dict[str, list[tuple[float, float]]],
) -> list[tuple[tuple[float, float], tuple[float, float]]]:
    result: list[tuple[tuple[float, float], tuple[float, float]]] = []
    for key in SELECTED_KEYS:
        points = routes[key]
        if key == "rootsiturg_loop" and points[0] != points[-1]:
            points = points + [points[0]]
        result.extend(zip(points, points[1:]))
    return result


def point_route_distance(
    point: tuple[float, float],
    segments: list[tuple[tuple[float, float], tuple[float, float]]],
) -> float:
    return min(point_segment_distance(point, a, b) for a, b in segments)


def edge_route_distance(
    edge: tuple[tuple[float, float], tuple[float, float]],
    segments: list[tuple[tuple[float, float], tuple[float, float]]],
) -> float:
    return min(segment_distance(edge[0], edge[1], a, b) for a, b in segments)


def write_multi_mesh_glb(
    output: Path,
    root_name: str,
    meshes_data: list[
        tuple[
            str,
            list[tuple[float, float, float]],
            list[tuple[float, float, float]],
            list[int],
        ]
    ],
    color: tuple[float, float, float, float],
) -> None:
    binary = b""
    buffer_views: list[dict[str, int]] = []
    accessors: list[dict[str, object]] = []
    meshes: list[dict[str, object]] = []
    nodes: list[dict[str, object]] = [{"name": root_name, "children": []}]

    for mesh_index, (name, positions, normals, indices) in enumerate(meshes_data):
        blobs = (
            (b"".join(struct.pack("<3f", *p) for p in positions), 34962),
            (b"".join(struct.pack("<3f", *n) for n in normals), 34962),
            (b"".join(struct.pack("<I", i) for i in indices), 34963),
        )
        accessor_base = len(accessors)
        for blob, target in blobs:
            offset = len(binary)
            binary += pad4(blob)
            buffer_views.append(
                {
                    "buffer": 0,
                    "byteOffset": offset,
                    "byteLength": len(blob),
                    "target": target,
                }
            )
        mins = [min(p[i] for p in positions) for i in range(3)]
        maxs = [max(p[i] for p in positions) for i in range(3)]
        accessors.extend(
            [
                {
                    "bufferView": len(buffer_views) - 3,
                    "componentType": 5126,
                    "count": len(positions),
                    "type": "VEC3",
                    "min": mins,
                    "max": maxs,
                },
                {
                    "bufferView": len(buffer_views) - 2,
                    "componentType": 5126,
                    "count": len(normals),
                    "type": "VEC3",
                },
                {
                    "bufferView": len(buffer_views) - 1,
                    "componentType": 5125,
                    "count": len(indices),
                    "type": "SCALAR",
                },
            ]
        )
        meshes.append(
            {
                "name": name,
                "primitives": [
                    {
                        "attributes": {
                            "POSITION": accessor_base,
                            "NORMAL": accessor_base + 1,
                        },
                        "indices": accessor_base + 2,
                        "material": 0,
                        "mode": 4,
                    }
                ],
            }
        )
        nodes.append({"name": name, "mesh": mesh_index})
        nodes[0]["children"].append(mesh_index + 1)

    document = {
        "asset": {"version": "2.0", "generator": "sauceit2 corridor builder"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": nodes,
        "meshes": meshes,
        "materials": [
            {
                "name": "OpaqueWhiteGraybox",
                "pbrMetallicRoughness": {
                    "baseColorFactor": list(color),
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.9,
                },
                "alphaMode": "OPAQUE",
                "doubleSided": True,
            }
        ],
        "buffers": [{"byteLength": len(binary)}],
        "bufferViews": buffer_views,
        "accessors": accessors,
    }
    json_blob = json.dumps(document, separators=(",", ":")).encode("utf-8")
    json_blob += b" " * ((-len(json_blob)) % 4)
    total = 12 + 8 + len(json_blob) + 8 + len(binary)
    output.write_bytes(
        struct.pack("<III", 0x46546C67, 2, total)
        + struct.pack("<II", len(json_blob), 0x4E4F534A)
        + json_blob
        + struct.pack("<II", len(binary), 0x004E4942)
        + binary
    )


def load_routes(
    origin_e: float, origin_n: float
) -> dict[str, list[tuple[float, float]]]:
    ways = base.read_osm_geometry()
    result: dict[str, list[tuple[float, float]]] = {}
    for key in SELECTED_KEYS:
        points = base.stitch_way_points(ways, base.ROUTE_SPECS[key])
        result[key], _ = base.project_points(points, origin_e, origin_n)
    return result


def build_buildings(
    origin_e: float,
    origin_n: float,
    origin_h: float,
    segments: list[tuple[tuple[float, float], tuple[float, float]]],
) -> tuple[list[dict[str, object]], list[tuple[tuple[float, float], tuple[float, float]]]]:
    with zipfile.ZipFile(base.BUILDINGS_ZIP) as archive:
        vertices, groups, offset = base.read_obj_groups(archive)
    world = [
        (v[0] + offset[0], v[1] + offset[1], v[2] + offset[2]) for v in vertices
    ]
    output_meshes = []
    manifest: list[dict[str, object]] = []
    plan_edges: set[tuple[tuple[float, float], tuple[float, float]]] = set()
    building_index = 0
    for material, faces in groups.items():
        used = {index for face in faces for index in face}
        xs = [world[i][0] - origin_e for i in used]
        zs = [origin_n - world[i][1] for i in used]
        if not (
            max(xs) >= base.CROP_X[0]
            and min(xs) <= base.CROP_X[1]
            and max(zs) >= base.CROP_Z[0]
            and min(zs) <= base.CROP_Z[1]
        ):
            continue

        positions: list[tuple[float, float, float]] = []
        normals: list[tuple[float, float, float]] = []
        indices: list[int] = []
        building_edges: set[tuple[tuple[float, float], tuple[float, float]]] = set()
        for face in faces:
            tri = [
                (
                    world[i][0] - origin_e,
                    world[i][2] - origin_h,
                    origin_n - world[i][1],
                )
                for i in face
            ]
            normal = base.triangle_normal(tri[0], tri[1], tri[2])
            first = len(positions)
            positions.extend(tri)
            normals.extend((normal, normal, normal))
            indices.extend((first, first + 1, first + 2))
            for i in range(3):
                a = (round(tri[i][0], 4), round(tri[i][2], 4))
                b = (round(tri[(i + 1) % 3][0], 4), round(tri[(i + 1) % 3][2], 4))
                edge = (a, b) if a <= b else (b, a)
                building_edges.add(edge)
                plan_edges.add(edge)

        distance = min(edge_route_distance(edge, segments) for edge in building_edges)
        encoded = f"{distance:07.3f}".replace(".", "p")
        name = f"Building_{building_index:03d}_d{encoded}"
        output_meshes.append((name, positions, normals, indices))
        manifest.append(
            {
                "name": name,
                "source_material": material,
                "corridor_distance_m": distance,
                "inside_default": distance <= DEFAULT_CORRIDOR_M,
            }
        )
        building_index += 1

    write_multi_mesh_glb(
        OUTPUT / "corridor_buildings.glb",
        "CorridorBuildings",
        output_meshes,
        (0.93, 0.93, 0.93, 1.0),
    )
    return manifest, list(plan_edges)


def build_terrain(
    image,
    origin_e: float,
    origin_n: float,
    origin_h: float,
    segments: list[tuple[tuple[float, float], tuple[float, float]]],
    bounds: dict[str, list[float]],
) -> tuple[int, int, int]:
    min_x, max_x = bounds["x"]
    min_z, max_z = bounds["z"]
    min_e, max_e = origin_e + min_x, origin_e + max_x
    min_n, max_n = origin_n - max_z, origin_n - min_z
    col0 = max(0, math.floor(min_e - 470000.0))
    col1 = min(image.width - 1, math.ceil(max_e - 470000.0))
    row0 = max(0, math.floor(6535000.0 - max_n))
    row1 = min(image.height - 1, math.ceil(6535000.0 - min_n))
    width, height = col1 - col0 + 1, row1 - row0 + 1
    crop = image.crop((col0, row0, col1 + 1, row1 + 1))
    heights = [float(value) for value in crop.getdata()]

    def height_at(col: int, row: int) -> float:
        row = max(0, min(height - 1, row))
        col = max(0, min(width - 1, col))
        return heights[row * width + col]

    positions: list[tuple[float, float, float]] = []
    normals: list[tuple[float, float, float]] = []
    for row in range(height):
        north = 6535000.0 - (row0 + row + 0.5)
        for col in range(width):
            east = 470000.0 + col0 + col + 0.5
            dh_dx = (height_at(col + 1, row) - height_at(col - 1, row)) * 0.5
            dh_dz = (height_at(col, row + 1) - height_at(col, row - 1)) * 0.5
            positions.append((east - origin_e, height_at(col, row) - origin_h, origin_n - north))
            normals.append(base.normalize((-dh_dx, 1.0, -dh_dz)))

    indices: list[int] = []
    for row in range(height - 1):
        north = 6535000.0 - (row0 + row + 1.0)
        for col in range(width - 1):
            east = 470000.0 + col0 + col + 1.0
            centre = (east - origin_e, origin_n - north)
            if point_route_distance(centre, segments) > DEFAULT_CORRIDOR_M:
                continue
            tl = row * width + col
            tr, bl, br = tl + 1, tl + width, tl + width + 1
            if min(heights[tl], heights[tr], heights[bl], heights[br]) <= -9990.0:
                continue
            indices.extend((tl, bl, tr, tr, bl, br))

    base.write_glb(
        OUTPUT / "corridor_terrain.glb",
        "CorridorTerrain",
        positions,
        normals,
        indices,
        (0.72, 0.72, 0.72, 1.0),
    )
    return width, height, len(indices) // 3


def build_routes_mesh(
    image,
    origin_e: float,
    origin_n: float,
    origin_h: float,
    routes: dict[str, list[tuple[float, float]]],
) -> None:
    positions: list[tuple[float, float, float]] = []
    normals: list[tuple[float, float, float]] = []
    indices: list[int] = []
    half_width = 0.38
    for key in SELECTED_KEYS:
        points = routes[key]
        if key == "rootsiturg_loop" and points[0] != points[-1]:
            points = points + [points[0]]
        left, right = [], []
        for i, (x, z) in enumerate(points):
            before, after = points[max(0, i - 1)], points[min(len(points) - 1, i + 1)]
            tangent = base.normalize((after[0] - before[0], 0.0, after[1] - before[1]))
            nx, nz = -tangent[2], tangent[0]
            east, north = origin_e + x, origin_n - z
            y = base.sample_dtm(image, east, north) - origin_h + 0.12
            left.append((x + nx * half_width, y, z + nz * half_width))
            right.append((x - nx * half_width, y, z - nz * half_width))
        first = len(positions)
        for a, b in zip(left, right):
            positions.extend((a, b))
            normals.extend(((0.0, 1.0, 0.0), (0.0, 1.0, 0.0)))
        for i in range(len(points) - 1):
            a = first + i * 2
            indices.extend((a, a + 2, a + 1, a + 1, a + 2, a + 3))
    base.write_glb(
        OUTPUT / "corridor_routes.glb",
        "SelectedRoutes",
        positions,
        normals,
        indices,
        (0.12, 0.12, 0.12, 1.0),
    )


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    image = base.Image.open(base.DTM_TIF)
    origin_e, origin_n = base.lest97(*base.ORIGIN_LON_LAT)
    origin_h = base.sample_dtm(image, origin_e, origin_n)
    routes = load_routes(origin_e, origin_n)
    segments = route_segments(routes)
    all_points = [point for key in SELECTED_KEYS for point in routes[key]]
    route_bounds = {
        "x": [min(p[0] for p in all_points), max(p[0] for p in all_points)],
        "z": [min(p[1] for p in all_points), max(p[1] for p in all_points)],
    }
    corridor_bounds = {
        "x": [route_bounds["x"][0] - DEFAULT_CORRIDOR_M, route_bounds["x"][1] + DEFAULT_CORRIDOR_M],
        "z": [route_bounds["z"][0] - DEFAULT_CORRIDOR_M, route_bounds["z"][1] + DEFAULT_CORRIDOR_M],
    }
    manifest, plan_edges = build_buildings(origin_e, origin_n, origin_h, segments)
    terrain_width, terrain_height, terrain_triangles = build_terrain(
        image, origin_e, origin_n, origin_h, segments, corridor_bounds
    )
    build_routes_mesh(image, origin_e, origin_n, origin_h, routes)

    route_lengths = {
        key: base.cumulative_lengths(
            points + ([points[0]] if key == "rootsiturg_loop" and points[0] != points[-1] else [])
        )[-1]
        for key, points in routes.items()
    }
    widths: list[tuple[str, float, float, tuple[float, float]]] = []
    for key, points in routes.items():
        if key == "rootsiturg_loop" and points[0] != points[-1]:
            points = points + [points[0]]
        lengths = base.cumulative_lengths(points)
        for station, width in base.route_widths(points, plan_edges):
            point, _ = base.point_at_distance(points, lengths, station)
            widths.append((key, station, width, point))
    width_values = [item[2] for item in widths]
    widest = max(widths, key=lambda item: item[2])
    total_length = sum(route_lengths.values())
    inside = sum(bool(item["inside_default"]) for item in manifest)
    scale_factors = {"test_scale_227": 2.27, "test_scale_180": 1.8}
    metrics = {
        "selected_routes": list(SELECTED_KEYS),
        "corridor_distance_m": DEFAULT_CORRIDOR_M,
        "route_bounds_local_xz_m": route_bounds,
        "corridor_bounds_local_xz_m": corridor_bounds,
        "buildings": {
            "total_wide_source": len(manifest),
            "inside_corridor": inside,
            "row3_outside": len(manifest) - inside,
            "classification": "minimum LoD2 plan-edge distance to either selected centreline",
        },
        "terrain": {
            "grid_size": [terrain_width, terrain_height],
            "triangles_inside_corridor": terrain_triangles,
        },
        "lengths_1x_m": route_lengths,
        "selected_total_1x_m": total_length,
        "widths_1x_m": {
            "combined_median": base.percentile(width_values, 0.5),
            "karja_reference_median": 13.800010415966568,
            "maximum": widest[2],
            "maximum_route": widest[0],
            "maximum_station_m": widest[1],
            "maximum_local_xz_m": list(widest[3]),
            "valid_samples": len(width_values),
        },
        "scale_tests": {
            name: {
                "factor": factor,
                "selected_total_m": total_length * factor,
                "combined_median_width_m": base.percentile(width_values, 0.5) * factor,
                "maximum_width_m": widest[2] * factor,
                "maximum_local_xz_m": [widest[3][0] * factor, widest[3][1] * factor],
                "route_bounds_local_xz_m": {
                    axis: [value * factor for value in limits]
                    for axis, limits in route_bounds.items()
                },
            }
            for name, factor in scale_factors.items()
        },
        "building_manifest": manifest,
    }
    (OUTPUT / "corridor_metrics.json").write_text(
        json.dumps(metrics, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(json.dumps({key: value for key, value in metrics.items() if key != "building_manifest"}, indent=2))


if __name__ == "__main__":
    main()
