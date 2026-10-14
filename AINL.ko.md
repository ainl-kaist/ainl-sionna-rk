# sionna-rk에 대한 AINL 연구실 추가 사항

[English](AINL.md) | **한국어**

**NVlabs/sionna-rk v1.2.0 (`fa405b8`)** 위에 우리 연구실(**AINL**)이 작업한 내용입니다.

이 파일은 **포크 전용**이며 업스트림 `README.md`와 일부러 분리해 두었습니다. 그래서
업스트림과 동기화할 때(`git merge upstream/main`) 이 파일에서 충돌이 나지 않습니다.
여기 적힌 것은 모두 우리가 추가하거나 바꾼 것이고, 그 밖의 업스트림 파일은 건드리지
않았습니다.

> **라벨 규칙:** **`[SH]`** 태그가 붙은 메모는 성현(연구실 책임자)이 남긴 개인
> 기록입니다. 학생과 협업자가 일반 프로젝트 문서와 구분할 수 있도록 표시합니다.

## 환경 (두 가지 RAN 토폴로지)

이 저장소는 RAN을 **서로 배타적인 두 가지 토폴로지**로 실행할 수 있습니다. 둘은 같은
5G 코어, docker 네트워크(`oai-public-net`), 컨테이너 이름을 공유하므로 한 번에 하나만
실행됩니다. [scripts/switch_env.sh](scripts/switch_env.sh)로 둘 사이를 전환합니다
(`switch_env.sh status`로 어느 쪽이 떠 있는지 확인).

| | **단일 gNB** (원본) | **CU + 2×DU F1 핸드오버** (우리가 추가) |
|---|---|---|
| RAN | 단일 `oai-gnb` | `oai-cu` + `oai-du-pci0` + `oai-du-pci1` |
| 설정 디렉터리 | [config/rfsim/](config/rfsim/) (rfsim) · [config/b200/](config/b200/) (B200 무선) · [config/testing/](config/testing/) (CI) | [config/rfsim-ho/](config/rfsim-ho/) |
| rfsim 역할 | gNB = 서버, UE = 클라이언트 | **UE = 서버, DU = 클라이언트** (UE가 두 DU를 모두 들어야 함) |
| 핸드오버 | 해당 없음 | CU 내부 F1, 수동 트리거(`trigger_f1_ho` telnet) |
| 문서 위치 | 업스트림 [README.md](README.md) + `config/*/.env` 파일 | **[config/rfsim-ho/README.md](config/rfsim-ho/README.md)** |
| 기동 | `./scripts/switch_env.sh single [rfsim\|b200]` | `./scripts/switch_env.sh ho` |

- **단일 gNB**는 NVlabs/sionna-rk 기본 스택이며, 동작은 업스트림 `README.md`에
  설명되어 있습니다. 우리는 `config/*/.env` 프로파일(`rfsim` / `b200` / `testing`)과
  `config/common/` 공용 설정만 추가했습니다.
- **CU + 2×DU 핸드오버**는 전부 우리가 추가한 것입니다. 전용 문서는
  [config/rfsim-ho/README.md](config/rfsim-ho/README.md)입니다. 토폴로지 그림, rfsim
  클라이언트/서버 역할이 뒤바뀐 이유, 핸드오버를 수동으로 트리거하는 이유, 실행 명령,
  **"What differs from the main single-gNB stack"** 섹션, DU를 더 늘리는 방법,
  `bin/nr-softmodem-cu` CU 바이너리 패치가 들어 있습니다.

## 변경된 파일

아래 목록은 `scripts/update-ainl.sh`가 **자동 생성**합니다(`pre-commit` git 훅에서
실행). 현재 작업 상태를 NVlabs base `fa405b8`과 비교한 결과입니다. 손으로 고치지
마세요. AUTO 마커 사이의 내용은 모두 덮어써집니다.

