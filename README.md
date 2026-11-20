# EV6 KR USB Wi-Fi 동글 시스템

> ⚠️ **[면책 고지](DISCLAIMER.md)를 먼저 읽어 주세요.**
> 비공식 개인 프로젝트입니다. **설치·사용으로 차량에 생기는 모든 문제의 책임은 사용자 본인에게 있습니다.**

**현재 버전: 4.12.0** (NEMESIS 패키지 id `usbwifi.hotspot`) · 🧪 시험판 [4.13.0](https://github.com/MANN1309/ev6-kr-usbwifi-dongle/releases/tag/v4.13.0): RTL8851BU 실험 지원 (저장소 `main`의 소스는 시험판 기준)

> 💡 **설치만 하실 분은 [Releases](https://github.com/MANN1309/ev6-kr-usbwifi-dongle/releases/latest)의 `EV6-dongle-USB-v버전.zip` 하나만 받으면 됩니다.** 저장소의 나머지 폴더는 소스 코드입니다.

## 📦 설치 방법

> ### 1. [Releases](https://github.com/MANN1309/ev6-kr-usbwifi-dongle/releases/latest)에서 `EV6-dongle-USB-v버전.zip` 받기
> ### 2. 압축을 풀고, 나온 폴더 **안의 내용**을 USB 맨 위에 복사
> ### 3. USB를 열었을 때 **`NEMESIS.data`와 `packages`가 바로 보이면** 완료 → 차에 꽂고 NEMESIS에서 설치
>
> ```
> USB 메모리
> ├── NEMESIS.data      ← 바로 보여야 함
> ├── packages/         ← 바로 보여야 함 (안의 zip은 풀지 않음)
> ├── 먼저_읽어주세요.txt
> └── 설명서/
> ```
> 설치 뒤 헤드유닛 재시작. 먼저 NEMESIS, HMG-API, Korea Projection이 설치되어 있어야 합니다(아래 링크).

## ✅ 연결과 정상 동작 확인
자세한 순서와 확인표: **[설치와 연결 방법](docs/설치와연결.md)**

| 단계 | 할 일 | 정상이면 |
|---|---|---|
| **1. 설치** (처음 한 번) | USB로 설치 → 헤드유닛 재시작 | 이 패키지의 Launch에 `bundled driver loaded, wlan0 present, chip mark yes, … aa_ap=1` |
| **2. 폰 등록** (처음 한 번) | 폰에서 무선 Android Auto 켜기 → 내비와 폰 양쪽 블루투스 등록을 지우고 새로 등록 → 내비에서 "무선 Android Auto 사용" 누르기 | 30초~1분 안에 안드로이드 오토 화면이 뜸 |
| **3. 다음부터** (매번) | 동글은 꽂아 둔 채 시동만 켬 | 40초 안에 저절로 연결 |

- 헤드유닛 재시작: RESET 버튼 또는 NEMESIS Manager의 재부팅 (시동만 끄면 안 됨)
- 연결이 안 되면 폰 블루투스를 껐다 켜 보세요.
- ⚠️ 재부팅 뒤에는 **3분 넘게 켜 두세요.** 3분 안에 재부팅을 반복하면 HMG-API가 무선 기능을 끕니다.

## 🗑 삭제 방법
> 정차 상태에서 **NEMESIS Manager → `USB WiFi dongle as built-in Wi-Fi` → 삭제** → 헤드유닛 재시작.
> 내비 업데이트나 서비스센터 입고 전에는 먼저 삭제하는 것을 권장합니다.

## 🔄 업데이트 안내
> 오류가 확인되면 **수정 중**이며, 수정이 끝나면 **[Releases의 최신 파일(Latest)](https://github.com/MANN1309/ev6-kr-usbwifi-dongle/releases/latest)에 반영**됩니다.
> 항상 최신 파일을 받아 같은 방법(USB → NEMESIS 설치)으로 설치하면 이전 판 위에 업데이트됩니다. 변경 내용은 [CHANGELOG](CHANGELOG.md).

내장 Wi-Fi 칩이 없는 국내형 기아 EV6 헤드유닛에서, USB Wi-Fi 동글을 차의 내장 Wi-Fi처럼 쓰게 해 주는 NEMESIS 패키지입니다.
핫스팟과 무선 안드로이드 오토 연결은 [Korea Projection](https://github.com/StopDragon/korea-projection)(별도 설치)이 맡고,
이 패키지는 그 아래에서 동글을 준비합니다.

## 만든 배경
처음에는 다른 차종(아이오닉5)용 USB Wi-Fi 패키지와 공개 자료를 참고해 시작했고, 이를 바탕으로 EV6 국내형에 맞게 발전시킨 시스템입니다.
핫스팟은 Korea Projection에 맡기고, 동글 준비·연결 유지·알림 숨김·끊김 기록은 이 프로젝트가 직접 만든 스크립트와 HMG-API 모드로 처리합니다.
참고한 시스템의 코드는 쓰지 않았고, GPL로 공개된 동글 드라이버만 원본 그대로 포함합니다([NOTICE](NOTICE.md)).

## 왜 새로 만들었나 (안전한 방식)
타 시스템 방식은 차량 시스템의 **핵심 파일(시스템 라이브러리)을 직접 고쳐야** 했습니다. 잘못되면 부팅 문제까지 생길 수 있어 위험하다고 판단했고,
같은 기능을 **핵심 파일을 고치지 않는 안전한 방법**으로 다시 만들었습니다.
- 이 패키지는 `/system`의 파일을 고치지 않습니다. 필요한 표시와 기록은 데이터 영역(`/data`)에만 둡니다.
- 동작 보완은 HMG-API의 모드 방식으로 하며, 설치·삭제를 HMG-API가 관리합니다. 차의 원본 파일이 시험한 펌웨어와 다르면 모드를 켜지 않습니다.
- 삭제하면 이 패키지가 만든 것을 지우고, 드라이버는 다음 재시작 때 내려갑니다.

## 먼저 설치할 것 (순서대로, 각 공식 안내를 따르세요)
| 순서 | 프로젝트 | 역할 | 받는 곳 | 제작자 시험 버전 |
|---|---|---|---|---|
| 1 | NEMESIS | 헤드유닛에 패키지를 설치·실행·삭제할 수 있게 해 주는 기반 (패키지 관리자) | [공식 사이트](https://xwtk.cloud/services/nemesis/) · [GitHub](https://github.com/xwtk/hmg_nemesis) | 차에 설치된 판 |
| 2 | HMG-API 코어 | 여러 모드가 차 시스템 기능을 바꿀 수 있게 해 주는 공통 플랫폼. 이 패키지의 연결 유지·알림 숨김 모드가 이 위에서 동작 | [GitHub](https://github.com/Open-HMG/HMG-API) · [설치 방법](https://github.com/Open-HMG/HMG-API/wiki/Installing-HMG-API) · [1.0.2](https://github.com/Open-HMG/HMG-API/releases/tag/v1.0.2) | 1.0.2 |
| 3 | Korea Projection | 동글로 핫스팟을 켜고 무선 안드로이드 오토 연결을 맡음 | [GitHub](https://github.com/StopDragon/korea-projection) · [1.7.2](https://github.com/StopDragon/korea-projection/releases/tag/v1.7.2) | 1.7.2 (그 뒤 판은 시험 전) |
| 4 | 이 패키지 | 동글 드라이버를 올리고 동글을 차의 Wi-Fi(wlan0)로 맞춤, 연결 유지, 알림 숨김, 끊김 기록 | [Releases](https://github.com/MANN1309/ev6-kr-usbwifi-dongle/releases) | 4.12.0 |

## 내려받기와 USB 만들기 (간단히)
1. [Releases](https://github.com/MANN1309/ev6-kr-usbwifi-dongle/releases)에서 **`EV6-dongle-USB-v4.12.0.zip`** 하나만 받습니다.
   (초록색 **Code → Download ZIP**은 소스 코드라서 설치용이 아닙니다.)
2. 압축을 풀면 `EV6-dongle-USB-v4.12.0` 폴더가 나옵니다. **그 폴더 안의 내용 전부**를 USB 맨 위에 복사합니다.
   USB를 열었을 때 바로 `NEMESIS.data` 와 `packages` 가 보여야 합니다. (폴더째 넣으면 NEMESIS가 찾지 못합니다)
3. 차에 꽂고 NEMESIS Manager에서 설치 → [설치와 연결 방법](docs/설치와연결.md) 3단계부터.

이미 NEMESIS USB를 쓰고 있다면 `NEMESIS.data`를 덮어쓰지 말고 [USB 구성](docs/USB구성.md)대로 한 묶음만 추가하세요.

## 무엇을 해 주나
- 동글 드라이버를 올리고, 동글을 차가 아는 Wi-Fi 이름(wlan0)으로 맞춥니다.
- 무선 안드로이드 오토가 잘 붙도록 도와줍니다(연결이 멈추면 자동으로 다시 시도).
- 동글을 꽂을 때 뜨는 순정 알림 2개("충전 모드만 지원", "지원하지 않는 미디어 기기")를 동글일 때만 숨깁니다.
- 연결이 끊기면 그 순간의 기록을 저장해 원인을 찾을 수 있게 합니다.
- 기록은 **개인정보를 빼고** 저장합니다: 연락처·통화기록·재생 곡·위치·전화번호·기기 이름·Wi-Fi 이름 줄은 빼고, 블루투스/Wi-Fi 주소는 끝 2자리만 남깁니다. 연결 분석에 필요한 차량 데이터만 남습니다.

## 지원 범위
| 항목 | 조건 |
|---|---|
| 차량 | 기아 EV6 국내형 펌웨어(`CVEV.KOR…`)에 설치됩니다. **실차 확인은 CVEV.KOR.0000.V039.001.260902**. 커널이 다른 펌웨어에서는 드라이버를 올리지 않고 상태 화면에 "kernel is not supported"로 알려 줍니다 |
| 대상 | **내장 Wi-Fi 칩이 없는 차** (내장 Wi-Fi가 있는 차는 이 패키지가 필요 없음) |
| 필요한 것 | NEMESIS, HMG-API 코어 1.0.2 이상, Korea Projection 1.7.2 (각 공식 배포처에서 설치) |
| 동글 | [지원 동글 목록](docs/지원동글.md) — 실차 확인은 TP-Link Archer T3U Nano 하나. 🧪 RTL8851BU(AX900급)는 시험판에서 실험 지원(실물 미확인) |
| 폰 | 무선 안드로이드 오토. **카플레이·아이폰은 시험하지 않음** |

## 제작자 차량 시험 조건
- 기아 EV6 국내형, CVEV.KOR.0000.V039.001.260902, 내장 Wi-Fi 없음
- HMG-API 코어 1.0.2(설치 스크립트만 보강한 판), Korea Projection 1.7.2(수정 없음)
- 동글: TP-Link Archer T3U Nano (USB ID 2357:012e)
- 폰: 안드로이드 1대, 무선 안드로이드 오토 + 클러스터/HUD 길안내
- **4.11.1 실차 확인 (2026-11-17):** 설치, 동글 준비, 무선 안드로이드 오토 연결이 이전 판과 같게 동작
- 끊김 기록(drop 로그)은 실제로 끊김이 생겼을 때 추가로 확인합니다

## 구성 (간단히)
| 폴더 | 내용 |
|---|---|
| `pkg/` | NEMESIS 패키지 본체: 설치 스크립트, 동글 관리 서비스, 드라이버(`modules/`), 드라이버 소스 정보(`source/driver/`) |
| `hmgapi_mod/` | 패키지 안에 함께 설치되는 HMG-API 모드 `ev6-kr-aa-keep`(연결 유지, 알림 숨김, 끊김 감지) 소스 |
| `docs/` | 사용 안내 |
| `usb/` | 설치 USB 묶음의 목록 파일(`NEMESIS.data`), 안내문, 묶음 만들기 스크립트 |
| `test_offline.sh` | PC에서 돌리는 스크립트 시험 |

직접 빌드하려면: [소스와 직접 빌드](docs/소스와빌드.md)

## 가져가서 발전시키기 (포크)
- 누구나 이 저장소를 포크해서 고치고 발전시킬 수 있습니다(AGPL-3.0). 개선한 내용은 Pull Request로 보내 주시면 반영을 검토합니다.
- 고쳐서 배포할 때는 [추가 조건](ADDITIONAL-TERMS.md)을 지켜 주세요: **출처 표기 유지, 수정판 표시, 전체 소스 공개(AGPL)**.
- **상업적 이용은 하지 말아 주세요** (판매, 유료 설치 대행 등). 무료로 나누려고 만든 프로젝트입니다. 자세한 내용: [ADDITIONAL-TERMS.md](ADDITIONAL-TERMS.md)

## 라이선스와 감사
- 이 저장소의 스크립트와 모드: **AGPL-3.0** ([LICENSE](LICENSE)) + [추가 조건](ADDITIONAL-TERMS.md), Copyright (c) 2026 MANN1309
- 동글 드라이버 `88x2bu.ko`: **GPL-2.0**, Realtek / [cilynx/rtl88x2bu](https://github.com/cilynx/rtl88x2bu) + GPL 패치 (제3자 구성요소). 자세한 내용은 [NOTICE](NOTICE.md)
- NEMESIS, HMG-API, Korea Projection은 각 제작자의 것이며 이 저장소에 포함하지 않습니다.
- "기아", "EV6"는 각 소유자의 상표이며, 이 프로젝트는 설명 목적으로만 이름을 씁니다.
