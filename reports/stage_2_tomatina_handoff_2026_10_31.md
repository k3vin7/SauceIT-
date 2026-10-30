# 스테이지 2 · 라 토마티나 (부뇰) — 구현 인수인계 (2026-10-31)

다른 머신에서 같은 구현을 이어서 시키기 위한 기록. **코드는 아직 한 줄도 바뀌지 않았다.**
아래는 (1) 확정된 기획, (2) 코드를 읽고 파악한 연결 지점, (3) 그레이박스 구현 계획이다.

구현 지시 원문 요약: "맵은 직육면체 그레이박스 + 잔해. 몬스터는 구·캡슐·원통으로. 토마토가 너무 많이 다 터지면 불편하니 터지는 범위는 줄이고, 랜덤으로 어떤 건 크게 터지게."

---

## 1. 확정된 기획

### 컨셉
- 스페인 부뇰(Buñol) 라 토마티나. 축제 음식이 괴물이 되어 날뛰고, 뚱보들이 소스로 제압.
- L4D 식: 시작 안전지대 → 좁은 골목(잔해로 분기) → 광장 피날레 → 소방차.
- 스테이지는 마리오식 개별 스테이지(기존 설계 유지). 트럭 로비에서 선택.

### 동선 (실제 축제 동선 차용)
| 구간 | 장소 | 역할 |
|---|---|---|
| 시작 | 마을 입구, 소스 트럭 | 안전지대 |
| 1막 | Calle San Luis 골목 | 잔해로 분기 2~3개 (짧고 즙 많은 길 vs 길고 깨끗한 길) |
| 2막 | Calle del Cid | 전복된 토마토 트럭 초크포인트 |
| 피날레 | Plaza del Pueblo | 사이렌 → 호드 → 소방차 도착 |
| 마무리 | 소방차 | **뚱보들이 소방차로 뛰어가 호스를 잡고 직접 물을 쏴서 적을 밀어내고 바닥을 씻는다** |

### 피날레 (수정 확정판)
1. 광장 기둥(palo jabón) 사이렌을 켜면 대포 1발, 소방차 출발. 호드가 오는 동안 **시간을 번다**.
2. 소방차가 광장 반대편에 도착. 즙 범벅 바닥을 가로질러 뛰어가야 함(달리면 고글이 가려짐).
3. 호스 2개. 먼저 온 둘이 잡고, 나머지는 소스로 엄호. 호스 든 사람은 이동·회전이 느림.
4. 호스 = 소스 발사의 거대 버전. 데미지 거의 없음, **밀쳐내기** + **바닥 즙 세척**. 물은 무한.
5. 광장에 적이 없고 바닥 세척 비율이 기준 이상이면 대포 2발 → 클리어.

### 바닥 규칙: 즙은 튀고, 소스는 미끄럽다
| 바닥 | 걷기 | 달리기 | 착지 |
|---|---|---|---|
| 토마토즙(얕은 오염) | 없음 | 고글에 작은 점 튐 | 크게 튐 + 몸 오염 |
| 토마토 더미 | 속도 절반 | 속도 절반, 터져서 크게 튐 | 같음 |
| 마요/케찹(깊은 오염) | 괜찮음 | 지금처럼 미끄러짐 | 미끄러짐 |

- 급수전 2~3곳: E로 틀면 주변 즙 제거 + 몸·고글 리셋 (L4D 구급킷 자리).
- 소스 보급: 매대 대신 길가 소스 트럭 / 비닐 덮인 상점 입구.

