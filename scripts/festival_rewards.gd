class_name FestivalRewards
extends RefCounted

## 축제를 마치고 사무실로 가져오는 것: 팀 공용 돈과 전리품.
##
## 돈은 완료하면 `BASE_MONEY`, 거기에 지닌물건에 담아 온 토마토 하나마다 1씩 `MAX_BONUS`까지,
## 그리고 축제에서 쓰지 않고 남긴 코인을 그대로 더한다(시체에서 얻은 것, 보스를 잡은 값 등).
## 전리품은 축제마다 하나다. 토마토 축제는 팀이 지닌물건에 토마토를 한 사람당
## `tomatoes_per_player`개 이상 담아 오면 "토마토 케찹"을 진열장에 올린다.
## 돈과 전리품의 원본은 방장의 저장 파일이고, 팀원에게는 사무실에서 보여 주기만 한다.

const BASE_MONEY := 40
const MAX_BONUS := 10
const TROPHIES := {
	"tomato_ketchup": {"name": "토마토 케찹", "stage": "stage_2", "tomatoes_per_player": 2},
}


static func trophy_name(trophy_id: String) -> String:
	return str(TROPHIES.get(trophy_id, {}).get("name", trophy_id))


static func trophy_for_stage(stage_id: String) -> String:
	for trophy_id in TROPHIES:
		if TROPHIES[trophy_id]["stage"] == stage_id:
			return trophy_id
	return ""


## 이 축제의 전리품을 얻으려면 팀이 담아 와야 하는 토마토 수. 전리품이 없으면 0.
static func tomatoes_needed(stage_id: String, players: int) -> int:
	var trophy_id := trophy_for_stage(stage_id)
	if trophy_id.is_empty():
		return 0
	return int(TROPHIES[trophy_id]["tomatoes_per_player"]) * maxi(players, 1)


## 축제 하나의 정산. `tomatoes`는 팀 전원의 지닌물건에 남아 있는 토마토 수.
## `coins`는 팀이 남긴 코인(`MayoPrototype.leftover_coin_count`).
## 돌려주는 것: money(번 돈), coins(그 가운데 남긴 코인), tomatoes, needed(전리품에 필요한 수,
## 없으면 0), trophy(얻은 전리품 id, 못 얻었으면 "").
static func settle(stage_id: String, tomatoes: int, players: int, coins := 0) -> Dictionary:
	var needed := tomatoes_needed(stage_id, players)
	return {
		"money": BASE_MONEY + clampi(tomatoes, 0, MAX_BONUS) + maxi(coins, 0),
		"coins": maxi(coins, 0),
		"tomatoes": maxi(tomatoes, 0),
		"needed": needed,
		"trophy": trophy_for_stage(stage_id) if needed > 0 and tomatoes >= needed else "",
	}
