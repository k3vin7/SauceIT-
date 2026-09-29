class_name MayoTutorial
extends Node

## The opening stretch of the festival street, run as a sequence of stages.
##
## **This builds no new gameplay.** Every beat of it is the game that is already
## here: the toast rushers and the burger are `MayoEnemy`, the fall is the floor's
## own thickness rule met by the existing run check, the top-up is the stall's own
## `refill_for`, the shared damage is the party scaling that was already written.
## What this file adds is *ordering* -- where the bodies stand, which line the
## doctor says next, and when a stage is allowed to end.
##
## The one piece of new behaviour is the drone, and even that leans on the enemy:
## `MayoEnemy.bait` makes the burger walk at the drone through the same router it
## walks at a player with, and refuses it a contact hit while it does.
##
## ## Authority
##
## The server owns the whole sequence. Stage changes, the roster for the first
## fight, who has topped up and when the drone dies are all decided here on the
## authority and pushed out; a client's copy of this node only renders what it is
## told. A client cannot declare a kill or a top-up -- both are read off state the
## server already owns.
##
## ## Tuning
##
## Everything worth moving -- positions, counts, gaps between lines, the drone's
## hover, the zone that triggers it -- is a constant at the top of this file.
## Nothing is buried in the stage code.

const DroneScript := preload("res://scripts/tutorial_drone.gd")

## Set to true **before the world is built** to keep the tutorial out of the way.
##
## Static rather than an export, because the world builds itself in `_ready()` and
## a probe has no chance to set a property before that runs; a probe sets this at
## the top of its own `_run`, before it instantiates the scene. Every existing
## probe does exactly that, so the checks that are about the street and the fight
## still see the street and the fight they were written against.
static var disabled := false


enum Stage {
	## Built, waiting for the world to settle and the party to appear.
	IDLE,
	## The doctor says hello and lights up a spot to walk to. Walking is allowed --
	## it is the thing being taught -- firing is not.
	INTRO,
	## Everyone is on the spot. Controls are held for the length of the briefing,
	## which is the one beat where the player is asked to listen rather than act.
	BRIEF,
	## A. The toast rushers come at the party. Ends when every one of them is down.
	## Controls come back here, which is what "and now you can move and shoot" is.
	FIRST_FIGHT,
	## B. The toasts are down. Controls are held again for one line while the
	## burger is put down behind wherever the party actually ended up.
	MONSTER_CUE,
	## Controls are back, the burger is walking, and the doctor is telling them to
	## get away from it.
	MONSTER_ARRIVES,
	## C. "Shift를 누르고 뛰어요!" -- the party runs, over their own mess.
	RUN,
	## D. The drone flies into the burger's face and holds it there.
	DRONE_BAIT,
	## E. Walk to the marked stall and top up. Ends when everybody has.
	REFILL,
	## F. The warning, then the burger swats the drone out of the air.
	DRONE_DOWN,
	## G. Everyone on the burger. Ends when it goes over.
	COOP_FIGHT,
	## Done, and the controls are still yours.
	COMPLETE,
}


# ---------------------------------------------------------------------------
# Tuning: placement
# ---------------------------------------------------------------------------

## How long after the world exists before the doctor says anything. Long enough
## that the player has their bearings and the street has finished appearing.
const INTRO_DELAY := 1.2

## Where the blue light stands, and how close counts as standing on it.
##
## Up the street from the spawn, in the open, with the whole of Kalda tänav still
## behind the party to back into -- backing away while shooting is the thing the
## opening fight teaches, and it needs somewhere to back to.
const MOVE_TARGET := Vector3(0.0, 0.0, -8.0)
## How close counts as standing on it, for one player. The circle is widened for
## a party: four capsules 1.28 m across cannot all stand inside a 2.4 m ring
## without shoving each other back out of it, which would leave the stage waiting
## on something the party physically cannot do.
const MOVE_REACH := 2.4
const MOVE_REACH_PER_PLAYER := 0.8
## How often the doctor repeats himself while the party stands there.
##
## A re-prompt, not a way out: the stage still ends only on somebody standing on
## the light. It used to hand over on this timer, which marked the lesson learned
## by a player who had not moved a step.
const INTRO_PATIENCE := 45.0
const MOVE_LIGHT_COLOR := Color("4fc3ff")
const MOVE_LIGHT_PULSE_HZ := 0.8
## How long the briefing holds the controls. Short: this is the only place the
## player is asked to stand still, and it is one line long.
const BRIEF_SECONDS := 4.2
## How long the controls stay held after "뒤를 조심하세요!" has actually appeared.
##
## The hold ends on that line rather than on a clock, the same way the blue light
## comes up with its own line: what it is there for is to put the burger down
## behind them while the warning is on screen.
const CUE_LINE_HOLD := 1.0
## And the cap on the whole hold, so a missing caption cannot leave the controls
## held forever.
const MONSTER_CUE_SECONDS := 7.0

## A. Where the rushers come from, as metres up the street from the start. The
## promenade runs north, which is -z, so this is negative.
const RUSHER_LINE_Z := -30.0
## Spread across the road so they arrive as a line rather than a column. One entry
## per body, used in order and wrapped if the party is bigger than the list.
##
## **Kept narrow on purpose.** A rusher charges straight at whoever it is after and
## dies somewhere on the line between its spawn and them, so how far out it starts
## decides how far off that line the mess ends up. At the original 7.5 m the two
## bodies died about 1.7 m either side of the party and left a clean lane straight
## up the middle -- which is exactly the lane a player runs down when the burger
## turns up behind them. Measured: at most 0.75 m of mayo on any escape line, and
## usually none. From 3 m out they die within a metre of it and the puddles meet.
##
## Still spread, and still not a column: the road is 37 m wide, the bodies are
## 1.35 m across, and which player each one comes for is decided separately -- see
## `targets_for`.
const RUSHER_SPREAD_X := [-3.0, 3.0, -1.0, 1.0, -5.0, 5.0]
## How much further back each successive pair starts, so five of them do not
## arrive shoulder to shoulder.
const RUSHER_RANK_Z := -3.4

## B. How far behind the party the burger is put down.
##
## **Behind them, not at a spot on the map.** The opening fight is fought backing
## away and turning, so where the party is facing when it ends is not something
## this file can know in advance -- a fixed spawn put the burger beside them, or
## in front, depending on how the fight went. It is placed relative to the body
## instead: ten metres off their backs, on the ground they have just given up.
##
## **Ten, not five.** At five it was on top of them the moment the warning let go
## of the controls -- they turned round into a burger already inside biting range,
## and the "it is coming for you" beat had nowhere to happen. At ten it takes the
## best part of three seconds to cross, which is the stretch the party spends
## watching it come.
const MONSTER_BEHIND := 10.0
## How close it gets before the doctor tells them to run.
##
## The other half of that stretch: "뒤를 조심하세요!" is said as it is put down,
## and "너무 가까워… 물리겠어요!!" waits until it actually is.
const MONSTER_CLOSE := 3.0
## If straight behind lands somewhere nothing can stand -- inside a stall, off the
## end of the street a party has backed into -- the spawn is swung around the back
## arc in these steps, and only then brought closer.
const MONSTER_ARC_STEPS := [0.0, 22.0, -22.0, 45.0, -45.0, 70.0, -70.0, 90.0, -90.0]
const MONSTER_CLEAR_STEP := 0.8
## Never nearer than this, whatever the search turns up. The burger is 1.7 m of
## body on its own, so anything closer is spawning it inside them -- which is how
## the first version failed when a party backed all the way down Kalda tänav and
## there was nothing behind them at all.
const MONSTER_NEAREST := 5.0

## C/D. What counts as "in the dangerous bit".
##
## **Asked of the floor, not of a circle drawn here.** Where the mess ends up is
## wherever the fight ended up, and the rushers charge -- so they die on top of
## whoever they were charging, not on a spot picked in advance. A fixed circle up
## the street was simply in the wrong place: the party stood in a lake of mayo and
## the sequence waited for them to walk to an empty stretch of road. Reading
## `is_slippery_at` off the same grid the shader draws means the stage triggers on
## the danger the player can actually see under their feet, wherever it formed.
##
## How far outside its own bite the burger has to be for the drone to come.
##
## **Measured off the body, not written down.** The burger reaches as far as both
## capsules' radii plus the reach that stands in for its arms -- about 2.9 m --
## and this is the margin on top.
##
## **Zero on purpose.** The run prompt already fires at `MONSTER_CLOSE`, which is
## further out than the burger's own reach -- so anything but zero here would put
## the drone in before the player had even been told to run. At zero this means
## "it is on them", which is the player who ignored the prompt; the ordinary cue
## for the drone is the fall, not this.
const DRONE_RESCUE_MARGIN := 0.0
## How often the doctor repeats the order to run, while nothing is happening.
##
## **The escape stage has no timer that ends it.** It ends on what the party does:
## somebody goes over, or somebody crosses the mess and gets clear. A player who
## does neither is being waited for, and what that deserves is the instruction
## again -- not the next stage handed to them for standing still, which is what a
## patience timer here amounted to.
const RUN_REPROMPT_SECONDS := 9.0
## How far from the burger counts as "got clear on their own feet". Stepping off
## the yellow with the thing still on your heels is not having got away with it.
const DODGE_SAFE_GAP := 12.0

