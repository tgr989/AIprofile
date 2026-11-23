#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/bin"
printf 'Test|same.test|\nTest|different.test|\n' > "$work/rules"

# 所有 HTTP、DNS 和 MTR 调用使用文档示例地址和固定响应。
cat > "$work/bin/curl" <<'MOCK'
#!/usr/bin/env bash
case "${!#}" in
    https://ipinfo.io/*/json)
        case "${!#}" in
            */192.0.2.1/json) asn="$TEST_HTTP_ASN" ;;
            */2001:db8::1/json) asn="${TEST_HTTP6_ASN-$TEST_HTTP_ASN}" ;;
            */198.51.100.2/json|*/2001:db8:1::2/json) asn=64520 ;;
            *) asn=64510 ;;
        esac
        [[ -n "$asn" ]] || exit 1
        printf '{"country":"US","org":"AS%s Test ISP"}\n' "$asn" ;;
    https://api.ip.sb/geoip/*|https://ipwho.is/*) exit 1 ;;
    *) case " $* " in *" -6 "*) echo '2001:db8::1' ;; *) echo '192.0.2.1' ;; esac ;;
esac
MOCK

cat > "$work/bin/getent" <<'MOCK'
#!/usr/bin/env bash
case "$2" in reference.test) host=10 ;; same.test) host=11 ;; different.test) host=12 ;; *) exit 1 ;; esac
case "$1" in ahostsv6) echo "2001:db8:2::$host STREAM" ;; *) echo "203.0.113.$host STREAM" ;; esac
MOCK

cat > "$work/bin/mtr" <<'MOCK'
#!/usr/bin/env bash
target="${!#}"
case "$1" in
    -6) prefix='2001:db8:1::'; base="${TEST_MTR6_BASE:-$TEST_MTR_BASE}" ;;
    *)  prefix='198.51.100.'; base="$TEST_MTR_BASE" ;;
esac
case "$target" in *.12|*::12) hop=2 ;; *) hop=1 ;; esac
row() { printf '%s. %s 0.0%% 3 1.0 1.0 1.0 1.0 0.0\n' "$1" "$2"; }
if [[ "$base" == hidden && ( "$target" == *.10 || "$target" == *::10 ) ]]; then
    row 1 "$target"
else
    row 1 "$prefix$hop"
    row 2 "$target"
fi
MOCK
printf '#!/bin/sh\nexit 1\n' > "$work/bin/nslookup"
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH" MTR_BASE_DOMAIN=reference.test MTR_ATTEMPTS=1

check() {
    local mode="$1" http_asn="$2" mtr_base="$3" same="$4" different="$5"
    local expected_asn="${6:+AS$6}" expected_source="$7"
    local cache="$work/cache-$mode-$http_asn-$mtr_base"
    EGRESS_BASE_MODE="$mode" TEST_HTTP_ASN="$http_asn" TEST_MTR_BASE="$mtr_base" EGRESS_CACHE="$cache" \
        bash "$project_dir/egress-check/ip.sh" --rules "$work/rules" --json > "$work/output.json"
    cmp "$work/output.json" "$cache/last.json"
    jq -e --argjson same "$same" --argjson different "$different" --arg asn "$expected_asn" --arg source "$expected_source" '
        def nullable: if . == "" then null else . end;
        all((.ipv4, .ipv6);
            .available and .summary.ok == 2 and
            has("baseline_asn") and .baseline_asn == ($asn | nullable) and
            has("baseline_source") and .baseline_source == ($source | nullable) and
            ([.results[] | {key: .domain, value: .split}] | from_entries) ==
                {"same.test": $same, "different.test": $different})
    ' "$work/output.json" >/dev/null
    printf 'PASS %s HTTP=%s MTR=%s\n' "$mode" "${http_asn:-unknown}" "$mtr_base"
}

# 两个目标的首跳分别为 AS64510 和 AS64520，稳定的 MTR 基准为 AS64510。
check auto ''    stable false true  64510 mtr
check auto 64520 stable false true  64510 mtr
check auto 64510 stable false true  64510 http_echo
check auto 64510 hidden false null  64510 http_echo
check auto ''    hidden null  null  ''    ''
check echo ''    stable null  null  ''    ''
check echo 64520 stable true  false 64520 http_echo
check mtr  ''    stable false true  64510 mtr
check mtr  64510 stable false true  64510 mtr
check mtr  64510 hidden false null  64510 http_echo

export EGRESS_BASE_MODE=auto TEST_HTTP_ASN='' TEST_MTR_BASE=stable
TEST_HTTP6_ASN=64520 TEST_MTR6_BASE=hidden EGRESS_CACHE="$work/mixed" \
    bash "$project_dir/egress-check/ip.sh" --rules "$work/rules" --json > "$work/mixed.json"
jq -e '[.ipv4, .ipv6] | map([.baseline_asn,.baseline_source]) ==
    [["AS64510","mtr"],["AS64520","http_echo"]]' "$work/mixed.json" >/dev/null
printf 'PASS independent IPv4/IPv6 baselines\n'

for format in --no-color --compact; do
    EGRESS_CACHE="$work/text" bash "$project_dir/egress-check/ip.sh" -4 "$format" --rules "$work/rules" > "$work/report"
    grep -Fq '比较基准  稳定 MTR 首跳 AS64510' "$work/report"
    grep -Fq '⮜ 首跳 ASN 差异已复测' "$work/report"
    grep -Fq '复测确认 1 个域名的可见首跳 ASN 与基准不同' "$work/report"
done
jq -e '.ipv6 | .available == false and has("baseline_asn") and has("baseline_source")
    and .baseline_asn == null and .baseline_source == null' "$work/text/last.json" >/dev/null
printf 'Test|same.test|\n' > "$work/one-rule"
EGRESS_CACHE="$work/text" bash "$project_dir/egress-check/ip.sh" -4 --rules "$work/one-rule" > "$work/report"
grep -Fq '所有已测域名的可见首跳 ASN 均与基准 AS64510 一致' "$work/report"
printf 'PASS matched and differing hops in terminal reports; skipped family has no baseline\n'
