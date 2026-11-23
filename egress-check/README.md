# 台湾 TOP 1000 分流检查

在 `egress-check` 目录下，用 `--rules` 加载随附名单。

```bash
bash ip.sh --rules ./tw-top1000.csv
```

也可以在存有这份 CSV 的目录直接运行本仓库的脚本。文件路径相对于执行命令时的工作目录。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tgr989/mmw-profile/refs/heads/main/egress-check/ip.sh) --rules ./tw-top1000.csv
```

`ip.sh` 基于上游 v2.19.6。本仓版本通过临时文件合并 IPv4 和 IPv6 的报告，支持保存整份 Top 1000 结果。无参数时使用脚本内置规则。[上游对应提交](https://github.com/AIFansX/egress-check/blob/7b4854073dc88bebfa50f68691845341009a8cb1/ip.sh) · [MIT 许可证](LICENSE)

默认的 `EGRESS_BASE_MODE=auto` 会分别选择 IPv4 和 IPv6 的路径比较基准。已取得公网 IP 但查不到其 ASN，或该 ASN 与稳定的 MTR 首跳 ASN 不同时，脚本采用复测确认的 MTR 首跳 ASN。两者均未知时，结果标为无法判定。

`--json` 输出和缓存 `last.json` 中的 `ipv4`、`ipv6` 各自记录 `baseline_asn`（例如 `AS64510`）和 `baseline_source`。`http_echo` 表示 HTTP 回显 IP 所属的 ASN，`mtr` 表示参考域名经复测稳定的首个可见公网跳的 ASN。基准未知或该协议跳过探测时，两项均为 `null`。

每个域名的 `split` 表示可见首跳 ASN 与本轮基准的比较结果。`true` 表示差异已复测，`false` 表示 ASN 一致，`null` 表示证据不足。汇总字段 `split_routing_detected` 在至少一个域名有复测差异时为 `true`，全部匹配时为 `false`，其余情况为 `null`。确认目标服务实际看到的出口 IP 需要该服务的回显或日志。

## TCSCloud SeedNet

- [TW Top 1000 分流与待判定报告](tcscloud-tw-top1000-review.txt)
- [全球 Top 2000 A/B 报告](tcscloud-global-top2000-review.txt)
- [全球第 2001–7000 名 A/B 报告](tcscloud-global-top2001-7000-review.txt)

| 妙妙屋分组 | 自维护规则 | 条数 |
| --- | --- | --- |
| Meta 服务 | [MRS](../mmw/ruleset/tcscloud-seednet/meta-tcscloud-seednet-avoid.mrs) · [源清单](../mmw/ruleset/tcscloud-seednet/meta-tcscloud-seednet-avoid.list) | 1 |
| Line 服务 | [MRS](../mmw/ruleset/tcscloud-seednet/line-tcscloud-seednet-avoid.mrs) · [源清单](../mmw/ruleset/tcscloud-seednet/line-tcscloud-seednet-avoid.list) | 1 |
| Shopee 服务 | [MRS](../mmw/ruleset/tcscloud-seednet/shopee-tcscloud-seednet-avoid.mrs) · [源清单](../mmw/ruleset/tcscloud-seednet/shopee-tcscloud-seednet-avoid.list) | 11 |
| TCSCloud 分流 | [MRS](../mmw/ruleset/tcscloud-seednet/category-tcscloud-seednet-avoid.mrs) · [源清单](../mmw/ruleset/tcscloud-seednet/category-tcscloud-seednet-avoid.list) | 11 |

`Meta 服务`、`Line 服务` 和 `Shopee 服务` 各加载上游 MRS 和表中的自维护 MRS。`Yahoo 服务` 使用上游规则。同步[妙妙屋分组清单](../mmw/proxy_groups/proxy_groups.json)后，可分别为各组选择出口。

## 名单格式

`tw-top1000.csv`、`global-top2000-no-cn.csv` 和 `global-top2001-7000-no-cn.csv` 均在首列提供 `EgressRule`，可直接通过 `--rules` 加载。其中 `tw-top1000.csv` 保留 `NetAPI_Rank_TW` 和 `Domain` 两个数据列，以下是表头和第一条记录。

```csv
EgressRule,NetAPI_Rank_TW,Domain
TW|google.com|,1,google.com
```

CSV 工具按逗号取列。检测脚本按竖线读取分类 `TW` 和域名 `google.com`，后面的逗号列落入它的保留字段。更新名单时，首列的域名须与 `Domain` 列相同。

数据取自 NetAPI 于 2026-11-21 更新的台湾地区热门网站榜单，共 1,000 个域名，按原排名排列。[台湾地区榜单](https://netapi.com/top-websites/tw/) · [NetAPI](https://netapi.com/) · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
