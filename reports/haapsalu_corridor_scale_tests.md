# Haapsalu 45 m 코리도어 스케일 테스트

## 보존 범위

이 작업은 별도 `assets/scale_tests/` 데이터와 테스트 씬만 추가했다.
`main_real_compare.tscn`, 기존 넓은 `RealGuide`, `main.tscn`,
`scripts/street_map.gd`, `project.godot`은 수정하지 않았다.

사용 중심선은 다음 두 개뿐이다.

- Karja: Kalda 교차점부터 Rootsiturg 남측 진입부
- Rootsiturg 외곽 루프 전체

Ehte 서·동측, 북동측 Lossiplats 분기와 LAVA 광장은 제외했다.

## 범위와 건물 분류

1배 로컬 좌표 기준 중심선 범위:

- X: -5.92..62.07 m
- Z: -194.65..0.00 m

45 m를 더한 코리도어 경계상자:

- X: -50.92..107.07 m
- Z: -239.65..45.00 m

판정은 각 LoD2 건물의 평면 외곽선과 두 중심선 중 가까운 쪽 사이의 최소거리다.

- 넓은 원본 범위의 건물: 197동
- 45 m 코리도어와 닿는 건물: 47동, 표시 및 삼각망 충돌체 생성
- 코리도어 밖: 150동, `Row3` 그룹, `visible = false`, 충돌체 없음
- 지형: 코리도어 안의 DTM 삼각형만 유지하고 삼각망 충돌체 생성

`CorridorGraybox.corridor_distance_m`는 기본값 45 m인 export 변수다. 실행 전
Inspector에서 바꾸거나 런타임에 바꾸면 건물 표시, `Row3`와 건물 충돌체가 다시
분류된다. 지형 메시의 물리적 절단 경계는 생성 시 지정한 45 m다.

## 1배 측정값

- Karja 길이: 164.67 m
- Rootsiturg 루프 길이: 109.36 m
- 합계: 274.03 m
- 두 동선 유효 단면의 파사드 간 중앙값: 14.33 m
- 기존 Karja 204 m 비교축의 대표 중앙값: 13.80 m
- 최대 유효 폭: 40.66 m
- 최대 폭 위치: Rootsiturg 루프 시작 후 70.0 m,
  로컬 X 45.03 m / Z -193.29 m

## 스케일별 결과

| 씬 | 배율 | Karja+루프 총길이 | 중앙 폭 | 최대 폭 | 최대 폭 로컬 위치 |
|---|---:|---:|---:|---:|---:|
| `test_scale_227.tscn` | 2.27 | 622.05 m | 32.53 m | 92.29 m | X 102.22 / Z -438.76 m |
| `test_scale_180.tscn` | 1.80 | 493.26 m | 25.79 m | 73.18 m | X 81.06 / Z -347.92 m |

스케일은 각 씬 스크립트의 `SCALE_FACTOR` 상수로 정의하며 X/Y/Z에 동일하게
적용한다. 2.56 m 플레이어 캡슐은 스케일하지 않고 Karja/Kalda 원점에 둔다.

## 스크린샷

- 2.27배: `reports/test_scale_227_spawn.png`
- 1.80배: `reports/test_scale_180_spawn.png`

두 화면 모두 불투명 흰색 LoD2 그레이박스, 잘린 DTM, 어두운 중심선과 주황색
2.56 m 플레이어를 사용한다.

## 검사

`tests/probe_scale_maps.gd`가 각 씬에서 다음을 검사한다.

- 배율 상수 적용
- 45 m export 값
- 코리도어 안 47동과 Row3 150동
- 건물 47개 + 지형 1개의 충돌체
- Row3 건물에 충돌체가 없음
- 플레이어 X/Z 원점 및 2.56 m 캡슐
- 스폰 지점의 지형 레이캐스트 충돌

검사 결과:

- `MAYO_MAP_OK test_scale_227.tscn`
- `MAYO_MAP_OK test_scale_180.tscn`
