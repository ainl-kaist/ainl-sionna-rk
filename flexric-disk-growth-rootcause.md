# FlexRIC 무한 디스크 증가 — 근본 원인 및 해결안 (sionna-rk 작업용)

> 작성 배경: 2026-07-24, `ainl-spark-02`의 Host Disk Usage가 37.9%(≈1.4TB/3.7TB)까지
> 오른 것을 조사한 결과, prometheus/loki가 아니라 **FlexRIC 두 컨테이너의 무한 증가
> 파일**이 원인이었다. 임시로 비워 341GB(10%)로 회수했으나, 스택이 도는 한 다시 찬다.
> 근본 해결은 **sionna-rk 쪽 FlexRIC**에서 해야 하므로 이 문서로 정리한다.

관측된 사용량(정리 직전):

| 컨테이너 | 파일 | 크기 | 이미지 |
|---|---|---|---|
| `nearRT-RIC` | `/log.txt` | **888 GB** | oai-flexric:latest |
| `monitor_xapp` | `/tmp/xapp_db_<us>` (+`-wal`,`-shm`) | **197 GB** | oai-flexric:latest |

두 파일 모두 Docker **볼륨이 아닌 컨테이너 writable 레이어**에 쌓여
`docker system df`의 "Containers"를 부풀렸다. 증가 속도는 대략 xApp DB 기준 ~24GB/일,
`/log.txt`는 그보다 훨씬 빠르다(UE·트래픽에 비례).

---

## 원인 A — nearRT-RIC `/log.txt` (888GB)

RIC 바이너리(PID 1)가 **모든 MAC indication을 `mac_stats: ...` 라인으로 파일에 덤프**한다.
sionna-rk 설정(compose/스크립트)에는 `> /log.txt` 리다이렉트가 **없다** — 경로가 flexric
소스에 하드코딩돼 있다.

**소스 위치** (sionna-rk 트리 내):
`ext/openairinterface5g/openair2/E2AP/flexric/src/ric/iApps/stdout.c`

```c
// line 43
const char* file_path = "log.txt";      // cwd 가 / 라서 실제로는 /log.txt

// line 76-89: init_fp()
const char* write = "w";                // append 아님 → 프로세스가 fd offset 유지
fp = fopen(file_path, write);

// line 92~: print_mac_stats() 가 indication 마다 fp 에 기록
```

- 이 "stdout iApp"은 RIC에 기본 등록되어(`src/ric/iApp/e42_iapp_api.c` `init_iapp_api`),
  `notify_msg_iapp_api()`(`src/ric/msg_handler_ric.c`)를 통해 **모든 indication마다** 호출된다.
- 로테이션/크기 제한/레벨 없음. `"w"` 모드라 **재시작 시 truncate**되지만, 실행 중에는
  단조 증가한다. (그래서 실행 중 `: > /log.txt`로 비워도 프로세스 offset이 유지돼
  sparse hole만 생기고 apparent size는 그대로 남는다.)

### 해결안 A

**권장(근본): 소스 패치 후 이미지 재빌드**
`stdout.c`에서 파일 기록을 없애거나 `/dev/null`로 돌린다. 가장 간단한 변경:
```c
const char* file_path = "/dev/null";    // line 43
```
또는 `print_mac_stats()`의 파일 기록부를 제거/가드(env 플래그로 조건부)한다.
그 후 재빌드:
```bash
cd ~/sionna-rk
./scripts/build-oai-images.sh        # 내부에서 --target oai-flexric-fixed 로 oai-flexric:latest 재빌드
# (docker/Dockerfile.flexric.ubuntu 기준, build-oai-images.sh:76-79)
```

**대안(재빌드 없이, compose 한 줄): `/dev/null` 바인드 마운트**
`config/common/docker-compose.yaml`의 `nearRT-RIC` 서비스 `volumes:`에 추가:
```yaml
    nearRT-RIC:
        ...
        volumes:
            - ../common/flexric.conf:/usr/local/etc/flexric/flexric.conf
            - /dev/null:/log.txt          # ← 추가: 로그를 그냥 버림
```
`fopen("log.txt","w")`가 바인드된 `/dev/null`을 열어 기록이 버려진다. RIC cwd가 `/`이므로
`log.txt` == `/log.txt`가 맞다(확인됨). 가장 빠른 완화책.