### 적
| 적 | L4D 역할 | 행동 | 형태(그레이박스) |
|---|---|---|---|
| 일반 토마토 (인간 크기) | 호드 | 러셔 틀. 걷는/굴러오는/던지는 3변종 | 구 + 작은 원통(꼭지) |
| 케찹 몬스터 | Spitter+Boomer | 원거리 케찹 줄기 → 고글 가림 + 바닥에 **깊은 오염** 웅덩이 | 원통 몸 + 구 머리 |
| 카프레제 애벌레 | Smoker+Jockey | 모짜렐라 실로 한 명을 묶어 끌고 감. 동료가 끊어야 함 | 캡슐 여러 개 사슬 |
| 근육 토마토 | Charger+Tank | 돌진, 넘어뜨리고 벽에 박음. 체력 최고 | 큰 구 + 팔 캡슐 2 |
| 볼링 토마토 | 환경형 Charger | 골목 끝에서 거대 토마토를 직선으로 굴림. 맞으면 넘어짐 | 원통 몸, 공은 구 |
| 가스파초 (선택) | Witch | 즙 웅덩이 속에 숨어 있다 밟으면 솟구침 | 납작한 구 |

### 토마토 터짐 (확정)
- 죽는 순간 즙 방울이 사방으로 날아가 바닥·벽·다른 적·**플레이어 몸과 고글**을 칠함. 가까이서 죽이면 뒤집어씀.
- **범위는 작게. 랜덤으로 일부만 크게.** 일반 토마토: 대부분 소(1.2~2.0 m), 일부 중(2.5~3.5 m), 드물게 대(5~6.5 m, "과숙 토마토"는 외형으로 미리 구분되게).
- 근육 토마토는 큰 폭발. 볼링 공은 벽에 부딪히면 터짐. 카프레제는 안 터짐. 가스파초는 퍼짐.
- 튄 즙은 **얕은 오염**(미끄럽지 않음). 케찹 몬스터만 깊은 오염을 남김.
- 네트워크: 서버만 궤적 계산, 클라이언트엔 칠해진 셀만 감(기존 splat 경로). 동시 다발 터짐엔 상한.

### 쓰러짐·구출 (권장, 이번 그레이박스에선 보류 가능)
체력 0 → 토마토 더미에 묻힌 "쓰러짐" 상태, 동료가 E로 꺼냄. 현재는 0이면 시작점 복귀라 4인 협동에서 팀이 갈라짐.

---

## 2. 코드에서 파악한 연결 지점 (읽은 결과)

### 세계 구성
- `scripts/mayo_prototype.gd` (5,592줄) = 세계 전체. `MapKind { FESTIVAL_STREET, TUTORIAL_RECTANGLE }` export로 맵 분기. `_build_world()` → `_floor`(FloorContamination, `floor_plane()`로 크기) → `_build_street()` 또는 `_build_tutorial_space()` → 플레이어 → `_build_enemies()`.
- 스테이지 씬은 아주 얇다: `stage_1_festival.tscn` = Node3D에 스크립트 붙이고 `map_kind=0, tutorial_enabled=false, stage_mode=true, network_ui_enabled=false`만 설정.
- `scripts/stage_registry.gd`: `STAGES` 딕셔너리 + `available_ids()`가 `["stage_1"]` 하드코딩. **`tests/probe_game_flow.gd:47`이 `available_ids() == ["stage_1"]`을 검사하므로 stage_2 추가 시 이 테스트를 고쳐야 한다.**
- `scripts/app_root.gd:178-182`: 방 만들기 패널의 스테이지 OptionButton이 `stage_1`만 넣고 `disabled = true`. `_host_room()`이 `"stage_1"`을 하드코딩해서 `session.begin_host_room(..., "stage_1")` 호출. → 선택값을 넘기도록 수정 필요.
- `scripts/net_game.gd`: `selected_stage`가 로비 동기화에 이미 실려 다닌다(`_accept_lobby`, `_sync_lobby`, `_begin_stage_transition`). 스테이지 id만 바꾸면 전파됨.
- `scripts/truck_lobby.gd:412`: 선택 스테이지 표시 라벨. 수정 불필요.

