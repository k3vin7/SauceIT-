class_name OfficeSlot
extends RefCounted

## 사무실 슬롯머신. 팀 돈을 걸고 돌린다. 판돈에 상한이 없고 횟수 제한도 없다.
## 굴리는 것은 방장이다(`MayoNet.request_slot_spin`) -- 돈의 원본이 방장의 저장 파일이라서.
##
## 배당표(`PAYOUTS`): [확률, 건 돈의 몇 배를 돌려받는가]. 위에서부터 차례로 뽑는다.
##   0.5%  10배 -- 7 7 7
##   1%    4배  -- 같은 소스 셋
##   4%    2배  -- 7 둘
##   33%   1배  -- 같은 소스 둘(본전)
##   61.5% 0배  -- 전부 다름(건 돈을 잃음)
## 평균으로는 건 돈의 50%가 돌아온다.

const PAYOUTS := [[0.005, 10.0], [0.01, 4.0], [0.04, 2.0], [0.33, 1.0], [0.615, 0.0]]
const SEVEN := 3
const SYMBOLS := ["케찹", "머스터드", "마요", "7"]
const SYMBOL_COLORS := [Color("c2433a"), Color("e6bd3f"), Color("efe6d2"), Color("7a55a8")]


## 0 이상 1 미만의 수 하나가 뽑는 배당.
static func multiplier_for(pick: float) -> float:
	var edge := 0.0
	for payout in PAYOUTS:
		edge += float(payout[0])
		if pick < edge:
			return float(payout[1])
	return 0.0


## `bet`을 걸어 `multiplier`배를 돌려받을 때 팀 돈이 변하는 양.
static func gain_for(bet: int, multiplier: float) -> int:
	return roundi(bet * multiplier) - bet


## 한 번 돌린 결과: multiplier, 그리고 그 배당에 맞는 세 칸의 그림(`SYMBOLS` 번호).
static func roll(rng: RandomNumberGenerator, pick := -1.0) -> Dictionary:
	var multiplier := multiplier_for(pick if pick >= 0.0 else rng.randf())
	var sauce := rng.randi_range(0, SEVEN - 1)
	var other := (sauce + rng.randi_range(1, SEVEN - 1)) % SEVEN
	var reels: PackedInt32Array
	if multiplier >= 10.0:
		reels = PackedInt32Array([SEVEN, SEVEN, SEVEN])
	elif multiplier >= 4.0:
		reels = PackedInt32Array([sauce, sauce, sauce])
	elif multiplier > 0.0:
		# 둘이 같고 하나가 다르다: 7 둘이면 2배, 같은 소스 둘이면 본전. 다른 한 칸의 자리는 아무 데나.
		var pair := SEVEN if multiplier >= 2.0 else sauce
		var odd := sauce if multiplier >= 2.0 else other
		reels = PackedInt32Array([pair, pair, pair])
		reels[rng.randi_range(0, 2)] = odd
	else:
		reels = PackedInt32Array([sauce, other, 3 - sauce - other])
		if rng.randf() < 0.5:
			reels[rng.randi_range(0, 2)] = SEVEN
	return {"multiplier": multiplier, "reels": reels}
