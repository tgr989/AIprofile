# AIprofile
AI-generated profile

妙妙屋使用的分组清单位于 [proxy_groups/proxy_groups.json](proxy_groups/proxy_groups.json)，本仓库维护的规则集位于 [ruleset](ruleset/)。

图标统一使用单个 emoji；同一分组的 `emoji`、`icon` 与 `group_label` 前缀保持一致。同类服务共用图标，例如 Wi-Fi Calling 使用 📶，ESET 安全服务使用 🛡️。

新增分组均加入 `comprehensive` 预设，也可以单独勾选：

| 分组 | 匹配内容 | 出口选择 |
| --- | --- | --- |
| TMO-WFC | T-Mobile Wi-Fi Calling 域名与 IP 网段 | 按需选择 |
| GG-WFC | giffgaff / O2 Wi-Fi Calling 域名与 IP 网段 | 按需选择 |
| ESET | 中国服务、更新下载、激活与云服务的域名/IP | 中国大陆网络选择 `DIRECT`；境外按需选择中国大陆出口 |
| 📍 苹果定位服务 | `gspe1-ssl.ls.apple.com` 及其子域名 | 按需选择，独立于 GG-WFC |

妙妙屋当前生成器为这些普通分组默认选择 `🚀 节点选择`，分组清单不能指定默认出口。生成后需在客户端为 **ESET** 选择统一出口：中国大陆网络使用 `DIRECT`；境外需要中国出口时选择中国大陆节点。`DIRECT` 使用设备当前网络，并不自动获得中国 IP。

本仓库维护的域名规则使用 `classical` YAML，保留精确匹配、后缀匹配和正则匹配。ESET 仅保留一个策略组，统一引用 MetaCubeX 的 `domain` / `mrs` 规则集，以及本地 `eset-cn.yaml`、`eset-up.yaml`、`eset-extra.yaml`；后者补充上游尚未收录的 ESET PROTECT 文件上传域名。IP 规则通过 `ip_rules` 引用，生成器会在对应的 `RULE-SET` 后添加 `no-resolve`。

ESET 本地规则按 [官方 KB332 服务清单](https://support.eset.com/en/kb332-ports-and-addresses-required-to-use-your-eset-product-with-a-third-party-firewall) 于 **2026-11-14** 核对。`eset-cn-ip.yaml`、`eset-up-ip.yaml`、`eset-ip.yaml` 按用途维护中国服务、更新下载、其余业务的精确 IPv4/IPv6 地址，全部归入同一个 **ESET** 策略组。更新域名包括欧美区域入口及官方仓库别名；其他规则涵盖激活、LiveGrid、LiveGuard、PROTECT、Inspect、反垃圾、样本提交等服务。[ESET Connect](https://help.eset.com/eset_connect/en-US/prerequisites.html) 的 API 域名已由上游 `eset.systems` 后缀覆盖。

IP 规则只收录官方列出的客户端出站服务地址，采用 `/32` 或 `/128`，不扩大到整个云厂商网段。`20.224.75.204` 和 `91.228.166.154` 同时用于下载和其他服务，记录在 `eset-ip.yaml` 中，与所有 ESET 域名规则使用同一出口。共享的 Microsoft OAuth 登录、第三方 OCSP，以及入站邮件、Syslog 的源地址不纳入 ESET 专用规则。本地 IP 清单是上述日期的快照，后续需依据官方清单和[变更记录](https://support.eset.com/en/kb8900-changelog-for-kb332)更新。

Apple Music 使用 MetaCubeX 的 `geo/geosite/apple-music.mrs`，通用代理使用 `geo-lite/geosite/proxy.mrs`。代理媒体的同名 MRS 当前为空，改用其上游 blackmatrix7 的 `GlobalMedia_Domain.yaml`，对应 `behavior: domain`、`format: yaml` 和 `./ruleset/proxymedia.yaml` 缓存路径。PT 站点的源文件包含带类型前缀的规则，使用 `behavior: classical`。

PT Tracker 使用 MetaCubeX 的 `geo/geosite/tracker.mrs`（`behavior: domain`、`format: mrs`），缓存路径为 `./ruleset/pttracker.mrs`，按实际域名匹配，不再将 URL 参数或 BT 协议字段作为域名关键词。该源也包含部分 PT 站点后缀，因此 PT 站点分组优先；同一域名上的网页与 Tracker 请求无法仅靠域名规则区分。

代理媒体另通过 `ip_rules` 引用同目录的 `GlobalMedia.yaml`（`behavior: classical`），补充 IPv4/IPv6、关键词和进程规则，缓存路径为 `./ruleset/proxymedia-ip.yaml`；生成器会在对应的 `RULE-SET` 后添加 `no-resolve`。

发布时将 `proxy_groups/proxy_groups.json` 与 `ruleset/` 一起推送到 GitHub 的 `main` 分支，再让妙妙屋重新同步分组清单并生成或更新订阅。妙妙屋的分组清单源地址需使用新的 `proxy_groups/proxy_groups.json` 路径。所有规则集下载地址统一添加 `https://gh-proxy.com/` 前缀，包括本仓库维护的规则集和 MetaCubeX 的 ESET 通用规则集。

分组按功能归类排列。开头为 **私有网络 → 广告拦截 → TMO-WFC → GG-WFC**，随后为 **PT 站点 → PT Tracker → AI 服务 → 云服务 → 国内服务 → ESET**；国内服务与 ESET 紧接云服务之后。

保留 **AI 服务 → 云服务**、**苹果定位紧邻苹果服务之前**、**油管视频 → 谷歌服务**的相对顺序。代理媒体、代理服务、非中国三个通用分组放在末尾。手动勾选分组或编辑已有订阅时，还需核对最终配置中的顺序。
