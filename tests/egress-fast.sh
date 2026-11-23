#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
fast_script="$project_dir/egress-check/ip-fast.sh"
command -v jq >/dev/null

# 1. 语法与 LF 行尾检查
bash -n "$fast_script"
! LC_ALL=C grep -q $'\r' "$fast_script"
printf 'PASS syntax & LF line endings\n'

# 2. 完整复用原版基线回归测试，确保 100% 协议/输出兼容
EGRESS_SCRIPT="$fast_script" bash "$project_dir/tests/egress-baseline.sh"
printf 'PASS full egress-baseline parity\n'

# 3. 针对性回归：目标禁 Ping 不误切 TCP、ipinfo 缺 country 不错位、
#    IP_CACHE 正负缓存生效、目标 IP 去重、--first-hop-only、Fake-IP 跳过
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/bin" "$work/logs"

cat > "$work/bin/curl" <<'MOCK'
#!/usr/bin/env bash
url="${!#}"
case "$url" in
    https://ipinfo.io/*/json)
        printf '%s\n' "$url" >> "$MOCK_LOG/geoip.log"
        case "$url" in
            */192.0.2.1/json)       printf '{"country":"US","org":"AS64510 Base ISP"}\n' ;;
            */198.51.100.1/json)    printf '{"country":"US","org":"AS64510 Base ISP"}\n' ;;
            */198.51.100.2/json)    printf '{"country":"TW","org":"AS64520 Split ISP"}\n' ;;
            */198.51.100.3/json)    exit 1 ;;
            */198.51.100.4/json)    printf '{"org":"AS64530 NoCountry ISP"}\n' ;;
            */198.51.100.99/json)   printf '{"country":"SG","org":"AS64599 Transit ISP"}\n' ;;
            *)                      exit 1 ;;
        esac
        ;;
    https://api.ip.sb/geoip/*)
        printf '%s\n' "$url" >> "$MOCK_LOG/geoip.log"
        case "$url" in
            */198.51.100.4) printf '{"country_code":"JP","asn":64530,"asn_organization":"Fallback ISP"}\n' ;;
            *) exit 1 ;;
        esac
        ;;
    https://ipwho.is/*)
        printf '%s\n' "$url" >> "$MOCK_LOG/geoip.log"
        exit 1
        ;;
    *)
        case " $* " in *" -6 "*) exit 1 ;; *) echo '192.0.2.1' ;; esac
        ;;
esac
MOCK

cat > "$work/bin/getent" <<'MOCK'
#!/usr/bin/env bash
case "$2" in
    reference.test)        echo "203.0.113.10 STREAM" ;;
    shared-a-*.test)       echo "203.0.113.11 STREAM" ;;
    shared-split-*.test)   echo "203.0.113.12 STREAM" ;;
    noping-split.test)     echo "203.0.113.13 STREAM" ;;
    fail-geo-*.test)       echo "203.0.113.14 STREAM" ;;
    nocountry.test)        echo "203.0.113.15 STREAM" ;;
    fakeip-hop.test)       echo "203.0.113.16 STREAM" ;;
    *) exit 2 ;;
esac
MOCK

cat > "$work/bin/mtr" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_LOG/mtr.log"
target="${!#}"
is_tcp=0
case " $* " in *" -T "*) is_tcp=1 ;; esac
row() { printf '%s. %s %s 3 1.0 1.0 1.0 1.0 0.0\n' "$1" "$2" "$3"; }
case "$target" in
    203.0.113.10|203.0.113.11)
        row 1 198.51.100.1 "0.0%"
        row 2 198.51.100.99 "0.0%"
        row 3 "$target" "0.0%"
        ;;
    203.0.113.12)
        row 1 198.51.100.2 "0.0%"
        row 2 198.51.100.99 "0.0%"
        row 3 "$target" "0.0%"
        ;;
    203.0.113.13)
        # 终点禁 ICMP Ping（100% 丢包），但首跳 ICMP 干净可见；TCP 才会通到终点
        row 1 198.51.100.2 "0.0%"
        if (( is_tcp == 1 )); then
            row 2 "$target" "0.0%"
        else
            row 2 "???" "100.0%"
        fi
        ;;
    203.0.113.14)
        row 1 198.51.100.3 "0.0%"
        row 2 "$target" "0.0%"
        ;;
    203.0.113.15)
        row 1 198.51.100.4 "0.0%"
        row 2 "$target" "0.0%"
        ;;
    203.0.113.16)
        # 首跳为 Clash Fake-IP 198.18.0.1（应视为私网跳过），第二跳才是真实公网跳
        row 1 198.18.0.1 "0.0%"
        row 2 198.51.100.1 "0.0%"
        row 3 "$target" "0.0%"
        ;;
esac
MOCK

printf '#!/bin/sh\nexit 1\n' > "$work/bin/nslookup"
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH" MOCK_LOG="$work/logs" MTR_BASE_DOMAIN=reference.test MTR_ATTEMPTS=1

