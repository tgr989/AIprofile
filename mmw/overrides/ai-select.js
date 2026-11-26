// 妙妙屋覆写脚本：转换为客户端配置前（post_fetch）。
const legacyAiName = "⚡ AI 节点";
const legacyNodeSelectionName = "🚀 节点选择";
const groupRenames = new Map([
  [legacyNodeSelectionName, "PROXY"],
  ["🐟 漏网之鱼", "FINAL"],
  ["♻️ 自动选择", "AUTO"],
  [legacyAiName, "AI"]
]);
const rulesWithTrailingTarget = new Set([
  "NOT", "OR", "AND", "DOMAIN-REGEX", "PROCESS-NAME-REGEX", "PROCESS-PATH-REGEX"
]);
const defaultPolicies = new Map([
  ["广告拦截", "REJECT"],
  ["国内服务", "DIRECT"],
  ["私有网络", "DIRECT"]
]);
const aiDefaultGroups = new Set(["AI 服务", "谷歌服务", "苹果服务", "云服务"]);

function main(config) {
  const groups = config["proxy-groups"];
  if (!Array.isArray(groups)) return config;

  const groupsByName = new Map(groups.map(group => [group.name, group]));
  const aiGroup = groupsByName.get("AI") || groupsByName.get(legacyAiName);
  const nodeSelectionGroups = [groupsByName.get("PROXY"), groupsByName.get(legacyNodeSelectionName)]
    .filter(Boolean);
  renameGroups(config, groupsByName);

  const aiName = aiGroup && aiGroup.name;
  const aiUpstreams = aiGroup ? collectAiUpstreams(config, groups, aiName) : new Set();
  if (aiGroup) stripAiCycles(groups, aiUpstreams, aiName);
  const [nodeSelection] = nodeSelectionGroups;
  if (aiGroup && nodeSelection) {
    groups.splice(groups.indexOf(aiGroup), 1);
    groups.splice(groups.indexOf(nodeSelection) + 1, 0, aiGroup);
    insertAiCandidates(groups, aiUpstreams, nodeSelectionGroups.map(group => group.name), aiName);
  }

  applyDefaultPolicies(groups);
  if (aiGroup) applyAiDefaults(groups, aiUpstreams, aiName);
  return config;
}

function renameGroups(config, groupsByName) {
  const proxies = Array.isArray(config.proxies) ? config.proxies : [];
  const proxyNames = new Set(proxies.map(proxy => proxy.name));
  const renames = new Map();
  for (const [oldName, newName] of groupRenames) {
    if (proxyNames.has(oldName) || proxyNames.has(newName)) continue;
    // 已改名的组也可能留有旧引用。两组并存时分别保留。
    if (groupsByName.has(oldName) !== groupsByName.has(newName)) {
      renames.set(oldName, newName);
    }
  }
  if (!renames.size) return;

  const rename = name => renames.get(name) || name;
  function renameField(entry, key) {
    if (entry && renames.has(entry[key])) entry[key] = rename(entry[key]);
  }

  for (const group of groupsByName.values()) {
    group.name = rename(group.name);
    if (Array.isArray(group.proxies)) group.proxies = group.proxies.map(rename);
    renameField(group, "default-selected");
    renameField(group, "empty-fallback");
  }

  for (const proxy of proxies) renameField(proxy, "dialer-proxy");
  for (const provider of Object.values(config["proxy-providers"] || {})) {
    renameField(provider, "proxy");
    renameField(provider, "dialer-proxy");
    renameField(provider.override, "dialer-proxy");
    if (Array.isArray(provider.payload)) {
      for (const proxy of provider.payload) renameField(proxy, "dialer-proxy");
    }
  }
  for (const provider of Object.values(config["rule-providers"] || {})) {
    renameField(provider, "proxy");
  }

  const renameRule = rule => renameRuleTarget(rule, rename);
  if (Array.isArray(config.rules)) config.rules = config.rules.map(renameRule);
  const subRules = config["sub-rules"] || {};
  for (const [name, rules] of Object.entries(subRules)) {
    if (Array.isArray(rules)) subRules[name] = rules.map(renameRule);
  }
}