<!-- AUTO:files start -->
- `.claude/settings.json` — 추가
- `.gitignore` — 수정
- `CLAUDE.md` — 추가
- `config/b200/.env.example.cuda.20260916` — 추가
- `config/b200/.env.example.n78` — 추가
- `config/b200/.env.example.n79` — 추가
- `config/b200/.env.example.n79.usrp_no_2.35D7C0A` — 추가
- `config/b200/.env.example.n79.usrp_no_2.35D7C0A.cuda` — 추가
- `config/common/docker-compose.override.yaml` — 추가
- `config/common/docker-compose.yaml` — 추가
- `config/common/flexric.conf` — 추가
- `config/common/gnb.sa.band78.106prbs.conf` — 추가
- `config/common/gnb.sa.band78.24prbs.conf` — 추가
- `config/common/gnb.sa.band78.51prbs.conf` — 추가
- `config/common/gnb.sa.band79.51prbs.conf` — 추가
- `config/common/mini_nonrf_config.yaml` — 추가
- `config/common/mysql-healthcheck.sh` — 추가
- `config/common/nrue.uicc.conf` — 추가
- `config/common/oai_db.sql` — 추가
- `config/common/sys_config.yaml` — 추가
- `config/rfsim-ho/.env.example` — 추가
- `config/rfsim-ho/.gitignore` — 추가
- `config/rfsim-ho/README.md` — 추가
- `config/rfsim-ho/docker-compose.yaml` — 추가
- `config/rfsim-ho/gnb-cu.conf` — 추가
- `config/rfsim-ho/gnb-du.conf` — 추가
- `config/rfsim-ho/neighbour-config.conf` — 추가
- `config/rfsim-ho/nrue.uicc.conf` — 추가
- `config/rfsim-ho/start_handover.sh` — 추가
- `config/rfsim/.env.example.cuda-used` — 추가
- `config/rfsim/.env.example.n78` — 추가
- `config/rfsim/.env.example.n79` — 추가
- `config/testing/.env.example` — 추가
- `doc/rfsim_vs_b200.md` — 추가
- `flexric-disk-growth-rootcause.md` — 추가
- `patches/flexric.patch` — 추가
- `patches/openairinterface5g.patch` — 수정
- `scripts/README.ko.md` — 추가
- `scripts/README.md` — 추가
- `scripts/channel_sweep.sh` — 추가
- `scripts/check-readme-sync.sh` — 추가
- `scripts/configure-system.dgx-spark.sh` — 수정
- `scripts/configure-system.sh` — 수정
- `scripts/hooks/pre-commit` — 추가
- `scripts/install-ue-status.sh` — 추가
- `scripts/install-ue-wwan-status.sh` — 추가
- `scripts/probe_env/mac-mini.out` — 추가
- `scripts/probe_env/probe_env.sh` — 추가
- `scripts/probe_env/samsung-wsl.out` — 추가
- `scripts/probe_env/spark-01.out` — 추가
- `scripts/probe_env/spark-02.out` — 추가
- `scripts/quickstart-oai.sh` — 수정
- `scripts/restart_ue.sh` — 추가
- `scripts/start_system.sh` — 수정
- `scripts/start_ue.sh` — 추가
- `scripts/start_ues.sh` — 추가
- `scripts/stop_system.sh` — 수정
- `scripts/stop_ue.sh` — 추가
- `scripts/stop_ues.sh` — 추가
- `scripts/switch_env.sh` — 추가
- `scripts/tests/test_ue_status.py` — 추가
- `scripts/tests/test_ue_wwan_status.py` — 추가
- `scripts/ue_status.py` — 추가
- `scripts/ue_wwan_status.py` — 추가
- `scripts/update-ainl.sh` — 추가
- `scripts/watch_MCS.sh` — 추가
- `uhd` — 추가
<!-- AUTO:files end -->

## 추가한 도구

