# 台湾 TOP 1000 分流检查

在 `egress-check` 目录下，用原版已有的 `--rules` 参数加载随附名单。

```bash
bash ip.sh --rules ./tw-top1000.csv
```

也可以在存有这份 CSV 的目录直接运行上游脚本。文件路径相对于执行命令时的工作目录。

```bash
bash <(curl -Ls https://raw.githubusercontent.com/AIFansX/egress-check/main/ip.sh) --rules ./tw-top1000.csv
```

`ip.sh` 使用上游 v2.19.6 原文件。无参数时使用原版默认规则。[上游对应提交](https://github.com/AIFansX/egress-check/blob/7b4854073dc88bebfa50f68691845341009a8cb1/ip.sh) · [MIT 许可证](LICENSE)

## TCSCloud SeedNet

- [TW Top 1000 分流与待判定报告](tcscloud-tw-top1000-review.txt)

| 妙妙屋分组 | 自维护规则 | 条数 |
| --- | --- | --- |
| 💬 Line 服务 | [MRS](../mmw/ruleset/line-tcscloud-seednet-avoid.mrs) · [源清单](../mmw/ruleset/line-tcscloud-seednet-avoid.list) | 1 |
| 🛍️ Shopee 服务 | [MRS](../mmw/ruleset/shopee-tcscloud-seednet-avoid.mrs) · [源清单](../mmw/ruleset/shopee-tcscloud-seednet-avoid.list) | 10 |
| 🔀 SeedNet 绕行 | [MRS](../mmw/ruleset/category-tcscloud-seednet-avoid.mrs) · [源清单](../mmw/ruleset/category-tcscloud-seednet-avoid.list) | 11 |

`💬 Line 服务` 和 `🛍️ Shopee 服务` 同时加载各自的上游 MRS。`♾️ Meta 服务` 和 `🟣 Yahoo 服务` 使用各自的上游规则。同步[妙妙屋分组清单](../mmw/proxy_groups/proxy_groups.json)后，可分别为各组选择出口。

## 名单格式

`tw-top1000.csv` 保留 `NetAPI_Rank_TW` 和 `Domain` 两个数据列，在首列增加 `EgressRule`。以下是表头和第一条记录。

```csv
EgressRule,NetAPI_Rank_TW,Domain
TW|google.com|,1,google.com
```

CSV 工具按逗号取列。原版脚本按竖线读取分类 `TW` 和域名 `google.com`，后面的逗号列落入它的保留字段。更新名单时，首列的域名须与 `Domain` 列相同。

数据取自 NetAPI 于 2026-11-21 更新的台湾地区热门网站榜单，共 1,000 个域名，按原排名排列。[台湾地区榜单](https://netapi.com/top-websites/tw/) · [NetAPI](https://netapi.com/) · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