cat > "$work/rules.csv" <<'EOF'
EgressRule,Rank,Domain
Cat|shared-a-1.test|,1,shared-a-1.test
Cat|shared-a-2.test|,2,shared-a-2.test
Cat|shared-a-3.test|,3,shared-a-3.test
Cat|shared-a-4.test|,4,shared-a-4.test
Cat|shared-split-1.test|,5,shared-split-1.test
Cat|shared-split-2.test|,6,shared-split-2.test
Cat|noping-split.test|,7,noping-split.test
Cat|fail-geo-1.test|,8,fail-geo-1.test
Cat|fail-geo-2.test|,9,fail-geo-2.test
Cat|fail-geo-3.test|,10,fail-geo-3.test
Cat|nocountry.test|,11,nocountry.test
Cat|fakeip-hop.test|,12,fakeip-hop.test
EOF

# 测试 A：默认模式（验证去重、禁 Ping 不切 TCP、ipinfo 缺 country 回退、负缓存、Fake-IP 过滤）
: > "$work/logs/mtr.log"
: > "$work/logs/geoip.log"
EGRESS_CACHE="$work/cache-a" bash "$fast_script" -4 --rules "$work/rules.csv" --json > "$work/out-a.json"

jq -e '
    .ipv4.available == true and
    .ipv4.summary.total == 12 and
    .ipv4.summary.ok == 12 and
    (.ipv4.results | map({key:.domain, value:.}) | from_entries) as $m |
    $m["shared-a-1.test"].split == false and
    $m["shared-a-4.test"].split == false and
    $m["shared-split-1.test"].split == true and
    $m["shared-split-2.test"].split == true and
    $m["noping-split.test"].split == true and
    $m["noping-split.test"].latency_ms == null and
    $m["nocountry.test"].country == "JP" and
    $m["nocountry.test"].asn == "AS64530" and
    $m["nocountry.test"].split == true and
    $m["fail-geo-1.test"].split == null and
    $m["fail-geo-3.test"].split == null and
    $m["fakeip-hop.test"].first_hop == "198.51.100.1" and
    $m["fakeip-hop.test"].split == false
' "$work/out-a.json" >/dev/null
printf 'PASS target dedup, no-ping ICMP retention, ipinfo empty-country fallback, Fake-IP filter\n'

# 断言 1：全程零 TCP 探测（noping-split.test 拿到干净 ICMP 首跳后未浪费 TCP）
tcp_calls=$(grep -c -- ' -T ' "$work/logs/mtr.log" || true)
[[ "$tcp_calls" -eq 0 ]] || { printf 'FAIL expected 0 TCP calls, got %s\n' "$tcp_calls" >&2; exit 1; }

# 断言 2：12 个域名仅有 6 个独立目标 IP（+ 1 个 reference.test）：
#   baseline(2) + 6 unique probes + 3 repeats (.12, .13, .15) = 11 次 mtr（未去重至少 18+ 次）
mtr_calls=$(wc -l < "$work/logs/mtr.log" | tr -d ' ')
[[ "$mtr_calls" -eq 11 ]] || { printf 'FAIL expected 11 deduplicated mtr calls, got %s\n' "$mtr_calls" >&2; cat "$work/logs/mtr.log" >&2; exit 1; }

# 断言 3：失败的 198.51.100.3 即使被 3 个域名共用，负缓存保证 3 个 API 仅各打 1 次（总计 3 次而非 9+ 次）
fail_geo_calls=$(grep -c '198.51.100.3' "$work/logs/geoip.log" || true)
[[ "$fail_geo_calls" -eq 3 ]] || { printf 'FAIL expected 3 geoip calls for failing IP, got %s\n' "$fail_geo_calls" >&2; exit 1; }

# 断言 4：成功的 198.51.100.1 和 198.51.100.99 各自仅打 1 次外部 API（父进程 IP_CACHE 真正生效）
ok_geo_calls=$(grep -c '198.51.100.99' "$work/logs/geoip.log" || true)
[[ "$ok_geo_calls" -eq 1 ]] || { printf 'FAIL expected 1 geoip call for transit IP, got %s\n' "$ok_geo_calls" >&2; exit 1; }
printf 'PASS zero TCP waste (%s), dedup mtr calls (%s), in-memory positive & negative IP_CACHE\n' "$tcp_calls" "$mtr_calls"

# 测试 B：--first-hop-only 模式（验证 -m 8 生效且完全跳过沿途 198.51.100.99 反查）
: > "$work/logs/mtr.log"
: > "$work/logs/geoip.log"
EGRESS_CACHE="$work/cache-b" bash "$fast_script" -4 --first-hop-only -j 8 --rules "$work/rules.csv" --json > "$work/out-b.json"
grep -Fq -- ' -m 8 ' "$work/logs/mtr.log"
transit_calls=$(grep -c '198.51.100.99' "$work/logs/geoip.log" || true)
[[ "$transit_calls" -eq 0 ]] || { printf 'FAIL expected 0 transit lookups in --first-hop-only, got %s\n' "$transit_calls" >&2; exit 1; }
jq -e 'all(.ipv4.results[]; .path_asn_chain == null)' "$work/out-b.json" >/dev/null
printf 'PASS --first-hop-only (-m 8 and skips intermediate path ASN lookups)\n'
