# RTL8851BU 실험 드라이버 소스 (GPL-2.0)

> ⚠️ **실험(EXPERIMENTAL):** 실물 동글로 시험하지 않았습니다. 이 차 커널용으로 빌드되는 것과, 빌드 검사(커널 버전 표시, 커널 심볼, 커널 설정, 모듈 파라미터)를 통과하는 것까지만 확인했습니다.

이 패키지의 `modules/8851bu.ko`(Realtek RTL8851BU USB Wi-Fi 6 드라이버)를 다시 빌드하는 데 필요한 파일입니다.

| 파일 | 내용 |
|---|---|
| `SOURCE.txt` | 원본 드라이버 주소와 커밋, 패치·커널·툴체인 정보, 빌드된 `8851bu.ko`의 해시 |
| `patches/` | 원본에 적용한 패치 4개 (이름 순서대로) |
| `build.sh`, `inner-build.sh` | 빌드 스크립트 (Docker, `../driver`와 같은 커널·툴체인 준비) |
| `config_tcc803x.txt` | 빌드에 쓴 차량 커널 설정 |
| `COPYING` | GPL-2.0 전문 |

## 원본 드라이버
Realtek 제조사 드라이버 https://github.com/fofajardo/rtl8851bu (GPL-2.0), 커밋 `9e37e7a1101316a05d5daede91549ea779b64539`

## 패치
1. `0001` 차량 플랫폼(Telechips tcc803x, ARMv7, Linux 3.18.24-tcc)용 빌드 설정
2. `0002` 드라이버가 잡은 동글을 usbfs로 열지 못하게 막음 (순정 안드로이드 오토의 "지원하지 않는 기기" 알림 방지)
3. `0003` 갑자기 뽑았을 때의 보호 (일부만 옮김)
4. `0004` Linux 3.18 / gcc 4.7로 빌드되게 고침

## 빌드
Docker가 필요합니다. 이 폴더에서 `./build.sh`를 실행하면 `out/8851bu.ko`와 `out/SOURCE.txt`가 만들어집니다.
