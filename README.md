# AIprofile
AI-generated profile

妙妙屋使用的分组清单位于 [mmw/proxy_groups/proxy_groups.json](mmw/proxy_groups/proxy_groups.json)，本仓库维护的规则集位于 [mmw/ruleset](mmw/ruleset/)。

[TCSCloud SeedNet 实测与 Mihomo 规则](egress-check/README.md#tcscloud-seednet)收录 TW Top 1000 实测报告，以及 TCSCloud 分流、Line 和 Shopee 使用的自维护域名规则。

图标统一使用单个 emoji；同一分组的 `emoji`、`icon` 与 `group_label` 前缀保持一致。同类服务共用图标，例如 Wi-Fi Calling 使用 📶，ESET 安全服务使用 🛡️。

原版妙妙屋通过 `post_fetch` 覆写生成 `🚀 AI 节点组`。客户端拉取 Clash/Mihomo 订阅时，脚本用实际节点和代理集合填充该组。模板已定义同名组时会更新它，只有节点或代理集合的配置也能创建它。`🚀 AI 节点组` 排在分组列表首位，已有的 `🚀 节点选择` 紧随其后，两组各自选择出口。[AI 节点组覆写脚本](mmw/overrides/ai-select.js)

启用覆写后，预设中的 `🤖 AI 服务`、`☁️ 云服务`、`🐟 漏网之鱼` 等普通手选组会依次列出 `🚀 AI 节点组` 和 `🚀 节点选择` 作为前两个候选。选择前者跟随 AI 出口，选择后者跟随通用出口。脚本会把已有的 AI 候选移到首位并去重。

广告拦截、私有网络、国内服务、TMO-WFC、GG-WFC、PT 站点、PT Tracker、ESET 和苹果定位均跳过。自动测速、故障转移、负载均衡、按条件筛选节点、仅从订阅动态取节点和仅含内置策略的组也跳过。`🚀 节点选择` 或链式拨号依赖的节点池保留原有候选。要调整跳过的服务组，可编辑脚本的 `excluded`。

**启用覆写**

1. 在妙妙屋「系统设置」开启「覆写脚本」。
2. 进入「覆写管理 → 添加覆写设置」，名称可填「AI 基础选择器」，类型选「脚本」，钩子选「转换为客户端配置前」（`post_fetch`），粘贴 [ai-select.js](mmw/overrides/ai-select.js) 的全部内容并启用、保存。
3. 在目标订阅的「覆写配置」中勾选该脚本，再让客户端更新订阅。将脚本放入本仓库或同步分组清单，不会自动启用它。
4. 在客户端为 `🚀 AI 节点组` 选定一个固定节点。首次使用且没有已保存选择时，普通手选组默认使用它。客户端若恢复了此前保存的选择，可在相应分组中切换。

已启用覆写的订阅可在妙妙屋保存新版脚本后刷新。AI 节点组可在客户端的代理组面板选择。原版网页编辑器的「特殊节点」栏固定显示内置选项。如果保存的订阅本身已定义 AI 组，桌面端也可以拖动组名左侧的手柄，把它加入其他组。

Claude / Claude Code 分流于 **2026-11-14** 对照 [Net.Coffee 域名清单](https://ip.net.coffee/claude/site.html)、[NodeSeek 原帖《整合了一下claude的分流规则，surge格式》](https://www.nodeseek.com/post-682343-1)（正文更新日期：2026-04-10）和 [Aiip.si 分流说明](https://aiip.si/routing/)核对并按需采用。**保持广告拦截 → AI 服务的原有顺序**。Sentry 等遥测域名若先命中广告拦截，视为已由规则处理，不作为 AI 分流遗漏。

AI 服务保留 `category-ai-!cn`、`openai` 和上游 `claude` 三个规则源，并通过 [claude-domain-extra.yaml](mmw/ruleset/claude-domain-extra.yaml) 补充域名、关键词与 GEOSITE 规则，通过 [claude-ip-extra.yaml](mmw/ruleset/claude-ip-extra.yaml) 补充 IP 网段。[claude-svc-extra.yaml](mmw/ruleset/claude-svc-extra.yaml) 保留为备用，文件中的 NTP UDP 123 规则未注释，WebRTC 端口规则仍已注释，**当前未在分组清单中引用**。已有等效覆盖的规则不重复添加。

`balanced`、`comprehensive` 两个预设还在 `openai` 后挂载了 ChatGPT 域名补充规则。该规则匹配以 `chatgpt-async-webps-prod-` 开头的主机名，适用于任意域名后缀。例如，发往 `chatgpt-async-webps-prod-eastus-4.webpubsub.azure.com` 的 TCP 443 会命中此规则并交给 `🤖 AI 服务`。[chatgpt-domian-extra.yaml](mmw/ruleset/chatgpt-domian-extra.yaml)

**拒绝 AI 的 UDP 443** 使用独立的 `classical` 规则集。每条规则都限定 UDP 和目标端口 443，目标命中 GeoSite 分类 `category-ai-!cn`、Anthropic 固定网段或 `AS399358` 中的任一项即拒绝。ASN 由客户端的 `ASN.mmdb` 识别。[ai-svc-extra.yaml](mmw/ruleset/ai-svc-extra.yaml) · [ARIN 的 AS399358 登记](https://rdap.arin.net/registry/autnum/399358)

截至 2026-11-21，Anthropic 公布的 API 入站地址为 `160.79.104.0/23`、`153.61.224.0/22` 和 `2607:6bc0::/48`，工具调用等出站请求使用 `160.79.104.0/21` 和 `153.61.208.0/20`。本规则将两类网段都作为目标地址匹配，其中 `/21` 已覆盖第一条入站 `/23`。[Anthropic 固定 IP 清单](https://platform.claude.com/docs/en/api/ip-addresses)

在启用 AI 服务的订阅模板中，将下面的提供方声明并入现有的 `rule-providers`，把 `RULE-SET,ai-svc-extra,REJECT` 插到第一条 AI 放行规则之前。已有的广告拦截和更高优先级的自定义规则排在它前面。

```yaml
rule-providers:
  ai-svc-extra:
    type: http
    behavior: classical
    format: yaml
    url: https://raw.githubusercontent.com/tgr989/AIprofile/refs/heads/main/mmw/ruleset/ai-svc-extra.yaml
    path: ./ruleset/ai-svc-extra.yaml
    interval: 86400
```

妙妙屋的分组清单会将规则指向所属代理组，此处由模板直接指定 `REJECT`。保存模板后重新生成并更新订阅。若部署过带 UDP 443 拦截的旧版 `ai-select.js`，请同步更新该脚本以移除重复规则。

域名和 IP 两份补充规则均以 `behavior: classical`、`format: yaml` 挂载在 AI 分组的 `site_rules` 中，按域名、IP 的顺序排列，保留现有匹配顺序。妙妙屋会把 `ip_rules` 统一排到所有域名规则之后，因此此处保持原位置。以后恢复服务端口规则时，也应使用 `behavior: classical`、`format: yaml`；端口与逻辑规则不能使用仅支持 IP 网段的 `ipcidr` 格式。

进程规则单独保存在 [claude-proc-extra.yaml](mmw/ruleset/claude-proc-extra.yaml)，包含此前的 5 条 `PROCESS-NAME` 规则，**当前未在分组清单中引用**。以后启用时使用 `behavior: classical`、`format: yaml`。

| 补充内容 | 作用与来源 |
| --- | --- |
| `statsig.com` | [Claude Code 官方开发容器的网络白名单](https://github.com/anthropics/claude-code/blob/main/.devcontainer/init-firewall.sh)；`statsigapi.net` 后缀无法覆盖 |
| `intercomassets.com` | [Aiip.si 分流说明](https://aiip.si/routing/)中的客服资源，按后缀匹配并交给 AI 服务 |
| `accounts.google.com`、`oauth2.googleapis.com`、`openidconnect.googleapis.com`、`www.googleapis.com` | **精确匹配，全部已注释**；原 Google 登录入口参考 [Aiip.si](https://aiip.si/routing/)，依据 [Google 官方 OpenID Connect 发现文档](https://accounts.google.com/.well-known/openid-configuration)补充令牌、用户信息及验签公钥接口。部分请求由网站后端发起，不一定经过本机代理；`www.googleapis.com` 还承载其他 Google API |
| `accounts.gstatic.com`、`ssl.gstatic.com`、`www.gstatic.com` | **精确匹配，全部已注释**；[Google 官方 ChromeOS 主机白名单](https://support.google.com/chrome/a/answer/6334001?hl=en)列出的账户与静态资源备用主机，后两者明确用于登录页面 JS / CSS；并非 Claude 必需依赖清单 |
| `apis.google.com` | **精确匹配，已注释**；[Google 官方迁移文档](https://developers.google.com/identity/gsi/web/guides/migration)中的旧版 Sign-In 脚本主机，新版 GIS 脚本已改用 `accounts.google.com` |
| `appleid.apple.com`、`idmsa.apple.com`、`appleid.cdn-apple.com` | **精确匹配，全部已注释**；参考 [Sign in with Apple 文档](https://developer.apple.com/documentation/signinwithapple/incorporating-sign-in-with-apple-into-other-platforms)和 [Apple 企业网络主机清单](https://support.apple.com/en-us/101555)，保留授权、账户认证与登录资源备用规则 |
| `maps.googleapis.com` | **精确匹配，已注释**；保留 Net.Coffee KYC 表格中的 Google 地图备用规则，当前交由 Google 分组处理 |
| `withpersona.com`、`frompersona.com` | Net.Coffee 的 KYC 表格列出，但其可复制的 YAML 未包含；继续按后缀匹配并交给 AI 服务 |
| `t0.gstatic.com` 至 `t3.gstatic.com`、`storage.googleapis.com` | **精确匹配，全部已注释**；保留 [NodeSeek 原帖](https://www.nodeseek.com/post-682343-1)中的页面资源和 Claude Code 下载备用规则，当前交由 Google 分组处理 |
| `modelcontextprotocol.com`、`.io`、`.net`、`.org`，以及 `cdn.growthbook.io` | 合并 [jinxinkai/clash-ai-rules 的 Anthropic 清单](https://github.com/jinxinkai/clash-ai-rules/blob/e25782af4ab7afb6ff528fc2a61e22523ff082cb/Anthropic.yaml) 中尚未覆盖的 MCP 与功能开关域名；不代表覆盖任意第三方 MCP 服务器 |
| `sentry`、`claude`、`anthropic` 关键词 | `sentry` 来自 Net.Coffee，`claude` / `anthropic` 兜底参考 [NodeSeek 原帖](https://www.nodeseek.com/post-682343-1)；覆盖包含这些字符串的域名，参考项目的 `anthropic.com.cn` 也由此覆盖 |
| `153.61.224.0/22` | Claude API 的入站网段，由 `claude-ip-extra` 按目标 IP 分流。[Anthropic 固定 IP 清单](https://platform.claude.com/docs/en/api/ip-addresses) |
| `153.61.208.0/20` | Anthropic 发起工具调用时使用的出站网段。客户端访问其中的目标 IP 时，也交给 `🤖 AI 服务`。[Anthropic 固定 IP 清单](https://platform.claude.com/docs/en/api/ip-addresses) |

参考项目的其他 Anthropic 域名、IP 和 ASN 已由现有规则覆盖；其 OpenAI 清单中的 `chatgpt.livekit.cloud`、`host.livekit.cloud`、`turn.livekit.cloud` 也已由 AI 服务中的 `openai` / `category-ai-!cn` 覆盖。本次按 Claude 与实时通信相关范围合并差异，不整体挂载该项目的 Facebook、X 等规则集。

hCaptcha 的 `hcaptcha.mrs` 从云服务移入 AI 服务，随 `balanced` 和 `comprehensive` 预设启用；其他应用使用 hCaptcha 时也按 AI 分组处理。

上游 `claude` 使用 `behavior: classical`，已包含网页列出的核心、CDN、认证、监控、客服域名。它的 `160.79.104.0/21` 覆盖官方入站 `160.79.104.0/23`，`2607:6bc0::/32` 覆盖官方入站 `2607:6bc0::/48`，并已有 `IP-ASN,399358,no-resolve`。上游和本地 IP 补充集都通过 AI 分组的 `site_rules` 加载。[上游 Claude 规则](https://github.com/iluobei/clash-pt-rules/blob/main/claude.yaml#L26-L29)

现有 `datadog` 关键词已覆盖 `datadoghq` 及 `browser-intake-us5-datadoghq.com` 等变体，`sift` 关键词和 `sentry.io` 后缀也继续保留。更早命中广告拦截的连接仍由广告分组处理。

Google / Apple 登录备用规则于 **2026-11-15** 按官方资料核对。上述登录规则及 Google 地图、页面资源、下载的精确匹配规则当前全部保持注释，由已启用的各自分组处理。推荐在客户端将 **`🔍 谷歌服务`、`🍏 苹果服务` 与 `🤖 AI 服务` 选择为同一个固定节点，保持出口 IP 一致**；仅选择相同地区或分别使用自动选择，不能保证出口一致。以后按需取消注释时，同域名的其他应用请求也会交给 AI 服务。

已启用的第三方服务域名由多个应用共用，其他应用访问相同域名也走 AI 服务；关键词还可能匹配无关站点。

`geosite:anthropic` 的当前条目已由 `category-ai-!cn` 覆盖。`claude-domain-extra` 保留 `GEOSITE,category-ntp`，将该分类内的时间服务器域名交给 AI 服务，需要客户端的 GeoSite 数据库包含 `category-ntp`。其中的 `time.google.com`、`time.apple.com` 仍按 NTP 规则处理，不受上述 Google / Apple 精确匹配规则注释影响。

**当前仅启用 NTP 域名分类，UDP 123 端口兜底已停用。** [Mihomo 的 GEOSITE 规则匹配域名，DST-PORT 规则匹配目标端口](https://wiki.metacubex.one/config/rules/)，两者并非等效覆盖。`claude-svc-extra` 已取消引用；纯 IP 连接且内核没有域名信息，或域名未被 NTP 分类收录时，流量按后续规则处理。

`claude-svc-extra` 保留一条未注释的 UDP 123 规则，但文件未被引用，因此不参与分流。以后恢复 NTP 端口分流时，将规则提供方加回 AI 分组的 `site_rules`，放在 `claude-ip-extra` 之后、`hcaptcha` 之前，并重新生成订阅以恢复对应的 `RULE-SET` 引用；WebRTC 规则仍需另行取消注释。

| 目标端口 | 传输协议 | 状态 | 作用与来源 |
| --- | --- | --- | --- |
| `123` | UDP | 保留，未引用 | 参考 [NodeSeek 原帖的 NTP 端口建议](https://www.nodeseek.com/post-682343-1)，恢复引用后可匹配直接访问 IP 或未知时间服务器的连接；转换为 Mihomo 的 `AND,((NETWORK,udp),(DST-PORT,123))` 语法 |
| `3478`、`5349` | TCP、UDP | 已注释 | [IANA 登记的 STUN/TURN 及其 TLS/DTLS 端口](https://www.iana.org/assignments/service-names-port-numbers/?search=stun) |
| `19302–19309` | UDP | 已注释 | [Google 官方列出的 WebRTC 音视频端口](https://knowledge.workspace.google.com/admin/meet/prepare-your-network-for-meet-meetings-and-live-streams) |

只有流量进入代理内核才会参与匹配。NTP 的 UDP 流量需要 TUN/透明代理等方式接管，并且所选节点支持 UDP，单独启用 HTTP 系统代理不能接管这些 UDP 请求。NTP 和 WebRTC 端口规则当前均停用，相关域名仍按现有域名规则匹配；以后启用这些端口规则时，会影响所有应用及目标 IP。[NTP 同步的是 UTC 时间](https://www.rfc-editor.org/rfc/rfc5905.html#section-4)，分流只改变匹配流量的出口，不改变系统时区。

下表分组均加入 `comprehensive` 预设，也可单独勾选。

| 分组 | 匹配内容 | 出口选择 |
| --- | --- | --- |
| TMO-WFC | T-Mobile Wi-Fi Calling 域名与 IP 网段 | 按需选择 |
| GG-WFC | giffgaff / O2 Wi-Fi Calling 域名与 IP 网段 | 按需选择 |
| ESET | MetaCubeX ESET 域名规则集（当前仅使用 MRS） | 中国大陆网络选择 `DIRECT`；境外按需选择中国大陆出口 |
| 📍 苹果定位服务 | `gspe1-ssl.ls.apple.com` 及其子域名 | 按需选择，独立于 GG-WFC |
| ♾️ Meta 服务 | Facebook、Instagram、Messenger、WhatsApp、Threads 等域名，以及 Facebook IP 网段。[域名清单](https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/meta.list) · [IP 清单](https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/facebook.list) | 按需选择 |
| 💬 Line 服务 | LINE 上游 MRS，并补充 `linebiz.com` 及其子域名。[补充 MRS](mmw/ruleset/line-tcscloud-seednet-avoid.mrs) | 按需选择 |

Meta 服务和 Line 服务排在社交媒体之前。单独勾选社交媒体时，Facebook 和 Instagram 仍可使用该组的出口。`🛍️ Shopee 服务` 和 `🟣 Yahoo 服务` 可以单独勾选，各自选择出口。

妙妙屋当前生成器为这些普通分组默认选择 `🚀 节点选择`，分组清单不能指定默认出口。生成后需在客户端为 **ESET** 选择统一出口：中国大陆网络使用 `DIRECT`；境外需要中国出口时选择中国大陆节点。`DIRECT` 使用设备当前网络，并不自动获得中国 IP。

妙妙屋分组引用的本地补充域名规则使用 `classical` YAML，保留精确匹配、后缀匹配和正则匹配。ESET 当前仅引用 MetaCubeX 的 `geo/geosite/eset.mrs`（`behavior: domain`、`format: mrs`），`ip_rules` 为空；实际启用的覆盖范围以上游 MRS 为准。

ESET 自维护规则已整合为两份备用文件，**当前均未挂载到 ESET 分组**：

| 文件 | 内容 | 恢复引用时的类型 |
| --- | --- | --- |
| [eset-domain.yaml](mmw/ruleset/eset-domain.yaml) | 26 条域名规则：原中国服务、更新仓库及企业云补充规则 | `site_rules`，`behavior: classical`、`format: yaml` |
| [eset-ip.yaml](mmw/ruleset/eset-ip.yaml) | 436 条精确 IP 规则，其中 19 条 IPv6 | `ip_rules`，`behavior: ipcidr`、`format: yaml` |

两份备用文件保留整合前的全部条目，旧的分类文件已移除。内容按 [官方 KB332 服务清单](https://support.eset.com/en/kb332-ports-and-addresses-required-to-use-your-eset-product-with-a-third-party-firewall) 于 **2026-11-14** 核对，包括中国服务、更新下载、激活、LiveGrid、LiveGuard、PROTECT、Inspect、反垃圾和样本提交等地址。若以后启用 IP 规则，生成器会在对应的 `RULE-SET` 后添加 `no-resolve`。[ESET Connect](https://help.eset.com/eset_connect/en-US/prerequisites.html) 的 API 域名已由上游 `eset.systems` 后缀覆盖。

备用 IP 规则只收录官方列出的客户端出站服务地址，采用 `/32` 或 `/128`，不扩大到整个云厂商网段。共享的 Microsoft OAuth 登录、第三方 OCSP，以及入站邮件、Syslog 的源地址不纳入 ESET 专用规则。本地清单是上述日期的快照，后续需依据官方清单和[变更记录](https://support.eset.com/en/kb8900-changelog-for-kb332)更新。

Apple Music 使用 MetaCubeX 的 `geo/geosite/apple-music.mrs`，通用代理使用 `geo-lite/geosite/proxy.mrs`。代理媒体的同名 MRS 当前为空，改用其上游 blackmatrix7 的 `GlobalMedia_Domain.yaml`，对应 `behavior: domain`、`format: yaml` 和 `./ruleset/proxymedia.yaml` 缓存路径。PT 站点的源文件包含带类型前缀的规则，使用 `behavior: classical`。

PT Tracker 使用 MetaCubeX 的 `geo/geosite/tracker.mrs`（`behavior: domain`、`format: mrs`），缓存路径为 `./ruleset/pttracker.mrs`，按实际域名匹配，不再将 URL 参数或 BT 协议字段作为域名关键词。该源也包含部分 PT 站点后缀，因此 PT 站点分组优先；同一域名上的网页与 Tracker 请求无法仅靠域名规则区分。

代理媒体另通过 `ip_rules` 引用同目录的 `GlobalMedia.yaml`（`behavior: classical`），补充 IPv4/IPv6、关键词和进程规则，缓存路径为 `./ruleset/proxymedia-ip.yaml`；生成器会在对应的 `RULE-SET` 后添加 `no-resolve`。

发布时将 `mmw/` 推送到 GitHub 的 `main` 分支。目录迁移后，在妙妙屋更新分组清单源地址，再重新同步清单并生成或更新订阅。手动配置了 `ai-svc-extra` 的模板也需改用上文的下载地址。[分组清单源地址](https://raw.githubusercontent.com/tgr989/AIprofile/refs/heads/main/mmw/proxy_groups/proxy_groups.json)

所有规则集下载 URL 均使用 GitHub 或 raw.githubusercontent.com 的原始地址，不附加第三方代理前缀。

Claude 分流更新后，还需在客户端刷新规则提供方，并为 `🤖 AI 服务` 选择固定节点。确认最终配置包含 `RULE-SET,claude-domain-extra,🤖 AI 服务`、`RULE-SET,claude-ip-extra,🤖 AI 服务` 和对应的规则提供方，且 AI 规则保持在 Google、云服务和通用代理规则之前；广告拦截继续优先。当前不应再包含 `claude-svc-extra` 的规则引用或规则提供方。规则提供方新增、更名或移除后，需在妙妙屋重新同步分组清单并生成或更新订阅，仅刷新旧规则文件无法完成引用迁移。网页检测只能验证浏览器发起的请求，Claude Code 的实际出口仍需结合客户端连接记录核对。

分组清单包含妙妙屋默认清单中的 24 个分组和本仓库新增的 14 个分组。清单开头为 **AI 节点组 → 广告拦截 → AI 服务**。`🔀 TCSCloud 分流` 可单独勾选。[妙妙屋官方默认清单](https://github.com/iluobei/miaomiaowu/blob/main/proxy_groups/proxy-groups-lite.json)

新增服务所在区段为 **私有网络 → TMO-WFC → GG-WFC → PT 站点 → PT Tracker → ESET → 哔哩哔哩 → 国内服务**。两个 Wi-Fi Calling 分组紧随私有网络。PT 站点先于 PT Tracker，两者均先于国内服务。ESET 也先于云服务。

清单末尾为 **Yahoo 服务 → Shopee 服务 → TCSCloud 分流 → 非中国**。其他额外分组按 **金融服务 → 数字货币 → 云服务 → Tiktok → Spotify** 排列。手动勾选分组或编辑已有订阅时，还需核对最终配置中的顺序。
