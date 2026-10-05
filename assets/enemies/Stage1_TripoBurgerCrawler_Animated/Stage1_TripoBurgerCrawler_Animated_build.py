"""Validate and export the user-authored Tripo burger crawler animation.

The canonical source is ``Stage1_TripoBurgerCrawler_Animated.blend`` beside
this script. That file contains the user's revised Crawl performance: broad
recovery arcs, a long rearward/inward pull, evaluated palm-down ground contact,
and the original hand-slam attack. This script intentionally does not rebuild
or replace that authored action. It provides a deterministic validation and
GLB export path for the game project.

Run with Blender 5.2:
    blender --background --factory-startup --python Stage1_TripoBurgerCrawler_Animated_build.py
"""

from math import isfinite
from pathlib import Path

import bpy


HERE = Path(__file__).resolve().parent
BLEND_PATH = HERE / "Stage1_TripoBurgerCrawler_Animated.blend"
RUNTIME_PATH = HERE.parent / "hamburger_monster" / "hamburger_monster.glb"
FPS = 24
REQUIRED_BONES = {
    "Root", "Body",
    "UpperArm.L", "Forearm.L", "Hand.L", "Hand_IK.L", "ElbowPole.L",
    "UpperArm.R", "Forearm.R", "Hand.R", "Hand_IK.R", "ElbowPole.R",
}
ACTION_SPECS = {
    "Crawl": (1, 49, True),
    "Attack_GroundSlam": (1, 36, False),
    "Death": (1, 56, False),
}


def pose_snapshot(scene, rig, frame):
    scene.frame_set(frame)
    bpy.context.view_layer.update()
    return {
        bone.name: tuple(value for row in bone.matrix for value in row)
        for bone in rig.pose.bones
    }


def maximum_pose_delta(first, second):
    return max(
        abs(a - b)
        for name in first
        for a, b in zip(first[name], second[name])
    )


def validate_action_metadata(actions):
    for name, (start, end, looping) in ACTION_SPECS.items():
        action = actions[name]
        actual = (int(action.frame_start), int(action.frame_end))
        if actual != (start, end):
            raise RuntimeError(f"{name} range is {actual}, expected {(start, end)}")
        if int(action.get("fps", 0)) != FPS:
            raise RuntimeError(f"{name} is missing {FPS} fps metadata")
        if bool(action.get("loop")) != looping:
            raise RuntimeError(f"{name} loop metadata is incorrect")
        if not action.use_fake_user:
            raise RuntimeError(f"{name} has no fake user")

    crawl = actions["Crawl"]
    if int(crawl.get("large_motion_revision", 0)) < 4:
        raise RuntimeError("Crawl is missing the user's large arm-motion revision")
    if int(crawl.get("inward_pull_revision", 0)) < 1:
        raise RuntimeError("Crawl is missing the inward hand pull")
    if "contact Z=0.002m" not in crawl.get("contact_revision", ""):
        raise RuntimeError("Crawl is missing evaluated palm-ground contact")
    attack = actions["Attack_GroundSlam"]
    if int(attack.get("impact_frame", -1)) != 16:
        raise RuntimeError("Attack impact frame is not 16")
    if int(attack.get("strong_slam_revision", 0)) < 1:
        raise RuntimeError("Attack is missing the revised strong hand slam")
    if "two-frame downstroke" not in attack.get("impact_note", ""):
        raise RuntimeError("Attack is missing its revised impact timing metadata")