### 맵 생성기 (`scripts/street_map.gd`, 653줄, 전부 static)
- 격자: `CELL = 1.28 * SCALE(3.6) = 4.608 m`. `ORIGIN_CELL = (29, 93)`이 월드 원점. `cell_corner`, `cell_at`, `cell_middle`, `from_pixels`.
- 설계도 데이터: `SEGMENTS: Array[Rect2i]`(거리 네모, 겹치면 교차로), `CIRCLES`, `STALL_ANCHORS`(51), `VENDING_ANCHORS`, `STAGE_PIXELS`, `TOWER_PIXELS`.
- 건설 기계: `floor_cells()`, `bounds()`, `wall_boxes()`(길 아닌 인접 2칸을 벽으로, greedy merge), `blocked_cells()`(매대 카운터·무대·탑이 길 위에 선 칸), `walkable_cells()`, `_anchored_boxes()`.
- **다른 곳에서 직접 호출하는 static**: `StreetNav.build()`가 `bounds()`, `walkable_cells()`; `StreetNav`와 `MayoEnemy._step_toward`가 `StreetMap.CELL`, `cell_at`, `cell_middle`; `minimap.gd`가 `bounds()`, `floor_cells()`, `stall_boxes()`, `stage_position()`, `tower_position()`, `CELL`, `ORIGIN_CELL`; 세계가 `floor_plane()`, `wall_boxes()`, `stall_boxes()`, `vending_boxes()`, `from_pixels`, `SCALE`.
- 전제: 바닥 평면 하나, 벽 자동 생성, 길 폭 `ROAD_CELLS = 8` 고정(`_wall_direction` 탐색 한계에도 쓰임). `tests/probe_map.gd`는 모든 SEGMENTS 폭이 `ROAD_CELLS` 이상인지 검사한다(스테이지 1 기준, 새 맵 데이터를 StreetMap.SEGMENTS에 넣지 않으면 영향 없음).
- 스폰: `spawn_position_for(slot)`이 FESTIVAL_STREET이면 월드 원점 근처 고정 4좌표 `(0,1.28,1.55)…(0,1.28,6.4)` → 새 맵도 원점 셀(29,93)~(30,94) 주변을 바닥으로 만들면 그대로 재사용 가능.
- 튜토리얼 맵(`scripts/tutorial_course.gd`)이 "StreetMap을 안 쓰는 손제작 직사각형 맵"의 선례. `floor_plane()`, `spawn_position()`, `can_stand()`, `seed_floor()`(바닥 미리 칠하기), `_box()` 헬퍼 참고.

### 오염 그리드
- `scripts/contamination_grid.gd`: 셀 1바이트 = `thickness << 2 | kind`. `KIND_MAYO=0, KIND_MUSTARD=1, KIND_KETCHUP=2`, 2비트라 **kind 하나 더(3) 추가 가능**. `MAX_THICKNESS=63`.
- `scripts/floor_contamination.gd`: `paint_mayo(world_pos, coat, kind)` → 중심 셀 반환(서버가 이 셀만 전송, 클라는 `paint_mayo_cell`로 재생). `is_slippery_at()`는 **KIND_MAYO이고 thickness ≥ slip_thickness(3)일 때만** true. `is_slowing_at()`는 머스타드만. → **케찹 kind를 얇게 칠하면 "빨간 얼룩, 안 미끄러움" = 토마토즙 바닥이 추가 코드 없이 된다.**
- 셰이더 `scripts/contamination.gdshader`: `mustard_tint`, `ketchup_tint`로 kind별 색. kind 3을 쓰려면 셰이더에 tint 한 줄 추가.
- 바닥 미리 칠하기 선례: `TutorialCourse.seed_floor()`가 0.2 m 간격으로 `paint_mayo` 반복 호출. 모든 피어가 빌드 시 결정적으로 같은 호출을 하면 전송 불필요(늦게 온 피어는 `grid_snapshot`으로 받음).