## E. Roughly where the stall we send people to should be, used to pick one before
## the fight has happened. It is an anchor, not a position, so it survives the map
## being re-laid.
##
## It is only the opening guess: the stall is chosen again once the party is
## actually running, off where they have ended up -- see `_pick_station_near`.
const REFILL_ANCHOR := Vector3(6.0, 0.0, -26.0)

## F. Beats between everyone topping up and the drone going down, so the drone
## does not vanish off screen the instant the last bottle is filled.
const DRONE_DOWN_WARN := 2.0
const DRONE_DOWN_TURN := 2.0

# ---------------------------------------------------------------------------
# Tuning: the spill that makes the floor dangerous
# ---------------------------------------------------------------------------

## A dying rusher bursts, and what it leaves is real sauce on the real grid.
##
## Without this the street never gets slippery enough to teach the lesson: nearly
## everything the party fires lands on the *rusher*, not on the road behind it, so
## a fight can end with the floor barely marked. A body splitting open is a cause
## you can see, which is the point -- nothing here is a hidden trigger.
## How big a puddle a bursting body leaves, and how finely it is stamped out.
##
## The spill is laid as a disc of brush stamps. The step is well under the brush's
## own 0.4 m radius on purpose: the brush has a wandering, noisy edge -- which is
## what keeps a splat from looking like a circle -- so stamps spaced at the
## nominal radius leave holes, and a puddle with holes in it is a puddle a running
## player crosses without touching.
##
## Sized so that two bodies dying near each other meet into one stretch of ruined
## road rather than two dots with a dry lane between them.
## Measured: at this radius and step one burst leaves an unbroken 3.4 m of road a
## running player cannot cross without going over, for about 7 ms of the frame it
## happens on. Stepping finer or reaching wider buys very little and costs the
## frame -- 1.9 m at 0.3 m was 13 ms and 516 splats down the wire.
const SPILL_RADIUS := 1.6
const SPILL_STEP := 0.30

## How many times the whole pattern is stamped, which is what sets the thickness.
##
## The stamps overlap far less than their nominal size suggests -- the brush has a
## deliberately noisy, wandering edge -- so most cells end up inside exactly one of
## them and take their whole thickness from this count. At one layer the puddle
## measured 17% of its own footprint and a running player went straight through
## the gaps.
##
## It has to clear `FloorContamination.slip_thickness`, and `tutorial_spill_sauce`
## enforces that rather than trusting this number: a puddle the party can see and
## cannot slip on would be the worst of both.
const SPILL_LAYERS := 3

# ---------------------------------------------------------------------------
# Tuning: the drone
# ---------------------------------------------------------------------------

## How high up the drone holds, measured from the burger's feet. Just above the
## top of a 4.1 m burger, so it is silhouetted against the sky rather than lost
## against the body.
const DRONE_FACE_HEIGHT := 4.4
## How far the drone pulls the burger away from the party before holding it there.
##
## **It holds a fixed spot, not a spot in front of the burger's nose.** Hovering
## relative to the body's own facing makes it chase its own face: it walks
## forward, the target moves forward with it, and it wanders off down the street
## for as long as the bait lasts -- which then leaves it too far away to notice
## anybody once the drone is gone. Anchoring the hover is what makes "distracted"
## mean standing there swiping at something.
const DRONE_LEAD := 6.0
## The circle it flies round that spot, which is what the burger keeps turning to
## follow. This is the "dodging rather than sitting still" part.
##
## **Wider than the burger is.** At 1.7 m the burger -- which is 1.7 m of
## half-width on its own -- simply walked onto the drone and stood there with it
## inside its head, which reads as a bug rather than as being harried. Circling
## outside its reach keeps the drone where the party can see it and keeps the
## burger turning after it.
const DRONE_ORBIT_RADIUS := 3.6
const DRONE_ORBIT_HZ := 0.3
## Bob, so it reads as flying rather than pinned.
const DRONE_BOB := 0.35
const DRONE_BOB_HZ := 1.6
## How quickly it slides to where it should be once it is on station. It is a
## fast little machine, but snapping would make it look attached to the head.
const DRONE_FOLLOW := 7.0
## And how fast it crosses the street on the way in, in metres a second.
##
## A speed rather than the smoothing above: exponential following covers nine
## tenths of the distance in the first fifth of a second, so the flight in was
## over in three frames and the burger turned away from a drone nobody saw
## arrive. At this it is most of a second of something crossing the screen.
const DRONE_FLY_IN_SPEED := 12.0
## Where it comes in from: over the party's own shoulder, so it is seen crossing
## the street into the burger's face rather than appearing already there.
const DRONE_ENTRY_HEIGHT := 7.0
const DRONE_ENTRY_BACK := 9.0
## And how close it has to actually get before the burger will look at it.
##
## **The hand-off is the whole beat.** Setting the bait the instant the node was
## built -- which is what this used to do -- turned the burger away while the
## drone was still a second of flying away and the player had not finished
## turning round: from behind, the thing about to bite them simply lost interest
## for no visible reason. It keeps coming until the drone is genuinely in its
## face, and latches once it is.
const DRONE_GRAB_GAP := 4.5
## And how long the drone will harry it before taking it regardless.
##
## The hand-off wants two things at once: the drone in its face, and the burger
## actually lunging at somebody -- being pulled off a player it was nowhere near
## is the thing that reads as the AI losing interest for no reason. A party that
## keeps running never gives it the second one, so this is the backstop that
## stops the stage hanging on a fight the party has walked away from.
const DRONE_GRAB_PATIENCE := 4.5

# ---------------------------------------------------------------------------
# Tuning: the script
# ---------------------------------------------------------------------------

## The doctor's lines. Only the index travels: every peer has this table, so a
## caption costs one int on the wire and cannot desync from the text.
##
## **Placeholder for voice.** These are captions standing in for spoken lines;
## replacing them with audio means playing a clip alongside the same event.
const LINES := [
	"좋아요, 들리나요? 저는 닥터예요. 이 거리를 되찾아야 해요.",   # 0
	"앞에서 뭔가 와요. 마우스 왼쪽으로 소스를 쏘세요!",             # 1
	"잘했어요!",                                                    # 2
	"어… 이건 무슨 소리지?",                                        # 3
	"뒤를 조심하세요!",                                             # 4
	"저건 못 이겨요. Shift를 누르고 뛰어요!",                       # 5
	"아차, 바닥의 마요네즈! 제가 시선을 끌게요!",                   # 6
	"마요네즈가 두껍게 쌓이면 미끄러워져요.",                       # 7
	"노란 곳에서는 뛰지 말고 천천히 걸어요!",                       # 8
	"옆 매대에 소스가 있어요. E를 눌러 보충하세요!",                # 9
	"좋아요, 병이 가득 찼어요!",                                    # 10
	"드론이 오래 못 버텨요. 준비하세요!",                           # 11
	"앗, 드론이! …이제 저놈이 당신을 봐요.",                        # 12
	"다 같이 쏘세요! 혼자보다 훨씬 빨라요!",                        # 13
	"해냈어요! 첫 번째 구간을 지켰어요.",                           # 14
	"넘어지지 않았네요, 잘 피했어요! 그래도 노란 곳은 조심해요.",   # 15
	"새로 왔군요! 매대에서 E를 눌러 소스를 채우세요.",              # 16
	"WASD로 파란 불빛까지 걸어오세요.",                             # 17
	"거기예요. 잠깐만 들어보세요.",                                 # 18
	"이 거리는 마요네즈에 잠겼어요. 당신 병이 유일한 무기예요.",    # 19
	"너무 가까워… 물리겠어요!!",                                    # 20
	"Shift를 누르고 뒤로 도망쳐요!",                                # 21
]

