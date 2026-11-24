class_name OfficeSlot
extends RefCounted

## 사무실 슬롯머신. 팀 돈을 걸고 돌린다. 판돈에 상한이 없고 횟수 제한도 없다.
## 굴리는 것은 방장이다(`MayoNet.request_slot_spin`) -- 돈의 원본이 방장의 저장 파일이라서.
##
## 배당표(`PAYOUTS`): [확률, 건 돈의 몇 배를 돌려받는가]. 위에서부터 차례로 뽑는다.
##   0.5%  10배 -- 황금 소스통 셋
##   1%    4배  -- 같은 소스 셋
##   4%    2배  -- 황금 소스통 둘
##   33%   1.1배 -- 같은 소스 둘
##   61.5% 0배  -- 전부 다름(건 돈을 잃음)
## 평균으로는 건 돈의 53.3%가 돌아온다.
##
## 잭팟: 꽝이 날 때마다 잃은 돈의 `JACKPOT_SHARE`가 잭팟으로 쌓이고, 황금 소스통 셋이 나오면
## 10배에 더해 쌓인 잭팟을 통째로 받는다. 잃은 돈에서 나오는 것이라 돈이 새로 생기지는 않는다
## (잭팟까지 합친 평균 회수율은 약 65.6%).

const PAYOUTS := [[0.005, 10.0], [0.01, 4.0], [0.04, 2.0], [0.33, 1.1], [0.615, 0.0]]
const JACKPOT_SHARE := 0.2
const GOLDEN := 3
## 칸에 나오는 그림은 소스통이다: 케찹, 머스터드, 마요네즈, 그리고 대박용 황금 소스통.
## `SYMBOL_COLORS`는 통 색, `SYMBOL_CAPS`는 뚜껑 색.
const SYMBOLS := ["케찹", "머스터드", "마요네즈", "황금 소스"]
const SYMBOL_COLORS := [Color("c2433a"), Color("e6bd3f"), Color("f1ead9"), Color("f0b93a")]
const SYMBOL_CAPS := [Color("f2f2ee"), Color("b9872a"), Color("5b8fc2"), Color("fff3c4")]


## 0 이상 1 미만의 수 하나가 뽑는 배당.
static func multiplier_for(pick: float) -> float:
	var edge := 0.0
	for payout in PAYOUTS:
		edge += float(payout[0])
		if pick < edge:
			return float(payout[1])
	return 0.0


## `bet`을 걸어 `multiplier`배를 돌려받을 때 팀 돈이 변하는 양. 1.1배의 우수리는 반올림한다
## (10을 걸면 +1, 4 이하를 걸면 +0).
static func gain_for(bet: int, multiplier: float) -> int:
	return roundi(bet * multiplier) - bet


## 한 번 돌린 결과: multiplier, 그리고 그 배당에 맞는 세 칸의 그림(`SYMBOLS` 번호).
static func roll(rng: RandomNumberGenerator, pick := -1.0) -> Dictionary:
	var multiplier := multiplier_for(pick if pick >= 0.0 else rng.randf())
	var sauce := rng.randi_range(0, GOLDEN - 1)
	var other := (sauce + rng.randi_range(1, GOLDEN - 1)) % GOLDEN
	var reels: PackedInt32Array
	if multiplier >= 10.0:
		reels = PackedInt32Array([GOLDEN, GOLDEN, GOLDEN])
	elif multiplier >= 4.0:
		reels = PackedInt32Array([sauce, sauce, sauce])
	elif multiplier > 0.0:
		# 둘이 같고 하나가 다르다: 황금 둘이면 2배, 같은 소스 둘이면 1.1배. 다른 한 칸의 자리는 아무 데나.
		var pair := GOLDEN if multiplier >= 2.0 else sauce
		var odd := sauce if multiplier >= 2.0 else other
		reels = PackedInt32Array([pair, pair, pair])
		reels[rng.randi_range(0, 2)] = odd
	else:
		reels = PackedInt32Array([sauce, other, 3 - sauce - other])
		if rng.randf() < 0.5:
			reels[rng.randi_range(0, 2)] = GOLDEN
	return {"multiplier": multiplier, "reels": reels}


## 꽝으로 `bet`을 잃었을 때 잭팟에 쌓이는 양.
static func jackpot_share(bet: int) -> int:
	return roundi(bet * JACKPOT_SHARE)


## 세 칸의 그림이 무엇을 맞혔는가: 0 꽝, 1 같은 소스 둘, 2 황금 둘, 3 같은 소스 셋, 4 황금 셋.
static func tier_of(reels: PackedInt32Array) -> int:
	if reels.size() != 3:
		return 0
	var golden := int(reels[0] == GOLDEN) + int(reels[1] == GOLDEN) + int(reels[2] == GOLDEN)
	var same := int(reels[0] == reels[1]) + int(reels[1] == reels[2]) + int(reels[0] == reels[2])
	if same == 3:
		return 4 if golden == 3 else 3
	if same == 1:
		return 2 if golden == 2 else 1
	return 0


## 돌리기 시작한 뒤 각 칸이 멈추는 시각(초). 왼쪽부터 하나씩 멈추고, 앞의 두 칸이 같으면
## 마지막 칸은 한참 더 끌다가 멈춘다 -- 그 칸이 1.1배냐 4배냐 10배냐를 가른다.
static func stop_times(reels: PackedInt32Array) -> PackedFloat32Array:
	var tease := reels.size() == 3 and reels[0] == reels[1]
	return PackedFloat32Array([0.7, 1.25, 3.4 if tease else 1.8])


## `elapsed`초까지 `index`번 칸의 그림이 넘어간 횟수. 끄는 칸은 둘째 칸이 멈춘 뒤로 점점 느려진다.
static func spin_ticks(index: int, reels: PackedInt32Array, elapsed: float) -> int:
	var stops := stop_times(reels)
	var until := minf(elapsed, stops[index])
	var tease := index == 2 and stops[2] > 2.0
	var fast_until := minf(until, stops[1]) if tease else until
	var ticks := int(fast_until / 0.06)
	if tease and until > stops[1]:
		var at := stops[1]
		while true:
			at += lerpf(0.08, 0.38, (at - stops[1]) / (stops[2] - stops[1]))
			if at > until:
				break
			ticks += 1
	return ticks
