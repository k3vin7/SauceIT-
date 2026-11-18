# 온라인 플레이어 봇 실행 계획 (보류, 2026-11-18)

현재 `scripts/player_bot_team.gd`는 오프라인 토마티나 연습 전용이다(`configure()`에서 온라인이면 `push_error` 후 정지). 이 문서는 로컬 호스트 1 + 클라이언트 1~3 인스턴스에서 각 인스턴스가 자기 캐릭터 하나를 봇으로 조작하는 2·3·4인 자동 플레이를 위한 계획이다. 아직 착수하지 않았다.

## 목표

- 네트워크 경로를 거친 실제 입력으로 2·3·4인 토마티나를 자동 진행하고, 게임 흐름과 화면 간 동기화를 함께 관찰한다.
- 실제 사람 플레이테스트를 대체하지 않는다(AGENTS.md). 결과는 "자동 검사"로만 보고한다.

## 현재 구조에서 막히는 지점

오프라인 봇은 한 월드 안의 4캐릭터를 호스트 권한 함수로 직접 조작한다. 온라인 클라이언트가 같은 함수를 부르면 호스트를 거치지 않아 화면이 갈라진다.

| 봇이 현재 직접 부르는 것 | 온라인에서 써야 하는 경로 |
|---|---|
| `shooter.player.input_*`, `shooter.firing`, `bottle_shake_input` (`_apply`) | 클라이언트: `world.debug_set_input` / `debug_set_aim` / `debug_input_shake` → `NetGame.send_input` (`net_game.gd:1700`) |
| `world.refill_for(peer, ...)` | `world._request_refill` (`mayo_prototype.gd:7443`) → `request_refill` |
| `world.begin_wipe_for(peer)` | `world._request_wipe` (`mayo_prototype.gd:7519`) → `request_wipe` |
| `world.tomato_action(peer, a)` | `world._request_tomato_action` (`mayo_prototype.gd:9794`) → `request_tomato_action` |
| `world.perform_context_action(peer, kind, id)` (구조·줍기) | 클라이언트: `NetGame.request_context_action` (`net_game.gd:2184`) |
| `world.create_avatar(9000+slot, ...)` 가짜 동료 생성 | 생성하지 않음. 동료는 실제 접속한 피어 |
| `set_character_variant` 직접 호출 | 로비의 `_choose_character` 경로로 캐릭터 선택 |

`_request_*` 래퍼는 이미 오프라인/온라인을 분기하므로, 봇이 래퍼만 쓰면 오프라인 동작도 유지된다.

## 구현 단계

1. **봇 두뇌와 조작 분리**: `player_bot_team.gd`의 판단 로직(`_think`, `_steer`, `_visible_enemy` 등)을 "의도"(이동/조준/발사/흔들기/행동 요청)를 내는 부분과, 의도를 적용하는 어댑터로 나눈다.
   - 오프라인 어댑터: 현행 방식(4캐릭터 직접 조작) 유지.
   - 온라인 어댑터: 자기 `_local` 하나만 조작하고, 모든 행동을 위 표의 래퍼/요청 경로로 보낸다.
2. **온라인 모드 `configure`**: 온라인이면 가짜 아바타를 만들지 않고 `world._local`에 두뇌 하나만 붙인다. 슬롯 번호는 로비 슬롯을 쓴다. 대형·리더 추종은 호스트(peer 1)를 리더로 본다.
3. **인지 차이 처리**: 클라이언트의 적·동료 위치는 보간된 복제 상태다. 사선 판정과 구조 대상 선택은 클라이언트가 본 값으로 하고, 거부된 요청(사거리 밖, 이미 구조됨)은 이벤트로 기록만 한다.
4. **경로 진행 판정**: 경로/안전지점 진행(`route_index`)은 호스트 봇만 결정한다. 클라이언트 봇은 리더를 따라간다. 체크포인트 확정은 기존 호스트 로직을 그대로 쓴다.
5. **실행 스크립트** `tests/play_tomatina_bots_online.gd`: 인자 `--role=host|client --players=N --seconds=S`.
   - 호스트는 로비를 열고 N명이 모이면 토마티나를 시작한다.
   - 각 인스턴스는 `reports/tomatina_bot_online_<role>_<peer>.json`에 기존 보고 항목과 네트워크 항목을 기록한다. 네트워크 항목은 거부된 요청 수, `dropped_packets`, 동기화 불일치 샘플이다.
   - 런처 셸 스크립트로 같은 PC에서 N개 인스턴스를 띄운다. 프로브 관례대로 `timeout`으로 감싼다.
6. **동기화 샘플링**: 일정 주기로 각 인스턴스가 피어별 위치·체력·소스·노즐 상태를 시각과 함께 기록한다. 종료 후 호스트 기록과 비교해 허용 오차(기존 `probe_network`의 "한 패킷 늦음" 규칙) 밖인 항목만 보고한다.
7. **회귀 검사**: 짧은 헤드리스 기능 검사 `probe_player_bots_online.gd`를 추가한다. 2인, 30초 안쪽이고, 봇 입력이 호스트에 도달하는지와 요청 경로만 쓰는지(직접 호출 0회) 확인한다.

## 실행 승인 규칙

- 2·3인 짧은 기능 검사는 로컬 연결 기능 회귀 검사로 본다.
- 4인 실행, 장시간 실행, FPS·부하 수치를 수집하는 실행은 AGENTS.md에 따라 매 실행 직전 범위와 예상 시간을 알리고 승인을 받는다.

## 한계

- 같은 PC의 루프백 연결이라 실제 지연·패킷 손실은 재현하지 않는다. 필요하면 별도 지연 주입 단계를 추가한다(별도 승인 대상).
- 봇은 게임 보행 격자로 길을 찾으므로 사람의 길 찾기 난이도를 반영하지 않는다(`player_bot_team_2026_11_17.md`와 동일).
