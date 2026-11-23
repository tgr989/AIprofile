// 妙妙屋覆写脚本：转换为客户端配置前（post_fetch）。
const aiName = "⚡ AI 节点";
const nodeSelectionName = "🚀 节点选择";
const defaultPolicies = new Map([
  ["广告拦截", "REJECT"],
  ["国内服务", "DIRECT"],
  ["私有网络", "DIRECT"]
]);
const aiDefaultGroups = new Set(["AI 服务", "谷歌服务", "苹果服务", "云服务"]);

function main(config) {
  const groups = config["proxy-groups"];
  if (!Array.isArray(groups)) return config;

  const aiGroup = groups.find(group => group.name === aiName);
  const nodeSelection = groups.find(group => group.name === nodeSelectionName);
  const aiUpstreams = aiGroup ? collectAiUpstreams(config, groups) : new Set();

  if (aiGroup) stripAiCycles(groups, aiUpstreams);
  if (aiGroup && nodeSelection) {
    groups.splice(groups.indexOf(aiGroup), 1);
    groups.splice(groups.indexOf(nodeSelection) + 1, 0, aiGroup);
    insertAiCandidates(groups, aiUpstreams);
  }

  applyDefaultPolicies(groups);
  if (aiGroup) applyAiDefaults(groups, aiUpstreams);
  return config;
}

function collectAiUpstreams(config, groups) {
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

function stripAiCycles(groups, aiUpstreams) {
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

function insertAiCandidates(groups, aiUpstreams) {
  for (const group of groups) {
    if (!isSelectGroup(group) || aiUpstreams.has(group.name)) continue;
    const members = membersOf(group);
    if (!members.includes(nodeSelectionName)) continue;

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

function applyAiDefaults(groups, aiUpstreams) {
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
