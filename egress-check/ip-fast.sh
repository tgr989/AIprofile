#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 家宽VPS分流一键自查检测 Egress-Check Fast (基于 v2.19.6 深度性能优化版)
# 鸣谢：https://ip.net.coffee · 上游：https://github.com/AIFansX/egress-check
#
# 面向千级/万级大名单（如 tw-top1000 / global-top5000）深度重构：
#   - 单次 awk 规则解析（消除每行 9 次子进程 fork）
#   - 并行探测默认/IPv4/IPv6 真实出口（免受 IPv6 丢包串行阻塞）
#   - 并发 DNS 预解析 + 目标 IP 去重（共享同 VIP 的域名仅测一次 MTR）
#   - 优先沿用基准协议且干净首跳即刻返回（修复目标禁 Ping 时误发 TCP 并覆盖证据）
#   - 事件驱动并发调度（Bash 4.3+ wait -n，消除 sleep 轮询与进度条 stat 风暴）
#   - 无子 Shell 真内存 IP_CACHE + 并行批量 ASN 预取 + 运行期负缓存
#   - 零 awk 延迟着色 + 单次 jq 批量输出 JSON（消除每域名 fork jq/awk）
#
# 退出码: 0=成功  1=配置/依赖错误  2=有域名探测失败
#
# 环境变量:
#   MTR_CONCURRENCY(默认16)  MTR_REPEAT_CONCURRENCY(默认4)  DNS_CONCURRENCY(默认32)
#   LOOKUP_CONCURRENCY(默认8)  MTR_INTERVAL(可选,传给 mtr -i)
#   EGRESS_RULES  EGRESS_CACHE  IP_LOOKUP_CACHE_TTL  EGRESS_BASE_MODE
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

VERSION="2.19.6-fast"
export LC_NUMERIC=C
if (( BASH_VERSINFO[0] < 4 )); then
    printf 'Bash 4.0+ is required.\n' >&2; exit 1
fi
HAS_WAIT_N=0
if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) )); then
    HAS_WAIT_N=1
fi
HAS_EPOCHSECONDS=0
if (( BASH_VERSINFO[0] >= 5 )); then
    HAS_EPOCHSECONDS=1
fi
BRAND_URL="https://ip.net.coffee"

# ─── 颜色 ──────────────────────────────────────────────────────────────────
USE_COLOR=1
[[ -t 1 ]] || USE_COLOR=0
set_colors() {
    if [[ $USE_COLOR -eq 1 ]]; then
        R=$'\e[0m'; BOLD=$'\e[1m'; DIM=$'\e[2m'
        RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'
        BLUE=$'\e[34m'; MAGENTA=$'\e[35m'; CYAN=$'\e[36m'; GRAY=$'\e[90m'; BROWN=$'\e[38;5;130m'
    else
        R=""; BOLD=""; DIM=""
        RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""; GRAY=""; BROWN=""
    fi
}
set_colors
err() { printf "%s[!]%s %s\n" "$RED" "$R" "$*" >&2; }

SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" 2>/dev/null && pwd || pwd)"
RULES_FILE="${EGRESS_RULES:-$SCRIPT_DIR/rules.conf}"
RULES_EXPLICIT="${EGRESS_RULES:+1}"
if [[ -n "${EGRESS_CACHE:-}" ]]; then
    CACHE_DIR="$EGRESS_CACHE"
else
    if [[ -z "${HOME:-}" ]]; then
        err "HOME 未设置且未指定 EGRESS_CACHE."
        exit 1
    fi
    CACHE_DIR="$HOME/.cache/egress-check"
fi

PASS_MODE="auto"
OUTPUT_JSON=0
COMPACT_OUTPUT=0
INTERACTIVE=0
ONLY_CAT=""
SKIP_PATH_LOOKUP=0
MTR_TIMEOUT="${MTR_TIMEOUT:-20}"
MTR_MAXTTL="${MTR_MAXTTL:-30}"
MTR_COUNT="${MTR_COUNT:-3}"
MTR_ATTEMPTS="${MTR_ATTEMPTS:-4}"
MTR_BUDGET="${MTR_BUDGET:-45}"
MTR_NICE="${MTR_NICE:-10}"
MTR_INTERVAL="${MTR_INTERVAL:-}"
MTR_CONCURRENCY="${MTR_CONCURRENCY:-16}"
MTR_REPEAT_CONCURRENCY="${MTR_REPEAT_CONCURRENCY:-4}"
DNS_CONCURRENCY="${DNS_CONCURRENCY:-32}"
LOOKUP_CONCURRENCY="${LOOKUP_CONCURRENCY:-8}"
PATH_SUMMARY_LIMIT="${PATH_SUMMARY_LIMIT:-8}"
MTR_BASE_DOMAIN="${MTR_BASE_DOMAIN:-google.com}"
EGRESS_BASE_MODE="${EGRESS_BASE_MODE:-auto}"
API_TIMEOUT="${API_TIMEOUT:-5}"
ENV_TIMEOUT="${ENV_TIMEOUT:-5}"
IP_LOOKUP_CACHE_TTL="${IP_LOOKUP_CACHE_TTL:-86400}"
UA="egress-check/${VERSION} (+${BRAND_URL})"

DEFAULT_RULES=$(cat <<'EOF'
# Built-in default rules. Format: Category | Domain | reserved | reserved | Note
AI|openai.com|||OpenAI
AI|chatgpt.com|||ChatGPT
AI|anthropic.com|||Anthropic
AI|claude.ai|||Claude
AI|gemini.google.com|||Google Gemini
AI|ai.google.dev|||Google AI Studio
AI|perplexity.ai|||Perplexity
AI|grok.com|||Grok
AI|x.ai|||xAI
AI|pixtv.ai|||PixTV
AI|copilot.microsoft.com|||Microsoft Copilot
AI|huggingface.co|||Hugging Face
Social|x.com|||X
Social|twitter.com|||Twitter legacy domain
Social|facebook.com|||Meta
Social|instagram.com|||Meta
Social|threads.net|||Meta
Social|whatsapp.com|||Meta
Social|tiktok.com|||TikTok
Social|telegram.org|||Telegram
Social|discord.com|||Discord
Social|reddit.com|||Reddit
Social|linkedin.com|||LinkedIn
Social|pinterest.com|||Pinterest
Social|line.me|||LINE
Social|zoom.us|||Zoom
Streaming|netflix.com|||Netflix
Streaming|youtube.com|||YouTube
Streaming|disneyplus.com|||Disney+
Streaming|hulu.com|||Hulu
Streaming|primevideo.com|||Prime Video
Streaming|max.com|||Max
Streaming|spotify.com|||Spotify
Streaming|twitch.tv|||Twitch
Streaming|static-cdn.jtvnw.net|||Twitch CDN
Streaming|linetv.tw|||LINE TV
Streaming|bilibili.com|||Bilibili
Streaming|iq.com|||iQIYI International
Streaming|crunchyroll.com|||Crunchyroll
Streaming|tv.apple.com|||Apple TV
Search|google.com|||Google Search
Search|bing.com|||Bing
Search|duckduckgo.com|||DuckDuckGo
Search|yahoo.com|||Yahoo
Search|baidu.com|||Baidu
Search|yandex.com|||Yandex
Search|brave.com|||Brave
Developer|github.com|||GitHub
Developer|gitlab.com|||GitLab
Developer|npmjs.com|||npm
Developer|pypi.org|||PyPI
Developer|docker.com|||Docker
Developer|stackoverflow.com|||Stack Overflow
Developer|cloudflare.com|||Cloudflare
Developer|vercel.com|||Vercel
Developer|netlify.com|||Netlify
Cloud|aws.amazon.com|||AWS
Cloud|azure.microsoft.com|||Microsoft Azure
Cloud|cloud.google.com|||Google Cloud
Cloud|digitalocean.com|||DigitalOcean
Cloud|linode.com|||Linode
Cloud|vultr.com|||Vultr
Cloud|hetzner.com|||Hetzner
Crypto|binance.com|||Binance
Crypto|coinbase.com|||Coinbase
Crypto|okx.com|||OKX
Crypto|kraken.com|||Kraken
Crypto|bybit.com|||Bybit
Crypto|bitget.com|||Bitget
Crypto|coingecko.com|||CoinGecko
Crypto|etherscan.io|||Etherscan
Gaming|steampowered.com|||Steam Store
Gaming|steamcommunity.com|||Steam Community
Gaming|steamcdn-a.akamaihd.net|||Steam CDN
Gaming|epicgames.com|||Epic Games
Gaming|battle.net|||Battle.net
Gaming|ea.com|||EA
Gaming|playstation.com|||PlayStation
Gaming|xbox.com|||Xbox
Gaming|nintendo.com|||Nintendo
Ecommerce|amazon.com|||Amazon
Ecommerce|ebay.com|||eBay
Ecommerce|aliexpress.com|||AliExpress
Ecommerce|taobao.com|||Taobao
Ecommerce|tmall.com|||Tmall
Ecommerce|jd.com|||JD
Ecommerce|temu.com|||Temu
Ecommerce|shein.com|||SHEIN
Ecommerce|walmart.com|||Walmart
Ecommerce|target.com|||Target
Ecommerce|etsy.com|||Etsy
Ecommerce|rakuten.co.jp|||Rakuten Japan
Ecommerce|coupang.com|||Coupang
Ecommerce|mercadolibre.com|||Mercado Libre
Ecommerce|shopee.com|||Shopee Global
Ecommerce|shopee.sg|||Shopee Singapore
Ecommerce|shopee.tw|||Shopee Taiwan
Ecommerce|shopee.co.id|||Shopee Indonesia
Ecommerce|shopee.vn|||Shopee Vietnam
Ecommerce|shopee.com.br|||Shopee Brazil
Ecommerce|lazada.com|||Lazada Global
Ecommerce|lazada.sg|||Lazada Singapore
Ecommerce|lazada.co.id|||Lazada Indonesia
Ecommerce|lazada.com.my|||Lazada Malaysia
Ecommerce|lazada.co.th|||Lazada Thailand
Ecommerce|lazada.vn|||Lazada Vietnam
Ecommerce|lazada.com.ph|||Lazada Philippines
China|qq.com|||Tencent QQ
China|wechat.com|||WeChat
China|weibo.com|||Weibo
China|douyin.com|||Douyin
China|zhihu.com|||Zhihu
China|163.com|||NetEase
China|sina.com.cn|||Sina
China|aliyun.com|||Alibaba Cloud
EOF
)

default_mtr_concurrency() {
    local cores=1
    if command -v nproc >/dev/null 2>&1; then
        cores="$(nproc 2>/dev/null || printf '1')"
    elif command -v getconf >/dev/null 2>&1; then
        cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')"
    fi
    [[ "$cores" =~ ^[0-9]+$ ]] || cores=1
    if (( cores <= 1 )); then printf '2'
    elif (( cores == 2 )); then printf '3'
    else printf '4'; fi
}

usage() {
    cat <<EOF
家宽VPS分流一键自查检测 Egress-Check Fast v${VERSION}   鸣谢：${BRAND_URL}
Usage: $(basename "$0") [options]
  (no flag)           自动检测网络环境并分别比较 IPv4、IPv6 的可见首跳 ASN
  -I, --interactive   交互菜单: 输入 0-7 选择检测模式，默认 1
  -4, --ipv4          只跑 IPv4
  -6, --ipv6          只跑 IPv6
  --json              JSON 输出
  --compact           简洁报告，略去路径 ASN 摘要和基准匹配组的域名
  --no-color          关闭颜色
  --low-resource      低并发低压力模式
  -j, --concurrency N 指定 MTR 组内并发数 (默认 16)
  --max-ttl N         指定 MTR 最大跳数 (默认 30；大名单首跳扫可用 8)
  --first-hop-only    大名单极速模式：限制 max-ttl=8 并跳过沿途多跳 ASN 反查
  --no-path-lookup    仅反查可见首跳 ASN，跳过完整路径多跳 ASN 反查
  --only <CAT>        只跑指定分类
  --rules <path>      自定义 rules.conf / CSV 名单
  -h, --help          帮助
EOF
}

interactive_menu() {
    cat <<EOF

家宽VPS分流一键自查检测 Egress-Check Fast v${VERSION}
请选择检测模式:

  0) 简洁模式          基于完整检测，展示更加简洁的排版效果
  1) 【默认】完整检测  网络环境 + IPv4 + IPv6，完整结果
  2) 只检测 IPv4
  3) 只检测 IPv6
  4) 只检测指定分类    AI / Social / Streaming / Search / Developer / Cloud / Crypto / Gaming
  5) 低并发低压力模式  根据CPU 自适应并发 + 减少探测包，更流畅
  6) JSON 输出         适合 cron / 监控
  7) 大名单极速模式    并发 24 + max-ttl=8 + 仅查首跳 + 关闭颜色

EOF
    local choice cat_name
    printf "请输入 0-7 [默认1]: "
    IFS= read -r choice
    choice="${choice:-1}"
    case "$choice" in
        0) PASS_MODE="auto"; COMPACT_OUTPUT=1 ;;
        1) PASS_MODE="auto"; COMPACT_OUTPUT=0 ;;
        2) PASS_MODE="v4-only" ;;
        3) PASS_MODE="v6-only" ;;
        4)
            printf "请输入分类名 [Social]: "
            IFS= read -r cat_name
            ONLY_CAT="${cat_name:-Social}"
            PASS_MODE="auto"
            ;;
        5)
            MTR_CONCURRENCY="$(default_mtr_concurrency)"
            MTR_REPEAT_CONCURRENCY=2
            MTR_COUNT="${MTR_LOW_COUNT:-2}"
            MTR_NICE="${MTR_LOW_NICE:-15}"
            ;;
        6) OUTPUT_JSON=1 ;;
        7)
            MTR_CONCURRENCY=24
            MTR_MAXTTL=8
            SKIP_PATH_LOOKUP=1
            USE_COLOR=0
            set_colors
            ;;
        *) err "无效选择: $choice"; exit 1 ;;
    esac
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -I|--interactive) INTERACTIVE=1 ;;
        -4|--ipv4)        PASS_MODE="v4-only" ;;
        -6|--ipv6)        PASS_MODE="v6-only" ;;
        --json)           OUTPUT_JSON=1 ;;
        --compact)        COMPACT_OUTPUT=1 ;;
        --no-color)       USE_COLOR=0; set_colors ;;
        --low-resource)
            MTR_CONCURRENCY="$(default_mtr_concurrency)"
            MTR_REPEAT_CONCURRENCY=2
            MTR_COUNT="${MTR_LOW_COUNT:-2}"
            MTR_NICE="${MTR_LOW_NICE:-15}"
            ;;
        -j|--concurrency) [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || { err '--concurrency 需要正整数'; exit 1; }; MTR_CONCURRENCY="$2"; shift ;;
        --max-ttl)        [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || { err '--max-ttl 需要正整数'; exit 1; }; MTR_MAXTTL="$2"; shift ;;
        --first-hop-only) MTR_MAXTTL=8; SKIP_PATH_LOOKUP=1 ;;
        --no-path-lookup) SKIP_PATH_LOOKUP=1 ;;
        --only)           [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || { err '--only 需要分类名'; exit 1; }; ONLY_CAT="$2"; shift ;;
        --rules)          [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || { err '--rules 需要文件路径'; exit 1; }; RULES_FILE="$2"; RULES_EXPLICIT=1; shift ;;
        -h|--help)        usage; exit 0 ;;
        *) err "未知参数: $1"; usage >&2; exit 1 ;;
    esac
    shift
