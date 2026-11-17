# 설치 USB 구성

Releases의 `EV6-dongle-USB-v버전.zip` 을 풀면 나오는 폴더의 **안의 내용**을 USB 맨 위에 복사합니다.

```
USB 메모리
├── NEMESIS.data            NEMESIS가 읽는 패키지 목록 (이름 바꾸지 않음)
├── packages/
│   └── usbwifi.hotspot.zip 설치 파일 (압축 풀지 않음)
├── 먼저_읽어주세요.txt      면책 고지 요약, USB 넣는 법, 읽는 순서
└── 설명서/
    ├── 1_면책고지.txt
    ├── 2_설치와연결.txt
    ├── 3_지원동글.txt
    ├── 4_라이선스와출처.txt
    ├── 5_변경기록.txt
    ├── 6_포크와상업이용.txt
    └── LICENSE_AGPL-3.0.txt
```

## 이미 NEMESIS USB를 쓰고 있다면
`usbwifi.hotspot.zip` 을 기존 `packages/` 에 넣고, 기존 `NEMESIS.data` 맨 끝에 아래 묶음을 추가합니다.
`N` 은 기존 마지막 번호 + 1.

```
[package.N]
path=packages/usbwifi.hotspot.zip
name=USB WiFi dongle as built-in Wi-Fi (KR v4.12)
short-desc=Driver, wlan0, AA keep-connected, no popups, safe drop logs
published=2026-11-16
```

> ⚠️ 설치·사용으로 생기는 문제의 책임은 사용자 본인에게 있습니다. ([면책 고지](../DISCLAIMER.md))