- **[scripts/channel_sweep.sh](scripts/channel_sweep.sh)** — OAI rfsimulator
  (`chanmod`) 채널 파라미터를 값 목록에 따라 바꿔 가며 단계마다 iperf3 처리량을
  기록합니다.
  - 기본 파라미터는 **경로 손실(`ploss`)**입니다. 주의: rfsimulator에서 `ploss`는
    *이득*(`10^(ploss/20)`)으로 적용되므로 **음수 = 감쇠(멀어짐), 양수 = 증폭**입니다
    (약 +20 dB를 넘으면 int16 샘플이 클리핑됨). 시뮬레이션 내 SNR 근사:
    `SNR_dB ≈ ploss − 2·noise_power_dB`.
  - 기본 스윕 `10,5,0,-5,-10`은 안전한 처리량 최고점(+10 dB)에서 시작해 링크를 점점
    약하게 만들어, UE가 셀에서 멀어지는 상황을 모델링합니다.
  - rfsimulator telnet 서버로 채널을 제어하고(DL = UE의 model 0, UL = gNB의
    model 1), 정상 상태 수치를 얻기 위해 워밍업 버스트와 `iperf3 -O 2`를 쓰며,
    종료할 때 처리량이 가장 좋았던 값으로 되돌립니다.
  - 사용법: `./scripts/channel_sweep.sh -h`

- **[scripts/start_ue.sh](scripts/start_ue.sh)** — 소프트 UE 컨테이너**만** 시작/재시작하고
  (5G 코어와 gNB는 그대로 둠) UE가 attach할 때(`oaitun_ue1`)까지 기다립니다. 이
  빌드의 rfsim UE가 간헐적으로 중단되기(`buffer overflow detected`) 때문에 다시
  띄울 때 유용합니다.
  - 사용법: `./scripts/start_ue.sh [rfsim|b200]`

- **[scripts/stop_ue.sh](scripts/stop_ue.sh)** — `start_ue.sh`의 짝입니다. 기본 UE만
  `docker compose stop`합니다(코어 + gNB는 계속 실행). 다시 시작할 수 있도록
  `down`이 아닌 `stop`을 씁니다. `restart: unless-stopped` 정책은 수동 정지를
  존중하므로 `start_ue.sh`를 실행할 때까지 UE가 자동으로 재시작되지 않습니다.
  - 사용법: `./scripts/stop_ue.sh [rfsim|b200]`

- **[scripts/restart_ue.sh](scripts/restart_ue.sh)** — 기본 UE에 대해서만 `stop_ue.sh`
  다음 `start_ue.sh`를 실행하는 얇은 래퍼입니다(코어 + gNB는 계속 실행). 시스템
  전체를 재시작하지 않고 깔끔하게 detach/reattach할 때 씁니다. rfsim UE가 중단된
  뒤나, 새로 attach해야 하는 채널 모델 변경 뒤에 유용합니다.
  - 사용법: `./scripts/restart_ue.sh [rfsim|b200]`

- **[scripts/start_ues.sh](scripts/start_ues.sh)** — 같은 gNB에 **여러 UE**를 한꺼번에
  attach합니다(rfsim). 기본 `oai-nr-ue` 옆에 추가 UE(`oai-nr-ue2`, `oai-nr-ue3`, …)를
  띄우며, 각 UE는 자기 컨테이너 이름, public_net IP(`.151`, `.152`, …), 등록된 IMSI
  (`oai_db.sql`에 이미 있는 여분: `…001101`, `…016069`), CPU 스레드 풀(기본 UE의
  코어에서 오프셋)을 가집니다. OAI rfsim 서버는 클라이언트를 최대 250개까지 받으므로
  (DL은 각각에 브로드캐스트, UL은 합산) 풀 스택 UE 여러 개가 gNB 하나에 붙을 수
  있습니다. UE별 설정은 `nrue.uicc.conf`에서 `config/common/generated/`로
  렌더링됩니다(IMSI만 다르고 key/opc는 공유). 여분 IMSI 수(2개)가 상한이며, 더
  늘리려면 `oai_db.sql`에 가입자를 추가합니다.
  - 사용법: `./scripts/start_ues.sh [-n <count>] [rfsim]`  (기본 추가 UE 2개)