def validate_scene(scene, rig, meshes, actions):
    if scene.render.fps != FPS:
        raise RuntimeError(f"Scene runs at {scene.render.fps} fps, expected {FPS}")
    if scene.unit_settings.system != "METRIC":
        raise RuntimeError("Scene is not metric")
    if set(rig.data.bones.keys()) != REQUIRED_BONES:
        missing = REQUIRED_BONES - set(rig.data.bones.keys())
        extra = set(rig.data.bones.keys()) - REQUIRED_BONES
        raise RuntimeError(f"Rig bone mismatch; missing={sorted(missing)}, extra={sorted(extra)}")
    for obj in [rig, *meshes]:
        if any(abs(value - 1.0) > 1e-6 for value in obj.scale):
            raise RuntimeError(f"{obj.name} has unapplied scale {tuple(obj.scale)}")
        if obj.type == "MESH":
            modifiers = [modifier for modifier in obj.modifiers if modifier.type == "ARMATURE"]
            if len(modifiers) != 1 or modifiers[0].object != rig:
                raise RuntimeError(f"{obj.name} is not controlled by the intended rig")

    validate_action_metadata(actions)

    rig.animation_data.action = actions["Crawl"]
    if maximum_pose_delta(
        pose_snapshot(scene, rig, 1), pose_snapshot(scene, rig, 49)
    ) > 1e-5:
        raise RuntimeError("Crawl loop seam does not match")

    for name, (start, end, _) in ACTION_SPECS.items():
        rig.animation_data.action = actions[name]
        for frame in range(start, end + 1):
            snapshot = pose_snapshot(scene, rig, frame)
            if not all(isfinite(value) for matrix in snapshot.values() for value in matrix):
                raise RuntimeError(f"{name} contains an invalid transform at frame {frame}")

    rig.animation_data.action = actions["Attack_GroundSlam"]
    impact_16 = pose_snapshot(scene, rig, 16)
    impact_19 = pose_snapshot(scene, rig, 19)
    for bone in ("Hand_IK.L", "Hand_IK.R"):
        if max(abs(a - b) for a, b in zip(impact_16[bone], impact_19[bone])) > 1e-5:
            raise RuntimeError(f"Attack contact drifts for {bone}")

    rig.animation_data.action = actions["Death"]
    if maximum_pose_delta(
        pose_snapshot(scene, rig, 48), pose_snapshot(scene, rig, 56)
    ) > 1e-5:
        raise RuntimeError("Death terminal hold is not stable")


def main():
    if not BLEND_PATH.exists():
        raise FileNotFoundError(BLEND_PATH)
    bpy.ops.wm.open_mainfile(filepath=str(BLEND_PATH), load_ui=False)
    bpy.context.preferences.filepaths.file_preview_type = "NONE"
    scene = bpy.context.scene
    rigs = [obj for obj in scene.objects if obj.type == "ARMATURE"]
    meshes = [obj for obj in scene.objects if obj.type == "MESH"]
    if len(rigs) != 1:
        raise RuntimeError(f"Expected one armature, found {len(rigs)}")
    if len(meshes) != 2:
        raise RuntimeError(f"Expected two skinned meshes, found {len(meshes)}")
    actions = {name: bpy.data.actions.get(name) for name in ACTION_SPECS}
    missing_actions = [name for name, action in actions.items() if action is None]
    if missing_actions:
        raise RuntimeError(f"Missing actions: {missing_actions}")
    rig = rigs[0]
    validate_scene(scene, rig, meshes, actions)

    rig.animation_data.action = actions["Crawl"]
    scene.frame_start = 1
    scene.frame_end = 48
    scene.frame_set(1)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    RUNTIME_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(RUNTIME_PATH),
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_anim_slide_to_zero=True,
        export_materials="EXPORT",
        export_extras=True,
    )
    print("VALIDATED", BLEND_PATH)
    print("EXPORTED", RUNTIME_PATH)
    print("ACTIONS", [(name, ACTION_SPECS[name]) for name in ACTION_SPECS])
    print("CRAWL_REVISION", actions["Crawl"].get("motion_note"))
    print("PULL_SEQUENCE", actions["Crawl"].get("pull_sequence"))
    print("ATTACK_REVISION", actions["Attack_GroundSlam"].get("impact_note"))


if __name__ == "__main__":
    main()