## Line ids, named so the stage code reads as a script rather than as numbers.
const SAY_HELLO := 0
const SAY_SHOOT := 1
const SAY_WELL_DONE := 2
const SAY_WHAT_NOISE := 3
const SAY_BEHIND_YOU := 4
const SAY_RUN := 5
const SAY_DRONE_IN := 6
const SAY_THICK_IS_SLIPPERY := 7
const SAY_WALK_ON_YELLOW := 8
const SAY_GO_REFILL := 9
const SAY_BOTTLE_FULL := 10
const SAY_DRONE_FAILING := 11
const SAY_DRONE_DOWN := 12
const SAY_ALL_TOGETHER := 13
const SAY_COMPLETE := 14
const SAY_STAYED_UP := 15
const SAY_LATE_JOIN := 16
const SAY_WALK_HERE := 17
const SAY_STAND_STILL := 18
const SAY_BRIEFING := 19
const SAY_TOO_CLOSE := 20
const SAY_RUN_AWAY := 21

## How long a caption stays up, and the gap before the next one is allowed to
## start. One line at a time, always: a stage that wants to say three things says
## them in order rather than stacking them.
const LINE_SECONDS := 3.4
const LINE_GAP := 0.35
## How long a shouted line holds the screen.
##
## Shorter than the rest on purpose. A warning is a shout, and whatever follows it
## is usually the instruction that acts on it -- "너무 가까워… 물리겠어요!!" sitting
## there for the full three and a half seconds meant "Shift를 누르고 뒤로 도망쳐요!"
## did not appear until after the thing had already caught them.
const URGENT_LINE_SECONDS := 1.8

## What a line is *about*, so a line can be withdrawn when it stops being true.
##
## Captions are queued, and a queue outlives the thing it was queued for: the
## order to run went on being shouted at somebody the drone had already saved,
## because nothing knew the order had stopped applying. A tag is the smallest
## thing that fixes that -- an instruction carries one, an explanation does not,
## and the stage that invalidates an instruction cancels that tag.
const TAG_NONE := 0
## "Run." Withdrawn the moment the escape resolves, however it resolved.
const TAG_RUN_ORDER := 1

## What each stage is asking for, shown as the standing objective. Taken from the
## stage rather than sent as a message, which is what makes a mid-session joiner
## work: they are told the stage, and the stage *is* the objective.
const OBJECTIVES := {
	Stage.INTRO: "WASD로 파란 불빛까지 이동하세요",
	Stage.BRIEF: "닥터의 설명을 듣는 중…",
	Stage.FIRST_FIGHT: "앞에서 오는 토스트를 모두 처치하세요",
	Stage.MONSTER_CUE: "뒤를 조심하세요!",
	Stage.MONSTER_ARRIVES: "뒤를 확인하세요",
	Stage.RUN: "Shift로 달려서 거리를 벌리세요",
	Stage.DRONE_BAIT: "닥터가 시간을 벌어주는 동안 이동하세요",
	Stage.REFILL: "표시된 매대에서 E로 소스를 보충하세요",
	Stage.DRONE_DOWN: "전투 준비",
	Stage.COOP_FIGHT: "함께 큰 괴물을 처치하세요",
	Stage.COMPLETE: "구간 완료",
}

## Enemy kinds, as they travel in the spawn message.
const KIND_RUSHER := 0
const KIND_BRUISER := 1


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var world: Node3D

var stage: int = Stage.IDLE
## The rushers this run of the first fight is about, by their index in the world's
## enemy list. **Fixed when the fight starts**: somebody joining mid-fight does
## not add another body, because the roster is what the stage is waiting on.
var fight_enemies: PackedInt32Array = PackedInt32Array()
## The burger, by the same index.
var monster_index := -1
## Peers that have topped up at the marked stall. Server-owned; mirrored to the
## clients so every screen can show the same "waiting for" count.
var supplied: Array[int] = []
var drone_alive := false
## Whether the drone has actually got in its face yet. Separate from `drone_alive`
## because the flight in is a beat of its own -- the burger is still coming for
## the party through all of it.
var drone_has_it := false
## Who went over and was rescued, or 0 for nobody. The dodge branch leaves this
## at 0 on purpose: nothing was rescued, so nothing should be described as having
## been.
var rescue_peer := 0
## Whether the escape ended with somebody crossing the mess on their own feet.
var dodged := false
## Whether a top-up at the marked stall counts yet. Opened when the stall is
## actually pointed out, which is the moment the player can act on it.
var _refill_open := false
## The spot the drone holds the burger at, in world space. Decided by the server
## when the drone arrives and sent with the stage, so every peer draws the drone
## in the same place as the body it is annoying.
var bait_anchor := Vector3.ZERO

## How many captions this peer has been handed, ever. Only ever goes up, and only
## on a caption *event* -- which is what makes it a usable check that an ordinary
## state packet cannot replay a line that has already been said.
var lines_shown := 0

var _drone: Node3D
var _move_light: Node3D
## Where the drone drops in, worked out when it is called for.
var _drone_entry := Vector3.ZERO
## How long the drone has been flying without having its attention yet.
var _drone_age := 0.0
## Slips taken during the escape, as peer -> true. An event log rather than a
## state poll: the floor reports the trip as it happens.
var _escape_slips: Dictionary = {}
## Who has stood on mayo thick enough to go over on, during the escape.
var _touched_mess: Dictionary = {}
var _stage_clock := 0.0
var _clock := 0.0
## Line currently on screen, and how long it has left.
var _line := -1
var _line_left := 0.0
var _line_queue: Array[Array] = []
## What the line on screen is about -- see `TAG_NONE`.
var _line_tag := TAG_NONE
var _line_gap := 0.0
## Which of `fight_enemies` were alive last frame, so a death is an edge rather
## than a state that keeps firing.
var _was_alive := {}
## The stall we send people to: index into the world's station list, plus the
## marker position.
var _station := -1
var _station_position := Vector3.INF
## Set once a player has been seen off their feet, so the doctor's line can
## acknowledge it instead of talking about a fall that never happened.
var _anyone_fell := false
## Guards so each one-shot fires once.
var _said := {}


func _ready() -> void:
	name = "Tutorial"


## Whether this node is in charge at all. Separate from `is_running` because the
## street's standing roster has to be skipped from the very first frame, before
## the sequence has started saying anything.
func is_enabled() -> bool:
	return not disabled


## Whether the party may walk and look about.
##
## Held for exactly two beats, both of them a line long: the briefing, and the
## moment the burger is put down behind them. Everywhere else this is true --
## including all of the opening fight, which is the point of holding it in the
## first place. The camera is never turned for them; it is only asked to wait.
func allows_movement() -> bool:
	return stage != Stage.BRIEF and stage != Stage.MONSTER_CUE


## Whether they may turn the camera.
##
## **Not the same question as walking.** "뒤를 조심하세요!" is a line whose whole
## content is "turn round", and it was being said with the mouse held: the party
## was told to look behind them by the same beat that stopped them looking
## anywhere. Only the briefing takes the camera, and that is one line long.
func allows_looking() -> bool:
	return stage != Stage.BRIEF


## Whether this body is allowed to hurt this player right now.
##
## **Scoped to the one threat the sequence is holding off, and to the stretch it
## is holding it off for.** Everything else on the street bites as it always did.
##
## The burger cannot hurt anybody while the escape is unresolved -- a player being
## asked again to run is a player the sequence is waiting on, and chewing through
## their health while they work it out is not a tutorial -- nor between the moment
## it catches somebody and the moment the drone takes it off them, which is the
## rescue it exists for. The swing still plays; it is the damage that is held.
func allows_contact_damage(enemy: MayoEnemy, player: MayoPlayer) -> bool:
	if disabled or monster_index < 0:
		return true
	if world.call("enemy_at", monster_index) != enemy:
		return true
	if stage == Stage.RUN:
		return false
	if stage == Stage.DRONE_BAIT and not drone_has_it:
		return rescue_peer != 0 and player != null \
			and world.call("shooter_for", rescue_peer) != null \
			and world.call("shooter_for", rescue_peer).player != player
	return true


## Whether the bottle works yet.
##
## Off until the toasts are actually on their way, so the first thing anybody
## fires at is the thing they were told to fire at, and off again through the two
## held beats.
func allows_firing() -> bool:
	if stage == Stage.IDLE or stage == Stage.INTRO or stage == Stage.BRIEF:
		return false
	return stage != Stage.MONSTER_CUE


## Where the blue light is standing, or INF when there is none to walk to.
func move_target() -> Vector3:
	if stage != Stage.INTRO or not _light_is_up():
		return Vector3.INF
	return MOVE_TARGET


## Whether the spot has actually been lit yet. Everything that points at it --
## the marker on screen, the objective line, the stage's own "are they there
## yet" -- waits on this, so none of them can give the instruction away before
## the doctor does.
func _light_is_up() -> bool:
	return _move_light != null and is_instance_valid(_move_light)