- **[scripts/stop_ues.sh](scripts/stop_ues.sh)** — `start_ues.sh`가 띄운 추가 UE
  (N≥2인 모든 `oai-nr-ue<N>`)를 제거합니다. 기본 UE는 건드리지 않습니다.
  - 사용법: `./scripts/stop_ues.sh`

- **[scripts/watch_MCS.sh](scripts/watch_MCS.sh)** — gNB 로그를 따라가며 채널 변화에
  실제로 반응하는 링크 품질 지표를 보여줍니다(OAI는 꾸준한 "SNR dB" 출력을 내지
  않음): UE별 **DL MCS/BLER**와 **UL MCS/SNR/BLER**. 각 줄 앞에는 **(1)** OAI 로그
  타임스탬프(UE별 통계 줄에는 자체 타임스탬프가 없어 블록 헤더 줄에서 추적)와
  **(2)** 현재 채널 값이 붙습니다. 스윕이 도는 동안에는 `channel_sweep.sh` 상태
  파일의 `ploss=N`, 그 외에는 rfsimulator telnet에서 바로 읽은 실시간 경로 손실입니다
  (스윕이 단일 클라이언트 telnet을 쓰는 동안에는 물러나는 백그라운드 폴러). 그래서
  스윕이 없어도 `ploss=N`과 링크 반응을 나란히 볼 수 있습니다. `ue` 모드는 대신 UE
  로그(harq / code rate / bit-symbol)를 읽습니다. `channel_sweep.sh`와 함께 쓰며,
  MCS는 트래픽이 흐를 때만 움직입니다.
  - 사용법: `./scripts/watch_MCS.sh [dl|ul|ue]`  (인자 없음 = 양방향)

- **[scripts/update-ainl.sh](scripts/update-ainl.sh)** — 위의 "변경된 파일" 영역을
  (`AINL.md`와 `AINL.ko.md` 모두) git에서 다시 생성합니다. `pre-commit` 훅이 자동으로
  실행하며, 손으로 실행해도 됩니다. 새로 clone한 뒤에는 훅을 한 번 설치합니다:
  `cp scripts/hooks/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit`

- **[scripts/check-readme-sync.sh](scripts/check-readme-sync.sh)** —
  `scripts/README.md`(영어)와 `scripts/README.ko.md`(한국어)의 구조(제목 수준, 스크립트
  항목, 주석을 뺀 코드 블록 명령)가 같은지 확인합니다. 두 README 중 하나가
  스테이징되면 `pre-commit` 훅이 스테이징된 쌍에 대해 실행하고, 어긋나면 커밋을
  막습니다. `AINL.md` / `AINL.ko.md` 쌍(이 파일)도 같은 방식으로 검사합니다.
  - 사용법: `./scripts/check-readme-sync.sh [<en.md> <ko.md>]`

## 환경 조정 (`config/` 안)

이 설정들은 `config/` 아래에 있습니다(이제 추적됨). 제외되는 것은 임시 디렉터리
`config/common/generated/`(`start_ues.sh`가 렌더링하는 UE별 설정)뿐이며 git에서
무시됩니다. 아래 조정을 이미 실행 중인 컨테이너에 다시 만들지 않고 적용하려면 함께
적힌 `docker update` / `docker compose up` 명령을 씁니다:

- **UE/gNB 자동 재시작** — `config/common/docker-compose.yaml`에서 `oai-gnb`와
  `oai-nr-ue` 서비스 모두에 `restart: unless-stopped`를 설정했습니다. rfsim
  softmodem은 channelmod 동작 중 간헐적으로 중단되는데(`buffer overflow detected`),
  이 설정으로 죽은 채 남아 수동 `./scripts/start_ue.sh`가 필요한 대신 스스로
  복구됩니다(docker가 자동 재시작하고 UE가 몇 초 안에 다시 attach). 이미 실행 중인
  컨테이너에 다시 만들지 않고 적용하려면:

  ```bash
  docker update --restart unless-stopped oai-gnb oai-nr-ue
  ```

  주의: 이것은 자가 복구일 뿐 수정이 아닙니다. 실행 중 softmodem이 죽으면 스윕의
  남은 단계는 여전히 잃을 수 있습니다. 진짜 수정은 OAI 이미지를 다시 빌드해야 합니다.