done

[[ $INTERACTIVE -eq 1 ]] && interactive_menu >&2

for setting in MTR_TIMEOUT MTR_MAXTTL MTR_COUNT MTR_ATTEMPTS MTR_BUDGET IP_LOOKUP_CACHE_TTL PATH_SUMMARY_LIMIT API_TIMEOUT ENV_TIMEOUT; do
    value="${!setting}"
    [[ "$value" =~ ^[1-9][0-9]*$ && ${#value} -le 7 ]] || { err "$setting 必须是正整数"; exit 1; }
done
for setting in MTR_CONCURRENCY MTR_REPEAT_CONCURRENCY DNS_CONCURRENCY LOOKUP_CONCURRENCY; do
    value="${!setting}"
    [[ "$value" =~ ^[1-9][0-9]*$ && ${#value} -le 3 ]] || { err "$setting 必须为 1-999"; exit 1; }
done
[[ "$MTR_NICE" =~ ^[0-9]+$ && ${#MTR_NICE} -le 2 ]] && (( 10#$MTR_NICE <= 19 )) || { err 'MTR_NICE 必须为 0-19'; exit 1; }
if [[ -n "$MTR_INTERVAL" ]]; then
    [[ "$MTR_INTERVAL" =~ ^[0-9]+([.][0-9]+)?$ ]] || { err 'MTR_INTERVAL 必须为正数'; exit 1; }
fi

if [[ $USE_COLOR -eq 1 ]]; then
    SYM_DOWN="${RED}✗${R}"; SYM_SKIP="${GRAY}⊘${R}"; SYM_STAR="${YELLOW}★${R}"
    SYM_WARN="${RED}⚠${R}"; SYM_INFO="${BLUE}ℹ${R}"
else
    SYM_DOWN="x"; SYM_SKIP="?"; SYM_STAR="*"; SYM_WARN="!"; SYM_INFO="i"
fi

need() {
    local cmd="$1" hint="${2:-}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        err "缺少依赖: $cmd"
        [[ -n "$hint" ]] && printf "    安装: %s\n" "$hint" >&2
        exit 1
    fi
}
ensure_runtime_deps() {
    local missing=()
    local need_mtr=0 need_jq=0
    command -v mtr >/dev/null 2>&1 || { missing+=(mtr); need_mtr=1; }
    command -v jq >/dev/null 2>&1 || { missing+=(jq); need_jq=1; }
    [[ ${#missing[@]} -eq 0 ]] && return 0

    local sudo=""
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
        if command -v sudo >/dev/null 2>&1; then sudo="sudo"
        else
            err "缺少依赖: ${missing[*]}, 当前非 root 且无 sudo, 无法自动安装"
            printf "    Debian/Ubuntu: apt install mtr-tiny jq\n" >&2
            printf "    Alpine: apk add mtr jq\n" >&2
            exit 1
        fi
    fi

    printf "%s[*]%s 未检测到依赖: %s, 正在自动安装...\n" "$BLUE" "$R" "${missing[*]}" >&2
    if command -v apt-get >/dev/null 2>&1; then
        $sudo apt-get update -qq >/dev/null 2>&1 || true
        local apt_pkgs=()
        [[ $need_mtr -eq 1 ]] && apt_pkgs+=(mtr-tiny)
        [[ $need_jq -eq 1 ]] && apt_pkgs+=(jq)
        $sudo apt-get install -y "${apt_pkgs[@]}" >/dev/null 2>&1 || {
            apt_pkgs=()
            [[ $need_mtr -eq 1 ]] && apt_pkgs+=(mtr)
            [[ $need_jq -eq 1 ]] && apt_pkgs+=(jq)
            $sudo apt-get install -y "${apt_pkgs[@]}" >/dev/null 2>&1 || true
        }
    elif command -v apk >/dev/null 2>&1; then
        local apk_pkgs=()
        [[ $need_mtr -eq 1 ]] && apk_pkgs+=(mtr)
        [[ $need_jq -eq 1 ]] && apk_pkgs+=(jq)
        $sudo apk add --no-cache "${apk_pkgs[@]}" >/dev/null 2>&1 || true
    elif command -v yum >/dev/null 2>&1; then
        local yum_pkgs=()
        [[ $need_mtr -eq 1 ]] && yum_pkgs+=(mtr)
        [[ $need_jq -eq 1 ]] && yum_pkgs+=(jq)
        $sudo yum install -y "${yum_pkgs[@]}" >/dev/null 2>&1 || true
    elif command -v dnf >/dev/null 2>&1; then
        local dnf_pkgs=()
        [[ $need_mtr -eq 1 ]] && dnf_pkgs+=(mtr)
        [[ $need_jq -eq 1 ]] && dnf_pkgs+=(jq)
        $sudo dnf install -y "${dnf_pkgs[@]}" >/dev/null 2>&1 || true
    elif command -v pacman >/dev/null 2>&1; then
        local pacman_pkgs=()
        [[ $need_mtr -eq 1 ]] && pacman_pkgs+=(mtr)
        [[ $need_jq -eq 1 ]] && pacman_pkgs+=(jq)
        $sudo pacman -Sy --noconfirm "${pacman_pkgs[@]}" >/dev/null 2>&1 || true
    fi

    local still_missing=()
    command -v mtr >/dev/null 2>&1 || still_missing+=(mtr)
    command -v jq >/dev/null 2>&1 || still_missing+=(jq)
    if [[ ${#still_missing[@]} -eq 0 ]]; then
        printf "%s[+]%s 依赖安装成功: %s\n" "$GREEN" "$R" "${missing[*]}" >&2
        { ${sudo} setcap cap_net_raw+ep "$(command -v mtr)" >/dev/null 2>&1 || true; }
        return 0
    fi

    err "依赖自动安装失败: ${still_missing[*]}"
    printf "    Debian/Ubuntu: apt install mtr-tiny jq\n" >&2
    printf "    Alpine: apk add mtr jq\n" >&2
    printf "    CentOS/RHEL: yum install mtr jq\n" >&2
    exit 1
}
ensure_runtime_deps
need curl    "apt install curl"
need timeout "coreutils"
need awk
need ps

HAS_GETENT=0; command -v getent >/dev/null 2>&1 && HAS_GETENT=1
HAS_NSLOOKUP=0; command -v nslookup >/dev/null 2>&1 && HAS_NSLOOKUP=1
HAS_NICE=0; command -v nice >/dev/null 2>&1 && HAS_NICE=1

USE_EMBEDDED_RULES=0
if [[ ! -f "$RULES_FILE" ]]; then
    if [[ -n "$RULES_EXPLICIT" ]]; then
        err "规则文件不存在: $RULES_FILE"
        exit 1
    elif [[ -f "$SCRIPT_DIR/rules.conf.example" ]]; then
        RULES_FILE="$SCRIPT_DIR/rules.conf.example"
    else
        USE_EMBEDDED_RULES=1
    fi
fi
if ! install -d -m 700 "$CACHE_DIR" 2>/dev/null; then
    err "无法创建/访问 cache 目录: $CACHE_DIR"; exit 1
fi
[[ -O "$CACHE_DIR" ]] && chmod 700 "$CACHE_DIR" 2>/dev/null || true
IP_LOOKUP_CACHE_DIR="$CACHE_DIR/ip-lookup"
if ! install -d -m 700 "$IP_LOOKUP_CACHE_DIR" 2>/dev/null; then
    err "无法创建/访问 IP 反查缓存目录: $IP_LOOKUP_CACHE_DIR"; exit 1
fi
[[ -O "$IP_LOOKUP_CACHE_DIR" ]] && chmod 700 "$IP_LOOKUP_CACHE_DIR" 2>/dev/null || true

# 探测一次 stat 格式，避免每次读取磁盘缓存都探测
STAT_MTIME_MODE="none"
if stat -c %Y "$CACHE_DIR" >/dev/null 2>&1; then
    STAT_MTIME_MODE="gnu"
elif stat -f %m "$CACHE_DIR" >/dev/null 2>&1; then
    STAT_MTIME_MODE="bsd"
fi

# ─── 纯 Bash 字符串与切分辅助（零外部进程） ───────────────────────────────
sanitize_str_into() {
    local _sn_s="$1" _sn_out="$2"
    # 剔除全部 ASCII 控制字符 (含 CR/LF/TAB/DEL)
    _sn_s="${_sn_s//[[:cntrl:]]/}"
    printf -v "$_sn_out" '%s' "$_sn_s"
}

split_tsv2() {
    local _sp2_data="$1" _sp2_v1="$2" _sp2_v2="$3" _sp2_1 _sp2_2
    if [[ "$_sp2_data" == *$'\t'* ]]; then
        _sp2_1="${_sp2_data%%$'\t'*}"
        _sp2_2="${_sp2_data#*$'\t'}"
    else
        _sp2_1="$_sp2_data"
        _sp2_2=""
    fi
    printf -v "$_sp2_v1" '%s' "$_sp2_1"
    printf -v "$_sp2_v2" '%s' "$_sp2_2"
}

split_lookup_data() {
    local _sp3_data="$1" _sp3_v1="$2" _sp3_v2="$3" _sp3_v3="$4" _sp3_rest _sp3_1 _sp3_2 _sp3_3
    _sp3_rest="$_sp3_data"
    if [[ "$_sp3_rest" == *$'\t'* ]]; then
        _sp3_1="${_sp3_rest%%$'\t'*}"
        _sp3_rest="${_sp3_rest#*$'\t'}"
    else
        _sp3_1="$_sp3_rest"
        _sp3_rest=""
    fi
    if [[ "$_sp3_rest" == *$'\t'* ]]; then
        _sp3_2="${_sp3_rest%%$'\t'*}"
        _sp3_3="${_sp3_rest#*$'\t'}"
    else
        _sp3_2="$_sp3_rest"
        _sp3_3=""
    fi
    printf -v "$_sp3_v1" '%s' "$_sp3_1"
    printf -v "$_sp3_v2" '%s' "$_sp3_2"
    printf -v "$_sp3_v3" '%s' "$_sp3_3"
}

split_tsv4() {
    local _sp4_data="$1" _sp4_v1="$2" _sp4_v2="$3" _sp4_v3="$4" _sp4_v4="$5" _sp4_rest _sp4_1 _sp4_2 _sp4_3 _sp4_4
    _sp4_rest="$_sp4_data"
    if [[ "$_sp4_rest" == *$'\t'* ]]; then _sp4_1="${_sp4_rest%%$'\t'*}"; _sp4_rest="${_sp4_rest#*$'\t'}"; else _sp4_1="$_sp4_rest"; _sp4_rest=""; fi
    if [[ "$_sp4_rest" == *$'\t'* ]]; then _sp4_2="${_sp4_rest%%$'\t'*}"; _sp4_rest="${_sp4_rest#*$'\t'}"; else _sp4_2="$_sp4_rest"; _sp4_rest=""; fi
    if [[ "$_sp4_rest" == *$'\t'* ]]; then _sp4_3="${_sp4_rest%%$'\t'*}"; _sp4_4="${_sp4_rest#*$'\t'}"; else _sp4_3="$_sp4_rest"; _sp4_4=""; fi
    printf -v "$_sp4_v1" '%s' "$_sp4_1"
    printf -v "$_sp4_v2" '%s' "$_sp4_2"
    printf -v "$_sp4_v3" '%s' "$_sp4_3"
    printf -v "$_sp4_v4" '%s' "$_sp4_4"
}

is_valid_domain() { [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]{0,253}[a-zA-Z0-9])?$ ]]; }

# ─── IP/ASN 反查与两级缓存（父进程真内存 IP_CACHE + 磁盘缓存） ─────────────
declare -A IP_CACHE=()
CACHE_NOW_EPOCH="$(date +%s)"

refresh_cache_now() {
    if (( HAS_EPOCHSECONDS )); then
        CACHE_NOW_EPOCH="$EPOCHSECONDS"
    else
        CACHE_NOW_EPOCH="$(date +%s)"
    fi
}

ip_lookup_cache_path_into() {
    local _cp_ip="$1" _cp_out="$2" _cp_key
    _cp_key="${_cp_ip//[^A-Za-z0-9_.-]/_}"
    printf -v "$_cp_out" '%s/%s.tsv' "$IP_LOOKUP_CACHE_DIR" "$_cp_key"
}

lookup_score_into() {
    local _ls_data="$1" _ls_out="$2" _ls_asn _ls_isp _ls_cc _ls_sc=0
    split_lookup_data "$_ls_data" _ls_asn _ls_isp _ls_cc
    [[ -n "$_ls_cc" && "$_ls_cc" != "??" && "$_ls_cc" != "null" ]] && _ls_sc=$((_ls_sc+1))
    [[ -n "$_ls_asn" && "$_ls_asn" != "??" && "$_ls_asn" != "null" ]] && _ls_sc=$((_ls_sc+1))
    [[ -n "$_ls_isp" && "$_ls_isp" != "Unknown" && "$_ls_isp" != "null" ]] && _ls_sc=$((_ls_sc+1))
    printf -v "$_ls_out" '%s' "$_ls_sc"
}

normalize_lookup_fields() {
    local _nl_v1="$1" _nl_v2="$2" _nl_v3="$3" _nl_a _nl_i _nl_c
    _nl_a="${!_nl_v1:-}"
    _nl_i="${!_nl_v2:-}"
    _nl_c="${!_nl_v3:-}"
    [[ "$_nl_a" == "??" || "$_nl_a" == "null" ]] && _nl_a=""
    [[ "$_nl_i" == "null" ]] && _nl_i=""
    [[ "$_nl_c" == "null" ]] && _nl_c=""
    printf -v "$_nl_v1" '%s' "$_nl_a"
    printf -v "$_nl_v2" '%s' "$_nl_i"
    printf -v "$_nl_v3" '%s' "$_nl_c"
}

lookup_via_ipinfo() {
    local ip="$1" json row cc org asn isp
    json=$(curl -fsS --max-time "$API_TIMEOUT" --proto '=https' --tlsv1.2 -A "$UA" "https://ipinfo.io/${ip}/json" 2>/dev/null) || return 1
    [[ -n "$json" ]] || return 1
    row=$(printf '%s' "$json" | jq -r '[.country // "", .org // ""] | @tsv' 2>/dev/null) || return 1
    # 用纯 Bash 切分，修复 country 为空时 IFS=$'\t' read 将 org 错位写入 cc 的问题
    split_tsv2 "$row" cc org
    [[ -n "$cc" ]] || return 1
    if [[ "$org" =~ ^AS([0-9]+)[[:space:]]+(.+)$ ]]; then
        asn="${BASH_REMATCH[1]}"; isp="${BASH_REMATCH[2]}"
    else
        asn=""; isp="$org"
    fi
    sanitize_str_into "$asn" asn
    sanitize_str_into "$isp" isp
    sanitize_str_into "$cc" cc
    printf '%s\t%s\t%s' "$asn" "${isp:0:32}" "${cc:0:3}"
}

lookup_via_ipsb() {
    local ip="$1" json cc asn isp row
    json=$(curl -fsS --max-time "$API_TIMEOUT" --proto '=https' --tlsv1.2 -A "$UA" "https://api.ip.sb/geoip/${ip}" 2>/dev/null) || return 1
    [[ -n "$json" ]] || return 1
    row=$(printf '%s' "$json" | jq -r '[.country_code // "", (.asn // "" | tostring), .asn_organization // .organization // ""] | @tsv' 2>/dev/null) || return 1
    split_lookup_data "$row" cc asn isp
    [[ -z "$cc" || "$cc" == "null" ]] && return 1
    [[ "$asn" == "null" ]] && asn=""
    sanitize_str_into "$asn" asn
    sanitize_str_into "$isp" isp
    sanitize_str_into "$cc" cc
    printf '%s\t%s\t%s' "$asn" "${isp:0:32}" "${cc:0:3}"
}

lookup_via_ipwhois() {
    local ip="$1" json ok cc asn isp row
    json=$(curl -fsS --max-time "$API_TIMEOUT" --proto '=https' --tlsv1.2 -A "$UA" "https://ipwho.is/${ip}" 2>/dev/null) || return 1
    [[ -n "$json" ]] || return 1
    row=$(printf '%s' "$json" | jq -r '[(.success // false | tostring), .country_code // "", (.connection.asn // "" | tostring), .connection.isp // ""] | @tsv' 2>/dev/null) || return 1
    split_tsv4 "$row" ok cc asn isp
    [[ "$ok" == "true" && -n "$cc" ]] || return 1
    [[ "$asn" == "null" ]] && asn=""
    sanitize_str_into "$asn" asn
    sanitize_str_into "$isp" isp
    sanitize_str_into "$cc" cc
    printf '%s\t%s\t%s' "$asn" "${isp:0:32}" "${cc:0:3}"
}

read_ip_lookup_cache_into() {
    local _rc_ip="$1" _rc_out="$2" _rc_path _rc_mtime="" _rc_line="" _rc_score=0
    ip_lookup_cache_path_into "$_rc_ip" _rc_path
    [[ -f "$_rc_path" ]] || return 1
    if [[ "$STAT_MTIME_MODE" == "gnu" ]]; then
        _rc_mtime="$(stat -c %Y "$_rc_path" 2>/dev/null || true)"
    elif [[ "$STAT_MTIME_MODE" == "bsd" ]]; then
        _rc_mtime="$(stat -f %m "$_rc_path" 2>/dev/null || true)"
    fi
    if [[ "$_rc_mtime" =~ ^[0-9]+$ ]] && (( CACHE_NOW_EPOCH - _rc_mtime > IP_LOOKUP_CACHE_TTL )); then
        return 1
    fi
    IFS= read -r _rc_line < "$_rc_path" || [[ -n "$_rc_line" ]] || return 1
    lookup_score_into "$_rc_line" _rc_score
    (( _rc_score >= 3 )) || return 1
    printf -v "$_rc_out" '%s' "$_rc_line"
    return 0
}

write_ip_lookup_cache() {
    local _wc_ip="$1" _wc_res="$2" _wc_score=0 _wc_path _wc_tmp
    lookup_score_into "$_wc_res" _wc_score
    (( _wc_score >= 3 )) || return 0
    ip_lookup_cache_path_into "$_wc_ip" _wc_path
    _wc_tmp="$(mktemp "${_wc_path}.XXXXXX")" || return 0
    printf '%s\n' "$_wc_res" > "$_wc_tmp" 2>/dev/null || { rm -f -- "$_wc_tmp" 2>/dev/null || true; return 0; }
    chmod 600 "$_wc_tmp" 2>/dev/null || true
    mv -f -- "$_wc_tmp" "$_wc_path" 2>/dev/null || rm -f -- "$_wc_tmp" 2>/dev/null || true
}

fetch_ip_online_into() {
    local _fi_ip="$1" _fi_out="$2" _fi_res _fi_best="" _fi_sc=0 _fi_best_sc=0 _fi_prov
    for _fi_prov in ipinfo ipsb ipwhois; do
        if _fi_res="$("lookup_via_${_fi_prov}" "$_fi_ip" 2>/dev/null)"; then
            lookup_score_into "$_fi_res" _fi_sc
            if (( _fi_sc > _fi_best_sc )); then
                _fi_best_sc="$_fi_sc"
                _fi_best="$_fi_res"
            fi
            (( _fi_sc >= 3 )) && break
        fi
    done
    if [[ -n "$_fi_best" ]]; then
        write_ip_lookup_cache "$_fi_ip" "$_fi_best"
        printf -v "$_fi_out" '%s' "$_fi_best"
        return 0
    fi
    printf -v "$_fi_out" '%s' $'\t\t??'
    return 1
}

# 无子 Shell 查询：直接命中/回填父进程 IP_CACHE（含负缓存，避免同次运行反复轰炸失败 IP）
lookup_ip_into() {
    local _li_ip="$1" _li_out="$2" _li_hit=""
    if [[ -n "${IP_CACHE[$_li_ip]+set}" ]]; then
        printf -v "$_li_out" '%s' "${IP_CACHE[$_li_ip]}"
        [[ "${IP_CACHE[$_li_ip]}" != $'\t\t??' ]]
        return
    fi
    if read_ip_lookup_cache_into "$_li_ip" _li_hit; then
        IP_CACHE[$_li_ip]="$_li_hit"
        printf -v "$_li_out" '%s' "$_li_hit"
        return 0
    fi
    if fetch_ip_online_into "$_li_ip" _li_hit; then
        IP_CACHE[$_li_ip]="$_li_hit"
        printf -v "$_li_out" '%s' "$_li_hit"
        return 0
    fi
    IP_CACHE[$_li_ip]=$'\t\t??'
    printf -v "$_li_out" '%s' $'\t\t??'
    return 1
}

# 并发批量预取未缓存 IP，结果统一回填至父进程 IP_CACHE
prefetch_ips() {
    local batch_dir="$1"; shift
    local -a ips=("$@")
    local -a uncached=()
    local -A seen_req=()
    local ip res=""
    refresh_cache_now
    for ip in "${ips[@]}"; do
        [[ -n "$ip" && "$ip" != __* ]] || continue
        [[ -n "${IP_CACHE[$ip]+set}" ]] && continue
        [[ -n "${seen_req[$ip]+set}" ]] && continue
        seen_req[$ip]=1
        if read_ip_lookup_cache_into "$ip" res; then
            IP_CACHE[$ip]="$res"
        else
            uncached+=("$ip")
        fi
    done
    local total=${#uncached[@]}
    (( total > 0 )) || return 0
    mkdir -p "$batch_dir"
    local maxjobs="$LOOKUP_CONCURRENCY" running=0 i=0 pid
    (( maxjobs > total )) && maxjobs=$total
    ACTIVE_WORKERS=()
    for (( i=0; i<total; i++ )); do
        ip="${uncached[$i]}"
        wait_worker_slot "$maxjobs" running
        (
            local r=""
            fetch_ip_online_into "$ip" r || true
            printf '%s\n' "$r" > "$batch_dir/$i.tmp"
            mv -f -- "$batch_dir/$i.tmp" "$batch_dir/$i"
        ) &
        ACTIVE_WORKERS+=("$!")
        running=$((running + 1))
    done
    drain_workers
    for (( i=0; i<total; i++ )); do
        ip="${uncached[$i]}"
        res=""
        if [[ -f "$batch_dir/$i" ]]; then
            IFS= read -r res < "$batch_dir/$i" || true
        fi
        [[ -n "$res" ]] || res=$'\t\t??'
        IP_CACHE[$ip]="$res"
    done
    rm -rf -- "$batch_dir" 2>/dev/null || true
}

# ─── 网络环境并行探测 ─────────────────────────────────────────────────────
ENV_ENDPOINTS=(
    "https://api.ip.sb/ip" "https://ipinfo.io/ip" "https://icanhazip.com"
    "https://ifconfig.me/ip" "https://api.ipify.org" "https://checkip.amazonaws.com"
)

ip_family_into() {
    local _f_ip="$1" _f_out="$2"
    if [[ "$_f_ip" == *:* ]]; then printf -v "$_f_out" 'ipv6'
    elif [[ "$_f_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then printf -v "$_f_out" 'ipv4'
    else printf -v "$_f_out" 'unknown'; fi
}

# ─── 可移植 IP 规范化与 MTR 解析（内置排除 Clash Fake-IP 198.18.0.0/15） ───
IP_AWK='
function v4(s, a,n,i) {
    n=split(s,a,"."); if(n!=4) return ""
    for(i=1;i<=4;i++) if(a[i]!~/^[0-9]+$/ || length(a[i])>3 || a[i]+0>255) return ""
    return (a[1]+0) "." (a[2]+0) "." (a[3]+0) "." (a[4]+0)
}
function norm(s, a,b,n,m,i,p,left,right,out,missing,tail,v) {
    s=tolower(s); sub(/%.*/, "", s)
    if(index(s,":")==0) return v4(s)
    if(s!~/^[0-9a-f:.]+$/) return ""
    if(index(s,".")) {
        tail=s; sub(/^.*:/,"",tail); v=v4(tail); if(v=="") return ""
        split(v,b,"."); s=substr(s,1,length(s)-length(tail)) sprintf("%x:%x",b[1]*256+b[2],b[3]*256+b[4])
    }
    p=index(s,"::")
    if(p) {
        left=substr(s,1,p-1); right=substr(s,p+2)
        if(index(right,"::")) return ""
        n=(left=="" ? 0 : split(left,a,":")); m=(right=="" ? 0 : split(right,b,":"))
        missing=8-n-m; if(missing<1) return ""
        for(i=1;i<=missing;i++) a[++n]="0"
        for(i=1;i<=m;i++) a[++n]=b[i]
    } else { n=split(s,a,":"); if(n!=8) return "" }
    out=""
    for(i=1;i<=8;i++) {
        if(a[i]!~/^[0-9a-f]+$/ || length(a[i])>4) return ""
        a[i]=substr("0000" a[i],length(a[i])+1)
        out=out (i==1 ? "" : ":") a[i]
    }
    return out
}
function private_ip(s, a) {
    if(index(s,":")) return s~/^(fc|fd|fe[89ab]|ff)/ || s=="0000:0000:0000:0000:0000:0000:0000:0000" || s=="0000:0000:0000:0000:0000:0000:0000:0001" || s~/^0000:0000:0000:0000:0000:ffff:/
    split(s,a,".")
    return a[1]==0 || a[1]==10 || a[1]==127 || a[1]>=224 || (a[1]==172 && a[2]>=16 && a[2]<=31) || (a[1]==192 && a[2]==168) || (a[1]==169 && a[2]==254) || (a[1]==100 && a[2]>=64 && a[2]<=127) || (a[1]==198 && (a[2]==18 || a[2]==19))
}
'

resolve_target() {
    local family="$1" domain="$2" limit="$3" raw="" target="" err_out="" rc=0
    local deadline=$((SECONDS + limit)) remaining
    if (( HAS_GETENT )); then
        remaining=$((deadline-SECONDS)); (( remaining > 0 )) || return 1
        raw="$(timeout -k 1 "$remaining" getent "ahostsv${family#-}" "$domain" 2>&1)" || rc=$?
        if (( rc == 0 )) && [[ -n "$raw" ]]; then
            target="$(printf '%s\n' "$raw" | LC_ALL=C awk -v family="$family" "$IP_AWK"'
                { ip=norm($1); if(ip!="" && ((family=="-6")==!!index(ip,":"))) { print $1; exit } }')"
            [[ -z "$target" ]] || { printf '%s' "$target"; return 0; }
        elif [[ "$raw" == *"Unknown database"* || "$raw" == *"unknown database"* ]]; then
            local database
            for database in ahosts hosts; do
                remaining=$((deadline-SECONDS)); (( remaining > 0 )) || return 1
                raw="$(timeout -k 1 "$remaining" getent "$database" "$domain" 2>/dev/null || true)"
                [[ -n "$raw" ]] || continue
                target="$(printf '%s\n' "$raw" | LC_ALL=C awk -v family="$family" "$IP_AWK"'
                    { ip=norm($1); if(ip!="" && ((family=="-6")==!!index(ip,":"))) { print $1; exit } }')"
                [[ -z "$target" ]] || { printf '%s' "$target"; return 0; }
            done
        fi
    fi
    if (( HAS_NSLOOKUP )); then
        remaining=$((deadline-SECONDS)); (( remaining > 0 )) || return 1
        local type=A; [[ "$family" == "-6" ]] && type=AAAA
        raw="$(timeout -k 1 "$remaining" nslookup "-type=$type" "$domain" 2>/dev/null || true)"
        [[ -n "$raw" ]] || return 1
        target="$(printf '%s\n' "$raw" | LC_ALL=C awk -v family="$family" "$IP_AWK"'
            /^Name:/ { answer=1 }
            answer { for(i=1;i<=NF;i++) { ip=norm($i); if(ip!="" && ((family=="-6")==!!index(ip,":"))) { print $i; exit } } }')"
    fi
    [[ -n "$target" ]] || return 1
    printf '%s' "$target"
}

parse_mtr_report() {
    local target="$1"
    LC_ALL=C awk -v target="$target" -v evidence="${2:-0}" "$IP_AWK"'
    BEGIN { target=norm(target); latency="-" }
    {
        gsub(/\r/,""); gsub(/\033\[[0-9;?]*[ -\/]*[@-~]/,"")
        if($1!~/^[0-9]+[.]([|]--)?$/) {
            alternate=norm($1)
            if(alternate!="" && current_ttl>0 && (first=="" || current_ttl==first_ttl) && alternate!=row_ip) ambiguous=1
            next
        }
        current_ttl=$1+0; row_ip=""
        if(first=="" && current_ttl!=previous_ttl+1) early_gap=1
        previous_ttl=current_ttl
        loss=0
        for(i=2;i<=NF;i++) if($i~/^[0-9]+([.][0-9]*)?%?$/) { loss=i; break }
        if(!loss) { if($0 !~ /waiting for reply/) malformed=1; if(first=="") early_gap=1; next }
        rows++
        ip=""; display=""
        for(i=2;i<loss;i++) {
            candidate=$i; gsub(/^[([]|[)\]]$/,"",candidate)
            key=norm(candidate)
            if(key!="") { ip=key; display=candidate; break }
        }
        if($(loss+1)!~/^[0-9]+$/ || $(loss+3)!~/^[0-9]+([.][0-9]*)?$/) { malformed=1; next }
        row_ip=ip
        if($loss+0>=100 || $(loss+1)+0==0) { if(first=="") early_gap=1; next }
        if(ip=="") { malformed=1; next }
        if(ip==target) { reached=1; latency=$(loss+3); sub(/[.]$/,".0",latency); next }
        if(!private_ip(ip)) {
            if(first=="") { first=display; first_ttl=current_ttl }
            if(ip!=previous) { path=path (path=="" ? "" : " ") display; previous=ip }
        }
    }
    END {
        if(malformed || !rows || target=="") print "__PARSE_ERROR__\t-\t"
        else if(first!="") print first "\t" latency "\t" path (evidence ? "\t" first_ttl "," (early_gap+0) "," (ambiguous+0) : "")
        else if(reached) print "__HIDDEN__\t" latency "\t"
        else print "__NO_REPLY__\t-\t"
    }'
}

run_mtr_report() {
    local ip_flag="$1" mode="$2" target="$3" limit="$4"
    local -a command=(mtr "$ip_flag" -r -n -c "$MTR_COUNT" -m "$MTR_MAXTTL")
    [[ -n "$MTR_INTERVAL" ]] && command+=(-i "$MTR_INTERVAL")
    [[ "$mode" == "tcp" ]] && command+=(-T -P 443)
    command+=("$target")
    if (( HAS_NICE )); then command=(nice -n "$MTR_NICE" "${command[@]}"); fi
    LC_ALL=C timeout -k 2 "$limit" "${command[@]}"
}

route_evidence_clean() {
    local ttl gap ambiguous mode target
    IFS=, read -r ttl gap ambiguous mode target <<< "$1"
    [[ "$ttl" =~ ^[1-9][0-9]*$ && "$gap" == 0 && "$ambiguous" == 0 && ( "$mode" == icmp || "$mode" == tcp ) && -n "$target" ]]
}

route_evidence_usable() {
    local ttl gap ambiguous mode target
    IFS=, read -r ttl gap ambiguous mode target <<< "$1"
    [[ "$ttl" =~ ^[1-9][0-9]*$ && ( "$gap" == 0 || "$gap" == 1 ) && "$ambiguous" == 0 && ( "$mode" == icmp || "$mode" == tcp ) && -n "$target" ]]
}

# 参数: ip_flag domain [target] [forced_mode] [prefer_mode]
# 当 prefer_mode（如基准的 icmp）已获干净首跳时立即返回，不再浪费第二轮异协议探测且绝不覆盖干净证据
first_public_hop() {
    local ip_flag="$1" domain="$2" target="${3:-}" forced_mode="${4:-}" prefer_mode="${5:-}"
    local output attempt parsed hop latency path_ips evidence mode remaining limit
    local -a modes=(icmp tcp)
    if [[ -n "$forced_mode" ]]; then
        modes=("$forced_mode")
    elif [[ "$prefer_mode" == "tcp" ]]; then
        modes=(tcp icmp)
    elif [[ "$prefer_mode" == "icmp" ]]; then
        modes=(icmp tcp)
    fi
    local deadline=$((SECONDS + MTR_BUDGET)) best="" best_rank=0 last_error="__PROBE_ERROR__"
    is_valid_domain "$domain" || { printf '__DNS_ERROR__\t-\t'; return; }
    limit=5; (( MTR_BUDGET < limit )) && limit=$MTR_BUDGET
    [[ -n "$target" ]] || target="$(resolve_target "$ip_flag" "$domain" "$limit" || true)"
    [[ -n "$target" ]] || { printf '__DNS_ERROR__\t-\t'; return; }
    for ((attempt=1; attempt<=MTR_ATTEMPTS; attempt++)); do
        for mode in "${modes[@]}"; do
            remaining=$((deadline-SECONDS)); (( remaining > 0 )) || break 2
            limit=$MTR_TIMEOUT; (( remaining < limit )) && limit=$remaining
            output="$(run_mtr_report "$ip_flag" "$mode" "$target" "$limit" 2>/dev/null || true)"
            if [[ "${EGRESS_DEBUG_MTR:-0}" == "1" ]]; then
                local dbg_dir="$CACHE_DIR/mtr-debug" dbg_file
                install -d -m 700 "$dbg_dir" 2>/dev/null || true
                dbg_file="$dbg_dir/${ip_flag#-}-${domain}-${BASHPID}-${attempt}-${mode}.txt"
                printf 'target: %s\nmode: %s\n--- output ---\n%s\n' "$target" "$mode" "$output" > "$dbg_file" 2>/dev/null || true
            fi
            [[ -n "$output" ]] || continue
            parsed="$(printf '%s\n' "$output" | parse_mtr_report "$target" 1)"
            split_tsv4 "$parsed" hop latency path_ips evidence
            case "$hop" in
                __HIDDEN__) printf '%s' "$parsed"; return ;;
                __*) last_error="$hop" ;;
                *)
                    local full_ev="${evidence},${mode},${target}"
                    parsed+=",${mode},${target}"
                    local clean=0 rank=1
                    if route_evidence_clean "$full_ev"; then
                        clean=1
                        rank=3
                    fi
                    if [[ -n "$prefer_mode" && "$mode" == "$prefer_mode" ]]; then
                        rank=$((rank + 4))
                    fi
                    if [[ "$latency" != "-" ]]; then
                        rank=$((rank + 1))
                    fi
                    if (( rank > best_rank )); then
                        best="$parsed"
                        best_rank=$rank
                    fi
                    # 若已命中基准首选协议且证据干净，直接返回（避免终点禁 Ping 误切 TCP 导致 2x 耗时与协议不一致）
                    if [[ -n "$prefer_mode" && "$mode" == "$prefer_mode" && $clean -eq 1 ]]; then
                        printf '%s' "$parsed"; return
                    fi
                    # 若未指定首选协议（如测基准本身），干净且拿到延迟则立即返回
                    if [[ -z "$prefer_mode" && "$latency" != "-" && $clean -eq 1 ]]; then
                        printf '%s' "$parsed"; return
                    fi
                    if [[ -n "$forced_mode" && "$latency" != "-" ]]; then
                        printf '%s' "$parsed"; return
                    fi
                    ;;
            esac
        done
        [[ -z "$best" ]] || break
        remaining=$((deadline-SECONDS))
        (( remaining > attempt )) || break
        (( attempt < MTR_ATTEMPTS )) && sleep "$attempt"
    done
    if [[ -n "$best" ]]; then printf '%s' "$best"
    else printf '%s\t-\t' "$last_error"; fi
}

route_visible_node_matches() {
    local base_ttl ttl _
    [[ -n "${3:-}" && "$3" != __* && "$3" == "${4:-}" ]] || return 1
    route_evidence_usable "$1" && route_evidence_usable "$2" || return 1
    IFS=, read -r base_ttl _ <<< "$1"
    IFS=, read -r ttl _ <<< "$2"
    [[ "$base_ttl" == "$ttl" ]]
}

route_evidence_reason() {
    local base_ttl base_gap base_ambiguous base_mode ttl gap ambiguous mode _
    IFS=, read -r base_ttl base_gap base_ambiguous base_mode _ <<< "$1"
    IFS=, read -r ttl gap ambiguous mode _ <<< "$2"
    if [[ "$ambiguous" == 1 || "$base_ambiguous" == 1 ]]; then
        printf '首段存在多个回应节点 / 无法判定'
    elif [[ "$base_mode" != "$mode" ]]; then
        printf '探测协议不一致（%s/%s）/ 无法判定' "$base_mode" "$mode"
    elif [[ "$base_ttl" != "$ttl" ]]; then
        printf '可见节点跳数不同（%s/%s）/ 无法判定' "$base_ttl" "$ttl"
    elif [[ "$gap" == 1 || "$base_gap" == 1 ]]; then
        printf '前段未完整回应且可见节点不同 / 无法判定'
    else
        printf '首跳证据无效 / 无法判定'
    fi
}

route_evidence_comparable() {
    local base_ttl base_mode ttl mode _
    route_evidence_clean "$1" && route_evidence_clean "$2" || return 1
    IFS=, read -r base_ttl _ _ base_mode _ <<< "$1"
    IFS=, read -r ttl _ _ mode _ <<< "$2"
    [[ "$base_ttl" == "$ttl" && "$base_mode" == "$mode" ]]
}

route_repeat_needed() {
    local base_evidence="$1" evidence="$2" base_asn="$3" asn="$4" base_mode mode target _
    [[ -n "$asn" && "$asn" == "$base_asn" ]] && return 1
    [[ -n "$asn" && -n "$base_asn" ]] && route_evidence_clean "$base_evidence" || return 1
    route_evidence_comparable "$base_evidence" "$evidence" || return 1
    IFS=, read -r _ _ _ base_mode _ <<< "$base_evidence"
    IFS=, read -r _ _ _ mode target <<< "$evidence"
    [[ -n "$target" && "$mode" == "$base_mode" ]]
}

detect_mtr_base_asn() {
    local ip_flag="$1" prefix="$2" hop_line hop latency path_ips evidence data="" asn isp country info
    local repeat_line repeat_hop repeat_evidence mode target _
    hop_line="$(first_public_hop "$ip_flag" "$MTR_BASE_DOMAIN" || true)"
    split_tsv4 "$hop_line" hop latency path_ips evidence
    [[ -n "$hop" && "$hop" != __* ]] || return 1
    route_evidence_usable "$evidence" || return 1
    IFS=, read -r _ _ _ mode target <<< "$evidence"
    repeat_line="$(first_public_hop "$ip_flag" "$MTR_BASE_DOMAIN" "$target" "$mode" || true)"
    split_tsv4 "$repeat_line" repeat_hop _ _ repeat_evidence
    route_visible_node_matches "$evidence" "$repeat_evidence" "$hop" "$repeat_hop" || return 1
    if route_evidence_clean "$repeat_evidence"; then evidence="$repeat_evidence"; fi
    lookup_ip_into "$hop" data || true
    split_lookup_data "$data" asn isp country
    normalize_lookup_fields asn isp country
    [[ -n "$asn" ]] || return 1
    [[ -z "$country" ]] && country="??"
    [[ -z "$isp" ]] && isp="Unknown"
    info="$country · AS$asn $isp"
    printf -v "${prefix}_MTR_BASE_ASN" '%s' "$asn"
    printf -v "${prefix}_MTR_BASE_HOP" '%s' "$hop"
    printf -v "${prefix}_MTR_BASE_INFO" '%s' "$info"
    printf -v "${prefix}_MTR_BASE_EVIDENCE" '%s' "$evidence"
}

# ─── 单次 awk 规则解析（5000 行 < 20ms，替代 45,000 次 fork） ────────────────
declare -a CATS=() DOMAINS=() NOTES=()
parse_rules() {
    local source="$1" row cat_v domain note
    while IFS= read -r row; do
        split_lookup_data "$row" cat_v domain note
        CATS+=("$cat_v")
        DOMAINS+=("$domain")
        NOTES+=("$note")
    done < <(LC_ALL=C awk -v only_cat="$ONLY_CAT" -v red="$RED" -v reset="$R" '
        function clean(s) {
            gsub(/[\001-\037\177]/, "", s)
            sub(/^[ \t]+/, "", s)
            sub(/[ \t]+$/, "", s)
            gsub(/[ \t]+/, " ", s)
            return s
        }
        function valid_domain(d) {
            if (length(d) < 1 || length(d) > 255) return 0
            if (length(d) == 1) return (d ~ /^[a-zA-Z0-9]$/)
            return (d ~ /^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$/)
        }
        NR == 1 { sub(/^\357\273\277/, "") }
        {
            sub(/\r$/, "")
            if ($0 == "" || $0 ~ /^[ \t]*#/) next
            n = split($0, f, "|")
            cat_v = clean(f[1])
            dom   = clean(f[2])
            note  = (n >= 5 ? clean(f[5]) : "")
            if (dom == "") next
            if (cat_v == "") {
                printf "%s[!]%s 规则分类不能为空\n", red, reset > "/dev/stderr"
                next
            }
            if (!valid_domain(dom)) {
                printf "%s[!]%s rules.conf:%d 跳过非法域名: %s\n", red, reset, NR, dom > "/dev/stderr"
                next
            }
            if (only_cat != "" && cat_v != only_cat) next
            printf "%s\t%s\t%s\n", substr(cat_v, 1, 16), dom, substr(note, 1, 80)
        }
    ' "$source")
}

if [[ $USE_EMBEDDED_RULES -eq 1 ]]; then
    parse_rules <(printf '%s\n' "$DEFAULT_RULES")
else
    parse_rules "$RULES_FILE"
fi
TOTAL=${#DOMAINS[@]}
[[ $TOTAL -eq 0 ]] && { err "规则中没有可用域名 (或 --only 过滤后为空)"; exit 1; }

# ─── 进程池与退出清理 ──────────────────────────────────────────────────────
TMP_V4_RESULTS=""; TMP_V6_RESULTS=""; FINAL_JSON=""
RUN_DIR=""
declare -a ACTIVE_WORKERS=()

stop_tree() {
    local parent="$1" child
    while read -r child; do
        [[ -n "$child" ]] && stop_tree "$child"
    done < <({ ps -eo pid=,ppid= 2>/dev/null || ps -o pid,ppid; } | awk -v p="$parent" '$2==p {print $1}')
    kill -TERM "$parent" 2>/dev/null || true
    kill -KILL "$parent" 2>/dev/null || true
}

cleanup_tmp() {
    local pid
    for pid in ${ACTIVE_WORKERS[@]+"${ACTIVE_WORKERS[@]}"}; do
        [[ -n "$pid" ]] || continue
        if kill -0 "$pid" 2>/dev/null; then stop_tree "$pid"; fi
        wait "$pid" 2>/dev/null || true
    done
    [[ -n "$TMP_V4_RESULTS" ]] && rm -f -- "$TMP_V4_RESULTS"
    [[ -n "$TMP_V6_RESULTS" ]] && rm -f -- "$TMP_V6_RESULTS"
    [[ -n "$FINAL_JSON" ]] && rm -f -- "$FINAL_JSON"
    [[ -z "$RUN_DIR" ]] || rm -rf -- "$RUN_DIR"
    return 0
}
trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP; trap cleanup_tmp EXIT
RUN_DIR="$(mktemp -d "$CACHE_DIR/.run.XXXXXXXX")"

# 事件驱动并发槽位等待：Bash 4.3+ 使用 wait -n，彻底消除 sleep 0.1 忙轮询
wait_worker_slot() {
    local _f_max="$1" _f_rvar="$2" _f_run="${!2}"
    local -a _f_pend=()
    local _f_pid
    if (( _f_run < _f_max )); then
        return 0
    fi
    if (( HAS_WAIT_N )); then
        wait -n 2>/dev/null || true
        _f_run=$((_f_run - 1))
        # 周期性压缩 ACTIVE_WORKERS 防止大名单下数组无限增长
        if (( ${#ACTIVE_WORKERS[@]} > _f_max * 4 )); then
            for _f_pid in "${ACTIVE_WORKERS[@]}"; do
                kill -0 "$_f_pid" 2>/dev/null && _f_pend+=("$_f_pid")
            done
            ACTIVE_WORKERS=(${_f_pend[@]+"${_f_pend[@]}"})
            _f_run=${#ACTIVE_WORKERS[@]}
        fi
        printf -v "$_f_rvar" '%s' "$_f_run"
        return 0
    fi
    while (( _f_run >= _f_max )); do
        _f_pend=()
        for _f_pid in ${ACTIVE_WORKERS[@]+"${ACTIVE_WORKERS[@]}"}; do
            if kill -0 "$_f_pid" 2>/dev/null; then _f_pend+=("$_f_pid")
            else wait "$_f_pid" 2>/dev/null || true; fi
        done
        ACTIVE_WORKERS=(${_f_pend[@]+"${_f_pend[@]}"})
        _f_run=${#ACTIVE_WORKERS[@]}
        (( _f_run < _f_max )) || sleep 0.05
    done
    printf -v "$_f_rvar" '%s' "$_f_run"
}

drain_workers() {
    local pid
    for pid in ${ACTIVE_WORKERS[@]+"${ACTIVE_WORKERS[@]}"}; do
        wait "$pid" 2>/dev/null || true
    done
    ACTIVE_WORKERS=()
}

# ─── 终端渲染（纯 Bash 延迟分级，0 awk fork） ───────────────────────────────
is_tty() { [[ -t 1 && $USE_COLOR -eq 1 ]]; }
repeat_char() { local c="$1" w="$2" r; printf -v r "%${w}s" ""; printf '%s' "${r// /$c}"; }
rule_double() { printf "%s%s%s\n" "$CYAN" "$(repeat_char "━" "${1:-72}")" "$R"; }
rule_single() { printf "%s%s%s" "$GRAY" "$(repeat_char "─" "${1:-60}")" "$R"; }

print_banner() {
    local stamp="$2" display_date display_time display_zone
    display_date="${stamp%%T*}"
    display_time="${stamp#*T}"
    display_zone="${display_time:8}"
    display_time="${display_time:0:8}"
    case "$display_zone" in
        Z) display_zone="UTC" ;;
        [+-]????) display_zone="UTC${display_zone:0:3}:${display_zone:3:2}" ;;
        [+-]??:??) display_zone="UTC$display_zone" ;;
    esac
    rule_double 72
    printf "  %s家宽VPS分流一键自查检测%s  %sEgress-Check v%s%s     %s鸣谢：%s%s\n" "$BOLD" "$R" "$CYAN" "$VERSION" "$R" "$GRAY" "$BRAND_URL" "$R"
    printf "  %s主机%s  %s%s%s\n" "$DIM" "$R" "$BOLD" "$1" "$R"
    printf "  %s日期%s  %s    %s时间%s  %s    %s服务器时区%s  %s\n" "$DIM" "$R" "$display_date" "$DIM" "$R" "$display_time" "$DIM" "$R" "$display_zone"
    rule_double 72
}

print_env_section() {
    local def="$1" v4="$2" v6="$3" v4info="$4" v6info="$5"
    printf "\n  %s网络环境 (真实对外 IP)%s\n" "$BOLD" "$R"
    printf "  %s\n" "$(rule_single 36)"
    case "$def" in
        ipv4) printf "    默认出口     %sIPv4%s  %s\n" "$GREEN" "$R" "$SYM_STAR" ;;
        ipv6) printf "    默认出口     %sIPv6%s  %s\n" "$GREEN" "$R" "$SYM_STAR" ;;
        *)    printf "    默认出口     %s无网络出口%s\n" "$RED" "$R" ;;
    esac
    if [[ -n "$v4" ]]; then printf "    IPv4 出口    %s%s%s  %s%s%s\n" "$BOLD" "$v4" "$R" "$DIM" "$v4info" "$R"
    else printf "    IPv4 出口    %s不可用%s\n" "$RED" "$R"; fi
    if [[ -n "${V4_MTR_BASE_ASN:-}" ]]; then
        printf "    IPv4 MTR     %s%s%s  %s%s%s\n" "$BOLD" "$V4_MTR_BASE_HOP" "$R" "$DIM" "$V4_MTR_BASE_INFO" "$R"
    fi
    if [[ -n "$v6" ]]; then printf "    IPv6 出口    %s%s%s  %s%s%s\n" "$BOLD" "$v6" "$R" "$DIM" "$v6info" "$R"
    else printf "    IPv6 出口    %s不可用 / 已禁用%s\n" "$YELLOW" "$R"; fi
    if [[ -n "${V6_MTR_BASE_ASN:-}" ]]; then
        printf "    IPv6 MTR     %s%s%s  %s%s%s\n" "$BOLD" "$V6_MTR_BASE_HOP" "$R" "$DIM" "$V6_MTR_BASE_INFO" "$R"
    fi
    local item
    if [[ -n "$v4" && $V4_ECHO_UNIQUE -gt 1 ]]; then
        printf "\n    %s%s 商家 SNAT 嫌疑%s — %s%d 个回声服务看到不同对外 IP%s\n" "$RED" "$SYM_WARN" "$R" "$DIM" "$V4_ECHO_UNIQUE" "$R"
        local IFS_save="$IFS"; IFS=';'
        for item in $V4_ECHO_DETAIL; do item="${item# }"; printf "      %s· %s%s\n" "$DIM" "$item" "$R"; done
        IFS="$IFS_save"
    fi
}

print_pass_header() {
    [[ $OUTPUT_JSON -eq 1 ]] && return 0
    printf "\n  %s%s MTR 首跳检测%s  %s%s%s\n" "$BOLD" "$1" "$R" "$GRAY" "$(repeat_char "─" 44)" "$R"
}

print_category_header() {
    [[ $OUTPUT_JSON -eq 1 ]] && return 0
    printf "\n    %s%s%s\n" "$BOLD" "$1" "$R"
}

# 纯 Bash 延迟格式化与着色（零 awk/子 Shell）
format_latency_into() {
    local _f_lat="${1:-"-"}" _f_fcol="${2:-}" _f_out="$3"
    local _f_txt _f_col _f_int _f_frac _f_num
    if [[ "$_f_lat" =~ ^([0-9]+)([.]([0-9]+))?$ ]]; then
        _f_int="${BASH_REMATCH[1]}"
        _f_frac="${BASH_REMATCH[3]:-0}"
        _f_num=$((10#$_f_int))
        if (( _f_num >= 1000 )); then
            printf -v _f_txt '%9s' "999+ms"
        else
            LC_ALL=C printf -v _f_txt '%7.1fms' "$_f_lat"
        fi
        if [[ -n "$_f_fcol" ]]; then
            _f_col="$_f_fcol"
        elif (( _f_num < 50 )); then
            _f_col="$GREEN"
        elif (( _f_num < 200 || (_f_num == 200 && 10#${_f_frac:0:6} == 0) )); then
            _f_col="$YELLOW"
        else
            _f_col="$BROWN"
        fi
    else
        printf -v _f_txt '%9s' "-"
        _f_col="${_f_fcol:-$GRAY}"
    fi
    printf -v "$_f_out" '%s%s%s' "$_f_col" "$_f_txt" "$R"
}

short_text_into() {
    local _st_txt="$1" _st_w="${2:-58}" _st_out="$3"
    if (( ${#_st_txt} > _st_w )); then
        printf -v "$_st_out" '%s...' "${_st_txt:0:$((_st_w-3))}"
    else
        printf -v "$_st_out" '%s' "$_st_txt"
    fi
}

# 无子 Shell 构造路径 ASN 链（全量命中父进程 IP_CACHE）
path_asn_chain_into() {
    local _pc_pips="$1" _pc_out="$2" _pc_ip _pc_d="" _pc_asn _pc_isp _pc_cc _pc_prev="" _pc_lbl _pc_sisp="" _pc_ch=""
    for _pc_ip in $_pc_pips; do
        lookup_ip_into "$_pc_ip" _pc_d || true
        split_lookup_data "$_pc_d" _pc_asn _pc_isp _pc_cc
        normalize_lookup_fields _pc_asn _pc_isp _pc_cc
        [[ -z "$_pc_asn" || "$_pc_asn" == 0 ]] && continue
        [[ "$_pc_asn" == "$_pc_prev" ]] && continue
        _pc_prev="$_pc_asn"
        _pc_lbl="AS$_pc_asn"
        if [[ -n "$_pc_isp" && "$_pc_isp" != "Unknown" ]]; then
            short_text_into "$_pc_isp" 22 _pc_sisp
            _pc_lbl+=" $_pc_sisp"
        fi
        if [[ -z "$_pc_ch" ]]; then _pc_ch="$_pc_lbl"; else _pc_ch+=" -> $_pc_lbl"; fi
    done
    printf -v "$_pc_out" '%s' "$_pc_ch"
}

path_asn_summary_into() {
    local _ps_ch="$1" _ps_out="$2" _ps_first _ps_rest
    _ps_first="${_ps_ch%% -> *}"
    if [[ "$_ps_ch" == *" -> "* ]]; then
        _ps_rest="${_ps_ch#* -> }"
        printf -v "$_ps_out" '%s -> %s' "$_ps_first" "${_ps_rest%% -> *}"
    else
        printf -v "$_ps_out" '%s' "$_ps_first"
    fi
}

print_result_row() {
    [[ $OUTPUT_JSON -eq 1 ]] && return 0
    local marker="$1" domain="$2" ip="$3" latency="$4" cc="$5" asn="$6" isp="$7" is_split="${8:-0}" asn_isp latency_disp=""
    [[ "$asn" == "??" || "$asn" == "null" ]] && asn=""
    [[ "$isp" == "null" ]] && isp="Unknown"
    if [[ -z "$asn" ]]; then asn_isp="$isp"; else asn_isp="AS${asn} ${isp}"; fi
    local domain_width="${DOMAIN_WIDTH:-24}" ip_width="${IP_WIDTH:-15}"
    if [[ "${COMPACT_OUTPUT:-0}" == 1 ]]; then
        local status="" asn_label="-"
        [[ -n "$asn" ]] && asn_label="AS$asn"
        [[ "$is_split" == -1 ]] && status="${9:-无法判定}"
        if [[ "$is_split" == 1 ]]; then
            format_latency_into "$latency" "$YELLOW" latency_disp
            printf "      %s  %s%-*s  %s  %s%-3s  %-12s  ⮜ 首跳 ASN 差异已复测%s\n" "$marker" "$YELLOW" "$domain_width" "$domain" "$latency_disp" "$YELLOW" "$cc" "$asn_label" "$R"
        else
            [[ -z "$asn" && "$is_split" != -1 ]] && status="$isp"
            [[ "$latency" == - && "$ip" != - ]] && status+=" (目标未回应)"
            format_latency_into "$latency" "" latency_disp
            printf "      %s  %-*s  %s  %-3s  %s%-12s%s" "$marker" "$domain_width" "$domain" "$latency_disp" "$cc" "$DIM" "$asn_label" "$R"
            [[ -n "$status" ]] && printf "  %s%s%s" "$DIM" "$status" "$R"
            printf '\n'
        fi
        return 0
    fi
    if [[ "$is_split" == "1" ]]; then
        format_latency_into "$latency" "$YELLOW" latency_disp
        printf "      %s  %s%-*s  %-*s  %s  %s%-3s  %s  ⮜ 首跳 ASN 差异已复测%s\n" "$marker" "$YELLOW" "$domain_width" "$domain" "$ip_width" "$ip" "$latency_disp" "$YELLOW" "$cc" "$asn_isp" "$R"
    else
        format_latency_into "$latency" "" latency_disp
        printf "      %s  %-*s  %-*s  %s  %-3s  %s%s%s\n" "$marker" "$domain_width" "$domain" "$ip_width" "$ip" "$latency_disp" "$cc" "$DIM" "$asn_isp" "$R"
    fi
}

print_route_summary_domains() {
    local dlist="$1" is_split="$2" linecol="$3" overflow_style="${4:-ellipsis}"
    [[ "${COMPACT_OUTPUT:-0}" == 1 && "$is_split" == 0 ]] && return 0
    local d total=0 shown=0 cnt=0 lineout="      "
    for d in $dlist; do
        total=$((total+1))
        if [[ "$is_split" == 0 && $shown -ge 10 ]]; then continue; fi
        lineout+="$d  "; shown=$((shown+1)); cnt=$((cnt+1))
        if [[ $cnt -eq 4 ]]; then
            printf '%s%s%s\n' "$linecol" "$lineout" "$R"
            lineout="      "; cnt=0
        fi
    done
    if [[ $cnt -gt 0 ]]; then
        [[ "$overflow_style" == ellipsis && $total -gt $shown ]] && lineout+="..."
        printf '%s%s%s\n' "$linecol" "$lineout" "$R"
    fi
    if [[ "$overflow_style" != ellipsis && $total -gt $shown ]]; then
        printf '      %s另有 %d 个域名（完整列表见上方明细）%s\n' "$linecol" "$((total-shown))" "$R"
    fi
    return 0
}

format_elapsed() {
    local s="$1"
    if (( s < 60 )); then printf '%ds' "$s"
    elif (( s < 3600 )); then printf '%dm %ds' $((s/60)) $((s%60))
    else printf '%dh %dm' $((s/3600)) $(((s%3600)/60)); fi
}

# ─── 组内并发 DNS 预解析 + 目标 IP 去重 + 并发 MTR ─────────────────────────
print_progress() {
    local action="$1" cat="$2" done_cnt="$3" total="$4" extra="${5:-}"
    [[ $OUTPUT_JSON -eq 0 ]] && is_tty || return 0
    printf "\r\033[K    %s%s%s %s%s 组%s %s(%d/%d%s)%s" \
        "$CYAN" "$action" "$R" "$BOLD" "$cat" "$R" "$DIM" "$done_cnt" "$total" "$extra" "$R"
}

clear_progress() {
    [[ $OUTPUT_JSON -eq 0 ]] && is_tty || return 0
    printf "\r\033[K"
}

resolve_group_targets() {
    local ip_flag="$1" out_dir="$2" cat="$3"; shift 3
    local -a idxs=("$@")
    local total=${#idxs[@]} maxjobs="$DNS_CONCURRENCY" running=0 done_cnt=0 idx limit=5
    (( MTR_BUDGET < limit )) && limit=$MTR_BUDGET
    (( maxjobs > total )) && maxjobs=$total
    ACTIVE_WORKERS=()
    print_progress "解析中" "$cat" 0 "$total"
    for idx in "${idxs[@]}"; do
        if (( running >= maxjobs )); then
            wait_worker_slot "$maxjobs" running
            done_cnt=$((done_cnt + 1))
            if (( done_cnt % 16 == 0 || done_cnt == total )); then
                print_progress "解析中" "$cat" "$done_cnt" "$total"
            fi
        fi
        (
            local dom="${DOMAINS[$idx]}" t=""
            if is_valid_domain "$dom"; then
                t="$(resolve_target "$ip_flag" "$dom" "$limit" || true)"
            fi
            printf '%s\n' "$t" > "$out_dir/$idx.ip"
        ) &
        ACTIVE_WORKERS+=("$!")
        running=$((running + 1))
    done
    drain_workers
    clear_progress
}

# 按唯一目标 IP 并发执行 MTR（phase=probe 或 repeat）
run_mtr_targets() {
    local ip_flag="$1" out_dir="$2" cat="$3" phase="$4" prefer_mode="$5"; shift 5
    local -a rep_idxs=("$@")
    local total=${#rep_idxs[@]}
    (( total > 0 )) || return 0
    local suffix="" action="检测中" maxjobs="$MTR_CONCURRENCY"
    if [[ "$phase" == "repeat" ]]; then
        suffix=".repeat"
        action="复核中"
        maxjobs="$MTR_REPEAT_CONCURRENCY"
    fi
    (( maxjobs < 1 )) && maxjobs=1
    (( maxjobs > total )) && maxjobs=$total

    local running=0 completed=0 idx
    ACTIVE_WORKERS=()
    print_progress "$action" "$cat" 0 "$total" " 独立目标"
    for idx in "${rep_idxs[@]}"; do
        if (( running >= maxjobs )); then
            wait_worker_slot "$maxjobs" running
            completed=$((completed + 1))
            print_progress "$action" "$cat" "$completed" "$total" " 独立目标"
        fi
        (
            local hop="" target="" evidence="" mode="" _line="" _
            if [[ "$phase" == "repeat" ]]; then
                IFS= read -r _line < "$out_dir/$idx" || true
                split_tsv4 "$_line" _ _ _ evidence
                IFS=, read -r _ _ _ mode target <<< "$evidence"
                hop="$(MTR_ATTEMPTS=1 first_public_hop "$ip_flag" "${DOMAINS[$idx]}" "$target" "$mode" || true)"
            else
                IFS= read -r target < "$out_dir/$idx.ip" || true
                if [[ -n "$target" ]]; then
                    hop="$(first_public_hop "$ip_flag" "${DOMAINS[$idx]}" "$target" "" "$prefer_mode" || true)"
                else
                    hop=$'__DNS_ERROR__\t-\t'
                fi
            fi
            printf '%s\n' "$hop" > "$out_dir/$idx$suffix.tmp"
            mv -f -- "$out_dir/$idx$suffix.tmp" "$out_dir/$idx$suffix"
        ) &
        ACTIVE_WORKERS+=("$!")
        running=$((running + 1))
    done
    drain_workers
    clear_progress
}

# ─── 单协议完整检测主循环 ──────────────────────────────────────────────────
run_check_pass() {
    local label="$1" ip_flag="$2" tmp_file="$3" prefix base_asn mtr_base_asn effective_base_asn base_source base_desc base_evidence base_mode=""
    case "$label" in
        IPv4) prefix=V4; base_asn="${V4_BASE_ASN:-}"; mtr_base_asn="${V4_MTR_BASE_ASN:-}"; base_evidence="${V4_MTR_BASE_EVIDENCE:-}" ;;
        IPv6) prefix=V6; base_asn="${V6_BASE_ASN:-}"; mtr_base_asn="${V6_MTR_BASE_ASN:-}"; base_evidence="${V6_MTR_BASE_EVIDENCE:-}" ;;
    esac
    if [[ -n "$base_evidence" ]]; then
        IFS=, read -r _ _ _ base_mode _ <<< "$base_evidence"
    fi
    effective_base_asn="$base_asn"
    base_source=""
    base_desc="未知"
    if [[ -n "$base_asn" ]]; then
        base_source=http_echo
        base_desc="HTTP 回显 IP 所属 AS$base_asn"
    fi
    if [[ -n "$mtr_base_asn" && "$EGRESS_BASE_MODE" != echo &&
          ( "$EGRESS_BASE_MODE" == mtr || "$mtr_base_asn" != "$base_asn" ) ]]; then
        effective_base_asn="$mtr_base_asn"
        base_source=mtr
        base_desc="稳定 MTR 首跳 AS$mtr_base_asn"
        if [[ "$mtr_base_asn" != "$base_asn" ]]; then
            local echo_asn="${base_asn:+AS$base_asn}"
            base_desc+="（HTTP 回显 ASN ${echo_asn:-未知}）"
        fi
    fi
    printf -v "${prefix}_EFFECTIVE_ASN" '%s' "$effective_base_asn"
    printf -v "${prefix}_BASE_SOURCE" '%s' "$base_source"

    local pass_ok=0 pass_down=0 pass_hidden=0 pass_unknown=0
    local SPLIT_COLORS=( "$YELLOW" "$MAGENTA" "$RED" "$CYAN" )
    local split_color_n=4
    print_pass_header "$label"
    [[ $OUTPUT_JSON -eq 0 ]] && printf "    %s比较基准  %s%s\n" "$DIM" "$base_desc" "$R"

    local out_dir; out_dir="$(mktemp -d "$RUN_DIR/mtr.XXXXXX")"
    local rows_tsv="$out_dir/rows.tsv"
    : > "$rows_tsv"

    local DOMAIN_WIDTH=24 IP_WIDTH=15 gi
    [[ "$ip_flag" == "-6" ]] && IP_WIDTH=39
    for gi in "${DOMAINS[@]}"; do (( ${#gi} <= DOMAIN_WIDTH )) || DOMAIN_WIDTH=${#gi}; done

    local -A cat_idxs=(); local -a cat_order=()
    for gi in "${!DOMAINS[@]}"; do
        local gc="${CATS[$gi]}"
        if [[ -z "${cat_idxs[$gc]+x}" ]]; then cat_order+=("$gc"); cat_idxs[$gc]=""; fi
        cat_idxs[$gc]+="$gi "
    done

    local -A route_isp=() route_cc=() route_domains=() route_dcount=() route_split=() route_scidx=() route_asn=() route_seen=()
    local -A path_domains=() path_counts=()
    local -a path_order=()
    local split_idx=0 split_domain_count=0
    local cat

    for cat in "${cat_order[@]}"; do
        print_category_header "$cat"
        local -a gidxs=()
        read -r -a gidxs <<< "${cat_idxs[$cat]}"

        # 1) 并发 DNS 预解析
        resolve_group_targets "$ip_flag" "$out_dir" "$cat" "${gidxs[@]}"

        # 2) 按解析到的目标 IP 去重，同 VIP 仅测一次 MTR
        local -A ip_to_rep=() idx_to_rep=()
        local -a unique_reps=()
        local idx target
        for idx in "${gidxs[@]}"; do
            target=""
            IFS= read -r target < "$out_dir/$idx.ip" || true
            if [[ -z "$target" ]]; then
                printf '__DNS_ERROR__\t-\t\n' > "$out_dir/$idx"
                idx_to_rep[$idx]="$idx"
            elif [[ -n "${ip_to_rep[$target]+set}" ]]; then
                idx_to_rep[$idx]="${ip_to_rep[$target]}"
            else
                ip_to_rep[$target]="$idx"
                idx_to_rep[$idx]="$idx"
                unique_reps+=("$idx")
            fi
        done

        # 3) 对唯一目标 IP 并发执行 MTR（优先沿用基准协议）
        run_mtr_targets "$ip_flag" "$out_dir" "$cat" "probe" "$base_mode" "${unique_reps[@]}"

        # 4) 收集本组全部需查 ASN 的唯一首跳 IP（以及路径 IP）并并行预取进父进程 IP_CACHE
        local -a need_lookup_ips=()
        local rep_idx hop_line hop latency path_ips evidence p_ip
        for rep_idx in "${unique_reps[@]}"; do
            hop_line=""
            IFS= read -r hop_line < "$out_dir/$rep_idx" || true
            split_tsv4 "$hop_line" hop latency path_ips evidence
            [[ -n "$hop" && "$hop" != __* ]] || continue
            need_lookup_ips+=("$hop")
            if [[ $SKIP_PATH_LOOKUP -eq 0 ]]; then
                for p_ip in $path_ips; do
                    need_lookup_ips+=("$p_ip")
                done
            fi
        done
        if (( ${#need_lookup_ips[@]} > 0 )); then
            prefetch_ips "$out_dir/lookup-init" "${need_lookup_ips[@]}"
        fi

        # 5) 仅对需要复测且可比较的唯一目标 IP 调度复测（同样按 IP 去重）
        local -a repeat_reps=()
        local initial_data="" initial_asn initial_isp initial_country
        for rep_idx in "${unique_reps[@]}"; do
            hop_line=""
            IFS= read -r hop_line < "$out_dir/$rep_idx" || true
            split_tsv4 "$hop_line" hop latency path_ips evidence
            [[ -n "$hop" && "$hop" != __* ]] || continue
            lookup_ip_into "$hop" initial_data || true
            split_lookup_data "$initial_data" initial_asn initial_isp initial_country
            normalize_lookup_fields initial_asn initial_isp initial_country
            if route_repeat_needed "$base_evidence" "$evidence" "$effective_base_asn" "$initial_asn"; then
                repeat_reps+=("$rep_idx")
            fi
        done

        if (( ${#repeat_reps[@]} > 0 )); then
            run_mtr_targets "$ip_flag" "$out_dir" "$cat" "repeat" "$base_mode" "${repeat_reps[@]}"
            local -a repeat_lookup_ips=()
            local rline rhop rpath
            for rep_idx in "${repeat_reps[@]}"; do
                [[ -f "$out_dir/$rep_idx.repeat" ]] || continue
                rline=""
                IFS= read -r rline < "$out_dir/$rep_idx.repeat" || true
                split_tsv4 "$rline" rhop _ rpath _
                [[ -n "$rhop" && "$rhop" != __* ]] || continue
                repeat_lookup_ips+=("$rhop")
                if [[ $SKIP_PATH_LOOKUP -eq 0 ]]; then
                    for p_ip in $rpath; do
                        repeat_lookup_ips+=("$p_ip")
                    done
                fi
            done
            if (( ${#repeat_lookup_ips[@]} > 0 )); then
                prefetch_ips "$out_dir/lookup-repeat" "${repeat_lookup_ips[@]}"
            fi
        fi

        # 6) 逐域名输出报告与 TSV 行（全部命中内存 IP_CACHE，零外部进程）
        for idx in "${gidxs[@]}"; do
            local cat_v="$cat" domain="${DOMAINS[$idx]}" note="${NOTES[$idx]}"
            local src_idx="${idx_to_rep[$idx]}"
            hop_line=""
            if [[ -f "$out_dir/$src_idx" ]]; then
                IFS= read -r hop_line < "$out_dir/$src_idx" || true
            fi
            split_tsv4 "$hop_line" hop latency path_ips evidence
            latency="${latency:-"-"}"

            if [[ "$hop" == "__HIDDEN__" ]]; then
                pass_hidden=$((pass_hidden + 1))
                pass_unknown=$((pass_unknown + 1))
                [[ $OUTPUT_JSON -eq 0 ]] && print_result_row "$SYM_SKIP" "$domain" "-" "$latency" "-" "" "路径隐藏 / 仅目标可见" 0
                printf 'hidden\t%s\t%s\t\t%s\t\t\t\t\t\t\t\t\t%s\t\n' \
                    "$cat_v" "$domain" "$latency" "$note" >> "$rows_tsv"
                continue
            fi

            if [[ -z "$hop" || "$hop" == __* ]]; then
                local failure_status="probe_error" failure_text="探测失败 / 无有效报告"
                case "$hop" in
                    __DNS_ERROR__)   failure_status="dns_error";   failure_text="DNS 解析失败 / 无该协议地址" ;;
                    __PARSE_ERROR__) failure_status="parse_error"; failure_text="MTR 报告解析失败" ;;
                    __NO_REPLY__)    failure_status="no_reply";    failure_text="目标未回应 / 无公网中间跳" ;;
                esac
                pass_down=$((pass_down + 1))
                pass_unknown=$((pass_unknown + 1))
                [[ $OUTPUT_JSON -eq 0 ]] && print_result_row "$SYM_DOWN" "$domain" "-" "-" "-" "" "$failure_text" 0
                printf 'error\t%s\t%s\t%s\t\t\t\t\t\t\t\t\t\t%s\t%s\n' \
                    "$cat_v" "$domain" "$failure_status" "$note" "$failure_text" >> "$rows_tsv"
                continue
            fi

            local data="" asn isp country
            lookup_ip_into "$hop" data || true
            split_lookup_data "$data" asn isp country
            normalize_lookup_fields asn isp country

            local confirmed=0 comparison_reason="" comparison="inconclusive" comparison_scope="none"
            local ttl repeat_line repeat_hop repeat_latency repeat_path repeat_evidence repeat_data="" repeat_asn repeat_isp repeat_country _
            if [[ -f "$out_dir/$src_idx.repeat" ]]; then
                repeat_line=""
                IFS= read -r repeat_line < "$out_dir/$src_idx.repeat" || true
                split_tsv4 "$repeat_line" repeat_hop repeat_latency repeat_path repeat_evidence
                if [[ -n "$repeat_hop" && "$repeat_hop" != __* ]] && route_evidence_comparable "$base_evidence" "$repeat_evidence"; then
                    lookup_ip_into "$repeat_hop" repeat_data || true
                    split_lookup_data "$repeat_data" repeat_asn repeat_isp repeat_country
                    normalize_lookup_fields repeat_asn repeat_isp repeat_country
                    if [[ "$repeat_asn" == "$effective_base_asn" ]]; then
                        hop="$repeat_hop"; latency="$repeat_latency"; path_ips="$repeat_path"; evidence="$repeat_evidence"
                        asn="$repeat_asn"; isp="$repeat_isp"; country="$repeat_country"
                    elif [[ "$repeat_hop" == "$hop" && "$repeat_asn" == "$asn" ]] && route_evidence_comparable "$base_evidence" "$evidence"; then
                        confirmed=1
                    else
                        comparison_reason="首跳复测不稳定 / 无法判定"
                    fi
                else
                    comparison_reason="首跳复测证据不足 / 无法判定"
                fi
            fi

            [[ -z "$country" ]] && country="??"
            [[ -z "$isp" ]] && isp="Unknown"
            pass_ok=$((pass_ok + 1))

            local is_split=-1
            if [[ -z "$effective_base_asn" || -z "$asn" ]]; then
                comparison_reason="ASN 未知 / 无法判定"
            elif [[ "$asn" == "$effective_base_asn" ]]; then
                is_split=0; comparison="baseline_match"; comparison_scope="asn"
                comparison_reason="可见首跳 ASN 与基准一致"
            elif [[ -z "$base_evidence" ]]; then
                comparison_reason="基准首跳不稳定或不可见 / 无法判定"
            elif ! route_evidence_comparable "$base_evidence" "$evidence"; then
                comparison_reason="$(route_evidence_reason "$base_evidence" "$evidence")"
            elif [[ "$confirmed" == 1 ]]; then
                is_split=1; comparison="repeatable_difference"; comparison_scope="complete_prefix"
                comparison_reason="复测确认可见首跳 ASN 与基准不同"
            elif [[ -z "$comparison_reason" ]]; then
                comparison_reason="首跳差异未经确认 / 无法判定"
            fi
            [[ $is_split -eq -1 ]] && pass_unknown=$((pass_unknown + 1))

            local route_id="$asn"; [[ -z "$route_id" ]] && route_id="ip:$hop"
            route_seen[$route_id]=1
            local key="$route_id:$is_split"
            if [[ -z "${route_split[$key]+x}" ]]; then
                route_asn[$key]="$route_id"
                route_isp[$key]="$isp"; route_cc[$key]="$country"
                route_domains[$key]="$domain"; route_dcount[$key]=1; route_split[$key]="$is_split"
                if [[ $is_split -eq 1 ]]; then route_scidx[$key]=$split_idx; split_idx=$((split_idx+1)); else route_scidx[$key]=-1; fi
            else
                route_domains[$key]+=" $domain"
                route_dcount[$key]=$((route_dcount[$key] + 1))
            fi
            [[ $is_split -eq 1 ]] && split_domain_count=$((split_domain_count+1))

            local path_chain="" path_summary=""
            if [[ $SKIP_PATH_LOOKUP -eq 0 && -n "$path_ips" ]]; then
                path_asn_chain_into "$path_ips" path_chain
                path_asn_summary_into "$path_chain" path_summary
                if [[ -n "$path_summary" ]]; then
                    if [[ -z "${path_counts[$path_summary]+x}" ]]; then
                        path_order+=("$path_summary")
                        path_counts[$path_summary]=0
                        path_domains[$path_summary]=""
                    fi
                    path_counts[$path_summary]=$((path_counts[$path_summary]+1))
                    path_domains[$path_summary]+="$domain "
                fi
            fi

            local marker display_isp="$isp"
            if [[ $is_split -eq 1 ]]; then marker="${YELLOW}●${R}"
            elif [[ $is_split -eq 0 ]]; then marker="${GREEN}●${R}"
            else marker="$SYM_SKIP"; display_isp+=" ($comparison_reason)"; fi
            [[ "$latency" == "-" ]] && display_isp+=" (目标未回应)"
            [[ $OUTPUT_JSON -eq 0 ]] && print_result_row "$marker" "$domain" "$hop" "$latency" "$country" "$asn" "$display_isp" "$is_split" "$comparison_reason" "$comparison_scope"

            IFS=, read -r ttl _ _ _ _ <<< "$evidence"
            [[ "$ttl" =~ ^[1-9][0-9]*$ ]] || ttl=""
            printf 'ok\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$cat_v" "$domain" "$hop" "$latency" "$ttl" "$comparison" "$comparison_scope" \
                "$path_chain" "$asn" "$isp" "$country" "$is_split" "$note" "$comparison_reason" >> "$rows_tsv"
        done
    done

    # 单次 jq 批量将整份 TSV 转为标准 JSON 数组（替代数千次 jq -n fork）
    jq -R -s '
        def to_num_or_null: if test("^[0-9]+([.][0-9]+)?$") then tonumber else null end;
        def to_int_or_null: if test("^[1-9][0-9]*$") then tonumber else null end;
        split("\n") | map(select(length > 0) | split("\t") |
            if .[0] == "hidden" then
                {category:.[1], domain:.[2], status:"hidden", first_hop:null,
                 latency_ms:(.[4] | to_num_or_null), path_asn_chain:null, asn:null,
                 isp:null, country:null, split:null, note:(.[13] + " 路径隐藏 / 仅目标可见")}
            elif .[0] == "error" then
                {category:.[1], domain:.[2], status:.[3], first_hop:null,
                 latency_ms:null, path_asn_chain:null, asn:null, isp:null,
                 country:null, split:null, note:.[13], reason:.[14]}
            else
                {category:.[1], domain:.[2], status:"ok", first_hop:.[3],
                 first_hop_ttl:(.[5] | to_int_or_null), comparison:.[6],
                 comparison_scope:.[7], reason:.[14],
                 latency_ms:(.[4] | to_num_or_null),
                 path_asn_chain:(if .[8] == "" then null else .[8] end),
                 asn:(if .[9] == "" then null else "AS" + .[9] end),
                 isp:.[10], country:.[11],
                 split:(if .[12] == "0" then false elif .[12] == "1" then true else null end),
                 note:.[13]}
            end)
    ' "$rows_tsv" > "$tmp_file"

    rm -rf -- "$out_dir" 2>/dev/null || true

    local route_count=${#route_seen[@]}
    printf -v "${prefix}_OK" '%s' "$pass_ok"
    printf -v "${prefix}_DOWN" '%s' "$pass_down"
    printf -v "${prefix}_HIDDEN" '%s' "$pass_hidden"
    printf -v "${prefix}_UNKNOWN" '%s' "$pass_unknown"
    printf -v "${prefix}_ROUTE_COUNT" '%s' "$route_count"
    printf -v "${prefix}_SPLIT_DOMAINS" '%s' "$split_domain_count"

    if [[ $OUTPUT_JSON -eq 0 && $route_count -gt 0 ]]; then
        printf "\n  %s\n" "$(rule_single 72)"
        printf "  %s%s 可见首跳汇总%s\n" "$BOLD" "$label" "$R"
        printf "  %s\n" "$(rule_single 72)"
        local key round
        for round in base split unknown; do
            for key in "${!route_split[@]}"; do
                if [[ "$round" == "base" ]]; then [[ "${route_split[$key]}" == "0" ]] || continue
                elif [[ "$round" == "split" ]]; then [[ "${route_split[$key]}" == "1" ]] || continue
                else [[ "${route_split[$key]}" == "-1" ]] || continue; fi
                local dlist="${route_domains[$key]}"
                local dcount="${route_dcount[$key]}"
                local asn_disp="${route_asn[$key]}"
                [[ "$asn_disp" == ip:* ]] && asn_disp="${asn_disp#ip:}" || asn_disp="AS$asn_disp"
                local marker tag tagcol
                if [[ "${route_split[$key]}" == "1" ]]; then
                    marker="${SPLIT_COLORS[${route_scidx[$key]} % split_color_n]}●${R}"; tag="⚠ 首跳 ASN 差异已复测"; tagcol="$YELLOW"
                elif [[ "${route_split[$key]}" == "0" ]]; then
                    marker="${GREEN}●${R}"; tag="✓ 首跳 ASN 与基准一致"; tagcol="$GREEN"
                else
                    marker="$SYM_SKIP"; tag="首跳证据不足 / 无法判定"; tagcol="$GRAY"
                fi
                if [[ $COMPACT_OUTPUT -eq 1 && "${route_split[$key]}" == 0 ]]; then
                    printf "    %s  %s%d 域名%s  %s%s%s\n" "$marker" "$BOLD" "$dcount" "$R" "$tagcol" "$tag" "$R"
                else
                    printf "    %s  %s%-26s%s %s(%s · %s)%s  %s%d 域名%s  %s%s%s\n" \
                        "$marker" "$BOLD" "${route_isp[$key]}" "$R" "$DIM" "$asn_disp" "${route_cc[$key]}" "$R" "$BOLD" "$dcount" "$R" "$tagcol" "$tag" "$R"
                fi
                local linecol="$DIM"; [[ "${route_split[$key]}" == "1" ]] && linecol="$YELLOW"
                print_route_summary_domains "$dlist" "${route_split[$key]}" "$linecol"
                printf "\n"
            done
        done
        if [[ $split_idx -ge 1 ]]; then
            printf "  %s%s %s复测确认 %d 个域名的可见首跳 ASN 与基准不同，涉及 %d 个 ASN%s\n" "$BOLD" "$SYM_WARN" "$YELLOW" "$split_domain_count" "$split_idx" "$R"
        elif [[ $pass_unknown -eq 0 ]]; then
            printf "  %s%s %s所有已测域名的可见首跳 ASN 均与基准 AS%s 一致%s\n" "$BOLD" "$SYM_INFO" "$GREEN" "$effective_base_asn" "$R"
        fi
        if [[ $pass_unknown -gt 0 ]]; then
            printf "  %s%s %s本轮 %d 个域名无法判定%s\n" "$BOLD" "$SYM_INFO" "$GRAY" "$pass_unknown" "$R"
        fi

        if [[ $COMPACT_OUTPUT -eq 0 && $SKIP_PATH_LOOKUP -eq 0 && ${#path_order[@]} -gt 0 ]]; then
            local max_paths="$PATH_SUMMARY_LIMIT"
            [[ "$max_paths" =~ ^[0-9]+$ ]] || max_paths=8
            (( max_paths < 1 )) && max_paths=1
            printf "\n  %s%s 路径 ASN 摘要%s  %s(辅助观察, 不直接等同分流)%s\n" "$BOLD" "$label" "$R" "$DIM" "$R"
            printf "  %s\n" "$(rule_single 72)"
            local chain shown=0 chain_disp="" dlist
            for chain in "${path_order[@]}"; do
                (( shown >= max_paths )) && break
                shown=$((shown+1))
                short_text_into "$chain" 58 chain_disp
                dlist="${path_domains[$chain]}"
                printf "    %s%-58s%s  %s%2d 域名%s\n" "$CYAN" "$chain_disp" "$R" "$BOLD" "${path_counts[$chain]}" "$R"
                print_route_summary_domains "$dlist" 0 "$DIM" ellipsis
            done
        fi
    fi
}

# ─── 主流程 ────────────────────────────────────────────────────────────────
START_EPOCH=$(date +%s)
START_TS="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
_raw_host="$(hostname 2>/dev/null || printf 'unknown')"
sanitize_str_into "$_raw_host" HOST_NAME; unset _raw_host
V4_OK=0; V4_DOWN=0; V4_HIDDEN=0; V4_UNKNOWN=0; V4_ROUTE_COUNT=0
V6_OK=0; V6_DOWN=0; V6_HIDDEN=0; V6_UNKNOWN=0; V6_ROUTE_COUNT=0
V4_PASS_RAN=0; V6_PASS_RAN=0; V4_ECHO_UNIQUE=0; V6_ECHO_UNIQUE=0
V4_ECHO_DETAIL=""; V6_ECHO_DETAIL=""; DEFAULT_EGRESS="none"
V4_IP=""; V6_IP=""; V4_INFO="—"; V6_INFO="—"
V4_BASE_ASN=""; V6_BASE_ASN=""; V4_SPLIT_DOMAINS=0; V6_SPLIT_DOMAINS=0
V4_MTR_BASE_ASN=""; V4_MTR_BASE_HOP=""; V4_MTR_BASE_INFO="—"; V4_MTR_BASE_EVIDENCE=""
V6_MTR_BASE_ASN=""; V6_MTR_BASE_HOP=""; V6_MTR_BASE_INFO="—"; V6_MTR_BASE_EVIDENCE=""
V4_EFFECTIVE_ASN=""; V6_EFFECTIVE_ASN=""; V4_BASE_SOURCE=""; V6_BASE_SOURCE=""
[[ $OUTPUT_JSON -eq 0 ]] && print_banner "$HOST_NAME" "$START_TS"

# 并行探测所有回显端点（6×v4 + 6×v6 + 默认），最长仅受单次 ENV_TIMEOUT 约束
do_env_detect() {
    local env_dir="$RUN_DIR/env"
    mkdir -p "$env_dir"
    local i ep ip def_ip="" line a c d="" isp_v
    local -a v4_lines=() v6_lines=()
    local -A v4_seen=() v6_seen=()
    ACTIVE_WORKERS=()

    for (( i=0; i<${#ENV_ENDPOINTS[@]}; i++ )); do
        ep="${ENV_ENDPOINTS[$i]}"
        if [[ "$PASS_MODE" == "auto" || "$PASS_MODE" == "v4-only" ]]; then
            (
                local out
                out=$(curl -fsS -4 --max-time "$ENV_TIMEOUT" --proto '=https' --tlsv1.2 -A "$UA" "$ep" 2>/dev/null || true)
                out="${out//[[:space:]]/}"
                [[ -n "$out" && "$out" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && printf '%s\n' "$out" > "$env_dir/v4-$i"
            ) &
            ACTIVE_WORKERS+=("$!")
        fi
        if [[ "$PASS_MODE" == "auto" || "$PASS_MODE" == "v6-only" ]]; then
            (
                local out
                out=$(curl -fsS -6 --max-time "$ENV_TIMEOUT" --proto '=https' --tlsv1.2 -A "$UA" "$ep" 2>/dev/null || true)
                out="${out//[[:space:]]/}"
                [[ -n "$out" && "$out" == *:* ]] && printf '%s\n' "$out" > "$env_dir/v6-$i"
            ) &
            ACTIVE_WORKERS+=("$!")
        fi
        if [[ "$PASS_MODE" == "auto" ]]; then
            (
                local out
                out=$(curl -fsS --max-time "$ENV_TIMEOUT" --proto '=https' --tlsv1.2 -A "$UA" "$ep" 2>/dev/null || true)
                out="${out//[[:space:]]/}"
                [[ -n "$out" ]] && printf '%s\n' "$out" > "$env_dir/def-$i"
            ) &
            ACTIVE_WORKERS+=("$!")
        fi
    done
    drain_workers

    for (( i=0; i<${#ENV_ENDPOINTS[@]}; i++ )); do
        ep="${ENV_ENDPOINTS[$i]}"
        if [[ -f "$env_dir/v4-$i" ]]; then
            ip=""
            IFS= read -r ip < "$env_dir/v4-$i" || true
            if [[ -n "$ip" ]]; then
                v4_lines+=("${ip}|${ep}")
                v4_seen[$ip]=1
            fi
        fi
        if [[ -f "$env_dir/v6-$i" ]]; then
            ip=""
            IFS= read -r ip < "$env_dir/v6-$i" || true
            if [[ -n "$ip" ]]; then
                v6_lines+=("${ip}|${ep}")
                v6_seen[$ip]=1
            fi
        fi
        if [[ -z "$def_ip" && -f "$env_dir/def-$i" ]]; then
            IFS= read -r def_ip < "$env_dir/def-$i" || true
        fi
    done
    rm -rf -- "$env_dir" 2>/dev/null || true

    local -a env_ips=()
    V4_ECHO_UNIQUE=${#v4_seen[@]}
    if (( ${#v4_lines[@]} > 0 )); then
        V4_IP="${v4_lines[0]%%|*}"
        env_ips+=("$V4_IP")
    fi
    V6_ECHO_UNIQUE=${#v6_seen[@]}
    if (( ${#v6_lines[@]} > 0 )); then
        V6_IP="${v6_lines[0]%%|*}"
        env_ips+=("$V6_IP")
    fi
    if (( ${#env_ips[@]} > 0 )); then
        prefetch_ips "$RUN_DIR/env-lookup" "${env_ips[@]}"
    fi

    if [[ -n "$V4_IP" ]]; then
        local detail=""
        for line in "${v4_lines[@]}"; do
            ip="${line%%|*}"; ep="${line##*|}"; ep="${ep#https://}"; ep="${ep%%/*}"
            detail+="${detail:+ ; }${ip}@${ep}"
        done
        V4_ECHO_DETAIL="$detail"
        lookup_ip_into "$V4_IP" d || true
        split_lookup_data "$d" a isp_v c; normalize_lookup_fields a isp_v c
        [[ -z "$c" ]] && c="??"; [[ -z "$isp_v" ]] && isp_v="Unknown"; V4_BASE_ASN="$a"
        if [[ -n "$a" ]]; then V4_INFO="$c · AS${a} ${isp_v}"; else V4_INFO="$c · ${isp_v}"; fi
    fi

    if [[ -n "$V6_IP" ]]; then
        local detail=""
        for line in "${v6_lines[@]}"; do
            ip="${line%%|*}"; ep="${line##*|}"; ep="${ep#https://}"; ep="${ep%%/*}"
            detail+="${detail:+ ; }${ip}@${ep}"
        done
        V6_ECHO_DETAIL="$detail"
        lookup_ip_into "$V6_IP" d || true
        split_lookup_data "$d" a isp_v c; normalize_lookup_fields a isp_v c
        [[ -z "$c" ]] && c="??"; [[ -z "$isp_v" ]] && isp_v="Unknown"; V6_BASE_ASN="$a"
        if [[ -n "$a" ]]; then V6_INFO="$c · AS${a} ${isp_v}"; else V6_INFO="$c · ${isp_v}"; fi
    fi

    if [[ "$PASS_MODE" == "auto" ]]; then
        if [[ -n "$def_ip" ]]; then ip_family_into "$def_ip" DEFAULT_EGRESS; fi
    elif [[ "$PASS_MODE" == "v4-only" ]]; then DEFAULT_EGRESS="ipv4"
    elif [[ "$PASS_MODE" == "v6-only" ]]; then DEFAULT_EGRESS="ipv6"; fi
}

do_env_detect
if [[ -n "$V4_IP" && ( "$PASS_MODE" == "auto" || "$PASS_MODE" == "v4-only" ) ]]; then
    detect_mtr_base_asn "-4" "V4" || true
fi
if [[ -n "$V6_IP" && ( "$PASS_MODE" == "auto" || "$PASS_MODE" == "v6-only" ) ]]; then
    detect_mtr_base_asn "-6" "V6" || true
fi
[[ $OUTPUT_JSON -eq 0 && "$PASS_MODE" == "auto" ]] && print_env_section "$DEFAULT_EGRESS" "$V4_IP" "$V6_IP" "$V4_INFO" "$V6_INFO"
[[ $OUTPUT_JSON -eq 0 ]] && printf "\n  %s共 %d 个域名, 按分类逐组检测 (绿●=首跳匹配, 黄●=复测差异, 灰⊘=无法判定)%s\n" "$DIM" "$TOTAL" "$R"

TMP_V4_RESULTS="$(mktemp "$RUN_DIR/v4.XXXXXXXX")"
TMP_V6_RESULTS="$(mktemp "$RUN_DIR/v6.XXXXXXXX")"
chmod 600 "$TMP_V4_RESULTS" "$TMP_V6_RESULTS"
V6_SKIP_REASON=""
case "$PASS_MODE" in
    auto)
        if [[ -n "$V4_IP" ]]; then run_check_pass "IPv4" "-4" "$TMP_V4_RESULTS"; V4_PASS_RAN=1
        else print_pass_header "IPv4"; [[ $OUTPUT_JSON -eq 0 ]] && printf "    %s  IPv4 出口不可用 — 跳过\n" "$SYM_SKIP"; fi
        if [[ -n "$V6_IP" ]]; then run_check_pass "IPv6" "-6" "$TMP_V6_RESULTS"; V6_PASS_RAN=1
        else V6_SKIP_REASON="IPv6 出口不可用或已禁用"; print_pass_header "IPv6"; [[ $OUTPUT_JSON -eq 0 ]] && printf "    %s  %s — 跳过\n" "$SYM_SKIP" "$V6_SKIP_REASON"; fi ;;
    v4-only) if [[ -n "$V4_IP" ]]; then run_check_pass "IPv4" "-4" "$TMP_V4_RESULTS"; V4_PASS_RAN=1; else err "IPv4 出口不可用"; exit 2; fi ;;
    v6-only) if [[ -n "$V6_IP" ]]; then run_check_pass "IPv6" "-6" "$TMP_V6_RESULTS"; V6_PASS_RAN=1; else err "IPv6 出口不可用"; exit 2; fi ;;
esac

END_EPOCH=$(date +%s); ELAPSED=$((END_EPOCH - START_EPOCH)); ELAPSED_STR="$(format_elapsed "$ELAPSED")"
if [[ $OUTPUT_JSON -eq 0 ]]; then
    printf "\n"; rule_double 72
    if [[ $V4_PASS_RAN -eq 1 ]]; then
        printf "  IPv4:  %s%d 个域名有可见首跳%s   %s%d 个首跳分组%s   %s%d 个域名首跳 ASN 差异已复测%s   %s%d 路径隐藏%s   %s%d 探测失败%s\n" "$GREEN" "$V4_OK" "$R" "$CYAN" "$V4_ROUTE_COUNT" "$R" "$YELLOW" "$V4_SPLIT_DOMAINS" "$R" "$GRAY" "$V4_HIDDEN" "$R" "$RED" "$V4_DOWN" "$R"
        printf "         %s%d 无法判定（包含隐藏、失败及首跳证据不足）%s\n" "$GRAY" "$V4_UNKNOWN" "$R"
    else printf "  IPv4:  %s skipped\n" "$SYM_SKIP"; fi
    if [[ $V6_PASS_RAN -eq 1 ]]; then
        printf "  IPv6:  %s%d 个域名有可见首跳%s   %s%d 个首跳分组%s   %s%d 个域名首跳 ASN 差异已复测%s   %s%d 路径隐藏%s   %s%d 探测失败%s\n" "$GREEN" "$V6_OK" "$R" "$CYAN" "$V6_ROUTE_COUNT" "$R" "$YELLOW" "$V6_SPLIT_DOMAINS" "$R" "$GRAY" "$V6_HIDDEN" "$R" "$RED" "$V6_DOWN" "$R"
        printf "         %s%d 无法判定（包含隐藏、失败及首跳证据不足）%s\n" "$GRAY" "$V6_UNKNOWN" "$R"
    else printf "  IPv6:  %s skipped  %s%s%s\n" "$SYM_SKIP" "$DIM" "${V6_SKIP_REASON:-}" "$R"; fi
    printf "\n  检测脚本：%shttps://github.com/tgr989/mmw-profile%s (基于 AIFansX/egress-check)\n" "$CYAN" "$R"
    printf "  %selapsed:%s %s\n" "$DIM" "$R" "$ELAPSED_STR"; rule_double 72
fi

FINAL_JSON="$(mktemp "$RUN_DIR/final.XXXXXXXX")"; chmod 600 "$FINAL_JSON"
build_pass_obj() {
    local prefix="$1" ran="$2" tmp_file="$3" skip_reason="$4"
    if [[ "$ran" == "1" ]]; then
        local ok_var="${prefix}_OK" down_var="${prefix}_DOWN" hidden_var="${prefix}_HIDDEN" routes_var="${prefix}_ROUTE_COUNT"
        local asn_var="${prefix}_EFFECTIVE_ASN" source_var="${prefix}_BASE_SOURCE"
        jq -n --argjson ok "${!ok_var}" --argjson dn "${!down_var}" --argjson hidden "${!hidden_var}" --argjson rc "${!routes_var}" \
            --arg asn "${!asn_var}" --arg source "${!source_var}" --slurpfile r "$tmp_file" \
            '$r[0] as $rows |
            {available:true, baseline_asn:(if $asn == "" then null else "AS"+$asn end),
             baseline_source:(if $source == "" then null else $source end),
             summary:{total:($ok+$hidden+$dn), ok:$ok, hidden:$hidden, down:$dn,
             unknown:([$rows[] | select(.split == null)] | length)},
             route_count:$rc, split_routing_detected:
               (if any($rows[]; .split == true) then true
                elif all($rows[]; .split == false) then false else null end),
             results:$rows}'
    else
        jq -n --arg reason "$skip_reason" '{available:false, baseline_asn:null, baseline_source:null, summary:null, route_count:0, split_routing_detected:null, results:null, reason:$reason}'
    fi
}
build_pass_obj V4 "$V4_PASS_RAN" "$TMP_V4_RESULTS" "IPv4 出口不可用" > "$RUN_DIR/ipv4.json"
build_pass_obj V6 "$V6_PASS_RAN" "$TMP_V6_RESULTS" "${V6_SKIP_REASON:-IPv6 出口不可用或已禁用}" > "$RUN_DIR/ipv6.json"
jq -n --arg ts "$START_TS" --arg host "$HOST_NAME" --arg ver "$VERSION" --arg defegr "$DEFAULT_EGRESS" \
    --arg v4ip "$V4_IP" --arg v4info "$V4_INFO" --arg v6ip "$V6_IP" --arg v6info "$V6_INFO" \
    --arg v4echo "$V4_ECHO_DETAIL" --arg v6echo "$V6_ECHO_DETAIL" \
    --argjson v4uniq "$V4_ECHO_UNIQUE" --argjson v6uniq "$V6_ECHO_UNIQUE" \
    --argjson elapsed "$ELAPSED" --slurpfile v4 "$RUN_DIR/ipv4.json" --slurpfile v6 "$RUN_DIR/ipv6.json" \
    '{ timestamp:$ts, host:$host, version:$ver, elapsed_seconds:$elapsed,
       env:{ default_egress:$defegr,
         ipv4:{ip:(if $v4ip=="" then null else $v4ip end), info:$v4info, echo_unique_count:$v4uniq, echo_detail:(if $v4echo=="" then null else $v4echo end), snat_suspected:($v4uniq>1)},
         ipv6:{ip:(if $v6ip=="" then null else $v6ip end), info:$v6info, echo_unique_count:$v6uniq, echo_detail:(if $v6echo=="" then null else $v6echo end), snat_suspected:($v6uniq>1)} },
       ipv4:$v4[0], ipv6:$v6[0] }' > "$FINAL_JSON"
[[ $OUTPUT_JSON -eq 1 ]] && cat "$FINAL_JSON"
LAST_JSON="$CACHE_DIR/last.json"
if mv -f -- "$FINAL_JSON" "$LAST_JSON" 2>/dev/null; then chmod 600 "$LAST_JSON" 2>/dev/null || true; FINAL_JSON=""
else err "保存 last.json 失败"; fi
TOTAL_DOWN=$((V4_DOWN + V6_DOWN))
[[ $V4_PASS_RAN -eq 0 && $V6_PASS_RAN -eq 0 ]] && exit 2
[[ $TOTAL_DOWN -gt 0 ]] && exit 2
exit 0