## True while the sequence is live and should be drawn. False before it starts and
## when it is switched off, which is how the probes that are about other things
## keep it out of the way.
func is_running() -> bool:
	return not disabled and stage != Stage.IDLE


func is_complete() -> bool:
	return stage == Stage.COMPLETE


func _is_authority() -> bool:
	return world != null and world.call("_is_authority")


# ---------------------------------------------------------------------------
# Frame
# ---------------------------------------------------------------------------

func advance(delta: float) -> void:
	if disabled or world == null:
		return
	_clock += delta
	_stage_clock += delta
	_advance_lines(delta)
	_advance_drone(delta)
	_advance_move_light(delta)
	# Only the server decides what happens next. A client renders the stage it
	# was handed and nothing else.
	if not _is_authority():
		return
	match stage:
		Stage.IDLE:
			if _clock >= INTRO_DELAY and not world.shooter_ids().is_empty():
				_enter(Stage.INTRO)
		Stage.INTRO:
			# Ends on the party standing on the light and on nothing else. It is an
			# instruction, so it is done when it has been followed -- a patience
			# timer here marked the lesson learned by somebody who never moved.
			if _everyone_on_the_light():
				_enter(Stage.BRIEF)
			elif _stage_clock >= INTRO_PATIENCE and _lines_done():
				_stage_clock = 0.0
				_say(SAY_WALK_HERE)
		Stage.BRIEF:
			# The one place the controls are taken, and only for as long as the
			# briefing takes.
			if _lines_done() and _stage_clock >= BRIEF_SECONDS:
				_begin_first_fight()
		Stage.FIRST_FIGHT:
			_watch_fight()
		Stage.MONSTER_CUE:
			# Released a beat after the warning is actually on screen, so the
			# player turns round to a burger that is standing five metres off and
			# only then starts walking -- rather than to one that has already
			# closed the gap while they were being talked at.
			var warned: bool = _line == SAY_BEHIND_YOU \
				and _line_left <= URGENT_LINE_SECONDS - CUE_LINE_HOLD
			if warned or _stage_clock >= MONSTER_CUE_SECONDS:
				_enter(Stage.MONSTER_ARRIVES)
		Stage.MONSTER_ARRIVES:
			# It is walking at them and they are watching it come. Ends far enough
			# out that the order to run arrives with room to act on it -- or at
			# once if somebody has already got on with it, because a party that ran
			# early does not need to be told to start.
			if _monster_within(MONSTER_CLOSE) or not _escape_slips.is_empty():
				_enter(Stage.RUN)
		Stage.RUN:
			_watch_run()
		Stage.DRONE_BAIT:
			# Not just "the doctor stopped talking". The drone has to have actually
			# taken the burger, and whoever went over has to be up and out of the
			# mess -- that is what "it bought you time" means, and it is what the
			# next stage assumes has happened.
			if _lines_done() and drone_has_it and _rescued_is_safe():
				_enter(Stage.REFILL)
		Stage.REFILL:
			_watch_refill()
		Stage.DRONE_DOWN:
			_watch_drone_down(delta)
		Stage.COOP_FIGHT:
			_watch_coop()
		Stage.COMPLETE:
			pass


# ---------------------------------------------------------------------------
# Stages
# ---------------------------------------------------------------------------

func _enter(next: int) -> void:
	if stage == next:
		return
	stage = next
	_stage_clock = 0.0
	match next:
		Stage.INTRO:
			_say(SAY_HELLO)
			# The light is not raised here: it comes up with its own line, a
			# caption later -- see `_line_began`.
			_say(SAY_WALK_HERE)
		Stage.BRIEF:
			_say(SAY_STAND_STILL)
			_say(SAY_BRIEFING)
		Stage.MONSTER_CUE:
			# The footsteps and the line that turns them round, with the body put
			# down behind them while they cannot walk away from it. The warning
			# interrupts whatever was still being said: the hold released off it,
			# so it has to be on screen now rather than whenever the queue drains.
			_stomp()
			_say_now(SAY_BEHIND_YOU)
			_spawn_monster()
		Stage.MONSTER_ARRIVES:
			# Nothing said here. The controls are back, the burger is walking, and
			# this stage is the party turning round and watching it come.
			pass
		Stage.RUN:
			# Not "you cannot win this": "it is too close". Said when it *is* too
			# close rather than when it was put down, and it interrupts, because by
			# now the thing is on its way. Both are orders, so both are withdrawn
			# the moment the escape resolves.
			_say_now(SAY_TOO_CLOSE, TAG_RUN_ORDER)
			_say(SAY_RUN_AWAY, TAG_RUN_ORDER)
		Stage.DRONE_BAIT:
			# Now that the fight has actually happened somewhere, send them to the
			# stall nearest to where that was.
			_pick_station_near()
			_raise_drone()
			_say(SAY_DRONE_IN)
			# What the doctor says about it is decided by what actually happened,
			# not by a flag that meant "nobody is upright at this instant". A
			# player who crossed the mess on their feet is congratulated for
			# crossing it; a player who went over gets the lesson about why.
			if dodged and rescue_peer == 0:
				_say(SAY_STAYED_UP)
			else:
				_say(SAY_THICK_IS_SLIPPERY)
				_say(SAY_WALK_ON_YELLOW)
			_say(SAY_GO_REFILL)
		Stage.REFILL:
			pass
		Stage.DRONE_DOWN:
			_say(SAY_DRONE_FAILING)
		Stage.COOP_FIGHT:
			_say(SAY_ALL_TOGETHER)
		Stage.COMPLETE:
			_say(SAY_COMPLETE)
	_push_state()


## A. The roster is decided here and only here: party size plus one, counted at
## the moment the fight begins.
func _begin_first_fight() -> void:
	var count: int = world.call("party_size") + 1
	fight_enemies = PackedInt32Array()
	_was_alive.clear()
	for index in count:
		var across: float = RUSHER_SPREAD_X[index % RUSHER_SPREAD_X.size()]
		var rank: float = float(index / RUSHER_SPREAD_X.size())
		var at := Vector3(across, 0.0, RUSHER_LINE_Z + rank * RUSHER_RANK_Z)
		var enemy_index: int = world.call("tutorial_spawn_enemy", KIND_RUSHER, at)
		if enemy_index < 0:
			continue
		fight_enemies.push_back(enemy_index)
		_was_alive[enemy_index] = true
	stage = Stage.FIRST_FIGHT
	_stage_clock = 0.0
	_drop_move_light()
	# Said as the bodies appear and the keys come back, which is the same instant.
	_say(SAY_SHOOT)
	_push_state()


## Ends when every body on the roster is down -- and spills sauce on the way, at
## the spot each one actually died on.
func _watch_fight() -> void:
	var standing := 0
	for enemy_index in fight_enemies:
		var enemy: MayoEnemy = world.call("enemy_at", enemy_index)
		if enemy == null or not is_instance_valid(enemy):
			continue
		var alive: bool = enemy.is_alive()
		if alive:
			standing += 1
		elif _was_alive.get(enemy_index, false):
			_was_alive[enemy_index] = false
			world.call("tutorial_spill_sauce", enemy.global_position,
				spill_offsets(), SPILL_LAYERS)
			# And it stops being a wall. The pair of them die shoulder to shoulder
			# in front of whoever they charged, which is exactly where the escape
			# has to go -- see `MayoPrototype.tutorial_clear_corpse`.
			world.call("tutorial_clear_corpse", enemy_index)
	if standing == 0 and not fight_enemies.is_empty():
		# No "잘했어요!" here any more: the warning that follows interrupts, so a
		# congratulation would be cut off mid-word. The toasts falling over is the
		# praise; what matters next is the thing behind them.
		_enter(Stage.MONSTER_CUE)


## C. Running over their own mess. This stage does not require anybody to fall:
## it ends on reaching the mess, however they cross it, because a tutorial that
## waits for a fall traps the player who walked.
## The escape. Three outcomes, and they are told apart by what the party did.
##
##   * somebody slipped and is on the floor -> the rescue, which is the lesson
##   * somebody crossed the mess on their feet and got clear -> they dodged it
##   * nobody has done either -> nothing happens; they are asked again
##
## **Nothing here ends on a clock.** Handing the next stage to a player who stood
## still was the bug: the drone arrived at 3.9 s, "잘 피했어요" was said to
## somebody who had not avoided anything, and the order to run turned up after the
## rescue it was supposed to prevent.
func _watch_run() -> void:
	_note_mess_contact()

	# 1. A real slip, in this escape, now on the floor. Not "is not upright":
	#    the opening fight leaves people picking themselves up, and the tail of
	#    an old fall is not a new one.
	var fallen := _peer_on_the_floor()
	if fallen != 0:
		rescue_peer = fallen
		_begin_rescue()
		return

	# 2. Or somebody who walked it. Position and route, not time.
	var clear := _peer_that_got_clear()
	if clear != 0:
		dodged = true
		_begin_rescue()
		return

	# 3. Otherwise the party is being waited for. Say it again, and let the
	#    burger keep coming -- it cannot hurt them while this is unresolved.
	if _stage_clock >= RUN_REPROMPT_SECONDS and _lines_done():
		_stage_clock = 0.0
		_say(SAY_RUN_AWAY, TAG_RUN_ORDER)