- **nearRT-RIC 자동 재시작** — `config/common/docker-compose.yaml`에서 `nearRT-RIC`
  서비스에 `restart: unless-stopped`를 설정했습니다. RIC는 gNB 연결이 끊길 때마다
  **`[E2AP]: SCTP_SHUTDOWN_EVENT`에서 segfault(exit 139)**가 납니다(원래 있던 FlexRIC
  버그). `oai-gnb`가 `restart: unless-stopped`이므로(위의 buffer overflow 자가 복구),
  이 설정이 없으면 gNB가 죽을 때마다 RIC가 조용히 영영 죽고(`restart: no`로
  배포되었음) xApp 모니터링이 끊깁니다. 이미 실행 중인 RIC에 다시 만들지 않고
  적용하려면(다시 만들면 gNB의 E2 등록이 사라져 복구하려면 gNB 재시작이 필요):

  ```bash
  docker update --restart unless-stopped nearRT-RIC
  ```

  주의: gNB가 RIC에 E2를 등록하기 전에 `monitor_xapp`이 시작되면 (설계상) 여전히
  종료됩니다. RIC를 다시 만들거나 RIC가 죽은 뒤의 깔끔한 복구 순서: 새
  `nearRT-RIC` 시작 → `docker restart oai-gnb`(새 RIC에는 수립된 E2 연결이 없으므로
  gNB를 재시작해도 segfault가 다시 일어나지 않음) → `docker compose up -d monitor_xapp`.

- **UE/gNB의 `SYS_PTRACE`** — 역시 `config/common/docker-compose.yaml`에서 `oai-nr-ue`와
  `oai-gnb`의 `cap_add` 목록에 `SYS_PTRACE`를 추가해, (비특권) 컨테이너 안에서
  `gdb`를 붙여 `buffer overflow detected` 중단을 디버깅할 수 있게 했습니다. 미리
  빌드된 바이너리에는 디버그 심볼이 모두 들어 있고, OAI는 일부러 `SIGABRT`/`SIGSEGV`를
  기본값으로 둡니다(`softmodem-common.c`의 핸들러가 코어 덤프를 위해 `#if 0` 처리됨).
  그래서 `gdb` 백트레이스가 바로 file:line을 알려 주며, 첫 추적에는 ASan 재빌드가
  필요 없습니다.

## 한국 이음5G(e-Um 5G) 밴드 n79 지원

한국의 특화망 5G 제도(**이음5G / e-Um 5G**)는 **4.72–4.82 GHz**(= 3GPP **밴드 n79**)와
28.9–29.5 GHz를 할당합니다. 4.7 GHz 대역은 우리 USRP **B200**(AD9364, 70 MHz–6 GHz)으로
쓸 수 있지만 28 GHz 대역은 안 됩니다. 밴드 n79 셀 프로파일을 추가했고 2026-09-14에
rfsim에서 종단 간 검증했습니다(UE 등록, PDU 세션 수립, UE ↔ ext-dn 양방향 ping).

- **[config/common/gnb.sa.band79.51prbs.conf](config/common/gnb.sa.band79.51prbs.conf)**
  — 51 PRB @ 30 kHz SCS, TDD. SSB는 **ARFCN 715680**(GSCN 8704 = 4735.20 MHz, n79
  동기 래스터 `8480 + 16k` 위), Point A는 **ARFCN 714964**(4724.46 MHz)입니다. 20 MHz
  채널이 4723.64–4743.64 MHz를 차지해 이음 할당 대역 안에 들어갑니다. band78 51-PRB
  설정과 SSB↔PointA 오프셋(716)이 같으므로 k_SSB 정렬이 그대로 유지됩니다.
