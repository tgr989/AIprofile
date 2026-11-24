# 台湾 TOP 1000 分流检查

在 `egress-check` 目录下，用 `--rules` 加载随附名单。

```bash
bash ip.sh --rules ./tw-top1000.csv
```

也可以在存有这份 CSV 的目录直接运行本仓库的脚本。文件路径相对于执行命令时的工作目录。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tgr989/mmw-profile/refs/heads/main/egress-check/ip.sh) --rules ./tw-top1000.csv
```

`ip.sh` 基于上游 v2.19.6，保留与上游的最小差异。本仓版本通过临时文件合并 IPv4 和 IPv6 的报告，支持保存整份 Top 1000 结果。无参数时使用脚本内置规则。[上游对应提交](https://github.com/AIFansX/egress-check/blob/7b4854073dc88bebfa50f68691845341009a8cb1/ip.sh) · [MIT 许可证](LICENSE)

## 大名单高速版 `ip-fast.sh`

跑 `tw-top1000.csv`、`global-top2000-no-cn.csv` 或 `global-top2001-7000-no-cn.csv` 等千/万级名单时，推荐使用独立重构的 `ip-fast.sh`。它保持与 `ip.sh` 一致的命令行选项、比较基线语义和 JSON 输出结构，并针对大名单做了多项性能与准确性优化：

```bash
# 仅测首跳分流（推荐用于 1,000–5,000 域名大名单）：限制 max-ttl=8、跳过沿途多跳 ASN 反查、24 并发
bash ip-fast.sh -4 --first-hop-only -j 24 --rules ./tw-top1000.csv

# 远程直接运行
bash <(curl -fsSL https://raw.githubusercontent.com/tgr989/mmw-profile/refs/heads/main/egress-check/ip-fast.sh) -4 --first-hop-only -j 24 --rules ./tw-top1000.csv
```

主要改动与新增参数：

- **规则解析与输出批量化**：单次 `awk` 解析规则、纯 Bash 格式化延迟、单次 `jq -R -s` 批量生成 JSON，消除每行/每域名进程 fork 风暴。
- **并行探测与去重**：并行探测默认/IPv4/IPv6 出口；组内并发 DNS 预解析并按目标 IP 去重（共享同一 VIP 的域名仅执行一次 MTR）；使用 Bash 4.3+ `wait -n` 事件驱动回收并发槽位并移除进度条 `stat` 轮询。
- **首跳协议保真与真内存缓存**：目标禁 Ping 但已取得基准协议干净首跳时立即返回，不再补发异协议 MTR 覆盖证据；修复 `IP_CACHE` 在子 Shell 失效与 `ipinfo.io` 缺 `country` 字段错位问题，并支持并发批量 ASN 预取与运行期负缓存。
- **新增选项与环境变量**：`-j, --concurrency N`（默认 `16`）、`--max-ttl N`、`--first-hop-only`（等价 `--max-ttl 8 --no-path-lookup`）、`--no-path-lookup`，以及 `DNS_CONCURRENCY`（默认 `32`）、`LOOKUP_CONCURRENCY`（默认 `8`）、`MTR_REPEAT_CONCURRENCY`（默认 `4`）、`MTR_INTERVAL`（可选，传给 `mtr -i`）。

默认的 `EGRESS_BASE_MODE=auto` 会分别选择 IPv4 和 IPv6 的路径比较基准。已取得公网 IP 但查不到其 ASN，或该 ASN 与稳定的 MTR 首跳 ASN 不同时，脚本采用复测确认的 MTR 首跳 ASN。两者均未知时，结果标为无法判定。

`--json` 输出和缓存 `last.json` 中的 `ipv4`、`ipv6` 各自记录 `baseline_asn`（例如 `AS64510`）和 `baseline_source`。`http_echo` 表示 HTTP 回显 IP 所属的 ASN，`mtr` 表示参考域名经复测稳定的首个可见公网跳的 ASN。基准未知或该协议跳过探测时，两项均为 `null`。

每个域名的 `split` 表示可见首跳 ASN 与本轮基准的比较结果。`true` 表示差异已复测，`false` 表示 ASN 一致，`null` 表示证据不足。汇总字段 `split_routing_detected` 在至少一个域名有复测差异时为 `true`，全部匹配时为 `false`，其余情况为 `null`。确认目标服务实际看到的出口 IP 需要该服务的回显或日志。

## TCSCloud SeedNet

- [TW Top 1000 分流与待判定报告](tcscloud-tw-top1000-review.txt)
- [全球 Top 2000 A/B 报告](tcscloud-global-top2000-review.txt)
- [全球第 2001–7000 名 A/B 报告](tcscloud-global-top2001-7000-review.txt)

| 妙妙屋分组 | 自维护规则 | 条数 |
| --- | --- | --- |
| Meta 服务 | [MRS](../mmw/ruleset/meta/domain-meta.mrs) · [源清单](../mmw/ruleset/meta/domain-meta.list)（含 `+.instagr.am`） | 17 |
| Line 服务 | [MRS](../mmw/ruleset/line/domain-line.mrs) · [源清单](../mmw/ruleset/line/domain-line.list) | 1 |
| Shopee 服务 | [MRS](../mmw/ruleset/shopee/domain-shopee.mrs) · [源清单](../mmw/ruleset/shopee/domain-shopee.list) | 11 |
| TCSCloud Avoid | [域名 MRS](../mmw/ruleset/tcscloud/category-tcscloud-seednet-avoid.mrs) · [域名清单](../mmw/ruleset/tcscloud/category-tcscloud-seednet-avoid.list) · [ASN 清单](../mmw/ruleset/tcscloud/asn-tcscloud-seednet-avoid.yaml) | 16 条域名规则、26 条 ASN 规则 |

`Meta 服务`、`Line 服务` 和 `Shopee 服务` 各加载上游 MRS 和表中的自维护 MRS。`Yahoo 服务` 使用上游规则。同步[妙妙屋分组清单](../mmw/proxy_groups/proxy_groups.json)后，可分别为各组选择出口。

`TCSCloud Avoid` 的 ASN 清单收录 Meta、LINE、Shopee 和 Yahoo 已观察到路由公告的自有网络。Mihomo 使用客户端的 `ASN.mmdb` 匹配目标 IP，规则带 `no-resolve`。

## 名单格式

`tw-top1000.csv`、`global-top2000-no-cn.csv` 和 `global-top2001-7000-no-cn.csv` 均在首列提供 `EgressRule`，可直接通过 `--rules` 加载。其中 `tw-top1000.csv` 保留 `NetAPI_Rank_TW` 和 `Domain` 两个数据列，以下是表头和第一条记录。

```csv
EgressRule,NetAPI_Rank_TW,Domain
TW|google.com|,1,google.com
```

CSV 工具按逗号取列。检测脚本按竖线读取分类 `TW` 和域名 `google.com`，后面的逗号列落入它的保留字段。更新名单时，首列的域名须与 `Domain` 列相同。

数据取自 NetAPI 于 2026-11-21 更新的台湾地区热门网站榜单，共 1,000 个域名，按原排名排列。[台湾地区榜单](https://netapi.com/top-websites/tw/) · [NetAPI](https://netapi.com/) · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
