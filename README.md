# AIprofile
AI-generated profile

妙妙屋使用的分组清单位于 [proxy_groups/proxy_groups.json](proxy_groups/proxy_groups.json)，本仓库维护的规则集位于 [ruleset](ruleset/)。

图标统一使用单个 emoji；同一分组的 `emoji`、`icon` 与 `group_label` 前缀保持一致。同类服务共用图标，例如 Wi-Fi Calling 使用 📶，ESET 安全服务使用 🛡️，更新使用 ⬆️。

新增分组均加入 `comprehensive` 预设，也可以单独勾选：

| 分组 | 匹配内容 | 出口选择 |
| --- | --- | --- |
| TMO-WFC | T-Mobile Wi-Fi Calling 域名与 IP 网段 | 按需选择 |
| GG-WFC | giffgaff / O2 Wi-Fi Calling 域名与 IP 网段 | 按需选择 |
| ESET CN | `cn.eset.com` 及其子域名 | `DIRECT` |
| ESET UP | 更新、下载与仓库域名 | `🚀 节点选择` |
| ESET | MetaCubeX ESET 域名规则集 | `DIRECT` |
| 📍 苹果定位服务 | `gspe1-ssl.ls.apple.com` 及其子域名 | 按需选择，独立于 GG-WFC |

妙妙屋当前生成器为这些普通分组默认选择 `🚀 节点选择`，分组清单不能指定默认出口。生成后需在客户端将 **ESET CN** 和 **ESET** 设为 `DIRECT`，以保持原规则的直连意图。

本仓库维护的域名规则使用 `classical` YAML，保留精确匹配、后缀匹配和正则匹配。ESET 通用分组使用 MetaCubeX 的 `domain` / `mrs` 规则集。IP 规则通过 `ip_rules` 引用，生成器会在对应的 `RULE-SET` 后添加 `no-resolve`。

Apple Music 使用 MetaCubeX 的 `geo/geosite/apple-music.mrs`，通用代理使用 `geo-lite/geosite/proxy.mrs`。代理媒体的同名 MRS 当前为空，改用其上游 blackmatrix7 的 `GlobalMedia_Domain.yaml`，对应 `behavior: domain`、`format: yaml` 和 `./ruleset/proxymedia.yaml` 缓存路径。PT 站点的源文件包含带类型前缀的规则，使用 `behavior: classical`。

PT Tracker 使用 MetaCubeX 的 `geo/geosite/tracker.mrs`（`behavior: domain`、`format: mrs`），缓存路径为 `./ruleset/pttracker.mrs`，按实际域名匹配，不再将 URL 参数或 BT 协议字段作为域名关键词。该源也包含部分 PT 站点后缀，因此 PT 站点分组优先；同一域名上的网页与 Tracker 请求无法仅靠域名规则区分。

代理媒体另通过 `ip_rules` 引用同目录的 `GlobalMedia.yaml`（`behavior: classical`），补充 IPv4/IPv6、关键词和进程规则，缓存路径为 `./ruleset/proxymedia-ip.yaml`；生成器会在对应的 `RULE-SET` 后添加 `no-resolve`。

发布时将 `proxy_groups/proxy_groups.json` 与 `ruleset/` 一起推送到 GitHub 的 `main` 分支，再让妙妙屋重新同步分组清单并生成或更新订阅。妙妙屋的分组清单源地址需使用新的 `proxy_groups/proxy_groups.json` 路径。所有规则集下载地址统一添加 `https://gh-proxy.com/` 前缀，包括本仓库维护的规则集和 MetaCubeX 的 ESET 通用规则集。

分组顺序保持 **AI 服务 → 云服务**，云服务包含 Cloudflare 和 hCaptcha 等规则。规则顺序需保持 **苹果定位服务紧邻苹果服务之前**，以及 **ESET CN → ESET UP → ESET 在通用规则之前**。本清单已按此顺序排列；手动勾选分组或编辑已有订阅时，还需核对最终配置中的顺序，避免被较宽泛的规则提前匹配。

PT 相关顺序为 **PT 站点 → PT Tracker → 国内服务**，使独立的 PT 出口优先于国内通用规则。尾部按 **E-Hentai → 代理媒体 → 代理服务 → 非中国** 排列，让专用分组先于通用代理规则匹配。