- **예시 env 프로파일** — [config/rfsim/](config/rfsim/)과 [config/b200/](config/b200/)의
  `.env.example.n78` / `.env.example.n79`에 두 밴드가 바로 쓸 수 있는 `.env` 파일로
  들어 있습니다. 전환 예: `cp config/rfsim/.env.example.n79 config/rfsim/.env`. 실제
  `.env` 파일은 모두 로컬 설정이며 Git에서 무시됩니다. B200 USRP #2(시리얼
  `35D7C0A`)는 **n79** 프로파일을
  `cp config/b200/.env.example.n79.usrp_no_2.35D7C0A config/b200/.env`로 초기화합니다.
  새로 checkout한 경우 필요하면 handover/testing도
  `cp config/rfsim-ho/.env.example config/rfsim-ho/.env` 또는
  `cp config/testing/.env.example config/testing/.env`로 초기화합니다.

OAI의 함정 두 가지가 각각 디버깅 한 바퀴씩을 잡아먹었습니다. 둘 다 이제 설정 파일에
주석으로 남겨 두었습니다:

1. **CORESET0 인덱스**: OAI는 n79를 *최소 채널 대역폭 40 MHz* 밴드로 취급하므로
   (`nr_mac_common.c`, 약 3551행) 38.213 **Table 13-6**이 적용되고
   `controlResourceSetZero`는 **10 미만**이어야 합니다. band78의 인덱스 12를 쓰면 gNB
   시작 시 `AssertFatal`로 죽습니다. n79 설정은 51-PRB 캐리어에 맞는 인덱스 0(24 RB,
   2 심볼, 오프셋 0)을 씁니다.
2. **소프트 UE `--band 79`는 필수**: `nr-uesoftmodem`의 기본 밴드는 78입니다
   (`softmodem-common.h`, `.defintval=78`). `--band 79`가 없으면 UE가 4.7 GHz에서
   PBCH는 잘 디코딩하지만, RX indication을 채우다가 `to_nrarfcn()`에서 중단됩니다
   ("DL carrier frequency 4735200 kHz > 3790820").

**OTA 메모** `[SH]`: B200 송신 전력은 3.5 GHz보다 4.7 GHz에서 몇 dB 떨어집니다.
`att_tx/att_rx`와 `max_rxgain`을 다시 맞춰야 할 것이고, 안테나가 실제로 4.7 GHz를
지원하는지 확인해야 합니다. 무선 송출에는 과기정통부 이음5G 주파수 할당(또는 실험국
허가)이 필요하며, 그 전까지는 케이블/차폐 환경에서 시험합니다. 국내 판매 상용
단말은 대부분 n79를 지원하지 않습니다(공중망은 n78/n257). Quectel RM5xx 모듈은
지원합니다.

## FlexRIC 소스 패치 (`patches/flexric.patch`)

FlexRIC에는 컨테이너 쓰기 레이어에서 **끝없이** 커지며 호스트 디스크를 조용히 채우는
기록기가 두 개 있습니다(근본 원인은
[flexric-disk-growth-rootcause.md](flexric-disk-growth-rootcause.md) 참고.
`ainl-spark-02`에서는 이 두 파일이 합쳐서 약 1.1 TB까지 커졌음). `flexric`은 *중첩*
서브모듈(`ext/openairinterface5g/openair2/E2AP/flexric`, SHA로 고정)이라
`patches/openairinterface5g.patch`로는 **다룰 수 없습니다**. 수정은 별도의
`patches/flexric.patch`에 있으며, `scripts/quickstart-oai.sh`가 `git submodule update`
직후 flexric 서브모듈 안에서 적용하고(멱등), 빌드는
`docker/Dockerfile.flexric.ubuntu`(`COPY openair2/E2AP/flexric`)를 통해 이를 가져갑니다.

- **RIC `/log.txt` (nearRT-RIC)** — `src/ric/iApps/stdout.c`가 모든 MAC/RLC/PDCP
  indication을 회전 없이 `log.txt`(cwd `/`)에 쏟아냈습니다(약 888 GB 관측). 패치는
  `file_path`의 기본값을 `/dev/null`로 바꿉니다. 파일 로그를 다시 켜려면
  **`FLEXRIC_IAPP_LOG=<path>`**를 설정합니다.
