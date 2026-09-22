# Haapsalu Maitsete Promenaad RealGuide 보고서

## 구현 결과

`main_real_compare.tscn`은 원본 `main.tscn`을 그대로 인스턴스하고, 확장된
`RealGuide`를 형제 노드로 겹친다. `main.tscn`, `scripts/street_map.gd`,
`project.godot`은 수정하지 않았다. `RealGuide`는 편집기에서 보이고 게임 실행
시에는 `scripts/real_guide.gd`의 기본값에 따라 숨겨진다.

확장 범위는 Karja/Kalda 교차점 원점을 기준으로 X -190..235 m, Z -320..80 m,
즉 425 × 400 m이다. 다음을 포함한다.

- Karja tänav: Kalda tänav 교차점부터 Rootsiturg 남측 진입부까지
- Rootsiturg 외곽 동선 전체 루프
- Ehte tänav: Rootsiturg 서측 짧은 진입부와 동측 32번 방향 구간
- Rootsiturg에서 Karja/Lossiplats 방향으로 갈라지는 북동측 대각선 구간
- Karja 동측 LAVA 위치의 광장 참고 면
- 위 동선 바깥의 배경 건물 여유 폭

동선은 `RealGuide/Routes` 아래에서 도로별 노드와 개별 GLB로 분리했다. 색상은
Karja 자홍색, Rootsiturg 노란색, Ehte 청색, 북동측 분기 보라색이며, LAVA
광장은 주황색 반투명 면이다.

## 원본과 좌표

- 기관: Maa- ja Ruumiamet(에스토니아 국토·공간개발청)
- 건물: Haapsalu linn LoD2, Wavefront OBJ + MTL + FWT + PRJ
- 지형: DTM 1 m, 도엽 `62371`, float32 GeoTIFF 5,000 × 5,000
- 도로 중심선 측정 보조: 저장된 OpenStreetMap XML
  (`assets/real_guide/source/haapsalu_festival_area_osm.xml`)
- 출력: `assets/real_guide/derived/*.glb`(glTF 2.0 binary)
- 취득일: 2026-09-21

공식 다운로드 안내:

- LoD2: https://geoportaal.maaamet.ee/est/ruumiandmed/geo3d/laadi-3d-andmed-alla-p833.html
- 높이자료: https://geoportaal.maaamet.ee/eng/spatial-data/elevation-data/download-elevation-data-p664.html
- 도엽 체계: https://geoportaal.maaamet.ee/eng/spatial-data/map-sheet-indexes-and-coordinate-systems-p359.html

원본 CRS는 EPSG:3301 / L-EST97이며 단위는 m이다. 로컬 원점은
Karja–Kalda 중심선 교차점이다.

- WGS84: 23.5362231 E, 58.9465648 N
- EPSG:3301: E 473304.699 m, N 6534255.864 m
- DTM 기준고: 4.860 m
- Godot: `X = Easting - 473304.699`, `Y = Height - 4.860`,
  `Z = 6534255.864 - Northing`

확장 범위의 EPSG:3301 경계는 도엽 `62371`의 E 470000..475000 m,
N 6530000..6535000 m 안에 모두 들어간다. 따라서 DTM 추가 도엽이나 모자이크는
필요하지 않았다.

출력에는 LoD2 건물 197동(13,046 삼각형)과 DTM 427 × 402 정점
(341,652 삼각형)이 들어 있다.

## 동선 길이

길이는 저장된 OSM 중심선을 EPSG:3301로 투영한 뒤 미터 단위로 합산했다.
전체 길이는 각 구간을 한 번씩 더한 네트워크 길이이며 분기 간 이동을 위한
되돌아가기 거리는 포함하지 않는다.

| 동선 | 1배 | 2.27배 |
|---|---:|---:|
| Karja: Kalda–Rootsiturg | 164.67 m | 373.80 m |
| Rootsiturg 전체 루프 | 109.36 m | 248.25 m |
| Ehte 서측 진입부 | 12.60 m | 28.60 m |
| Ehte 동측 32번 방향 | 33.39 m | 75.80 m |
| Ehte 합계 | 45.99 m | 104.40 m |
| 북동측 Karja/Lossiplats 분기 | 128.24 m | 291.10 m |
| **전체 동선** | **448.26 m** | **1,017.55 m** |

현재 GLB와 씬 변환은 모두 1배다. 2.27배 값은 보고용 환산치이며 노드에 스케일을
적용하지 않았다.

## LAVA 광장

첨부 축제 지도에서 LAVA가 놓인 위치와 일치하는 OSM의 잔디/보행 공간 외곽
(way 1467386804)을 참고 면으로 사용했다.

- 최소 회전 경계상자: 약 24.06 × 8.90 m
- 면적: 약 125.81 m²
- 2.27배 환산 치수: 약 54.62 × 20.19 m
- 2.27배 환산 면적: 약 648.27 m²

이 외곽은 축제 지도의 무대 위치를 공간 데이터에 대응시킨 비교 기준이며,
주최 측이 제공한 공식 무대 설치·안전구역 경계는 아니다.

## 13.8 m 폭의 측정 기준

13.8 m는 차도 폭이나 특정 한 지점의 폭이 아니다. Karja/Kalda 원점부터
Rootsiturg 동측 굴곡까지 이어지는 204 m 비교 중심선에 5 m 간격의 직교 단면을
만들고, 각 단면이 양쪽 Maa-amet LoD2 건물 외곽과 처음 만나는 점 사이의
파사드-대-파사드 거리를 구했다.

- 중심선 양쪽 1..45 m 안에서 모두 건물 교차점이 잡힌 단면만 채택
- 유효 단면: 21개
- 중앙값: 13.80 m
- 10 백분위: 11.89 m
- 90 백분위: 30.17 m
- 차도뿐 아니라 보도와 건물 전면의 열린 공간도 포함

Rootsiturg처럼 한쪽 또는 양쪽이 열리는 곳에서는 값이 커진다. 따라서 13.8 m는
일반적인 건물 사이 거리의 대표값이지 전 구간 고정 폭이 아니다.

## 기존 거리와의 이전 비교

기존 거리 원본은 수정하지 않았다. 최초 204 m 메인 축과 기존 추상화 중심선의
비교 결과도 수치 파일에 유지했다.

| 항목 | 기존 거리 | 실측 기준 | 차이 |
|---|---:|---:|---:|
| 메인 중심선 길이 | 289.42 m | 204.00 m | 기존이 1.419배(+85.42 m) |
| 거리 폭 | 36.864 m(일정) | 중앙값 13.80 m | 약 2.67배 |

## 재생성 및 수치 원본

```sh
python3 tools/real_guide/build_real_guide.py
```

정밀 수치와 사용한 OSM way ID는
`assets/real_guide/derived/real_guide_metrics.json`에 있다.

출처 표기: “Hoonete 3D ruumiandmed ja DTM 1 m: Maa- ja Ruumiamet, 2026.”
도로 측정 보조선은 OpenStreetMap contributors, ODbL 자료를 사용했다.