### 스플랫 전송 경로
- `_record_splat(surface, pos, normal, shooter, damaging)`: 벽/플레이어/지붕/적 구분해 칠하고 `_pending_splats`에 `[code, target, cx, cy]` 4 int 추가. `_splat_code(SPLAT_*, sauce)`.
- `_record_visor_splat(player, hit_position, sauce)`: 월드 점을 고글 로컬로 바꿔 `visor.paint_from_hit`. 눈 뒤/높이 밖이면 무시. 케찹 폭발은 폭발 중심을 그대로 넘긴다.
- `apply_splats(data)`: 클라이언트 재생. 새 표면 종류가 없으면 손댈 일 없음.
- `_pending_splats`는 `_physics_process` 끝에서 `_net.end_of_frame()`으로 매 틱 전송.

### 이미 있는 "터짐" = 케찹 폭발 (`_burst_ketchup`, 4429~4545행) — **토마토 터짐의 원형**
- `_burst_ketchup(enemy, shooter)`: 반경 `ketchup_burst_radius`(6.5) 안 적에 데미지+얼룩, 플레이어는 **데미지 없이** 몸 얼룩 + `_record_visor_splat`, 그리고 `_ketchup_ground(centre)`(반경 안에 `ketchup_ground_splats`=68개 바닥 스플랫, `sqrt(rand)`로 균일 분포), `_ketchup_fragments(centre, shooter)`(`_take_speck`로 파편 28개, 장식).
- 서버에서만 실행. 파편은 클라이언트에 안 보임(스테인만 감). 토마토 터짐을 클라에서도 보이게 하려면 `apply_network_state`에서 alive→dead 전환을 감지해 로컬 파편을 뿌리면 됨(반경은 결정적으로 정해야 함 — 아래 참고).
- `_take_speck(now, at, velocity, radius, peer_id, sauce)`: 파편 풀 API.

### 적 (`scripts/enemy.gd`, 1,648줄, `MayoEnemy extends CharacterBody3D`)
- `enum EnemyKind { BRUISER, MOLDY_TOAST_RUSHER, FRY_STALKER }`, `enum Grade { MINION, HEAVY }`. 빌더 3개: `build()`(햄버거), `build_moldy_toast_rusher()`, `build_fry_stalker()`(프리미티브로 비주얼을 만드는 `fry_stalker_visual.gd`가 **프리미티브 몬스터의 선례**).
- 빌더가 하는 일: 수치 세팅 → CollisionShape 추가 → `_body_mesh`(숨긴 마스크 타깃 메시) → `_visual_root` → `BodyContamination` configure + `add_visual_overlay`.
- `advance(delta, targets)`: 권위 전용. 사망 시 `_advance_fall`. 타깃 선택(`_nearest`, `sight_range`/`give_up_range` 래치), `_step_toward`(nav 경로), 속도 = `move_speed * (1 - soiled_slowdown*soiled) * mustard_factor()`, `_shove` 가산, `move_and_slide`, 접촉 판정(`radius + target_radius + contact_reach`), `impact_push_speed`/`impact_lift_speed`가 0보다 크면 `target.apply_enemy_impact(gap, push, lift)`(러셔의 밀치기), `attack_impact_delay_seconds`로 지연 타격.
- 상태 패킷 `network_state()` = `[position, facing_yaw, health, fall_angle, max_health]` (7 float, `ENEMY_STATE_STRIDE=7`). 클라는 `apply_network_state`만.
- `take_sauce_hit(from)` → 죽으면 true. `take_shove`, `soak_ketchup`, `splash_mustard`, `paint_mayo`.
- 플레이어 쪽: `MayoPlayer.apply_enemy_impact(flat_dir, push, lift)`(누적, `max_enemy_impact` 9.5로 캡), `begin_slip()`(NORMAL이면 STUMBLE 시작), `can_slip()`, `is_running()`, `State { NORMAL, STUMBLE, FALLING, DOWN, STANDING_UP, DEAD }`.
- 세계의 적 목록 `_enemies`는 **append only**(스플랫·패킷이 인덱스로 주소 지정). 런타임 스폰은 `tutorial_spawn_enemy(kind, at)` → 서버가 `_net.broadcast_tutorial_enemy` → 모든 피어 `tutorial_add_enemy(kind, at)`로 같은 순서로 빌드. 늦게 온 피어는 `tutorial_spawned()` 목록으로 따라잡음. kind는 `MayoTutorial.KIND_RUSHER=0, KIND_BRUISER=1`뿐 → **새 kind 추가 지점**.
- `_build_enemies()`: `ENEMY_SPAWNS`(픽셀) 루프로 햄버거+토스트 2, 프라이 스토커 1. `rescale_enemies()`로 파티 규모 보정.
- 클리어: `_check_stage_clear()`가 `stage_mode`에서 살아있는 적 0이면 `stage_cleared` emit. 목표 라벨 `_stage_objective`("목표 · 남은 적 N명 처치").
- 체력 0 플레이어: `_damage_player` → `begin_death` → `death_duration` 후 `finish_respawn(spawn_position_for)`.