## Which peer is on the floor from a slip taken during this escape, or 0.
##
## Both halves matter. The slip has to have been recorded here -- `note_slip` is
## called from the floor's own trip, so it is an event rather than a guess -- and
## the body has to have actually reached FALLING or DOWN. A drone that arrives
## before the stumble has even started is arriving before anything has happened.
func _peer_on_the_floor() -> int:
	for peer_id in _escape_slips.keys():
		var shooter = world.call("shooter_for", peer_id)
		if shooter == null:
			continue
		var player: MayoPlayer = shooter.player
		if player == null or not is_instance_valid(player):
			continue
		if player.state == MayoPlayer.State.FALLING \
				or player.state == MayoPlayer.State.DOWN:
			return peer_id
	return 0


## Which peer crossed the mess on their own feet and got somewhere safe, or 0.
##
## Three conditions, all about where they are and where they have been: they went
## over the yellow, they are off it now and still upright, and the burger is a
## long way behind. Somebody who slipped is not eligible however well they
## recovered -- that is the other branch, and calling it a dodge would be telling
## them they avoided the thing that just happened to them.
func _peer_that_got_clear() -> int:
	var monster: MayoEnemy = _monster()
	for peer_id in _touched_mess.keys():
		if _escape_slips.has(peer_id):
			continue
		var shooter = world.call("shooter_for", peer_id)
		if shooter == null:
			continue
		var player: MayoPlayer = shooter.player
		if player == null or not is_instance_valid(player):
			continue
		if player.state != MayoPlayer.State.NORMAL:
			continue
		if world.call("floor_is_slippery_at", player.global_position):
			continue
		if monster == null or not is_instance_valid(monster):
			continue
		var gap := Vector2(player.global_position.x - monster.global_position.x,
			player.global_position.z - monster.global_position.z).length()
		if gap >= DODGE_SAFE_GAP:
			return peer_id
	return 0


## Notes who has been standing on mayo thick enough to go over on. The dodge
## branch needs it: crossing the mess is the thing being avoided, and somebody who
## walked round it entirely has not avoided anything either.
func _note_mess_contact() -> void:
	for peer_id in world.shooter_ids():
		var shooter = world.call("shooter_for", peer_id)
		if shooter == null:
			continue
		var player: MayoPlayer = shooter.player
		if player == null or not is_instance_valid(player):
			continue
		if world.call("floor_is_slippery_at", player.global_position):
			_touched_mess[peer_id] = true


## A player went over. Called from the floor's own trip, with the peer it
## happened to -- see `MayoPrototype._update_slip`.
##
## Only counted from the moment the burger is behind them: a slip in the opening
## fight is not the escape, and the escape is what the drone is about.
func note_slip(peer_id: int) -> void:
	if disabled or not _is_authority():
		return
	if stage != Stage.MONSTER_ARRIVES and stage != Stage.RUN:
		return
	_escape_slips[peer_id] = true
	_anyone_fell = true


## The rescue, however it was earned. Same drone either way; the difference is
## what the doctor says about it and what gets recorded as having happened.
func _begin_rescue() -> void:
	# The order to run is over. Leaving it queued is what had the doctor shouting
	# "Shift를 누르고 뒤로 도망쳐요!" at somebody the drone had already saved.
	_cancel(TAG_RUN_ORDER)
	_enter(Stage.DRONE_BAIT)


## Whether whoever this stage rescued is back on their feet and off the mess.
## A dodge has nobody to recover, so it is satisfied by definition.
func _rescued_is_safe() -> bool:
	if rescue_peer == 0:
		return true
	var shooter = world.call("shooter_for", rescue_peer)
	if shooter == null:
		return true
	var player: MayoPlayer = shooter.player
	if player == null or not is_instance_valid(player):
		return true
	return player.state == MayoPlayer.State.NORMAL


## E. Ends when everybody in the session has topped up at the marked stall.
##
## "Everybody" means everybody connected *now*: somebody who left is dropped from
## the list, and somebody who arrives during this stage is asked to top up like
## anyone else. A joiner landing on the very last bottle can therefore hold the
## stage open a moment longer, which is the simple reading and is fine -- they get
## the objective and a line telling them what to do.
func _watch_refill() -> void:
	var waiting := 0
	for peer_id in world.shooter_ids():
		if not supplied.has(peer_id):
			waiting += 1
	if waiting == 0 and not world.shooter_ids().is_empty() and _lines_done():
		_enter(Stage.DRONE_DOWN)


## F. The warning, a beat to look at the monster, then the swat. Driven off the
## stage clock rather than off a timer started somewhere else, so it cannot fire
## before the party has actually finished topping up.
func _watch_drone_down(_delta: float) -> void:
	if _stage_clock < DRONE_DOWN_WARN:
		return
	if drone_alive and _stage_clock >= DRONE_DOWN_WARN + DRONE_DOWN_TURN:
		_kill_drone()
		_say(SAY_DRONE_DOWN)
		_enter(Stage.COOP_FIGHT)


## G. The burger is back on the party and has to be put down with the bottles the
## party already has. No new damage rule: this is the existing stream against the
## existing party-scaled health.
func _watch_coop() -> void:
	var monster: MayoEnemy = _monster()
	if monster == null or not is_instance_valid(monster):
		return
	if not monster.is_alive():
		_enter(Stage.COMPLETE)


## The stamp pattern for one spill: a filled disc of `SPILL_RADIUS`, stepped by
## `SPILL_STEP`. Worked out once and kept, because it never changes.
static var _spill_pattern: Array = []


static func spill_offsets() -> Array:
	if not _spill_pattern.is_empty():
		return _spill_pattern
	var pattern: Array = []
	var steps := int(ceil(SPILL_RADIUS / SPILL_STEP))
	for row in range(-steps, steps + 1):
		for column in range(-steps, steps + 1):
			var at := Vector2(float(column) * SPILL_STEP, float(row) * SPILL_STEP)
			if at.length() <= SPILL_RADIUS:
				pattern.push_back(at)
	_spill_pattern = pattern
	return _spill_pattern


## Which of the party this body is coming for.
##
## All of them by default -- the enemy picks the nearest, which is the behaviour
## the street has always had. The exception is the opening fight: each rusher is
## given one player of its own, round robin over the roster, so a party of two
## does not watch both rushers pile onto whoever happens to be a metre nearer.
##
## It is a preference, not a leash: a rusher whose player has gone (left, or is
## mid-respawn somewhere else) falls straight back to the whole party rather than
## standing still.
func targets_for(enemy: MayoEnemy, targets: Array) -> Array:
	if disabled:
		return targets
	# **The burger waits to be looked at.** It is put down behind the party while
	# they are being warned about it and cannot turn round; letting it walk
	# through that hold meant it had crossed its five metres and was biting them
	# before they got the camera back. It stands where it lands -- it has only
	# just arrived -- and sets off the moment the warning is over.
	if stage == Stage.MONSTER_CUE and monster_index >= 0 \
			and world.call("enemy_at", monster_index) == enemy:
		return []
	if stage != Stage.FIRST_FIGHT or targets.size() < 2:
		return targets
	var slot := -1
	for index in fight_enemies.size():
		if world.call("enemy_at", fight_enemies[index]) == enemy:
			slot = index
			break
	if slot < 0:
		return targets
	var mine = targets[slot % targets.size()]
	var player := mine as MayoPlayer
	if player == null or not is_instance_valid(player):
		return targets
	return [player]


# ---------------------------------------------------------------------------
# The monster and the drone
# ---------------------------------------------------------------------------

## Everybody standing on the light. It is an instruction, so it ends when it has
## been followed -- by all of them, the same rule the top-up stage uses.
## Whether the burger has got within `gap` of anybody.
func _monster_within(gap: float) -> bool:
	var monster: MayoEnemy = _monster()
	if monster == null or not is_instance_valid(monster) or not monster.is_alive():
		return false
	for peer_id in world.shooter_ids():
		var shooter = world.call("shooter_for", peer_id)
		if shooter == null:
			continue
		var player: MayoPlayer = shooter.player
		if player == null or not is_instance_valid(player):
			continue
		var flat := Vector2(player.global_position.x - monster.global_position.x,
			player.global_position.z - monster.global_position.z)
		if flat.length() <= gap:
			return true
	return false