- **xApp sqlite DB (monitor_xapp)** — `src/xApp/msg_handler_xapp.c`가 모든 E2
  indication을 `/tmp/xapp_db_<us>`에 영원히 INSERT했습니다(하루 약 24 GB, 약 197 GB
  관측). 우리 xApp은 ZMQ로 스트리밍하고 이 DB를 읽지 않으므로, 패치는 기본적으로
  `write_db_xapp`을 건너뜁니다. 되살리려면 **`FLEXRIC_XAPP_DB=1`**을 설정합니다.

적용하려면 다시 빌드합니다: `./scripts/build-oai-images.sh <ext/openairinterface5g>`
(`oai-flexric:latest` 재빌드). 그다음 각 호스트에서 `nearRT-RIC` / `monitor_xapp`을
다시 만듭니다. `quickstart-oai.sh`를 새로 실행하면 패치가 자동으로 적용됩니다.

## 변경 이력

이 표는 손으로 관리합니다(연구실 작업이 들어올 때마다 갱신). 위의 파일 목록은 자동
생성입니다. 원본 이력은 `git log --oneline fa405b8..ainl-dev`로 봅니다.

| 커밋 | 요약 |
|--------|---------|
| `311c9e1` | 한국 이음5G: 밴드 n79 gNB 설정(4.7 GHz) + n78/n79 .env 예시 |
| `7687a27` | restart_ue.sh; watch_MCS: 로그 타임스탬프 접두어 + 실시간 ploss 대체 |
| `2a59c8b` | config/ 추적 시작(연구실 설정, compose, 가입자 DB) |
| `da0f698` | 다중 UE rfsim 스크립트(start_ues/stop_ues) + stop_ue 추가 |
| `83c89c7` | channel_sweep: 상태 파일 전달 + 중단 시 채널 복원 |
| `43cf196` | watch_MCS: 방향별 지표 선택(dl/ul/ue) |
| `7fbefad` | scripts/watch_MCS.sh 추가 — 실시간 MCS/SNR/BLER 모니터 |
| `ab9f7c2` | channel_sweep: 단계 시간을 줄여 ploss가 약 2배 자주 바뀌게 함 |
| `395658a` | channel_sweep: 현실적인 경로 손실 스윕(ploss를 이득으로) + 견고성 개선 |
| `02b1ae2` | channel_sweep: 결과 열에 스윕 방향(DL/UL) 라벨 |
| `7f6a1e9` | rfsim 채널 스윕과 UE 전용 시작 스크립트 추가 |

## 저장소 / 브랜치 구성

- `origin`   → `sunghyunc7/ainl-sionna-rk` (우리 포크, 기본 push/pull 대상)
- `upstream` → `NVlabs/sionna-rk` (업데이트 pull 전용)
- `main`     → `upstream/main`을 그대로 따름(동기화를 위해 깨끗하게 유지)
- `ainl-dev` → 우리 작업 브랜치(연구실 작업은 모두 여기에)

### 업스트림과 동기화

```bash
git fetch upstream
git switch main && git merge upstream/main && git push
git switch ainl-dev && git merge main
```

### 개발 머신  `[SH]`

연구실 작업은 여러 호스트에서 이루어지며, 호스트들은 `origin/ainl-dev`로만 상태를
공유합니다. 따라서 브랜치가 갈라지지 않도록 **시작 전에 항상 `git pull`, 끝나면
`git push`** 합니다.

- **`ainl-spark-01`** — 주 개발 호스트(2026-06 기준).
- **`ainl-spark-02`** — 주로 한 학생이 자기 개발에 사용합니다.
  (`5ff39e3`까지의 초기 연구실 작업은 `ainl-spark-01`로 옮기기 전에 여기서 했습니다.)

Claude Code 설정: 공용 `.claude/settings.json`(엄선한 허용 목록)은 모두가 물려받도록
커밋되어 있습니다. 개인/호스트별 덮어쓰기는 git에서 무시되는
`.claude/settings.local.json`에 둡니다.