### 검증 도구
- Godot 실행 파일: `~/Downloads/Godot_v4.7.2-stable_win64.exe` (Windows). 프로젝트는 4.7, GL Compatibility. `.godot/` 임포트 캐시 있음.
- 헤드리스: `godot --headless --path . --script res://tests/smoke_test.gd` 등. 새 클론이면 먼저 `--import`.
- 관련 테스트: `probe_game_flow.gd`(레지스트리), `probe_map.gd`(스테이지 1 맵), `probe_enemy.gd`, `probe_toast_rusher.gd`, `probe_fry_stalker.gd`(적 빌더 검증 선례), `probe_burst.gd`(케찹 폭발).

---

## 3. 그레이박스 구현 계획 (이 순서로)

### A. 스테이지 등록·선택
1. `stage_registry.gd`에 `"stage_2": {display_name: "스테이지 2 · 토마토 축제", scene: "res://stage_2_tomatina.tscn", clear_condition: "..."}` 추가, `available_ids()`에 포함.
2. `stage_2_tomatina.tscn` 생성: `stage_1_festival.tscn` 복제, `map_kind`만 새 값.
3. `app_root.gd` OptionButton 활성화 + 선택 metadata를 `begin_host_room`에 전달.
4. `tests/probe_game_flow.gd:47` 기대값을 `["stage_1", "stage_2"]`로.

### B. 맵 (`scripts/tomatina_map.gd` 신설 + StreetMap 스위치)
- `MapKind`에 `TOMATINA` 추가.
- 격자·`CELL`·`ORIGIN_CELL`은 그대로 쓰고, **설계도만 바꿔치기**: `StreetMap`에 `static var layout_override = null`을 두고 `floor_cells()`, `bounds()`, `blocked_cells()`가 override가 있으면 그쪽을 호출. `wall_boxes()`, `walkable_cells()`, `floor_plane()`, `StreetNav`는 그대로 돌아간다. 세계 빌드 전(`_build_world` 첫 줄)에 `map_kind == TOMATINA`면 `StreetMap.layout_override = TomatinaMap.new()`, 아니면 null.
- `TomatinaMap`(RefCounted): `SEGMENTS`(골목은 3~4칸 폭, 광장은 큰 네모), `floor_cells()`, `bounds()`, `blocked_cells()`(잔해 박스들의 AABB 칸), `debris_boxes()`, `juice_zones()`, `refill_boxes()`, `enemy_spawns()`, `fire_truck_zone()`.
- 레이아웃 초안(격자 칸, y가 +z 남쪽; 시작이 아래, 피날레가 위):
  - 시작 광장 `Rect2i(26, 90, 8, 6)` — 원점 (29,93) 포함
  - 골목 A(북) `Rect2i(28, 72, 4, 19)`
  - 분기 서(짧고 즙 많음): `Rect2i(16, 70, 13, 3)`, `Rect2i(16, 56, 3, 15)`, `Rect2i(16, 54, 14, 3)`
  - 분기 동(길고 깨끗함): `Rect2i(31, 70, 12, 3)`, `Rect2i(40, 50, 3, 21)`, `Rect2i(30, 50, 13, 3)`
  - 합류 Calle del Cid `Rect2i(28, 48, 4, 8)` (전복 트럭), `Rect2i(28, 36, 4, 13)`
  - Plaza del Pueblo `Rect2i(20, 22, 20, 15)`
  - 소방차 베이 `Rect2i(27, 16, 6, 7)`
  - 네모끼리 최소 1칸 겹치게(A*는 4방향).
