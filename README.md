# AIprofile
AI-generated profile

妙妙屋使用的分组清单位于 [proxy_groups/proxy_groups.json](proxy_groups/proxy_groups.json)，本仓库维护的规则集位于 [ruleset](ruleset/)。

图标统一使用单个 emoji；同一分组的 `emoji`、`icon` 与 `group_label` 前缀保持一致。同类服务共用图标，例如 Wi-Fi Calling 使用 📶，ESET 安全服务使用 🛡️。

Claude / Claude Code 分流于 **2026-11-14** 对照 [Net.Coffee 域名清单](https://ip.net.coffee/claude/site.html)、[NodeSeek 原帖《整合了一下claude的分流规则，surge格式》](https://www.nodeseek.com/post-682343-1)（正文更新日期：2026-04-10）和 [Aiip.si 分流说明](https://aiip.si/routing/)核对并按需采用。**保持广告拦截 → AI 服务的原有顺序**。Sentry 等遥测域名若先命中广告拦截，视为已由规则处理，不作为 AI 分流遗漏。

AI 服务保留 `category-ai-!cn`、`openai` 和上游 `claude` 三个规则源，并通过 [claude-domain-extra.yaml](ruleset/claude-domain-extra.yaml) 补充域名、关键词与 GEOSITE 规则，通过 [claude-ip-extra.yaml](ruleset/claude-ip-extra.yaml) 补充 IP 网段，通过 [claude-svc-extra.yaml](ruleset/claude-svc-extra.yaml) 补充 NTP 服务端口规则，并保留已注释的 WebRTC 端口规则。已有等效覆盖的规则不重复添加。

三份补充规则均以 `behavior: classical`、`format: yaml` 挂载在 AI 分组的 `site_rules` 中，按域名、IP、服务端口的顺序排列，保留拆分前的匹配顺序。妙妙屋会把 `ip_rules` 统一排到所有域名规则之后，因此此处保持原位置，确保 NTP 端口规则仍优先于 Google、云服务等后续分组。服务端口文件包含端口与逻辑规则，不能使用仅支持 IP 网段的 `ipcidr` 格式。

进程规则单独保存在 [claude-proc-extra.yaml](ruleset/claude-proc-extra.yaml)，包含此前的 5 条 `PROCESS-NAME` 规则，**当前未在分组清单中引用**。以后启用时使用 `behavior: classical`、`format: yaml`。

| 补充内容 | 作用与来源 |
| --- | --- |
| `statsig.com` | [Claude Code 官方开发容器的网络白名单](https://github.com/anthropics/claude-code/blob/main/.devcontainer/init-firewall.sh)；`statsigapi.net` 后缀无法覆盖 |
| `intercomassets.com` | [Aiip.si 分流说明](https://aiip.si/routing/)中的客服资源，按后缀匹配并交给 AI 服务 |
| `accounts.google.com`、`oauth2.googleapis.com`、`openidconnect.googleapis.com`、`www.googleapis.com` | **精确匹配，全部已注释**；原 Google 登录入口参考 [Aiip.si](https://aiip.si/routing/)，依据 [Google 官方 OpenID Connect 发现文档](https://accounts.google.com/.well-known/openid-configuration)补充令牌、用户信息及验签公钥接口。部分请求由网站后端发起，不一定经过本机代理；`www.googleapis.com` 还承载其他 Google API |
| `accounts.gstatic.com`、`ssl.gstatic.com`、`www.gstatic.com` | **精确匹配，全部已注释**；[Google 官方 ChromeOS 主机白名单](https://support.google.com/chrome/a/answer/6334001?hl=en)列出的账户与静态资源备用主机，后两者明确用于登录页面 JS / CSS；并非 Claude 必需依赖清单 |
| `apis.google.com` | **精确匹配，已注释**；[Google 官方迁移文档](https://developers.google.com/identity/gsi/web/guides/migration)中的旧版 Sign-In 脚本主机，新版 GIS 脚本已改用 `accounts.google.com` |
| `appleid.apple.com`、`idmsa.apple.com`、`appleid.cdn-apple.com` | **精确匹配，全部已注释**；参考 [Sign in with Apple 文档](https://developer.apple.com/documentation/signinwithapple/incorporating-sign-in-with-apple-into-other-platforms)和 [Apple 企业网络主机清单](https://support.apple.com/en-us/101555)，保留授权、账户认证与登录资源备用规则 |
| `maps.googleapis.com`、`withpersona.com`、`frompersona.com` | Net.Coffee 的 KYC 表格列出，但其可复制的 YAML 未包含 |
| `t0.gstatic.com` 至 `t3.gstatic.com`、`storage.googleapis.com` | 补齐 [NodeSeek 原帖](https://www.nodeseek.com/post-682343-1)中的页面资源和 Claude Code 下载域名，优先于 Google 分组匹配 |
| `modelcontextprotocol.com`、`.io`、`.net`、`.org`，以及 `cdn.growthbook.io` | 合并 [jinxinkai/clash-ai-rules 的 Anthropic 清单](https://github.com/jinxinkai/clash-ai-rules/blob/e25782af4ab7afb6ff528fc2a61e22523ff082cb/Anthropic.yaml) 中尚未覆盖的 MCP 与功能开关域名；不代表覆盖任意第三方 MCP 服务器 |
| `sentry`、`claude`、`anthropic` 关键词 | `sentry` 来自 Net.Coffee，`claude` / `anthropic` 兜底参考 [NodeSeek 原帖](https://www.nodeseek.com/post-682343-1)；覆盖包含这些字符串的域名，参考项目的 `anthropic.com.cn` 也由此覆盖 |
| `153.61.224.0/22` | [Anthropic 官方当前 API 入站网段](https://platform.claude.com/docs/en/api/ip-addresses)，补在上游已有 IP 规则之外 |

参考项目的其他 Anthropic 域名、IP 和 ASN 已由现有规则覆盖；其 OpenAI 清单中的 `chatgpt.livekit.cloud`、`host.livekit.cloud`、`turn.livekit.cloud` 也已由 AI 服务中的 `openai` / `category-ai-!cn` 覆盖。本次按 Claude 与实时通信相关范围合并差异，不整体挂载该项目的 Facebook、X 等规则集。

hCaptcha 的 `hcaptcha.mrs` 从云服务移入 AI 服务，随 `balanced` 和 `comprehensive` 预设启用；其他应用使用 hCaptcha 时也按 AI 分组处理。

上游 `claude` 使用 `behavior: classical`，已包含网页列出的核心、CDN、认证、监控、客服域名，以及 IPv4、IPv6 和 ASN 规则；因此 AI 分组的 `ip_rules` 为空并不代表缺少 IP 兜底。现有 `datadog` 关键词已覆盖 `datadoghq` 及 `browser-intake-us5-datadoghq.com` 等变体，`sift` 关键词和 `sentry.io` 后缀也继续保留。更早命中广告拦截的连接仍由广告分组处理。

Google / Apple 登录备用规则于 **2026-11-15** 按官方资料核对，当前全部保持注释，由已启用的各自分组处理。推荐在客户端将 **`🔍 谷歌服务`、`🍏 苹果服务` 与 `🤖 AI 服务` 选择为同一个固定节点，保持出口 IP 一致**；仅选择相同地区或分别使用自动选择，不能保证出口一致。以后按需取消注释时，同域名的其他应用请求也会交给 AI 服务。

已启用的第三方服务和 Google 域名由多个应用共用，其他应用访问相同域名也走 AI 服务；关键词还可能匹配无关站点。

`geosite:anthropic` 的当前条目已由 `category-ai-!cn` 覆盖。`claude-domain-extra` 保留 `GEOSITE,category-ntp`，将该分类内的时间服务器域名交给 AI 服务，需要客户端的 GeoSite 数据库包含 `category-ntp`。`claude-svc-extra` 中的目标端口规则状态如下，已启用的规则由 `🤖 AI 服务` 处理，并保持广告拦截优先：

| 目标端口 | 传输协议 | 状态 | 作用与来源 |
| --- | --- | --- | --- |
| `123` | UDP | 启用 | 参考 [NodeSeek 原帖的 NTP 端口建议](https://www.nodeseek.com/post-682343-1)，直接访问 IP 或未知时间服务器时也匹配；转换为 Mihomo 的 `AND,((NETWORK,udp),(DST-PORT,123))` 语法 |
| `3478`、`5349` | TCP、UDP | 已注释 | [IANA 登记的 STUN/TURN 及其 TLS/DTLS 端口](https://www.iana.org/assignments/service-names-port-numbers/?search=stun) |
| `19302–19309` | UDP | 已注释 | [Google 官方列出的 WebRTC 音视频端口](https://knowledge.workspace.google.com/admin/meet/prepare-your-network-for-meet-meetings-and-live-streams) |

已启用的 NTP 端口规则适用于所有应用及目标 IP；只有流量进入代理内核才会参与匹配。UDP 需要 TUN/透明代理等方式接管，并且所选节点支持 UDP，单独启用 HTTP 系统代理不能接管这些 UDP 请求。WebRTC 的三条端口规则已全部注释，相关域名仍按现有域名规则匹配。[NTP 同步的是 UTC 时间](https://www.rfc-editor.org/rfc/rfc5905.html#section-4)，分流只改变匹配流量的出口，不改变系统时区。

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

Claude 分流更新后，还需在客户端刷新规则提供方，并为 `🤖 AI 服务` 选择固定节点。确认最终配置包含 `RULE-SET,claude-domain-extra,🤖 AI 服务`、`RULE-SET,claude-ip-extra,🤖 AI 服务`、`RULE-SET,claude-svc-extra,🤖 AI 服务` 和对应的规则提供方，且 AI 规则保持在 Google、云服务和通用代理规则之前；广告拦截继续优先。规则提供方新增或更名后，需在妙妙屋重新同步分组清单并生成或更新订阅，仅刷新旧规则文件无法完成迁移。网页检测只能验证浏览器发起的请求，Claude Code 的实际出口仍需结合客户端连接记录核对。

分组顺序以[妙妙屋官方默认清单](https://github.com/iluobei/miaomiaowu/blob/main/configs/proxy-groups-lite.json)为基准，保留其中 24 个现有分组的相对顺序，将本仓库额外的 8 个分组插入相应位置。

新增服务所在区段为 **私有网络 → TMO-WFC → GG-WFC → PT 站点 → PT Tracker → ESET → 国内服务**。两个 Wi-Fi Calling 分组紧随私有网络；PT 站点先于 PT Tracker，两者均先于国内服务；ESET 紧邻国内服务之前，也先于云服务。

其他额外分组按 **苹果定位 → 苹果服务**、**金融服务 → 数字货币 → 云服务 → Tiktok → Spotify** 插入。手动勾选分组或编辑已有订阅时，还需核对最终配置中的顺序。