function renameRuleTarget(rule, rename) {
  if (typeof rule !== "string") return rule;
  const parts = rule.split(",");
  const type = parts[0].trim().toUpperCase();
  if (parts.length < 2 || type === "SUB-RULE") return rule;

  let targetIndex = 2;
  if (type === "MATCH") targetIndex = 1;
  if (rulesWithTrailingTarget.has(type)) targetIndex = parts.length - 1;
  if (targetIndex >= parts.length) return rule;

  const target = parts[targetIndex].trim();
  const newName = rename(target);
  if (newName === target) return rule;
  parts[targetIndex] = parts[targetIndex].replace(target, newName);
  return parts.join(",");
}

function collectAiUpstreams(config, groups, aiName) {
  const proxies = Array.isArray(config.proxies) ? config.proxies : [];
  const proxyNames = proxies.map(proxy => proxy.name);
  const providers = new Map(Object.entries(config["proxy-providers"] || {}));
  const providerNames = Array.from(providers.keys());
  const edges = new Map();
  function addEdge(from, to) {
    if (!to || to === aiName) return;
    if (!edges.has(from)) edges.set(from, []);
    edges.get(from).push(to);
  }

  for (const group of groups) {
    const all = Boolean(group["include-all"]);
    for (const member of membersOf(group)) addEdge(group.name, member);
    if (all || group["include-all-proxies"]) {
      for (const name of proxyNames) addEdge(group.name, name);
    }
    const used = all || group["include-all-providers"]
      ? providerNames
      : (Array.isArray(group.use) ? group.use : []);
    for (const key of used) addEdge(group.name, providers.get(key));
    addEdge(group.name, group["empty-fallback"]);
  }

  for (const proxy of proxies) addEdge(proxy.name, proxy["dialer-proxy"]);
  for (const provider of providers.values()) {
    const override = provider.override || {};
    const dialer = override["dialer-proxy"] || provider["dialer-proxy"];
    if (dialer) addEdge(provider, dialer);
    if (Array.isArray(provider.payload)) {
      for (const proxy of provider.payload) addEdge(provider, proxy["dialer-proxy"]);
    }
  }

  const seen = new Set([aiName]);
  for (const item of seen) {
    for (const next of edges.get(item) || []) seen.add(next);
  }
  return seen;
}

function stripAiCycles(groups, aiUpstreams, aiName) {
  for (const group of groups) {
    if (!aiUpstreams.has(group.name)) continue;
    const members = membersOf(group);
    if (!members.includes(aiName)) continue;

    const filtered = members.filter(name => name !== aiName);
    if (!filtered.length && !hasDynamicSources(group)) filtered.push("DIRECT");
    group.proxies = filtered;
    if (group["default-selected"] === aiName) delete group["default-selected"];
  }
}

function insertAiCandidates(groups, aiUpstreams, nodeSelectionNames, aiName) {
  for (const group of groups) {
    if (!isSelectGroup(group) || aiUpstreams.has(group.name)) continue;
    const members = membersOf(group);
    const nodeSelectionName = nodeSelectionNames.find(name => members.includes(name));
    if (!nodeSelectionName) continue;

    const candidates = members.filter(name => name !== aiName);
    candidates.splice(candidates.indexOf(nodeSelectionName) + 1, 0, aiName);
    group.proxies = candidates;
  }
}

function applyDefaultPolicies(groups) {
  for (const group of groups) {
    const policy = defaultPolicies.get(group.name);
    if (!isSelectGroup(group) || !policy) continue;

    group.proxies = [...new Set([policy, ...membersOf(group)])];
    group["default-selected"] = policy;
  }
}

function applyAiDefaults(groups, aiUpstreams, aiName) {
  for (const group of groups) {
    if (!isSelectGroup(group) || !aiDefaultGroups.has(group.name) || aiUpstreams.has(group.name)) continue;

    const members = membersOf(group);
    group.proxies = members.includes(aiName) ? [...new Set(members)] : [aiName, ...members];
    group["default-selected"] = aiName;
  }
}

function hasDynamicSources(group) {
  return Boolean(
    (Array.isArray(group.use) && group.use.length) ||
    group["include-all"] ||
    group["include-all-proxies"] ||
    group["include-all-providers"]
  );
}

function isSelectGroup(group) {
  return Boolean(group && group.type === "select");
}

function membersOf(group) {
  return Array.isArray(group.proxies) ? group.proxies : [];
}