- 세계 `_build_tomatina()`: `wall_boxes()`로 벽, 잔해는 `_create_wall()`(ContaminableObject 박스, 축 정렬만), 보급은 `_create_vending_machine` + `_add_refill_station`(튜토리얼이 쓰는 방식), 소방차는 큰 빨간 박스 + 구역 마커, 시작 화살표 `_build_start_marker()` 재사용. 미니맵은 `stall_boxes` 등 스테이지 1 전제라 TOMATINA에선 `visible = false`.
- 잔해 종류: 쓰러진 부스(길 절반), 전복 트럭(길 2/3 + 옆 1칸 틈 + 1 m 높이 토마토 더미 박스로 점프 통과), 비닐 가림막은 보류.
- 즙 바닥: `_floor.paint_mayo(pos, -1, KIND_KETCHUP)`를 0.5 m 간격으로 `juice_zones()`에 칠함(빌드 시, 모든 피어 동일). 두께 1 → 얼룩만, 안 미끄러움.

### C. 즙 튀김 (권위, `_update_slip` 옆)
- 달리는 중 발밑 `_floor.thickness_at > 0`이고 kind가 KETCHUP이면 0.35 s마다 `_record_visor_splat(player, 눈앞 점, KIND_KETCHUP)` + 몸 `paint_mayo`. 비율은 낮게.

### D. 적 (프리미티브) — `enemy.gd`에 빌더 추가, 비주얼은 `scripts/tomato_visuals.gd` static 헬퍼
- `EnemyKind`에 `TOMATO_GRUNT, TOMATO_BRUTE, BOWLING_TOMATO, TOMATO_BALL, KETCHUP_SPITTER, CAPRESE_CRAWLER` 추가. `tutorial_add_enemy`의 kind 분기에 전부 추가(런타임 호드 스폰용).
- 각 빌더는 `build_fry_stalker` 패턴: 수치 → 콜라이더 → 숨긴 `_body_mesh` → 프리미티브 `_visual_root` → contamination.
- **grunt**: 구 r≈1.0 + 꼭지 원통. 러셔 수치 기반(속도 비율 1.0, 체력 40, 접촉 6, 밀치기 약함). `burst_radius` 필드.
- **brute**: 구 r≈1.8 + 팔 캡슐 2. 체력 300, 돌진: 타깃 14 m 안·직선 가능이면 1.2 s 동안 2.2× 속도, `impact_push 12, lift 4`. `advance()` 안에 kind별 훅 `_advance_special(delta, target)` 하나 추가해서 처리.
- **bowling**: 원통 몸, 제자리(move_speed 0). 4 s마다 타깃 방향으로 공 발사. **공은 `TOMATO_BALL` kind 적으로 빌드 시 미리 N개 풀링**(append only 제약 때문), 쉴 때는 y=-50에 숨김. 상태 패킷이 위치를 실어 나르니 네트워크 추가 없음. 플레이어 접촉 시 `begin_slip()` 또는 큰 `apply_enemy_impact`. 벽에 닿으면 소형 터짐. 클리어 카운트·타깃 선택에서 제외.
- **spitter**: 원통 몸 + 구 머리. 사거리 18 m, 3 s마다 히트스캔: 타깃 `_record_visor_splat` + 몸 얼룩 + 발밑에 `KIND_KETCHUP` 두께 ≥3 웅덩이(현재 규칙상 케찹은 안 미끄러움 → 깊은 케찹을 미끄럽게 하려면 `is_slippery_at`에 `KIND_KETCHUP && thickness ≥ slip_thickness` 추가. 기존 플레이어 케찹 폭발 바닥에도 영향이 있으니 결정 필요).
- **caprese**: 캡슐 5개 사슬. 사거리 8 m 안 직선이면 매 틱 `apply_enemy_impact(자기 쪽 방향, 3.0, 0)`으로 끌어당김. 피격 flinch 때 2 s 해제.

