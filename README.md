# AIprofile
AI-generated profile

妙妙屋使用的分组清单位于 [mmw/proxy_groups/proxy_groups.json](mmw/proxy_groups/proxy_groups.json)，本仓库维护的规则集位于 [mmw/ruleset](mmw/ruleset/)。

TCSCloud SeedNet 的 TW Top 1000 和 A/B 实测报告收录在 `egress-check`。TCSCloud 分流、Meta、Line 和 Shopee 的自维护域名规则集中在 `mmw/ruleset/tcscloud-seednet`。 [实测报告](egress-check/README.md#tcscloud-seednet) · [域名规则](mmw/ruleset/tcscloud-seednet/)

AI 组的 `label` 为 `AI 节点`，客户端分组名 `group_label` 为 `⚡ AI 节点`。每组的 `emoji` 和 `icon` 使用同一个图标。两个 Wi-Fi Calling 组共用 🛜，ESET 安全服务使用 🛡️。

妙妙屋在 `post_fetch` 阶段应用覆写。订阅同时定义 `⚡ AI 节点` 和 `🚀 节点选择` 时，脚本把 AI 组移到 `🚀 节点选择` 的紧后一位。 [AI 节点覆写脚本](mmw/overrides/ai-select.js)

其他 `select` 策略组的 `proxies` 含有 `🚀 节点选择` 且不处于 `⚡ AI 节点` 的上游拨号路径时，脚本把 `⚡ AI 节点` 放在它的紧后一位并去重；已存在循环引用的上游组会移除 `⚡ AI 节点`。

`广告拦截`、`国内服务` 和 `私有网络` 同样按候选中是否含有 `🚀 节点选择` 应用上述规则，分别将 `REJECT`、`DIRECT` 和 `DIRECT` 置顶去重并设为 `default-selected`。

订阅包含 `⚡ AI 节点` 时，脚本为不构成循环的 `AI 服务`、`谷歌服务`、`苹果服务` 和 `云服务` 补齐该候选（缺失时置顶），并设为 `default-selected`。

**启用覆写**

1. 在妙妙屋「系统设置」开启「覆写脚本」。
2. 进入「覆写管理 → 添加覆写设置」，名称可填「AI 基础选择器」，类型选「脚本」，钩子选「转换为客户端配置前」（`post_fetch`），粘贴 [ai-select.js](mmw/overrides/ai-select.js) 的全部内容并启用、保存。
3. 在目标订阅的「覆写配置」中勾选该脚本，再让客户端更新订阅。将脚本放入本仓库或同步分组清单，不会自动启用它。
4. 要让业务组跟随 AI 出口，在业务组内选择 `⚡ AI 节点`，再为 AI 组选定节点。客户端若为 `广告拦截` 或直连组记住了其他出口，可在相应的组手动切回 `REJECT` 或 `DIRECT`。

更新已有订阅的覆写时，在妙妙屋保存新版脚本，再在客户端刷新订阅。修改分组清单后，可在妙妙屋同步清单并重新生成订阅。原版网页编辑器的「特殊节点」栏固定显示内置选项。如果保存的订阅本身已定义 AI 组，桌面端也可以拖动组名左侧的手柄，把它加入其他组。

Claude / Claude Code 分流于 **2026-11-14** 对照 [Net.Coffee 域名清单](https://ip.net.coffee/claude/site.html)、[NodeSeek 原帖《整合了一下claude的分流规则，surge格式》](https://www.nodeseek.com/post-682343-1)（正文更新日期：2026-04-10）和 [Aiip.si 分流说明](https://aiip.si/routing/)核对并按需采用。**保持广告拦截 → AI 服务的原有顺序**。Sentry 等遥测域名若先命中广告拦截，视为已由规则处理，不作为 AI 分流遗漏。

`balanced` 和 `comprehensive` 预设中，AI 服务的 `site_rules` 依次为 `claude-domain` → `claude` → `openai` → `openai-domain` → `gemini` → `category-ai-!cn` → `ai-fallback`。`claude` 匹配 NTP GeoSite 和 Anthropic ASN，`claude-ip` 匹配 IPv4 和 IPv6 CIDR。 [Claude 补充规则](mmw/ruleset/claude.yaml) · [iluobei 原始规则](https://raw.githubusercontent.com/iluobei/clash-pt-rules/refs/heads/main/claude.yaml)

上游 `openai` 提供方使用 MetaCubeX 的 `classical` YAML，包含 ChatGPT 的 Azure Web PubSub 动态域名规则。`openai-domain` 收录 OpenAI、ChatGPT 和 Codex 的补充域名，包括这些客户端使用的第三方服务端点。 [OpenAI 上游规则](https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/classical/openai.yaml) · [补充域名清单](mmw/ruleset/openai/domain-openai.list) · [MRS](mmw/ruleset/openai/domain-openai.mrs)

Mihomo 能获取主机名时，ChatGPT 网页、API 和 Codex 使用域名分流。AI 分组的 `ip_rules` 引用 `openai-ip` 和 `openai-asn`。`openai-ip` 匹配 OpenAI 汇总 CIDR，`openai-asn` 指向本仓的 `openai.yaml`，其中的 ASN `payload` 目前以注释保留。 [汇总 MRS](mmw/ruleset/openai/ipcidr-openai.mrs) · [汇总明文清单](mmw/ruleset/openai/ipcidr-openai.list) · [OpenAI 补充规则](mmw/ruleset/openai.yaml)

**启用 AI 拦截**

共用 AI 和 Claude 的 UDP 443 拦截默认关闭。两个源文件中的 `# rules:` 都是注释。同步分组清单会加载分流规则，启用拦截还要把选中的 `REJECT` 规则加入最终订阅。 [AI 兜底规则](mmw/ruleset/ai-fallback.yaml) · [Claude 规则](mmw/ruleset/claude.yaml)

1. 按需准备依赖。共用 AI 规则需要客户端的 GeoSite 数据库含 `category-ai-!cn`。Claude 规则需要 `ASN.mmdb` 和顶层 `rule-providers` 中的 `claude-ip`。`balanced` 和 `comprehensive` 预设会随 AI 服务生成该提供方。手动维护订阅时，用 `claude-ip` 作为 YAML 键，复制分组清单中该条目除 `key` 外的字段。 [分组清单](mmw/proxy_groups/proxy_groups.json)
2. 从下例复制所需的 `-` 列表项，插入订阅已有的顶层 `rules`，放在广告拦截和高优先级自定义规则之后、常规 AI 分流之前。从源文件复制时，取 `# rules:` 中引号内的完整规则，写成同样的列表项。迁移已有的 `RULE-SET,ai-routing-reject,REJECT` 时，用选中的列表项替换它。

   ```yaml
   rules:
     # 共用 AI 域名的 UDP 443
     - 'AND,((NETWORK,UDP),(DST-PORT,443),(GEOSITE,category-ai-!cn)),REJECT'
     # Claude 网段或 Anthropic ASN 的 UDP 443
     - 'AND,((NETWORK,UDP),(DST-PORT,443),(OR,((RULE-SET,claude-ip,no-resolve),(IP-ASN,399358,no-resolve),(IP-ASN,60808,no-resolve),(IP-ASN,4167,no-resolve),(IP-ASN,400243,no-resolve),(IP-ASN,401551,no-resolve)))),REJECT'
   ```

3. 若还需启用 ChatGPT Voice 拦截，从 `openai.yaml` 的注释示例复制 `chatgpt-voice` 定义到订阅的 `rule-providers`，去掉复制行开头的 `# ` 并保留缩进。将同文件的拦截规则按上例加入 `rules`。它依赖 `ASN.mmdb`，拒绝目标 IP 命中 Voice 官方网段或 OpenAI ASN 的 UDP 3478 和 UDP 443。TCP 443 继续按后续规则分流。 [Voice 配置示例](mmw/ruleset/openai.yaml)
4. 合并后运行 `mihomo -t -d <客户端配置目录> -f <订阅配置.yaml>` 检查配置。刷新订阅后，可在客户端连接日志中核对 UDP 443 的命中规则和 `REJECT` 动作。

截至 2026-11-22，已将 OpenAI 的七份官方 CIDR 清单分别编译为 Mihomo `ipcidr` MRS。

| 官方用途 | CIDR 条目 | 文件与来源 |
| --- | ---: | --- |
| ChatGPT Voice 目标地址 | 411 | [MRS](mmw/ruleset/openai/ipcidr-openai-chatgpt-voice.mrs) · [明文](mmw/ruleset/openai/ipcidr-openai-chatgpt-voice.list) · [官方 JSON](https://openai.com/chatgpt-voice.json) |
| ChatGPT 集成出站 | 289 | [MRS](mmw/ruleset/openai/ipcidr-openai-chatgpt-connectors.mrs) · [明文](mmw/ruleset/openai/ipcidr-openai-chatgpt-connectors.list) · [官方 JSON](https://openai.com/chatgpt-connectors.json) |
| ChatGPT Agents 和 Codex Cloud 出站 | 2,923 | [MRS](mmw/ruleset/openai/ipcidr-openai-chatgpt-agents.mrs) · [明文](mmw/ruleset/openai/ipcidr-openai-chatgpt-agents.list) · [官方 JSON](https://openai.com/chatgpt-agents.json) |
| ChatGPT-User | 237 | [MRS](mmw/ruleset/openai/ipcidr-openai-chatgpt-user.mrs) · [明文](mmw/ruleset/openai/ipcidr-openai-chatgpt-user.list) · [官方 JSON](https://openai.com/chatgpt-user.json) |
| OAI-SearchBot | 39 | [MRS](mmw/ruleset/openai/ipcidr-openai-searchbot.mrs) · [明文](mmw/ruleset/openai/ipcidr-openai-searchbot.list) · [官方 JSON](https://openai.com/searchbot.json) |
| GPTBot | 18 | [MRS](mmw/ruleset/openai/ipcidr-openai-gptbot.mrs) · [明文](mmw/ruleset/openai/ipcidr-openai-gptbot.list) · [官方 JSON](https://openai.com/gptbot.json) |
| OAI-AdsBot | 2 | [MRS](mmw/ruleset/openai/ipcidr-openai-adsbot.mrs) · [明文](mmw/ruleset/openai/ipcidr-openai-adsbot.list) · [官方 JSON](https://openai.com/adsbot.json) |

截至 2026-11-23，七份服务清单均只包含 IPv4。汇总库包含七份清单合并后的 2,936 条 IPv4 CIDR，以及 ARIN 分配给 OpenAI OpCo, LLC 的 IPv6 网段 `2604:f20::/28`。 [汇总 MRS](mmw/ruleset/openai/ipcidr-openai.mrs) · [汇总明文清单](mmw/ruleset/openai/ipcidr-openai.list) · [ARIN IPv6 登记](https://rdap.arin.net/registry/ip/2604:f20::/28)

AI 分组通过 `category-ai-!cn` 识别 Meta AI 流量。Meta / Muse 的补充域名和 6 个 ASN 作为备用规则供后续单独挂载，`facebook`、`fbcdn` 关键词以注释形式保留在 `ai-fallback.yaml`。ASN 对照 Meta 公布的对等集合和 Facebook Singapore 的 APNIC 登记补齐。 [备用域名 MRS](mmw/ruleset/meta/domain-meta.mrs) · [域名清单](mmw/ruleset/meta/domain-meta.list) · [ASN 备用规则](mmw/ruleset/meta.yaml)

`gemini` 以 `classical` YAML 收录 Gemini CLI 站点和 Gemini Docs MCP 域名；`ai-fallback` 排在末尾加载 `ai-fallback.yaml` 中的关键词兜底与诊断探针规则。更新各 `.mrs` 域名规则时编辑对应的 `.list`，再运行 `mihomo convert-ruleset domain text <输入.list> <输出.mrs>`。仍引用 `common-ai` 或 `ai-routing` 的订阅应重新同步分组清单并生成，以加载拆分后的各提供方。 [Gemini 补充规则](mmw/ruleset/gemini.yaml) · [AI 兜底规则](mmw/ruleset/ai-fallback.yaml)

截至 2026-11-21，Anthropic 公布的 API 入站地址为 `160.79.104.0/23`、`153.61.224.0/22` 和 `2607:6bc0::/48`，工具调用等出站请求使用 `160.79.104.0/21` 和 `153.61.208.0/20`。本规则将两类网段都作为目标地址匹配，其中 `/21` 已覆盖第一条入站 `/23`。[Anthropic 固定 IP 清单](https://platform.claude.com/docs/en/api/ip-addresses)

`claude-domain` 和 `claude` 依次挂载在 AI 分组的 `site_rules` 中，分别使用 `domain` MRS 和 `classical` YAML。`claude-ip` 以 `behavior: ipcidr`、`format: mrs` 挂载在 `ip_rules` 中。妙妙屋会把 `ip_rules` 排到域名规则之后，并加上 `no-resolve`。以后恢复服务端口规则时，也应使用 `behavior: classical`、`format: yaml` 以支持端口和逻辑匹配。

| 补充内容 | 作用与来源 |
| --- | --- |
| `anthropiccdn.com`、`anthropic-cdn.com`、`anthropicsystem.com`、`anthropic.cloud` | 为社区清单的四个域名配置显式后缀匹配。 [Linux DO 规则帖](https://linux.do/t/topic/2292545/4) |
| `intercom-messenger.com`、`us5.datadoghq.com`、`siftscience.com` | 补充客服、遥测和风控。共用的 `r.stripe.com`、`fcmtoken.googleapis.com` 和 Cloudflare 验证以注释形式保留，按需启用。 [X 分流帖](https://x.com/qwerty__cs/status/2124495008070091159) · [作者更正](https://x.com/qwerty__cs/status/2124502685210804571) |
| `statsig.com` | [Claude Code 官方开发容器的网络白名单](https://github.com/anthropics/claude-code/blob/main/.devcontainer/init-firewall.sh)；`statsigapi.net` 后缀无法覆盖 |
| `intercomassets.com` | 已注释并改由云服务的 `intercom.mrs` 统一覆盖（上游未收录的 `intercom-messenger.com` 继续保留在 `claude-domain`）；参考 [Aiip.si 分流说明](https://aiip.si/routing/) |
| `accounts.google.com`、`oauth2.googleapis.com`、`openidconnect.googleapis.com` | Google 登录授权、令牌交换和用户信息接口，均以精确匹配的注释备用规则保留。参考 [Aiip.si](https://aiip.si/routing/)和 [Google 官方 OpenID Connect 发现文档](https://accounts.google.com/.well-known/openid-configuration) |
| `appleid.apple.com`、`idmsa.apple.com` | Apple 授权和账户认证的精确匹配备用规则，均以注释保留。参考 [Sign in with Apple 文档](https://developer.apple.com/documentation/signinwithapple/incorporating-sign-in-with-apple-into-other-platforms)和 [Apple 企业网络主机清单](https://support.apple.com/en-us/101555) |
| `maps.googleapis.com` | **精确匹配，已注释**；保留 Net.Coffee KYC 表格中的 Google 地图备用规则，当前交由 Google 分组处理 |
| `withpersona.com`、`frompersona.com`、`yoti.com` | Net.Coffee 的 KYC 表格及 Claude 身份/年龄核验使用的 Persona 与 Yoti 域名，按后缀匹配并交给 AI 服务 |
| `t0.gstatic.com` 至 `t3.gstatic.com`、`storage.googleapis.com` | 页面静态资源和 Claude Code 下载的精确匹配备用规则，均以注释保留。参考 [NodeSeek 原帖](https://www.nodeseek.com/post-682343-1) |
| `modelcontextprotocol.com`、`.io`、`.net`、`.org`，以及 `cdn.growthbook.io` | 合并 [jinxinkai/clash-ai-rules 的 Anthropic 清单](https://github.com/jinxinkai/clash-ai-rules/blob/e25782af4ab7afb6ff528fc2a61e22523ff082cb/Anthropic.yaml) 中尚未覆盖的 MCP 与功能开关域名；不代表覆盖任意第三方 MCP 服务器 |
| `claude`、`anthropic`、`openai`、`chatgpt`、`codex` 及遥测风控关键词 | 收敛于 [ai-fallback.yaml](mmw/ruleset/ai-fallback.yaml) 的关键词兜底（参考 Net.Coffee 与 [NodeSeek 原帖](https://www.nodeseek.com/post-682343-1)），覆盖各区域变体及 `anthropic.com.cn` 等包含对应字符串的域名 |
| `153.61.224.0/22` | Claude API 的入站网段，由 `claude-ip` 按目标 IP 分流。[Anthropic 固定 IP 清单](https://platform.claude.com/docs/en/api/ip-addresses) |
| `153.61.208.0/20` | Anthropic 发起工具调用时使用的出站网段。客户端访问其中的目标 IP 时，也交给 `AI 服务`。[Anthropic 固定 IP 清单](https://platform.claude.com/docs/en/api/ip-addresses) |

参考项目的其他 Anthropic 域名、IP 和 ASN 已由现有规则覆盖；其 OpenAI 清单中的 `chatgpt.livekit.cloud`、`host.livekit.cloud`、`turn.livekit.cloud` 也已由 AI 服务中的 `openai` / `category-ai-!cn` 覆盖。本次按 Claude 与实时通信相关范围合并差异，不整体挂载该项目的 Facebook、X 等规则集。

云服务的 `site_rules` 以 hCaptcha、WorkOS、Sentry、Intercom、GitHub、GitLab 开头，其中 `workos` 由本仓维护的 MRS 统一覆盖 WorkOS / AuthKit 域名，`sentry` 与 `intercom` 分别引用 MetaCubeX 的 `geo/geosite/sentry.mrs` 和 `geo/geosite/intercom.mrs`。OneDrive 由「微软服务」的 `microsoft` 提供方匹配，上游清单覆盖 OneDrive 和 SharePoint 域名。云服务和微软服务随 `balanced` 和 `comprehensive` 预设启用。 [WorkOS MRS](mmw/ruleset/workos.mrs) · [WorkOS 明文清单](mmw/ruleset/workos.list) · [Sentry 域名清单](https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/sentry.list) · [Intercom 域名清单](https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/intercom.list) · [微软域名清单](https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/microsoft.list)

`claude-domain` 收录 7 条精确域名、34 条域名后缀和 1 条 AWS 区域通配规则。更新时编辑明文清单，再运行 `mihomo convert-ruleset domain text mmw/ruleset/claude/domain-claude.list mmw/ruleset/claude/domain-claude.mrs`。 [MRS](mmw/ruleset/claude/domain-claude.mrs) · [明文清单](mmw/ruleset/claude/domain-claude.list)

`claude-ip` 收录 41 条 CIDR，涵盖 Anthropic 登记网段、运营商转分配、BGP 公告及 Claude 官方 IP 清单。更新地址时编辑明文清单，再运行 `mihomo convert-ruleset ipcidr text mmw/ruleset/claude/ipcidr-claude.list mmw/ruleset/claude/ipcidr-claude.mrs`。 [MRS](mmw/ruleset/claude/ipcidr-claude.mrs) · [明文清单](mmw/ruleset/claude/ipcidr-claude.list)

`ai-fallback.yaml` 保留 `intercom`、`statsig`、`fathom`、`growthbook`、`datadog`、`sift`、`sentry` 等关键词兜底（覆盖 `browser-intake-us5-datadoghq.com` 等变体）；`domain-claude.list` 中重复的 `sentry.io` 与三条 Intercom 后缀已注释并交由云服务的 `sentry.mrs` 和 `intercom.mrs` 维护。更早命中广告拦截的连接仍由广告分组处理。

Google / Apple 登录备用规则于 **2026-11-15** 按官方资料核对。登录、Google 地图、页面静态资源和下载域名在 `domain-claude.list` 中以注释形式保留，默认交由订阅的其他规则匹配。推荐在客户端将 **`谷歌服务`、`苹果服务` 与 `AI 服务` 选择为同一个固定节点，保持出口 IP 一致**；仅选择相同地区或分别使用自动选择，不能保证出口一致。按需取消注释并重新编译 MRS 后，同域名的其他应用请求也会交给 AI 服务。

已启用的第三方服务域名由多个应用共用，其他应用访问相同域名也走 AI 服务；关键词还可能匹配无关站点。

`geosite:anthropic` 的当前条目已由 `category-ai-!cn` 覆盖。`claude.yaml` 保留 `GEOSITE,category-ntp`，将该分类内的时间服务器域名交给 AI 服务，需要客户端的 GeoSite 数据库包含 `category-ntp`。其中的 `time.google.com`、`time.apple.com` 仍按 NTP 规则处理，不受上述 Google / Apple 精确匹配规则注释影响。

**当前启用 NTP 域名分类。** `claude.yaml` 中的 UDP 123 端口兜底以注释形式保留。纯 IP 连接且内核未识别到域名，或域名未被 NTP 分类收录时，流量按后续规则处理。 [Mihomo 的域名与端口匹配说明](https://wiki.metacubex.one/config/rules/)

需要启用 NTP 端口兜底时，在 `claude.yaml` 中取消对应规则的注释，发布后在客户端刷新 `claude` 规则提供方。

| 目标端口 | 传输协议 | 状态 | 作用与来源 |
| --- | --- | --- | --- |
| `123` | UDP | 注释备用 | `AND,((NETWORK,UDP),(DST-PORT,123))` 按目标端口匹配，包含直接访问 IP 或未知时间服务器的连接。参考 [NodeSeek 原帖](https://www.nodeseek.com/post-682343-1) |

只有流量进入代理内核才会参与匹配。NTP 的 UDP 流量需要 TUN/透明代理等方式接管，并且所选节点支持 UDP，单独启用 HTTP 系统代理不能接管这些 UDP 请求。UDP 123 备用规则按目标端口匹配，适用于所有应用及目标 IP。[NTP 同步的是 UTC 时间](https://www.rfc-editor.org/rfc/rfc5905.html#section-4)，分流只改变匹配流量的出口，不改变系统时区。

下表分组均加入 `comprehensive` 预设，也可单独勾选。

| 分组 | 匹配内容 | 出口选择 |
| --- | --- | --- |
| TMO-WFC | T-Mobile Wi-Fi Calling 域名与 IP 网段 | 按需选择 |
| GG-WFC | giffgaff / O2 Wi-Fi Calling 域名与 IP 网段 | 按需选择 |
| ESET | MetaCubeX ESET 域名规则集（当前仅使用 MRS） | 中国大陆网络选择 `DIRECT`；境外按需选择中国大陆出口 |
| 苹果定位 | `gspe1-ssl.ls.apple.com` 及其子域名 | 按需选择，独立于 GG-WFC |
| Meta 服务 | Facebook、Instagram、Messenger、WhatsApp、Threads 等域名，以及 Facebook IP 网段。[域名清单](https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/meta.list) · [IP 清单](https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/facebook.list) | 按需选择 |
| Line 服务 | LINE 上游 MRS，并补充 `linebiz.com` 及其子域名。[补充 MRS](mmw/ruleset/tcscloud-seednet/line-tcscloud-seednet-avoid.mrs) | 按需选择 |

Meta 服务和 Line 服务排在社交媒体之前。单独勾选社交媒体时，Facebook 和 Instagram 仍可使用该组的出口。`Shopee 服务` 和 `Yahoo 服务` 可以单独勾选，各自选择出口。

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

发布时将 `mmw/` 推送到 GitHub 的 `main` 分支。目录迁移后，在妙妙屋更新分组清单源地址，再重新同步清单并生成或更新订阅。 [分组清单源地址](https://raw.githubusercontent.com/tgr989/AIprofile/refs/heads/main/mmw/proxy_groups/proxy_groups.json)

所有规则集下载 URL 均统一使用 `raw.githubusercontent.com` 的原始地址，减少重定向且不附加第三方代理前缀。

在妙妙屋重新同步分组清单并生成订阅，再在客户端更新订阅和规则提供方。`withpersona.com`、`frompersona.com`、`yoti.com` 及其子域由 `RULE-SET,claude-domain,AI 服务` 匹配。 [Claude 域名清单](mmw/ruleset/claude/domain-claude.list)

确认最终配置包含 `claude-domain`、`claude`、`claude-ip` 三个提供方及各自的 `RULE-SET`，其中 `claude-ip` 带 `no-resolve`。AI 域名规则排在 Google、云服务和通用代理规则之前，广告拦截继续优先。在客户端为 `AI 服务` 选择固定节点，并通过连接记录确认 Claude Code 的实际出口。

分组清单包含 37 个分组。清单开头为 **⚡ AI 节点 → 广告拦截 → AI 服务**。`TCSCloud 分流` 可单独勾选。[妙妙屋官方默认清单](https://github.com/iluobei/miaomiaowu/blob/main/proxy_groups/proxy-groups-lite.json)

**苹果服务 → 微软服务 → 云服务** 三组相邻，随后是 **私有网络 → TMO-WFC → GG-WFC → PT 站点 → PT Tracker → ESET → 哔哩哔哩 → 国内服务 → 电报消息**。两个 Wi-Fi Calling 分组紧随私有网络。PT 站点先于 PT Tracker，两者均先于国内服务。

社交媒体之后依次是 **Tiktok → Spotify → 流媒体**。清单末尾为 **Yahoo 服务 → Shopee 服务 → TCSCloud 分流 → 代理媒体 → 代理服务 → 非中国**。手动勾选分组或编辑已有订阅时，还需核对最终配置中的顺序。
