#!/usr/bin/env bash
# EE49904 AI-Native Networking — 실습 환경 점검 스크립트 (Phase 1 보조)
# 사용법:  bash probe_env.sh            (일부 항목은 sudo 없이 SKIP)
#          sudo bash probe_env.sh       (권장 — 커널 qdisc/netns 항목까지 실제로 시험)
# 결과를 통째로 복사해 보내주시면 됩니다. 시스템을 변경하지 않습니다(임시 인터페이스는 즉시 삭제).

echo "==================================================================="
echo " EE49904 lab environment probe   $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "==================================================================="

ok(){ printf "  %-34s %s\n" "$1" "$2"; }

# ---------- 1. 플랫폼 ----------
echo; echo "[1] PLATFORM"
UNAME=$(uname -s)
ok "uname" "$(uname -srm)"
if [ "$UNAME" = "Darwin" ]; then
  ok "macOS" "$(sw_vers -productVersion 2>/dev/null) $(uname -m)"
  ok "CPU / RAM" "$(sysctl -n hw.ncpu) cores / $(( $(sysctl -n hw.memsize) / 1073741824 )) GB"
else
  ok "distro" "$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
  ok "kernel" "$(uname -r)"
  if grep -qi microsoft /proc/version 2>/dev/null; then
    ok "WSL" "YES  (WSL_DISTRO_NAME=${WSL_DISTRO_NAME:-?})"
    ok "WSL interop" "$(wslinfo --version 2>/dev/null || echo n/a)"
  else
    ok "WSL" "no (native Linux or VM)"
  fi
  ok "CPU / RAM" "$(nproc) cores / $(free -g 2>/dev/null | awk '/^Mem:/{print $2}') GB"
  ok "disk free (\$HOME)" "$(df -h "$HOME" 2>/dev/null | awk 'NR==2{print $4}')"
  case "$PWD" in /mnt/[a-z]/*) ok "!! CWD" "Windows 드라이브(/mnt/…) — 빌드가 5~10배 느립니다. ~/ 로 옮기세요";; esac
fi

# ---------- 2. 커널 네트워크 기능 (리눅스/WSL 전용) ----------
if [ "$UNAME" != "Darwin" ]; then
echo; echo "[2] KERNEL NETWORK FEATURES  (lab #1 FlexRIC, #5 Mininet, #6 TSN 판정용)"
  if [ "$(id -u)" != "0" ]; then
    echo "  (sudo 없이 실행됨 — 모듈 존재 여부만 확인, 실제 생성 시험은 생략)"
    for m in sch_netem sch_taprio sch_etf sch_cbs sch_mqprio sch_htb openvswitch sctp; do
      printf "  %-34s " "$m"; modinfo "$m" >/dev/null 2>&1 && echo "모듈 있음" || echo "**없음**"
    done
  else
    ip link add probe0 type veth peer name probe1 2>/dev/null
    if ip link show probe0 >/dev/null 2>&1; then ok "veth 생성" "OK"; else ok "veth 생성" "**실패**"; fi
    # 주의: tbf/etf/cbs/taprio는 인자가 없으면 문법 오류가 난다.
    # "Specified qdisc kind is unknown" 만 커널 미지원으로 판정한다.
    for q in netem htb tbf prio fq_codel mqprio etf cbs taprio; do
      printf "  qdisc %-28s " "$q"
      err=$(tc qdisc replace dev probe0 root "$q" 2>&1)
      if echo "$err" | grep -qi "qdisc kind is unknown"; then echo "**커널 미지원**"
      else echo "커널 지원 O"; fi
      tc qdisc del dev probe0 root >/dev/null 2>&1
    done
    ip link del probe0 2>/dev/null
    printf "  %-34s " "netns 생성"; ip netns add probe_ns >/dev/null 2>&1 && { echo OK; ip netns del probe_ns; } || echo "**실패**"
    printf "  %-34s " "bridge 생성"; ip link add probebr type bridge >/dev/null 2>&1 && { echo OK; ip link del probebr; } || echo "**실패**"
    printf "  %-34s " "SCTP 소켓 (E2AP)"; modprobe sctp 2>/dev/null; python3 - <<'PY' 2>/dev/null || echo "**실패 — FlexRIC 불가**"
import socket,sys
s=socket.socket(socket.AF_INET, socket.SOCK_STREAM, 132); s.close(); print("OK")
PY
    printf "  %-34s " "IPv6 소켓 (OAI rfsim)"; python3 - <<'PY' 2>/dev/null || echo "**실패 — OAI rfsim 불가**"
import socket; s=socket.socket(socket.AF_INET6, socket.SOCK_STREAM); s.close(); print("OK")
PY
    printf "  %-34s " "bridge-nf-call-iptables"; cat /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null || echo "n/a (br_netfilter 미로드)"
  fi
fi

# ---------- 3. 툴체인 ----------
echo; echo "[3] TOOLCHAIN"
for t in python3 pip3 gcc g++ cmake ninja make git docker protoc; do
  printf "  %-34s " "$t"
  if command -v "$t" >/dev/null 2>&1; then "$t" --version 2>&1 | grep -v "^Picked up" | head -1; else echo "없음"; fi
done
for t in tc ip; do
  printf "  %-34s " "$t"
  if command -v "$t" >/dev/null 2>&1; then "$t" -V 2>&1 | head -1; else echo "없음"; fi
done

# ---------- 4. 네트워크 접근성 ----------
echo; echo "[4] NETWORK REACHABILITY"
for u in https://github.com https://pypi.org/simple/ https://gitlab.eurecom.fr \
         https://gitlab.com https://registry-1.docker.io/v2/ https://huggingface.co \
         https://registry.ollama.ai https://download.pytorch.org/whl/cpu/; do
  printf "  %-42s " "$(echo "$u" | sed 's|https://||;s|/.*||')"
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$u" 2>/dev/null)
  [ "$code" = "000" ] && echo "도달 불가" || echo "HTTP $code"
done

# ---------- 5. Docker ----------
echo; echo "[5] DOCKER"
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    ok "daemon" "실행 중"
    ok "server" "$(docker version --format '{{.Server.Version}}' 2>/dev/null)"
    printf "  %-34s " "hello-world pull"; timeout 120 docker pull -q hello-world >/dev/null 2>&1 && echo "OK" || echo "**실패**"
    printf "  %-34s " "batfish/allinone pull (~1.5GB)"
    if [ "${PULL_BIG:-0}" = "1" ]; then
      t0=$(date +%s); timeout 900 docker pull -q batfish/allinone >/dev/null 2>&1 \
        && echo "OK ($(( $(date +%s)-t0 ))초)" || echo "**실패**"
    else echo "생략 (PULL_BIG=1 로 실행하면 시험)"; fi
  else ok "daemon" "**정지됨 / 접근 불가**"; fi
else ok "docker" "설치 안 됨"; fi

# ---------- 6. GPU ----------
echo; echo "[6] GPU / ACCELERATOR"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null | sed 's/^/  /'
  ok "CUDA (nvcc)" "$(nvcc --version 2>/dev/null | tail -1)"
elif [ "$UNAME" = "Darwin" ]; then
  ok "Apple Silicon GPU" "$(sysctl -n machdep.cpu.brand_string 2>/dev/null) (Metal/MPS)"
else ok "NVIDIA GPU" "없음 (CPU-only)"; fi

# ---------- 7. LLM 로컬 추론 (lab #3 판정용) ----------
echo; echo "[7] LOCAL LLM  (lab #3 'LLM을 어디서 돌릴 것인가' 결정용)"
if command -v ollama >/dev/null 2>&1; then
  ok "ollama" "$(ollama --version 2>&1 | tail -1)"
  echo "  설치된 모델:"; ollama list 2>/dev/null | sed 's/^/    /' | head -8
  if [ "${LLM_BENCH:-0}" = "1" ]; then
    # 모델은 LLM_MODELS 로 바꿀 수 있음.  예: LLM_MODELS="qwen2.5:7b llama3.1:70b"
    for M in ${LLM_MODELS:-qwen2.5:7b}; do
      echo "  --- $M ---"
      ollama pull "$M" >/dev/null 2>&1
      # --verbose 는 stderr 로 eval rate(tok/s)를 낸다
      ollama run "$M" --verbose \
        'Write a Cisco IOS interface configuration for a routed port with IP 10.0.0.1/30, MTU 9000, and OSPF area 0. Output config only.' \
        2>&1 >/dev/null | grep -E "eval rate|eval count|total duration|load duration" | sed 's/^/    /'
    done
  else
    echo "  (벤치마크 생략 — 실행하려면:  LLM_BENCH=1 LLM_MODELS=\"qwen2.5:7b\" bash probe_env.sh)"
  fi
else ok "ollama" "설치 안 됨"; fi

echo; echo "=== 끝 — 위 출력을 전부 복사해 보내주세요 ==="