### E. 토마토 터짐 (`_burst_tomato(enemy)` — `_burst_ketchup` 복제·축소)
- 사망 시(`_record_splat`의 killed 분기, 그리고 케찹 폭발로 죽을 때도) 호출.
- **반경은 빌드 시 결정적으로 배정**: 적 인덱스+맵 시드로 RNG → grunt 70% 소(1.2~2.0), 25% 중(2.5~3.5), 5% 대(5~6.5, 외형을 더 크고 어둡게). brute 6.0. ball 1.5. spitter 3.0. caprese 0(없음). 클라이언트도 같은 값을 갖게 되므로 파편을 로컬에서 뿌릴 수 있음.
- 바닥 스플랫 수 = 반경 면적 비례(≈6/m²), `KIND_KETCHUP` 두께 1(얕음). 적 데미지 없음(케찹 폭발과 달리). 반경 안 플레이어는 몸 + 고글 스플랫.
- 파편은 `_take_speck`로, 서버는 즉시, 클라는 `apply_network_state`에서 alive→dead 감지 시(세계가 `_enemy_seen_dead` 배열로 추적).
- 동시 터짐 상한: 한 틱에 바닥 스플랫 총 300개 넘으면 나머지는 생략.

### F. 호드·클리어
- 광장 진입 트리거(플레이어가 광장 Rect 안) → 서버가 `tutorial_spawn_enemy(TOMATO_GRUNT, 광장 가장자리 좌표)`를 `minion_spawn_count(8)`회 호출(이미 있는 파티 규모 산식).
- 클리어 조건(이번 그레이박스): **HEAVY 등급 전원 사망 + 플레이어 1명 이상이 소방차 구역 안**. `_check_stage_clear`에 `map_kind` 분기. 목표 라벨: "엘리트 N 남음 → 소방차로 이동".
- 호스·세척·사이렌은 다음 단계(기획 §1 피날레 참조).

### G. 검증
- `probe_game_flow.gd` 수정 후 통과, `smoke_test.gd`, `probe_map.gd`(스테이지 1 회귀), `probe_enemy.gd`, `probe_burst.gd` 통과.
- 새 프로브 `tests/probe_tomatina.gd`: 스테이지 2 씬 로드 → 시작 원점이 바닥인지, 소방차 구역까지 `StreetNav.route`가 비어 있지 않은지, 적 kind별 빌드가 되는지, grunt 하나 죽였을 때 바닥 케찹 스플랫이 생기고 `is_slippery_at`은 false인지, 반경 분포(소/중/대)가 시드로 재현되는지.

### 미결정 (구현자가 기본값으로 진행, 나중에 사용자 확인)
- 깊은 케찹을 미끄럽게 할지 (D-spitter 참고). 기본: **보류, 케찹 몬스터 웅덩이도 얕은 오염으로.**
- 경사/층 없음(평면). 길 폭은 세그먼트별로 다르게(3~4칸 골목), 스테이지 1 `ROAD_CELLS` 검사는 새 맵에 적용 안 함.
- 쓰러짐·구출은 이번 패스에서 제외.