---

## 원인 B — monitor_xapp `/tmp/xapp_db_<us>` sqlite (197GB)

FlexRIC xApp SDK가 **수신하는 모든 E2 indication을 sqlite DB에 무한 적재**한다.
경로는 `flexric.conf`로 지정된다.

**설정 위치:** `config/common/flexric.conf`
```ini
[XAPP]
DB_DIR = /tmp/          # → /tmp/xapp_db_<timestamp> 로 DB 생성
```

**소스 위치:**
- DB 생성: `.../flexric/src/xApp/e42_xapp.c:215-236`
  ```c
  char* dir = get_conf_db_dir(args);            // flexric.conf 의 DB_DIR
  ...
  n = snprintf(filename, 255, "%sxapp_db_%ld", dir, now);   // /tmp/xapp_db_<us>
  init_db_xapp(&xapp->db, filename);
  ```
- 매 indication 기록: `.../flexric/src/xApp/msg_handler_xapp.c:268`
  ```c
  write_db_xapp(&xapp->db, &ans.val.e2_node, &msg_disp.rd);   // indication 마다 INSERT
  ```
- 기록 구현: `.../flexric/src/xApp/db/db.c`, `.../db/sqlite3/sqlite3_wrapper.c`
- `flexric.conf`에 **DB 비활성 옵션은 없다**(`get_conf_db_dir`가 비면 컴파일 기본값
  `XAPP_DB_DIR` 사용). 즉 설정만으로는 끌 수 없다.

우리 `monitor_xapp`는 `zmq_stats_server.py`(`plugins/ric_xapps/src/zmq_stats_server.py`)로
ZMQ 실시간 전달만 하고 **이 sqlite를 조회하지 않는다** → DB 적재는 순수 낭비다.

### 해결안 B

**권장(근본): 소스 패치 후 재빌드**
`write_db_xapp(...)` 호출(msg_handler_xapp.c:268)을 제거하거나, `init_db_xapp`/`write_db_xapp`를
env 플래그로 조건부(no-op) 처리한다. 그 후 위와 동일하게 `build-oai-images.sh`로 재빌드.
`monitor_xapp`만 쓰면 DB 자체를 완전히 끄는 것이 안전하다.

**대안 1(재빌드 없이): 크기 제한 tmpfs**
`config/common/docker-compose.yaml`의 `monitor_xapp`에 `/tmp`를 상한 있는 tmpfs로:
```yaml
    monitor_xapp:
        ...
        tmpfs:
            - /tmp:size=1g          # RAM 상한 1GB. 초과 시 sqlite write 실패 위험
```
⚠️ 주의: DB가 상한에 닿으면 xApp이 오류/크래시할 수 있다. 증가 속도(~24GB/일)를 감안하면
상한을 넘기는 시점에 문제가 생기므로 **재시작 스케줄과 병행**해야 실효가 있다. 근본책 아님.

**대안 2(재빌드 없이): 주기적 재시작 + 옛 DB 삭제**
xApp는 재시작 때마다 새 `xapp_db_<us>`를 만들고 옛 파일은 orphan으로 남는다. cron/타이머로:
```bash
docker restart monitor_xapp
# 재시작 후, 활성 DB(가장 최신)만 남기고 옛 xapp_db_* 삭제
docker exec monitor_xapp sh -c 'cd /tmp && ls -t xapp_db_* 2>/dev/null | grep -v -- -wal | grep -v -- -shm | tail -n +2 | xargs -r rm -f'
```
증가 자체는 못 막지만 상한을 두는 스톱갭. (2026-07-24 spark-02 정리도 이 방식으로 회수함.)

---

## 소스 패치를 sionna-rk 방식으로 반영하기

sionna-rk는 `ext/openairinterface5g` 서브모듈을 **`patches/openairinterface5g.patch`**로
패치한 뒤 `--target oai-flexric-fixed`로 빌드한다(빌드 이름의 "fixed"가 이 패치 적용본).
따라서 원인 A/B의 소스 수정은 트리를 직접 고치기보다 **이 패치에 hunk를 추가**하는 것이
정석이다. 대략적인 흐름:

