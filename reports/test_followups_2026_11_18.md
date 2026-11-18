# 검사 후속 기록 — 2026-11-18

`cd8c255`를 pull한 뒤 네트워크 검사와 토마티나 기능 검사를 실행한 결과 중, 이번에 고치지 않고 기록만 남기는 항목이다. 모두 자동 기능 검사 결과이며 사람 플레이테스트가 아니다.

## 실행 전 준비

- pull 직후 `Stage2_PumpGenerator.glb`가 로컬에 import되지 않았다. 그래서 토마티나를 불러오는 검사가 발전기 없이 돌거나 시간 초과로 멈췄다.
- `godot --headless --path . --import`를 실행한 뒤 다시 돌렸다. 새 에셋을 받은 다른 PC에서도 같은 준비가 필요하다.

## 튜토리얼 (스테이지 1 범위, 보류)

### `probe_tutorial_net` — 테스트 갱신 필요 + 함정 판정 확인 필요

1. `guest's unfinished pickup was hidden`: 테스트가 문제다.
   - cd8c255에서 소스 선택 방식이 숫자 1/2/3에서 "[E] 소스통 받기"로 바뀌었다.
   - 테스트는 아직 `"1 마요네즈"` 문구를 찾는다.
2. `guest's mustard bottle choice was not replicated`: 테스트가 문제다.
   - 매대마다 정해진 소스를 주는 방식(`STATION_SAUCE_HERE`)으로 바뀌었다.
   - 테스트는 `_request_refill(1)`로 머스타드를 직접 고른다.
3. `network heavy never trapped`: 실제 버그 가능성이 있다.
   - 함정 조건은 괴물 x가 `radius + 0.5` 안쪽이다(`scripts/tutorial.gd:308`).
   - 손님이 x=4에 서 있으면 괴물이 손님을 쫓다가 입구 옆(x≈2.9, z≈-0.6)의 포장마차에 걸려 멈춘다.
   - 그러면 함정이 발동하지 않고, `RUN` 단계에서 12초마다 대사만 반복된다.
   - 실제 다인 플레이에서도 동료가 옆에 서 있으면 튜토리얼이 멈출 수 있다.
   - 같은 실패가 2026-11-02 prototype 브랜치의 수정 전 상태에서도 기록되어 있어서, 최근 pull로 생긴 회귀는 아니다. 처음 생긴 커밋은 찾지 않았다.

### `probe_tutorial` — 결과가 들쭉날쭉함

- 같은 코드로 두 번 실행했을 때 한 번은 `no monster warning after toasts`로 실패하고, 한 번은 `MAYO_TUTORIAL_OK`로 통과했다.
- 단계 추적에서는 `MONSTER_CUE → MONSTER_ARRIVES`가 약 2.3초 뒤 정상적으로 넘어갔다.

### `probe_tutorial_actions` — 미조사 (2026-11-09부터 같은 실패)

- 실패 항목: `real sauce stream cannot hit pinned monster`, `outro never completed`, `missing closing dialogue 11~13`.

## 소스통 표시

### `probe_reliability` — 테스트가 낡음

- 소스통이 GLB 모델(`ProductionSauceTube`)로 바뀌면서 테스트가 찾는 `Sway/Body` 노드가 없어졌다(`tests/probe_reliability.gd:171`).
- 그래서 null 접근으로 멈춘 뒤 시간 초과로 끝난다.
- 고치려면 투명도와 내용물 확인을 새 모델 구조에 맞게 다시 써야 한다.

## 토마티나 `probe_tomatina` — 처리 완료 (2026-11-18)

현재 `TOMATINA_OK`이다. 고친 내용과 판단 근거는 다음과 같다.

- **실제 버그를 고친 것**
  - 피날레 특수 적(케첩 스피터, 카프레제 크롤러, 브루트)이 나오지 않을 수 있었다.
    - 광장 경비 잡몹 36마리가 시작부터 활성 잡몹 상한(1인 32, 2인 36)을 채운다.
    - 그래서 광장을 비우지 않고 발전기를 켜면 증원과 특수 적이 전혀 나오지 않았다.
    - 상한은 잡몹 수를 세는 것이므로, 웨이브의 특수 적 1마리는 상한과 관계없이 나오게 했다(`_advance_horde_spawn`).
    - 잡몹 증원이 상한에 막히는 동작은 그대로 두었다.
  - 상호작용 안내가 `[E - Physical] ...`로 표시되던 문제를 고쳤다. 이제 `game_options.key_label`을 쓴다(`tomatina_play_support.gd`).
- **11-17 수정으로 바뀐 수치에 테스트를 맞춘 것**
  - 무리 2배(계획 114→228), 증원 잡몹 4→8: 첫 골목은 빈칸이 부족해 8 중 7만 들어간다.
  - 광장 경비 잡몹 20→36, 폭발 비율 50/28/22%, 호스 반격 인원의 파티 보정(`minion_spawn_count`)도 반영했다.
- **테스트 방식을 고친 것**
  - 상점·샤워 안내: 대상을 바라보게 하고 안내 계산 결과를 비운 뒤 확인한다. 문구는 "장비 개조"로 바꿨다.
  - 피날레 상한 확인: 상한과 기존 광장 경비 수 중 큰 값과 비교한다.
- 처음에 "추정"으로 분류했던 곡사·호스·안전지점 실패는 원래 테스트에서는 나오지 않았다. 이번 세션의 첫 테스트 수정이 조준을 바닥으로 남기고 프레임을 진행시켜서 생긴 것이었고, 바로잡았다.
- 수정 후 통과 확인: `probe_tomatina_party_balance`, `_revision`, `_session_revision`, `_roster`, `probe_boss_entrance(_network)`, `probe_generator_truck_flow/_network`, `probe_press_king_charge`, `probe_player_bots(_app)`, `probe_context_network`, `probe_network`.

## 3·4인 토마티나 동기화 검사 — 1단계 추가 (2026-11-18)

- 새 검사 `tests/probe_tomatina_party_sync.gd` (`-- --players=2|3|4`):
  - 로컬 ENet으로 호스트 1명과 손님 1~3명이 트럭 로비, 로딩 장벽을 거쳐 토마티나에 들어간다.
  - 손님마다 다른 방향으로 걷는다.
  - 그 뒤 모든 화면에서 모든 플레이어의 위치(1 m 이내), 체력, 소스가 호스트와 같은지 확인한다.
  - 호스트의 인원수 보정(활성 잡몹 상한, 호스 반격 인원, 중형 적 체력)도 확인한다.
- 결과: 2·3·4인 모두 `TOMATINA_PARTY_SYNC_OK`. 정지 후 위치 차이는 0.000 m이고, 호스트 화면에서도 손님이 2.8~3.5 m 움직인 것을 확인했다. 각 실행은 약 10초 걸린다.
- 확인하지 않은 것(2단계 후보):
  - 이동 중(정지 전) 오차
  - 상호작용 요청(보급, 구조, 호스, 발전기)
  - 적과 전투 상태 동기화
  - 중간 참가와 퇴장
  - 실제 인터넷 지연과 손실
- 성능 측정이 아니다. FPS는 수집하지 않는다.
