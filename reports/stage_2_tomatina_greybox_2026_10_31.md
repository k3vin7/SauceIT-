# 스테이지 2 · 라 토마티나 — 그레이박스 구현 기록 (2026-10-31)

`stage_2_tomatina_handoff_2026_10_31.md`의 §3 계획(A~G)을 그대로 따라 구현했다. 이 문서는 무엇이 들어갔고, 어디서 계획과 달라졌고, 무엇이 남았는지의 기록이다.

## 들어간 것

| 계획 | 구현 | 파일 |
|---|---|---|
| A 등록·선택 | `stage_2` 등록, 씬 생성, 호스트 패널 드롭다운이 실제 선택을 `begin_host_room`에 전달 | `stage_registry.gd`, `stage_2_tomatina.tscn`, `app_root.gd`, `probe_game_flow.gd` |
| B 맵 | `TomatinaMap`(12개 세그먼트, 잔해·소스 트럭·소방차·즙 구역·로스터), `StreetMap.layout_override`로 `floor_cells/bounds/blocked_cells`만 교체 | `tomatina_map.gd`, `street_map.gd`, `mayo_prototype.gd:_build_tomatina` |
| C 즙 튀김 | 달리는 중 발밑이 케찹이면 0.35 s마다 다리에 얼룩, 50% 확률로 고글 아래쪽에 작은 점 | `_update_juice_splash` |
| D 적 | grunt / brute / bowler(+ball 3개 풀) / spitter / crawler. `advance()` 안에 `_advance_special` 훅 하나 | `enemy.gd`, `tomato_visuals.gd` |
| E 터짐 | `_burst_tomato`: 반경 면적 × 6개 바닥 스플랫(터짐당 240, 틱당 300 상한), 주변 몸 얼룩, 플레이어 몸+고글. 데미지 없음. 반경은 `_deal_grunt_burst(index)`로 결정적 배정, 클라이언트는 패킷의 alive→dead 전환에서 파편을 스스로 뿌림 | `mayo_prototype.gd` |
| F 호드·클리어 | 광장 진입 시 `minion_spawn_count(16)` grunt를 가장자리에서 스폰(기존 spawn 경로, 늦은 피어 재생됨). 클리어 = HEAVY 전원 사망 + 소방차 구역에 1명 이상. 목표 라벨 분기 | `_check_horde_trigger`, `_check_stage_clear` |
| G 검증 | `tests/probe_tomatina.gd` 신설, 기존 프로브 전부 통과 | |

## 계획과 달라진 곳

- **카프레제의 끌기**는 `apply_enemy_impact(…, 3.0, 0)` 매 틱이 아니라 **위치 기반 릴링**(6.5 m/s, `move_and_collide`) + `splash_mustard()`로 했다. 임펄스를 매 틱 더하면 플레이어의 가속(0.6 m/s/틱)이 상쇄하지 못해 속도가 무한히 커진다. 머스타드 느려짐이 "묶임"의 역할을 하므로 플레이어 쪽에 새 상태는 없다.
- **근육 토마토 넘어뜨리기**: 돌진 중 접촉 시 `begin_slip()`. 벽에 박으면 0.8 s 멈춤(`_attack_lock_left`).
- **볼링 공**은 소스에 안 죽는다(`take_sauce_hit` 조기 반환, 얼룩만). 벽(법선 y<0.5인 StaticBody3D)에 닿으면 세계에 터짐을 요청하고 바닥 아래(y=-50)에 주차. 클라이언트는 위치가 -40 아래로 점프하는 걸 보고 파편을 뿌린다.
- **전복 트럭 틈의 토마토 더미**(1 m 높이)는 `blocked_cells`에서 뺐다. 넣으면 골목→광장 경로가 끊겨 `route()`가 빈 배열을 돌려주고 적이 직선으로 벽에 기댄다. 대신 더미가 틈을 거의 막으므로 골목 쪽 적은 트럭 앞에서 멈춘다(의도된 초크포인트).
- **급수전(E로 즙 제거·리셋)**과 비닐 가림막은 §3에 없어 이번 패스에서 뺐다.
- 호드로 런타임 스폰되는 grunt는 시야 90 m / 포기 120 m(튜토리얼 스폰과 같은 값). 광장이 92×69 m라 기본 30 m로는 못 본다.

## 미결정(기본값으로 진행)

- 깊은 케찹 미끄러움: **보류**. `is_slippery_at`는 그대로 마요 전용. 스피터 웅덩이는 깊은 띠로 그려지지만 안 미끄럽다.
- 경사 없음, 쓰러짐·구출 없음, 사이렌·호스·세척·대포 없음(다음 단계).

## 검증

```
godot --headless --path . --script res://tests/probe_tomatina.gd
```
레이아웃(시작→소방차 경로 103 웨이포인트, 트럭이 4칸 중 3칸 차단), 로스터(grunt 22, brute/bowler/spitter/crawler 각 1, ball 3), 400명 분포(소 287 / 중 95 / 대 18, 재현 가능), 즙(서쪽 골목 36 샘플 중 14 칠해짐·전부 케찹·안 미끄러움, 동쪽 골목 0), grunt 터짐(1.38 m → 바닥 스플랫 36개 큐잉, 미끄러운 셀 0), 공(2.8 m 굴러 벽에서 터지고 주차), 호드 16, 클리어 조건 양쪽 부정 케이스 + 긍정 케이스, 스테이지 1 복귀 시 `layout_override == null`.

`probe_game_flow.gd`는 `res://tmp/`가 없는 클론에서는 저장 관련 검사가 실패한다(이번 작업과 무관, 폴더만 만들면 통과).

## 사용자 피드백 반영 (10/31)

- **충전 포장마차 부족** → 소스 트럭 3대에서 7대로. 시작 광장, Calle San Luis 중간(동쪽 벽), 서쪽 골목(바깥 벽, 쓰러진 부스 앞), 동쪽 골목(바깥 벽, 상자 앞), Cid 전복 트럭 지난 곳, 광장 양쪽 벽. 전부 `TomatinaMap.refill_boxes()`에서 벽에 붙여 세우고 `blocked_cells()`에 포함되므로 경로 탐색이 피해 간다. `_truck_against_wall`의 깊이는 3 m라 3칸(13.8 m) 골목도 막히지 않는다.
- **토마토 수 2배, 크기 70%** → 상비 grunt 11 → 22(경로 전 구간에 고르게 추가), 호드 기본 8 → 16. `MayoEnemy.TOMATO_SCALE = 0.7`을 grunt/brute/bowler/ball 반지름(bowler는 높이도)에 곱한다. 스피터(케찹병)와 카프레제 크롤러는 토마토가 아니라 그대로 둠. 터짐 반경(`burst_radius`)은 몸 크기와 무관하게 유지.
- `probe_tomatina`는 트럭 7대, grunt ≥ 20, 호드 16으로 통과.