```bash
cd ~/sionna-rk/ext/openairinterface5g      # 패치가 적용되는 서브모듈 루트

# 1) 원인 A: RIC 로그 끄기
#    openair2/E2AP/flexric/src/ric/iApps/stdout.c 의 file_path 를 /dev/null 로,
#    또는 print_mac_stats 의 파일 기록부 제거
# 2) 원인 B: xApp DB 끄기
#    openair2/E2AP/flexric/src/xApp/msg_handler_xapp.c:268 write_db_xapp 제거/조건부화

# 3) 변경을 patches/openairinterface5g.patch 에 반영 (예: 현재 diff 를 갱신)
git diff -- openair2/E2AP/flexric/src/ric/iApps/stdout.c \
            openair2/E2AP/flexric/src/xApp/msg_handler_xapp.c
#    → 이 diff hunk 들을 ../../patches/openairinterface5g.patch 에 병합

# 4) 재빌드
cd ~/sionna-rk && ./scripts/build-oai-images.sh
```
> 주의: 서브모듈 트리를 직접 커밋하지 말 것. sionna-rk의 재현성은 `patches/*.patch`로
> 관리되므로, 수정은 반드시 패치 파일에 담아야 다른 기기/클린 빌드에서도 반영된다.

---

## 이번에 spark-02에서 한 임시 조치 (참고)

근본 수정 전까지의 임시 회수. **다시 찬다.**
```bash
# A) RIC 로그 즉시 비우기 (비파괴적, 실험 무영향, 약 860GB 회수)
docker exec nearRT-RIC sh -c ': > /log.txt'

# B) xApp DB: 재시작으로 fd 해제 후 옛 파일 삭제 (xApp 잠깐 끊김, 약 197GB 회수)
docker restart monitor_xapp
docker exec monitor_xapp sh -c 'rm -f /tmp/xapp_db_<옛timestamp> /tmp/xapp_db_<옛timestamp>-wal /tmp/xapp_db_<옛timestamp>-shm'
```
결과: 디스크 `1.4T(40%) → 341G(10%)`.

---

## 권장 작업 순서 (sionna-rk)

1. `stdout.c:43`을 `/dev/null`로 바꾸거나 파일 기록 제거 (원인 A)
2. `msg_handler_xapp.c:268`의 `write_db_xapp` 제거/조건부화, 또는 최소한 `monitor_xapp`용으로 DB off (원인 B)
3. `./scripts/build-oai-images.sh`로 `oai-flexric:latest` 재빌드
4. **모든 spark 기기**에서 새 이미지로 `nearRT-RIC`/`monitor_xapp` 재생성
   (spark-02뿐 아니라 spark-01 등도 동일 증상 → 이미지 레벨 수정이 전 기기에 반영됨)
5. 재빌드가 어려우면 임시로 compose 마운트(원인 A의 `/dev/null` 바인드 + 원인 B의 재시작 cron)로 상한

### 검증
```bash
# 며칠 가동 후 다시 커지지 않는지
docker ps -as --format '{{.Names}}\t{{.Size}}' | grep -E 'nearRT-RIC|monitor_xapp'
df -h /
# 컨테이너 내부
docker exec nearRT-RIC sh -c 'ls -lh /log.txt; du -h /log.txt'
docker exec monitor_xapp sh -c 'ls -lhS /tmp | head'
```

## 관련 파일 요약

| 대상 | 파일 | 핵심 |
|---|---|---|
| RIC 로그 | `ext/openairinterface5g/openair2/E2AP/flexric/src/ric/iApps/stdout.c` | L43 `file_path="log.txt"`, L85 `fopen("w")`, L93 `print_mac_stats` |
| RIC iApp 등록 | `.../flexric/src/ric/iApp/e42_iapp_api.c`, `.../ric/msg_handler_ric.c` | 매 indication `notify_msg_iapp_api` |
| xApp DB 경로 | `config/common/flexric.conf` | `[XAPP] DB_DIR=/tmp/` |
| xApp DB 생성 | `.../flexric/src/xApp/e42_xapp.c` | L215-236 `xapp_db_<us>` 생성 |
| xApp DB 기록 | `.../flexric/src/xApp/msg_handler_xapp.c` | L268 `write_db_xapp` (indication마다) |
| xApp 구현 | `.../flexric/src/xApp/db/db.c`, `.../db/sqlite3/sqlite3_wrapper.c` | sqlite INSERT |
| 이미지 빌드 | `scripts/build-oai-images.sh` (L76-79), `ext/openairinterface5g/docker/Dockerfile.flexric.ubuntu` | `--target oai-flexric-fixed` |
| 컨테이너 정의 | `config/common/docker-compose.yaml` | L187 `nearRT-RIC`, L201 `monitor_xapp` |

