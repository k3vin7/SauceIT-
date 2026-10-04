class_name SauceTank
extends RefCounted

## **The bottle's arithmetic: what is left, how long a squeeze lasts, how hard it
## pushes, and what the sauce in it does to those.**
##
## Numbers only. Nothing here decides whether the nozzle delivers -- that is the
## stage bands, the catch rolls and the `Nozzle` state, which own enums and a
## signal and stay with the world. Nothing here touches a surface, a body, or the
## wire.
##
## **Static, and told everything.** No state to go stale and no reference back, so
## a value changed in the inspector is in effect on the next call. The caller
## passes the level or the elapsed time it already holds; the tank never reaches
## for a Shooter.
##
## **Invariant worth keeping in view:** `seconds_left` is the reason the drain is
## written as a flow rather than as a lifetime. Change `flow_per_second` and both
## the countdown on the HUD and the tank agree, because they are the same
## division.


## What is left of the squeeze: 1 at the start of a burst, and
## `1 - falloff` once it has run `over_seconds`.
##
## Driven by *elapsed delivery*, not by trigger time -- the caller passes
## `burst_elapsed`, which every peer advances for itself off the replicated
## nozzle state, so a client and the host reach the same pressure without the
## number being sent.
static func squeeze_pressure(burst_elapsed: float, falloff: float,
		over_seconds: float, curve: float) -> float:
	if falloff <= 0.0:
		return 1.0
	var through := clampf(burst_elapsed / maxf(over_seconds, 0.001), 0.0, 1.0)
	return 1.0 - falloff * pow(through, curve)


## Seconds of delivery left in a bottle at this level, which is the whole point
## of expressing the drain as a flow.
static func seconds_left(level: float, flow_per_second: float) -> float:
	return level / maxf(flow_per_second, 0.0001)


## How long a press may run at this tank level: three pinned points with straight
## lines between them. Two segments rather than one because the curve bends at the
## middle point -- the drop from full to half is steeper than the drop from half
## to empty, which is what keeps the last of the bottle usable while still making
## every press shorter than the one before it.
static func burst_seconds_at(level: float, full: float, half: float,
		empty: float, midpoint: float) -> float:
	var at := clampf(level, 0.0, 1.0)
	var middle := clampf(midpoint, 0.01, 0.99)
	if at >= middle:
		return lerpf(half, full, (at - middle) / (1.0 - middle))
	return lerpf(empty, half, at / middle)


## True once this squirt has had everything it is getting: its allowance is up, or
## the tank is dry.
static func burst_spent(level: float, burst_time: float, allowance: float) -> bool:
	return level <= 0.0 or burst_time >= allowance


## The level after `delta` of spending, and after `delta` of standing still.
##
## Two calls rather than one returning a pair: a pair would be a `Vector2`, whose
## components are 32-bit, and the level is a 64-bit float. Rounding the tank
## through a smaller type to save a call is exactly the sort of silent change a
## move like this must not make.
##
## Air counts as spending: the last of a bottle still coughs its way out.
static func after_spending(level: float, delta: float,
		flow_per_second: float) -> float:
	return maxf(level - flow_per_second * delta, 0.0)


static func after_idle(level: float, delta: float,
		refill_per_second: float) -> float:
	return minf(level + refill_per_second * delta, 1.0)