## Whether the burger is close enough to somebody to be going for them.
func _monster_is_lunging(monster: MayoEnemy) -> bool:
	for peer_id in world.shooter_ids():
		var shooter = world.call("shooter_for", peer_id)
		if shooter == null:
			continue
		var player: MayoPlayer = shooter.player
		if player == null or not is_instance_valid(player):
			continue
		var gap := Vector2(player.global_position.x - monster.global_position.x,
			player.global_position.z - monster.global_position.z).length()
		if gap <= _bite_reach(monster, player):
			return true
	return false


## How close the burger has to be to actually land a bite on this player: the
## same sum its own contact test uses, plus `DRONE_RESCUE_MARGIN`.
func _bite_reach(monster: MayoEnemy, player: MayoPlayer) -> float:
	var player_radius := 0.64
	if player.contamination != null:
		player_radius = player.contamination.radius
	return monster.radius + player_radius + monster.contact_reach + DRONE_RESCUE_MARGIN


## How wide the ring is for the party that is actually here.
func move_reach() -> float:
	var party: int = maxi(world.shooter_ids().size(), 1)
	return MOVE_REACH + MOVE_REACH_PER_PLAYER * float(party - 1)


func _everyone_on_the_light() -> bool:
	if not _light_is_up():
		return false
	var reach := move_reach()
	var counted := 0
	for peer_id in world.shooter_ids():
		var shooter = world.call("shooter_for", peer_id)
		if shooter == null:
			continue
		var player: MayoPlayer = shooter.player
		if player == null or not is_instance_valid(player):
			continue
		counted += 1
		var flat := Vector2(player.global_position.x - MOVE_TARGET.x,
			player.global_position.z - MOVE_TARGET.z)
		if flat.length() > reach:
			return false
	return counted > 0


