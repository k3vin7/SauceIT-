class_name OfficeSlot
extends RefCounted

## 사무실 슬롯머신. 팀 돈을 걸고 돌린다: 세 칸이 같으면 건 만큼 더 받고(두 배), 아니면 잃는다.
## 판돈에 상한이 없고 횟수 제한도 없다. 대신 맞을 확률이 낮다(`WIN_CHANCE`).
## 굴리는 것은 방장이다(`MayoNet.request_slot_spin`) -- 돈의 원본이 방장의 저장 파일이라서.

const WIN_CHANCE := 0.3
const SYMBOLS := ["케찹", "머스터드", "마요", "7"]
const SYMBOL_COLORS := [Color("c2433a"), Color("e6bd3f"), Color("efe6d2"), Color("7a55a8")]


## 한 번 돌린 결과: won, 그리고 세 칸의 그림(`SYMBOLS` 번호). 맞으면 셋이 같고, 아니면
## 적어도 하나가 다르다.
static func roll(rng: RandomNumberGenerator, chance := WIN_CHANCE) -> Dictionary:
	var won := rng.randf() < chance
	var first := rng.randi_range(0, SYMBOLS.size() - 1)
	var reels := PackedInt32Array([first, first, first])
	if not won:
		reels[1] = rng.randi_range(0, SYMBOLS.size() - 1)
		reels[2] = rng.randi_range(0, SYMBOLS.size() - 1)
		if reels[1] == first and reels[2] == first:
			reels[2] = (first + rng.randi_range(1, SYMBOLS.size() - 1)) % SYMBOLS.size()
	return {"won": won, "reels": reels}
