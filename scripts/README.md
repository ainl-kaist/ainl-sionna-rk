# scripts/

Sionna-RK / OAI 스택을 위한 헬퍼 스크립트들을 분야별로 정리한 문서입니다. 대체로
라이프사이클 순서(호스트 설정 → 이미지 빌드 → 시스템 실행 → 실험)를 따르며, 마지막에
개발자/버전 추적용 헬퍼를 둡니다.

런타임 스크립트 상당수는 **config 프로필** 인자를 받아 어떤 `config/<profile>/.env`를
읽을지 선택합니다(기본값 `rfsim`). 유효 프로필: `rfsim`(소프트웨어 RF 시뮬레이터),
`b200`(실제 USRP B200 라디오).

일부 스크립트는 최상위 `make` 타깃으로 묶여 있습니다 — `make prepare-system`(호스트
설정), `make sionna-rk`(OAI 가져오기 + 빌드 + 설정 + 플러그인), `make build-gnb`(RAN
이미지).

## 목차
1. [호스트 설정 & 설치](#1-호스트-설정--설치)
2. [소스 가져오기, 패치 & 이미지 빌드](#2-소스-가져오기-패치--이미지-빌드)
3. [런타임 — 시스템 라이프사이클](#3-런타임--시스템-라이프사이클)
4. [런타임 — UE 제어](#4-런타임--ue-제어)
5. [런타임 — GPU MPS](#5-런타임--gpu-mps)
6. [런타임 — 환경 전환](#6-런타임--환경-전환)
7. [실험, 데모 & 모니터링](#7-실험-데모--모니터링)
8. [개발자 / 버전 추적 헬퍼](#8-개발자--버전-추적-헬퍼)

---

## 1. 호스트 설정 & 설치

머신당 1회 수행하는 설정(Jetson / Grace 계열 호스트). `make prepare-system`으로 묶여
있습니다. 일부는 `sudo`가 필요합니다.

- **`detect_host.sh`** — 보드 정보로 플랫폼을 감지합니다(예: "Orin Nano Super", "AGX
  Orin", "DGX Spark"). 다른 스크립트가 플랫폼별 설정을 고를 때 사용합니다.
- **`configure-system.sh`** — 호스트 설정을 적용합니다. 해당하는
  **`configure-system.<platform>.sh`**(`agx-orin`, `agx-thor`, `dgx-spark`,
  `orin-nano`)로 분기합니다. 플래그: `--force-platform <p>`, `--verbose`,
  `--dry-run`.
- **`build-custom-kernel.sh`** — 커스텀 L4T 커널을 빌드합니다(실시간 동작 / USRP에
  필요). `<destination_path>`, `--l4t-version`, `--clean`, `--dry-run` 등. `sudo`
  필요.
- **`install-custom-kernel.sh`** — 빌드된 커널 + 모듈을 설치하고 부트 시퀀스를
  갱신합니다. `sudo` 필요.
- **`install-usrp.sh`** — UHD/USRP 드라이버를 설치합니다(`b200` 프로필용).
  `--branch <branch|tag>`, `--force`, `--dry-run`.

## 2. 소스 가져오기, 패치 & 이미지 빌드

업스트림 OAI를 가져와 이 킷의 패치를 적용하고 docker 이미지를 빌드합니다.
`make sionna-rk`와 `make build-gnb`로 묶여 있습니다.

- **`quickstart-oai.sh`** — RAN 엔드투엔드: 고정된 버전의 OAI를 가져와 패치하고
  빌드합니다. `--source <kit-rootdir> --dest <oai5g_dir>`, `--oai-version`,
  `--no-build`, `--clean`, `--debug`, `--tag`.
- **`quickstart-cn5g.sh`** — OAI CN5G 코어에 대해 동일하게 수행. `--arch (x86|arm64)`,
  `--branch`, `--source`, `--dest` 등.
- **`patch-oai.sh`** — 이 킷의 소스 변경을 OAI RAN 트리에 적용합니다(quickstart-oai
  내부에서 사용).
- **`patch-oai-cn5g.sh`** — CN5G 트리에 패치를 적용합니다.
- **`generate-configs.sh`** — `config/` 트리를 생성합니다: 공통 파일은
  `config/common`으로, compose/env는 `config/<name>`으로 넣고 config별 패치를
  적용합니다.
- **`build-oai-images.sh`** — CUDA RAN 이미지를 빌드합니다(`ran-base-cuda` →
  `ran-build-cuda` → `oai-gnb-cuda`, `oai-nr-ue-cuda`, `oai-flexric`).
  `<oai5g_dir>`, `--debug`, `--tag`, `--no-cache`, `--force-platform`.
- **`build-cn5g-images.sh`** — CN5G 코어 이미지를 빌드합니다. `<oai-cn5g_dir>`,
  `--tag`, `--debug`.
- **`show_build_errors.sh`** — `build.log`를 스캔해 컴파일 에러를 출력합니다(빌드 실패
  후 빠른 원인 파악용).

## 3. 런타임 — 시스템 라이프사이클

단일 gNB 스택 전체를 올리고 내립니다.

- **`start_system.sh [rfsim|b200]`** — 단일 gNB 스택 전체를 기동: 5G 코어(`mysql`,
  `oai-amf`, `oai-smf`, `oai-upf`, `oai-ext-dn`), `nearRT-RIC`, `oai-gnb`, 기본
  `oai-nr-ue`, `monitor_xapp`. 각 컨테이너가 healthy가 될 때까지 대기합니다. 기본
  프로필 `rfsim`. 일반적인 진입점입니다.
- **`stop_system.sh`** — `config/common`에서 `docker compose down`: 컨테이너 **및
  공유 네트워크**를 제거합니다. 인자 없음.

> **두 개의 환경.** 단일 gNB 스택(`config/common`)과 CU+2×DU handover
> 스택(`config/rfsim-ho`, §6 참조)은 같은 네트워크(`oai-public-net`)와 컨테이너
> 이름을 공유하므로 **동시에 하나만 실행**됩니다. 다른 쪽을 시작하기 전에 먼저 내려야
> 합니다. 모니터링 스택은 별도 네트워크라 영향을 받지 않습니다.

## 4. 런타임 — UE 제어

코어 + gNB는 그대로 두고 UE만 관리합니다.

- **`start_ue.sh [rfsim|b200]`** — 기본 `oai-nr-ue`만 (재)기동합니다. healthy 상태가
  되고 터널(`oaitun_ue1`)에 IP가 붙을 때까지 대기하므로, 성공 시 바로 트래픽을 받을
  준비가 된 상태입니다. `oai-gnb`가 실행 중이 아니면 경고합니다.
- **`stop_ue.sh [rfsim|b200]`** — 기본 UE만 `docker compose stop`(`down` 아님)으로
  중지합니다. 컨테이너는 보존되며 `restart: unless-stopped` 정책보다 우선하므로,
  다시 시작하기 전까지 자동 재기동되지 않습니다.
- **`restart_ue.sh [rfsim|b200]`** — `stop_ue.sh` 후 `start_ue.sh`; 깔끔한
  분리/재접속. rfsim UE가 abort하거나 채널을 바꾼 뒤 유용합니다.
- **`start_ues.sh [-n <count>] [rfsim|b200]`** — 같은 gNB에 대해 **추가**
  soft-UE(`oai-nr-ue2`, `oai-nr-ue3`, …)를 기동합니다. 각 UE는 고유한 이름,
  IP(`192.168.71.151`, …), 프로비저닝된 IMSI, thread-pool을 갖습니다. `-n`은 기본
  2이며 `config/common/oai_db.sql`의 여분 IMSI 수만큼 제한됩니다. 기본 UE는 건드리지
  않습니다. (이들은 compose 서비스가 아니라 순수 `docker run` 컨테이너입니다.)
- **`stop_ues.sh`** — 모든 추가 UE(`oai-nr-ue<N>`, N ≥ 2)를 제거하고 기본 UE와 나머지
  시스템은 유지합니다. `stop_system.sh`는 이들을 제거하지 **않으므로**, 정리/전환 시
  이 스크립트를 먼저 실행하세요.

## 5. 런타임 — GPU MPS

CUDA Multi-Process Service. gNB PHY와 Sionna RT GUI가 GPU를 공유할 수 있게 합니다.
(compose 파일이 `CUDA_MPS_*` 환경변수로 참조합니다.)

- **`start_mps.sh`** — MPS 제어 데몬을 시작합니다.
- **`stop_mps.sh`** — 중지합니다.

## 6. 런타임 — 환경 전환

- **`switch_env.sh`** — 단일 gNB 환경과 handover 환경 사이를 전환합니다. *반대쪽*을
  완전히 내리고(추가 UE 포함) 요청한 쪽을 올립니다 — "한 번에 하나만" 규칙을 자동으로
  강제합니다.

  ```bash
  ./scripts/switch_env.sh ho              # -> handover 스택 (CU + 2x DU)
  ./scripts/switch_env.sh single          # -> 단일 gNB, rfsim (기본)
  ./scripts/switch_env.sh single b200     # -> 단일 gNB, b200 프로필
  ./scripts/switch_env.sh status          # 현재 어느 환경이 떠 있는지
  ./scripts/switch_env.sh down            # 둘 다 내림 (idle)
  ```

  내부 동작: `single` → `start_handover.sh down` 후 `start_system.sh <profile>`;
  `ho` → `stop_ues.sh` + `stop_system.sh` 후 `start_handover.sh up`.

  handover 스택 자체는 **`config/rfsim-ho/start_handover.sh
  {up|ho|status|watch|down}`**로 구동됩니다(`ho`가 F1 handover 1회 트리거). 전체
  설명은 `config/rfsim-ho/README.md`를 참조하세요.

## 7. 실험, 데모 & 모니터링

- **`channel_sweep.sh`** — rfsim `chanmod` 파라미터(예: path loss)를 스윕합니다. 각
  값마다 rfsimulator 텔넷으로 `channelmod modify …`를 보내고(DL은 UE, UL은 gNB
  경유), 짧은 iperf3를 돌린 뒤 처리량 표를 출력합니다.
- **`start_channel_emulation_demo.sh`** — 엔드투엔드 채널 에뮬레이션 데모: CUDA 채널
  에뮬레이터(ZMQ CIR 소스)로 네트워크를 띄우고 UE 접속을 기다린 뒤 iperf3를 돌리고,
  MPS와 함께 Sionna RT GUI를 실행합니다. 빌드된 이미지 + Sionna RT GUI 설치가
  필요합니다.
- **`watch_MCS.sh`** — OAI 로그를 따라가며 채널 변화에 실제로 반응하는 링크 품질
  지표를 보여줍니다(NR_MAC 통계에서 UE별 DL/UL MCS, BLER, SNR; UE 쪽 HARQ / code
  rate). `channel_sweep.sh`와 함께 쓰기 좋습니다.

## 8. 개발자 / 버전 추적 헬퍼

이 킷이 업스트림 OAI 대비 무엇을 바꾸는지 확인하고 변경 매니페스트를 유지합니다.
주로 CI와 git 훅에서 사용됩니다.

- **`get-oai-commit-versions.sh`** / **`get-oai-cn5g-commit-versions.sh`** — RAN /
  CN5G 소스의 고정된 업스트림 커밋/버전을 출력합니다.
- **`get-oai-changed-files.sh`** / **`get-oai-cn5g-changed-files.sh`** — 이 킷이
  업스트림 base 대비 수정한 파일들을 나열합니다.
- **`get-config-changes.sh`** — 생성된 config의 변경 사항을 보여줍니다.
- **`update-ainl.sh`** — `AINL.md`의 자동 관리 "Changed files" 영역을
  git 기준으로(NVlabs base 커밋 `AINL_BASE` 대비) 재생성합니다. pre-commit 훅에서
  실행됩니다.

---

## 전형적인 사용 흐름

단일 gNB에 추가 UE 2개, 그리고 UE 재시작:

```bash
./scripts/start_system.sh rfsim       # 코어 + gNB + 기본 UE
./scripts/start_ues.sh -n 2           # oai-nr-ue2, oai-nr-ue3 추가
./scripts/restart_ue.sh               # 기본 UE 재기동
./scripts/stop_ues.sh                 # 추가 UE 제거
./scripts/stop_system.sh              # 전체 종료
```

handover로 전환하고, handover 1회 실행 후, 다시 전환:

```bash
./scripts/switch_env.sh ho
cd config/rfsim-ho && ./start_handover.sh status   # UE가 DU0에
./start_handover.sh ho                              # UE -> DU1
cd ../.. && ./scripts/switch_env.sh single          # 다시 단일 gNB로
```