## The blue light on the road. **Placeholder presentation**, like the drone: a
## lit ring and an omni light rather than authored signage, built from primitives
## so there is one function to replace.
func _raise_move_light() -> void:
	if _move_light != null and is_instance_valid(_move_light):
		return
	_move_light = Node3D.new()
	_move_light.name = "TutorialMoveLight"
	world.add_child(_move_light)
	_move_light.global_position = MOVE_TARGET

	var ring := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = move_reach()
	disc.bottom_radius = move_reach()
	disc.height = 0.04
	disc.radial_segments = 24
	ring.mesh = disc
	ring.position = Vector3(0.0, 0.03, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = MOVE_LIGHT_COLOR
	material.emission_enabled = true
	material.emission = MOVE_LIGHT_COLOR
	material.emission_energy_multiplier = 2.2
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = material
	_move_light.add_child(ring)

	var glow := OmniLight3D.new()
	glow.light_color = MOVE_LIGHT_COLOR
	glow.light_energy = 4.0
	glow.omni_range = move_reach() * 4.0
	glow.position = Vector3(0.0, 1.6, 0.0)
	_move_light.add_child(glow)


func _drop_move_light() -> void:
	if _move_light != null and is_instance_valid(_move_light):
		_move_light.queue_free()
	_move_light = null


## The light pulses so it reads as a marker rather than as painted road.
func _advance_move_light(_delta: float) -> void:
	if _move_light == null or not is_instance_valid(_move_light):
		return
	var show := stage == Stage.INTRO
	_move_light.visible = show
	if not show:
		return
	var pulse: float = 0.75 + 0.25 * sin(_clock * TAU * MOVE_LIGHT_PULSE_HZ)
	_move_light.scale = Vector3(pulse, 1.0, pulse)


func _monster() -> MayoEnemy:
	if monster_index < 0:
		return null
	return world.call("enemy_at", monster_index)


## Puts the burger down behind the party, on the ground they just backed over.
##
## Worked out from the bodies rather than from the map: the opening fight is
## fought backing away and turning, so "behind" is only knowable at the moment it
## ends. The party's average facing decides which way that is; the spawn is walked
## back in toward them if it lands somewhere nothing can stand.
func _spawn_monster() -> void:
	if monster_index >= 0:
		return
	var centre := Vector3.ZERO
	var backs := Vector3.ZERO
	var counted := 0
	for peer_id in world.shooter_ids():
		var shooter = world.call("shooter_for", peer_id)
		if shooter == null:
			continue
		var player: MayoPlayer = shooter.player
		if player == null or not is_instance_valid(player):
			continue
		centre += player.global_position
		# A body's front is its -z, so its back is +z in its own basis.
		var back: Vector3 = player.global_basis.z
		back.y = 0.0
		if back.length_squared() > 0.000001:
			backs += back.normalized()
		counted += 1
	if counted == 0:
		return
	centre /= float(counted)
	if backs.length_squared() < 0.000001:
		# Everyone facing exactly opposite ways: fall back to down the street,
		# which is the way they came in.
		backs = Vector3.BACK
	backs = backs.normalized()

	monster_index = world.call("tutorial_spawn_enemy", KIND_BRUISER,
		_behind_the_party(centre, backs))
	_push_state()


## Somewhere behind `centre`, facing `backs`, that a body can actually stand.
##
## Swung around the back arc before being brought closer, so a party with a wall
## straight behind them gets the burger over their shoulder rather than on top of
## them. Distance is given up last and never below `MONSTER_NEAREST`: a burger
## spawned inside the party is worse than one at a slight angle.
func _behind_the_party(centre: Vector3, backs: Vector3) -> Vector3:
	var reach := MONSTER_BEHIND
	while reach >= MONSTER_NEAREST:
		for degrees in MONSTER_ARC_STEPS:
			var way: Vector3 = backs.rotated(Vector3.UP, deg_to_rad(degrees))
			var at: Vector3 = centre + way * reach
			at.y = 0.0
			if world.call("tutorial_can_stand_at", at):
				return at
		reach -= MONSTER_CLEAR_STEP
	# Nothing in the whole arc: straight back at the shortest allowed distance,
	# which at least keeps it off them.
	var last: Vector3 = centre + backs * MONSTER_NEAREST
	last.y = 0.0
	return last


## A few heavy steps, from the sound the game already makes rather than from a new
## audio system. **Placeholder**: it stands in for a footstep clip, and swapping
## it means playing that clip here instead.
func _stomp() -> void:
	if world == null:
		return
	world.call("tutorial_stomp")


func _raise_drone() -> void:
	drone_alive = true
	var monster: MayoEnemy = _monster()
	if monster != null and is_instance_valid(monster):
		var away := _away_from_party(monster)
		# It comes in from the party's own side, past them, into the burger's
		# face: `away` points from the nearest player to the burger, so backing
		# up along it puts the entry behind their shoulder. Seen from a body
		# turning round, the drone crosses the screen and arrives -- which is the
		# thing that makes the rescue read as a rescue.
		_drone_entry = monster.global_position - away * DRONE_ENTRY_BACK
		_drone_entry.y = monster.global_position.y - monster.height * 0.5 \
			+ DRONE_ENTRY_HEIGHT
	_push_state()


## Which way is "off the party" from the burger, for whoever is nearest it.
func _away_from_party(monster: MayoEnemy) -> Vector3:
	var away := Vector3.ZERO
	var nearest := INF
	for peer_id in world.shooter_ids():
		var shooter = world.call("shooter_for", peer_id)
		if shooter == null:
			continue
		var player: MayoPlayer = shooter.player
		if player == null or not is_instance_valid(player):
			continue
		var gap: Vector3 = monster.global_position - player.global_position
		gap.y = 0.0
		if gap.length() < nearest and gap.length() > 0.01:
			nearest = gap.length()
			away = gap.normalized()
	if away == Vector3.ZERO:
		away = Vector3.BACK
	return away


## The spot the drone will hold it at once it has its attention: a little way off
## the party, so the burger is led away from them rather than through them, and
## near enough that it comes straight back the moment the drone is gone.
##
## Decided at the hand-off rather than at launch: between the two the burger is
## still chasing, so a spot chosen when the drone took off is a spot neither of
## them is near any more.
func _settle_bait_anchor(monster: MayoEnemy) -> void:
	bait_anchor = monster.global_position + _away_from_party(monster) * DRONE_LEAD
	bait_anchor.y = monster.global_position.y - monster.height * 0.5


func _kill_drone() -> void:
	if not drone_alive:
		return
	drone_alive = false
	drone_has_it = false
	_drone_age = 0.0
	if _drone != null and is_instance_valid(_drone):
		_drone.call("smash")
	_clear_bait()
	_push_state()


func _clear_bait() -> void:
	var monster: MayoEnemy = _monster()
	if monster != null and is_instance_valid(monster):
		monster.bait = null


## The drone exists on every peer and is placed off the burger, whose position is
## already replicated -- so it needs no packet of its own beyond "is it up".
func _advance_drone(delta: float) -> void:
	var monster: MayoEnemy = _monster()
	if not drone_alive:
		if _drone != null and is_instance_valid(_drone):
			_drone.call("advance", delta, Vector3.INF)
		return
	if monster == null or not is_instance_valid(monster):
		return
	if _drone == null or not is_instance_valid(_drone):
		_drone = DroneScript.new()
		world.add_child(_drone)
		_drone.global_position = _drone_entry
	var turn: float = _clock * TAU * DRONE_ORBIT_HZ
	var hover: Vector3
	if drone_has_it:
		# Circling a fixed spot rather than hovering off the body's own nose --
		# see `DRONE_LEAD`. The burger walks to the spot and then turns on the
		# spot to follow it round, which is what being kept busy looks like.
		hover = bait_anchor + Vector3(
			cos(turn) * DRONE_ORBIT_RADIUS, 0.0, sin(turn) * DRONE_ORBIT_RADIUS)
		hover.y = bait_anchor.y + DRONE_FACE_HEIGHT \
			+ sin(_clock * TAU * DRONE_BOB_HZ) * DRONE_BOB
	else:
		# Still chasing it down, and cutting in between it and the party: the
		# burger is running at somebody through all of this, so a drone that flew
		# to a spot picked at launch would be left behind by it.
		var cut: Vector3 = monster.global_position \
			- _away_from_party(monster) * DRONE_ORBIT_RADIUS
		hover = cut
		hover.y = monster.global_position.y - monster.height * 0.5 \
			+ DRONE_FACE_HEIGHT
	_drone.call("advance", delta, hover)
	if drone_has_it:
		_drone.global_position = _drone.global_position.lerp(hover,
			clampf(DRONE_FOLLOW * delta, 0.0, 1.0))
	else:
		# Still on its way in: flown at a speed, so it reads as crossing the
		# street rather than as appearing where it is needed.
		_drone.global_position = _drone.global_position.move_toward(hover,
			DRONE_FLY_IN_SPEED * delta)
	# The hand-off, once the drone is actually in its face and not before. Held on
	# the authority only: what travels is the burger's position, and the bait is
	# what produced it. Latched, so the burger does not lose interest again the
	# moment the orbit swings the drone wide.
	if not _is_authority():
		return
	if not drone_has_it:
		_drone_age += delta
		var head: Vector3 = monster.global_position \
			+ Vector3(0.0, monster.height * 0.5, 0.0)
		var in_its_face: bool = _drone.global_position.distance_to(head) \
			<= DRONE_GRAB_GAP
		# Taken off them at the moment it goes for somebody, not on the way over:
		# a burger that turns away while still most of a street from the party has
		# visibly lost interest in nothing.
		if in_its_face and (_monster_is_lunging(monster)
				or _drone_age >= DRONE_GRAB_PATIENCE):
			drone_has_it = true
			_settle_bait_anchor(monster)
			_push_state()
	monster.bait = _drone if drone_has_it else null


# ---------------------------------------------------------------------------
# Captions
# ---------------------------------------------------------------------------

## Queued rather than shown: two stages' worth of lines arriving together still
## come out one after another, in order.
func _say(line_id: int, tag := TAG_NONE) -> void:
	if not _is_authority():
		return
	_line_queue.push_back([line_id, tag])
	lines_shown += 1
	world.call("tutorial_broadcast_line", line_id, false, tag)


## A line that cannot wait its turn.
##
## The queue is first-come-first-served, which is right for a doctor narrating and
## wrong for a warning. "뒤를 조심하세요!" queued behind whatever happened to still
## be on screen arrived six seconds after the thing it warns about had been put
## down -- so the hold that is supposed to cover it ran out first and the player
## got the camera back before ever being told why. This drops what is pending and
## says it now.
func _say_now(line_id: int, tag := TAG_NONE) -> void:
	if not _is_authority():
		return
	_line_queue.clear()
	_line = line_id
	_line_tag = tag
	_line_left = URGENT_LINE_SECONDS
	_line_gap = 0.0
	lines_shown += 1
	_line_began(line_id)
	world.call("tutorial_broadcast_line", line_id, true, tag)


## Withdraws everything queued under `tag`, and takes it off the screen if it is
## up. Explanations are untagged, so nothing that still needs saying is lost.
func _cancel(tag: int) -> void:
	_drop_tag(tag)
	if _is_authority():
		world.call("tutorial_broadcast_cancel", tag)


## Everyone's side of that, the server's own included.
func _drop_tag(tag: int) -> void:
	if tag == TAG_NONE:
		return
	var kept: Array[Array] = []
	for entry in _line_queue:
		if int(entry[1]) != tag:
			kept.push_back(entry)
	_line_queue = kept
	if _line >= 0 and _line_tag == tag:
		_line = -1
		_line_tag = TAG_NONE
		_line_left = 0.0
		_line_gap = LINE_GAP


func cancel_lines(tag: int) -> void:
	_drop_tag(tag)


## The client's side, and the server's own: a line to put on screen.
func show_line(line_id: int, urgent := false, tag := TAG_NONE) -> void:
	if line_id < 0 or line_id >= LINES.size():
		return
	if _is_authority():
		# Already queued by `_say`; the broadcast is for everyone else.
		return
	lines_shown += 1
	if urgent:
		_line_queue.clear()
		_line = line_id
		_line_tag = tag
		_line_left = URGENT_LINE_SECONDS
		_line_gap = 0.0
		_line_began(line_id)
		return
	_line_queue.push_back([line_id, tag])


func _advance_lines(delta: float) -> void:
	if _line_left > 0.0:
		_line_left = maxf(_line_left - delta, 0.0)
		if _line_left <= 0.0:
			_line_gap = LINE_GAP
		return
	if _line_gap > 0.0:
		_line_gap = maxf(_line_gap - delta, 0.0)
		return
	if _line_queue.is_empty():
		_line = -1
		_line_tag = TAG_NONE
		return
	var entry: Array = _line_queue.pop_front()
	_line = int(entry[0])
	_line_tag = int(entry[1])
	_line_left = LINE_SECONDS
	_line_began(_line)


## Presentation that belongs to one caption rather than to a whole stage.
##
## **The blue light comes up with the line that tells you to walk to it.** Lit at
## the top of the stage it was already burning while the doctor was still saying
## hello, and a glowing spot on the road is a far louder instruction than a
## caption is -- so it got walked to and the line it was supposed to illustrate
## never got read. Now the caption arrives and the light arrives with it.
func _line_began(line_id: int) -> void:
	if line_id == SAY_WALK_HERE:
		_raise_move_light()
	if line_id == SAY_GO_REFILL:
		# **The stall counts from the moment it is pointed out.** The marker comes
		# up with this line, and a player who walks over and presses E while the
		# doctor is still talking has done exactly what they were told -- refusing
		# it because an internal stage had not turned over yet meant doing as you
		# are told did not work.
		_refill_open = true


## Whether everything queued has been said. Stages that follow a speech wait on
## this so the player is not read to while the next thing is already happening.
func _lines_done() -> bool:
	return _line_queue.is_empty() and _line_left <= 0.0


## Which line is on screen, by id, or -1. The checks read the event rather than
## the rendered text.
func current_line_id() -> int:
	return _line


func current_line() -> String:
	if _line < 0 or _line >= LINES.size():
		return ""
	return LINES[_line]


func current_line_alpha() -> float:
	if _line < 0:
		return 0.0
	return clampf(_line_left / MayoTutorialHud.SUBTITLE_FADE, 0.0, 1.0)


# ---------------------------------------------------------------------------
# What the HUD asks for
# ---------------------------------------------------------------------------

func objective_text() -> String:
	# The standing objective is the same instruction in shorter words, so it
	# waits for the light too.
	if stage == Stage.INTRO and not _light_is_up():
		return ""
	var text: String = OBJECTIVES.get(stage, "")
	# Once the stall has been pointed out, that is the objective -- even though
	# the drone stage has not formally handed over yet.
	if stage == Stage.DRONE_BAIT and _refill_open:
		text = OBJECTIVES.get(Stage.REFILL, text)
	if stage == Stage.REFILL:
		var waiting := 0
		for peer_id in world.shooter_ids():
			if not supplied.has(peer_id):
				waiting += 1
		# Only worth saying with company: solo, "1명 남음" is just noise.
		if world.shooter_ids().size() > 1:
			text += "  (%d명 남음)" % waiting
	return text


## Where the thing the player cannot see is, or INF when there is nothing to point
## at. Only while it matters: once the party has turned round and is fighting it,
## an arrow is clutter.
func threat_position() -> Vector3:
	# Also while the drone is going down: the party has just walked twenty metres
	# to a stall with their backs to the fight, and the one thing they are meant
	# to watch is about to happen behind them. Pointing is what the arrow is for --
	# the camera is still theirs.
	if stage != Stage.MONSTER_ARRIVES and stage != Stage.RUN \
			and stage != Stage.DRONE_DOWN:
		return Vector3.INF
	var monster: MayoEnemy = _monster()
	if monster == null or not is_instance_valid(monster) or not monster.is_alive():
		return Vector3.INF
	return monster.global_position


## The one thing on screen the party is being sent to, whatever that is at the
## moment: the light to walk to at the start, the stall to top up at later.
func marker_position() -> Vector3:
	if stage == Stage.INTRO:
		if not _light_is_up():
			return Vector3.INF
		return MOVE_TARGET + Vector3(0.0, 1.2, 0.0)
	# From the moment the stall is pointed out rather than from the stage: the
	# marker and the line that names it are the same instruction, and a top-up
	# counts from the same moment -- see `note_refill`.
	if _refill_open and (stage == Stage.DRONE_BAIT or stage == Stage.REFILL):
		return _station_position
	return Vector3.INF


func marker_label() -> String:
	if stage == Stage.INTRO:
		return "여기로"
	return "소스 보충"


## Whether a top-up at the marked stall is being counted yet, for the HUD and the
## checks.
func refill_is_open() -> bool:
	return _refill_open and (stage == Stage.DRONE_BAIT or stage == Stage.REFILL)


## What colour that marker is drawn in. The walk-to spot is the doctor's blue,
## the stall is the sauce's green, so the two never read as the same errand.
func marker_color() -> Color:
	return MOVE_LIGHT_COLOR if stage == Stage.INTRO else Color("8fe38f")


# ---------------------------------------------------------------------------
# Top-ups
# ---------------------------------------------------------------------------

## The station this run of the tutorial sends people to, picked off the world's
## own list. Called once the street exists.
func choose_station(stations: Array) -> void:
	var best := -1
	var best_distance := INF
	for index in stations.size():
		var station: Dictionary = stations[index]
		var at: Vector3 = station["position"]
		var flat := Vector2(at.x - REFILL_ANCHOR.x, at.z - REFILL_ANCHOR.z)
		if flat.length() < best_distance:
			best_distance = flat.length()
			best = index
	_station = best
	if best >= 0:
		_station_position = stations[best]["position"]


## Picks the stall again, off where the party is standing when they need one.
##
## The build-time choice is made before anything has happened, so it is a guess
## about where the fight will end up. It was 43 m from the burger when the party
## got there -- far enough that the drone holding it was a couple of pixels and
## the hand-off, which they are supposed to watch, could not be made out at all.
##
## Two rules, both about what the party can see: nearest to them, and never
## further from them than the burger is -- a stall on the far side of the thing
## chasing you is not somewhere to be sent. Falls back to the opening guess if
## nothing qualifies, so there is always a stall to go to.
func _pick_station_near() -> void:
	var stations: Array = world.call("refill_stations")
	if stations.is_empty():
		return
	var centre := Vector3.ZERO
	var counted := 0
	for peer_id in world.shooter_ids():
		var shooter = world.call("shooter_for", peer_id)
		if shooter == null:
			continue
		var player: MayoPlayer = shooter.player
		if player == null or not is_instance_valid(player):
			continue
		centre += player.global_position
		counted += 1
	if counted == 0:
		return
	centre /= float(counted)

	var monster: MayoEnemy = _monster()
	var to_monster := INF
	if monster != null and is_instance_valid(monster):
		to_monster = Vector2(centre.x - monster.global_position.x,
			centre.z - monster.global_position.z).length()

	var best := -1
	var best_distance := INF
	for index in stations.size():
		var at: Vector3 = stations[index]["position"]
		var from_party := Vector2(at.x - centre.x, at.z - centre.z).length()
		if from_party >= best_distance:
			continue
		if monster != null and is_instance_valid(monster):
			var from_monster := Vector2(at.x - monster.global_position.x,
				at.z - monster.global_position.z).length()
			# Not past the burger, and not so close to it that topping up means
			# standing next to the thing the drone is holding off.
			if from_monster < to_monster or from_monster < DRONE_LEAD * 2.0:
				continue
		best_distance = from_party
		best = index
	if best < 0:
		return
	_station = best
	_station_position = stations[best]["position"]
	_push_state()


func station_index() -> int:
	return _station


## Where the drone drops in from. Synced, so it crosses the same sky on every
## screen rather than each peer guessing from its own copy of the burger.
func drone_entry() -> Vector3:
	return _drone_entry


## Server side: this peer topped up, and it counted. Called from the world's own
## refill path, so it is the same top-up the game already does -- there is no
## second "tutorial refill".
##
## A player whose bottle was already full still counts: `refill_for` succeeds on
## standing at the machine, not on being empty, and this follows it.
func note_refill(peer_id: int, station: int) -> void:
	if not _is_authority() or not refill_is_open():
		return
	if _station >= 0 and station != _station:
		return
	if supplied.has(peer_id):
		return
	supplied.push_back(peer_id)
	if not _said.has("full"):
		_said["full"] = true
		_say(SAY_BOTTLE_FULL)
	_push_state()


## Somebody left. They stop being waited for, or the stage never ends.
func peer_left(peer_id: int) -> void:
	supplied.erase(peer_id)
	if _is_authority():
		_push_state()


## Somebody arrived. During the top-up stage they are told what to do; at every
## other stage the objective they were just sent is enough.
func peer_joined(peer_id: int) -> void:
	if not _is_authority():
		return
	if stage == Stage.REFILL:
		world.call("tutorial_line_to", peer_id, SAY_LATE_JOIN)


# ---------------------------------------------------------------------------
# Replication
# ---------------------------------------------------------------------------

## Everything a peer needs to render the same tutorial, as plain ints. Sent when
## something changes and to a peer as it joins -- never every frame, so a caption
## cannot be re-triggered by an ordinary state packet.
func state() -> PackedInt32Array:
	var out := PackedInt32Array([stage, monster_index, 1 if drone_alive else 0,
		1 if drone_has_it else 0,
		1 if _anyone_fell else 0,
		roundi(bait_anchor.x * 100.0), roundi(bait_anchor.y * 100.0),
		roundi(bait_anchor.z * 100.0),
		# The stall is chosen by the server after the fight, so a peer that only
		# has the stage does not know which one it is -- and would mark a
		# different stall on its own screen than the one the server counts.
		_station,
		roundi(_station_position.x * 100.0), roundi(_station_position.y * 100.0),
		roundi(_station_position.z * 100.0),
		1 if _refill_open else 0,
		# Where the drone comes in from, so it crosses the same sky everywhere.
		roundi(_drone_entry.x * 100.0), roundi(_drone_entry.y * 100.0),
		roundi(_drone_entry.z * 100.0),
		rescue_peer, 1 if dodged else 0,
		fight_enemies.size()])
	out.append_array(fight_enemies)
	out.push_back(supplied.size())
	for peer_id in supplied:
		out.push_back(peer_id)
	return out


func apply_state(data: PackedInt32Array) -> void:
	if data.size() < 18:
		return
	var next: int = data[0]
	monster_index = data[1]
	drone_alive = data[2] == 1
	drone_has_it = data[3] == 1
	_anyone_fell = data[4] == 1
	# Centimetres: a prop's hover does not need more than that, and it keeps the
	# whole message one array of ints.
	bait_anchor = Vector3(float(data[5]) * 0.01, float(data[6]) * 0.01,
		float(data[7]) * 0.01)
	_station = data[8]
	_station_position = Vector3(float(data[9]) * 0.01, float(data[10]) * 0.01,
		float(data[11]) * 0.01)
	_refill_open = data[12] == 1
	_drone_entry = Vector3(float(data[13]) * 0.01, float(data[14]) * 0.01,
		float(data[15]) * 0.01)
	rescue_peer = data[16]
	dodged = data[17] == 1
	var roster: int = data[18]
	var at := 19
	fight_enemies = PackedInt32Array()
	for _i in roster:
		if at >= data.size():
			return
		fight_enemies.push_back(data[at])
		at += 1
	if at >= data.size():
		return
	var count: int = data[at]
	at += 1
	supplied.clear()
	for _i in count:
		if at >= data.size():
			return
		supplied.push_back(data[at])
		at += 1
	if next != stage:
		stage = next
		_stage_clock = 0.0


func _push_state() -> void:
	if world == null or not _is_authority():
		return
	world.call("tutorial_broadcast_state")
