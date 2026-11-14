# AIprofile
AI-generated profile

妙妙屋使用的分组清单位于 [proxy_groups/proxy_groups.json](proxy_groups/proxy_groups.json)，本仓库维护的规则集位于 [ruleset](ruleset/)。

图标统一使用单个 emoji；同一分组的 `emoji`、`icon` 与 `group_label` 前缀保持一致。同类服务共用图标，例如 Wi-Fi Calling 使用 📶，ESET 安全服务使用 🛡️。

新增分组均加入 `comprehensive` 预设，也可以单独勾选：

| 分组 | 匹配内容 | 出口选择 |
| --- | --- | --- |
| TMO-WFC | T-Mobile Wi-Fi Calling 域名与 IP 网段 | 按需选择 |
| GG-WFC | giffgaff / O2 Wi-Fi Calling 域名与 IP 网段 | 按需选择 |
| ESET | MetaCubeX ESET 域名规则集（当前仅使用 MRS） | 中国大陆网络选择 `DIRECT`；境外按需选择中国大陆出口 |
| 📍 苹果定位服务 | `gspe1-ssl.ls.apple.com` 及其子域名 | 按需选择，独立于 GG-WFC |

妙妙屋当前生成器为这些普通分组默认选择 `🚀 节点选择`，分组清单不能指定默认出口。生成后需在客户端为 **ESET** 选择统一出口：中国大陆网络使用 `DIRECT`；境外需要中国出口时选择中国大陆节点。`DIRECT` 使用设备当前网络，并不自动获得中国 IP。

本仓库维护的域名规则使用 `classical` YAML，保留精确匹配、后缀匹配和正则匹配。ESET 当前仅引用 MetaCubeX 的 `geo/geosite/eset.mrs`（`behavior: domain`、`format: mrs`），`ip_rules` 为空；实际启用的覆盖范围以上游 MRS 为准。

ESET 自维护规则已整合为两份备用文件，**当前均未挂载到 ESET 分组**：

| 文件 | 内容 | 恢复引用时的类型 |
| --- | --- | --- |
| [eset-domain.yaml](ruleset/eset-domain.yaml) | 26 条域名规则：原中国服务、更新仓库及企业云补充规则 | `site_rules`，`behavior: classical`、`format: yaml` |
| [eset-ip.yaml](ruleset/eset-ip.yaml) | 436 条精确 IP 规则，其中 19 条 IPv6 | `ip_rules`，`behavior: ipcidr`、`format: yaml` |

两份备用文件保留整合前的全部条目，旧的分类文件已移除。内容按 [官方 KB332 服务清单](https://support.eset.com/en/kb332-ports-and-addresses-required-to-use-your-eset-product-with-a-third-party-firewall) 于 **2026-11-14** 核对，包括中国服务、更新下载、激活、LiveGrid、LiveGuard、PROTECT、Inspect、反垃圾和样本提交等地址。若以后启用 IP 规则，生成器会在对应的 `RULE-SET` 后添加 `no-resolve`。[ESET Connect](https://help.eset.com/eset_connect/en-US/prerequisites.html) 的 API 域名已由上游 `eset.systems` 后缀覆盖。

备用 IP 规则只收录官方列出的客户端出站服务地址，采用 `/32` 或 `/128`，不扩大到整个云厂商网段。共享的 Microsoft OAuth 登录、第三方 OCSP，以及入站邮件、Syslog 的源地址不纳入 ESET 专用规则。本地清单是上述日期的快照，后续需依据官方清单和[变更记录](https://support.eset.com/en/kb8900-changelog-for-kb332)更新。

Apple Music 使用 MetaCubeX 的 `geo/geosite/apple-music.mrs`，通用代理使用 `geo-lite/geosite/proxy.mrs`。代理媒体的同名 MRS 当前为空，改用其上游 blackmatrix7 的 `GlobalMedia_Domain.yaml`，对应 `behavior: domain`、`format: yaml` 和 `./ruleset/proxymedia.yaml` 缓存路径。PT 站点的源文件包含带类型前缀的规则，使用 `behavior: classical`。

PT Tracker 使用 MetaCubeX 的 `geo/geosite/tracker.mrs`（`behavior: domain`、`format: mrs`），缓存路径为 `./ruleset/pttracker.mrs`，按实际域名匹配，不再将 URL 参数或 BT 协议字段作为域名关键词。该源也包含部分 PT 站点后缀，因此 PT 站点分组优先；同一域名上的网页与 Tracker 请求无法仅靠域名规则区分。

代理媒体另通过 `ip_rules` 引用同目录的 `GlobalMedia.yaml`（`behavior: classical`），补充 IPv4/IPv6、关键词和进程规则，缓存路径为 `./ruleset/proxymedia-ip.yaml`；生成器会在对应的 `RULE-SET` 后添加 `no-resolve`。

发布时将 `proxy_groups/proxy_groups.json` 与 `ruleset/` 一起推送到 GitHub 的 `main` 分支，再让妙妙屋重新同步分组清单并生成或更新订阅。妙妙屋的分组清单源地址需使用新的 `proxy_groups/proxy_groups.json` 路径。所有规则集下载 URL 均使用 GitHub 或 raw.githubusercontent.com 的原始地址，不附加第三方代理前缀。

分组顺序以[妙妙屋官方默认清单](https://github.com/iluobei/miaomiaowu/blob/main/configs/proxy-groups-lite.json)为基准，保留其中 24 个现有分组的相对顺序，将本仓库额外的 8 个分组插入相应位置。

新增服务所在区段为 **私有网络 → TMO-WFC → GG-WFC → PT 站点 → PT Tracker → ESET → 国内服务**。两个 Wi-Fi Calling 分组紧随私有网络；PT 站点先于 PT Tracker，两者均先于国内服务；ESET 紧邻国内服务之前，也先于云服务。

其他额外分组按 **苹果定位 → 苹果服务**、**金融服务 → 数字货币 → 云服务 → Tiktok → Spotify** 插入。手动勾选分组或编辑已有订阅时，还需核对最终配置中的顺序。