---

## 해결 완료 (2026-07-24) — sionna-rk 반영 내용

근본 수정을 **소스 패치 + 재현 배선**으로 반영했다. 원인 문서가 놓친 핵심은
**`flexric`이 SHA로 고정된 *중첩(nested) 서브모듈*** 이라 기존
`patches/openairinterface5g.patch`로는 건드릴 수 없다는 점 — 별도
`patches/flexric.patch`로 처리했다.

| 파일 | 변경 |
|---|---|
| `ext/.../flexric/src/ric/iApps/stdout.c` | `file_path` 기본값 `"log.txt"` → `"/dev/null"`. `FLEXRIC_IAPP_LOG=<path>`로 재활성. (원인 A) |
| `ext/.../flexric/src/xApp/msg_handler_xapp.c` | `write_db_xapp` 를 기본 skip, `FLEXRIC_XAPP_DB=1`로 복원. `<stdlib.h>` 추가. (원인 B) |
| `patches/flexric.patch` (신규) | 위 두 hunk. flexric 서브모듈 루트 기준(`a/src/...`). 정/역방향 clean 적용 검증됨. |
| `scripts/quickstart-oai.sh` | `git submodule update` 직후 flexric 서브모듈에 `flexric.patch` **멱등** 적용. |
| `AINL.md` | "FlexRIC source patches" 섹션 문서화. |

> ⚠️ `ext/openairinterface5g`는 outer repo에서 git-ignore 대상이라, 재현성은
> **전적으로 `patches/flexric.patch` + quickstart 배선**에 달려 있다. 서브모듈
> 트리를 직접 커밋하지 말 것.

### 호스트별 배포 체크리스트 (rollout)

이미지 레벨 수정이므로 **모든 spark 호스트**에서 재빌드 + 컨테이너 재생성해야
실제로 반영된다.

- [x] **ainl-spark-02** — 소스 패치/커밋/푸시 + 재빌드·재생성 (이 작업 세션, 2026-07-24)
- [ ] **ainl-spark-01** — `git pull` 후 아래 절차로 배포 **(미적용 — primary 호스트)**

### 기존 호스트에 배포하는 절차 (이미 repo/서브모듈이 체크아웃된 경우)

`quickstart-oai.sh`를 다시 돌리지 않는 이상, 이미 체크아웃된 flexric 서브모듈은
**패치가 자동 반영되지 않는다.** 아래처럼 수동 적용 후 재빌드한다:

```bash
cd ~/sionna-rk
git pull                                   # patches/flexric.patch + quickstart 변경 수신

# 1) 이미 체크아웃된 flexric 서브모듈에 패치 멱등 적용
FLEX="$PWD/ext/openairinterface5g/openair2/E2AP/flexric"
PATCH="$PWD/patches/flexric.patch"
if git -C "$FLEX" apply --check "$PATCH" 2>/dev/null; then
    git -C "$FLEX" apply "$PATCH"; echo "applied"
elif git -C "$FLEX" apply --reverse --check "$PATCH" 2>/dev/null; then
    echo "already applied"
else
    echo "WARN: flexric.patch does not apply cleanly"; fi

# 2) flexric 이미지 재빌드 (oai-flexric:latest)
./scripts/build-oai-images.sh ext/openairinterface5g

# 3) 두 컨테이너만 새 이미지로 재생성 (compose project=common)
cd config/common
docker compose up -d --force-recreate --no-deps nearRT-RIC monitor_xapp

# 4) 검증 — 며칠 가동 후에도 안 커지는지
docker exec nearRT-RIC   sh -c 'ls -lh /log.txt; du -h /log.txt'          # /dev/null 이어야 함
docker exec monitor_xapp sh -c 'ls -lhS /tmp/xapp_db_* 2>/dev/null | head' # 새 DB 없거나 미증가
df -h /
```

> 완전 클린 배포라면 `scripts/quickstart-oai.sh --clean ...` 만으로도 flexric
> 패치가 자동 적용된다(위 1단계 불필요). 위 절차는 **재클론 없이** 기존 호스트를
> 갱신하는 용도.
