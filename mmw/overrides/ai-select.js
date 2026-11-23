// 妙妙屋覆写脚本：转换为客户端配置前（post_fetch）。
function main(config) {
  const aiName = "AI 节点组", mainName = "🚀 节点选择";
  const defaultPolicies = new Map([["广告拦截", "REJECT"], ["国内服务", "DIRECT"], ["私有网络", "DIRECT"]]);
  const excluded = new Set([
    ...defaultPolicies.keys(), "TMO-WFC", "GG-WFC", "PT 站点", "PT Tracker", "ESET", "苹果定位"
  ]);
  const builtins = new Set(["DIRECT", "REJECT", "REJECT-DROP", "REJECT-TINYGIF", "PASS", "COMPATIBLE"]);
  const { "proxy-groups": groups = [] } = config;
  if (!Array.isArray(groups)) return config;

  const membersOf = group => Array.isArray(group.proxies) ? group.proxies : [];
  const hasDynamicNodes = group => (group.use || []).length || group["include-all"] ||
    group["include-all-proxies"] || group["include-all-providers"];
  function prefer(group, policy) {
    group.proxies = [policy].concat(membersOf(group).filter(p => p !== policy));
  }
  for (const group of groups) {
    const policy = defaultPolicies.get(group.name);
    if (group.type === "select" && policy) {
      prefer(group, policy);
      group["default-selected"] = policy;
    }
  }

  const proxies = config.proxies || [];
  const proxyNames = proxies.map(p => p.name);
  if (proxyNames.includes(aiName)) return config;
  // 代理集合用对象标识，节点和组用名称标识。
  const providers = new Map(Object.entries(config["proxy-providers"] || {}));
  const providerNames = Array.from(providers.keys());
  if (!proxyNames.length && !providers.size) return config;

  let mainGroup = groups.find(g => g.name === mainName);
  const orderedGroups = groups.filter(g => g.name !== aiName && g.name !== mainName);
  if (mainGroup) {
    if (membersOf(mainGroup).includes(aiName)) {
      const choices = membersOf(mainGroup).filter(p => p !== aiName);
      if (!choices.length && !hasDynamicNodes(mainGroup)) choices.push("DIRECT");
      mainGroup = Object.assign({}, mainGroup, { proxies: choices });
    }
    orderedGroups.unshift(mainGroup);
  }

  const dependencies = new Map(), dependents = new Map();
  function link(source, target) {
    if (!target) return;
    if (!dependencies.has(source)) dependencies.set(source, []);
    if (!dependents.has(target)) dependents.set(target, []);
    dependencies.get(source).push(target);
    dependents.get(target).push(source);
  }
  function linkGroup(group) {
    const all = group["include-all"];
    membersOf(group).forEach(p => link(group.name, p));
    if (all || group["include-all-proxies"]) proxyNames.forEach(p => link(group.name, p));
    const use = all || group["include-all-providers"] ? providerNames : group.use || [];
    use.forEach(key => link(group.name, providers.get(key)));
    link(group.name, group["empty-fallback"]);
  }
  proxies.forEach(p => link(p.name, p["dialer-proxy"]));
  providers.forEach(provider => {
    const override = provider.override || {};
    // 从最后一条覆写往前读。动态改写可能指向 AI，确定的赋值会覆盖更早的拨号设置。
    const edits = [].concat(override["override-expr"] || []).reverse();
    for (const edit of edits) {
      const target = expressionDialer(edit);
      if (typeof target === "string") return link(provider, target);
      if (target === undefined) link(provider, aiName);
    }
    if (override["dialer-proxy"] != null) link(provider, override["dialer-proxy"]);
    else if (provider["dialer-proxy"]) link(provider, provider["dialer-proxy"]);
    else if (Array.isArray(provider.payload)) provider.payload.forEach(p => link(provider, p["dialer-proxy"]));
  });
  orderedGroups.forEach(linkGroup);

  // Set 迭代也会访问新加入的项，每个可达节点只展开一次。
  function reachable(edges, roots) {
    const seen = new Set(roots);
    for (const source of seen) {
      for (const target of edges.get(source) || []) seen.add(target);
    }
    return seen;
  }
  const usesAI = reachable(dependents, [aiName]);
  const nodes = proxyNames.filter(p => !usesAI.has(p));
  const sources = providerNames.filter(key => !usesAI.has(providers.get(key)));
  if (!nodes.length && !sources.length) {
    let existing = groups.find(g => g.name === aiName);
    if (!existing) return config;
    linkGroup(existing);
    if ((dependencies.get(aiName) || []).some(p => usesAI.has(p))) {
      const safe = membersOf(existing).filter(p => !usesAI.has(p) && (builtins.has(p) || dependencies.has(p)));
      existing = { name: aiName, type: "select", proxies: safe.length ? safe : ["REJECT"] };
    }
    config["proxy-groups"] = groups.map(g => {
      if (g.name === aiName) return existing;
      return g.name === mainName ? mainGroup : g;
    });
    return config;
  }

  const upstreams = reachable(dependencies, [mainName, ...proxyNames, ...providers.values()]);
  for (const group of orderedGroups) {
    if (group.type !== "select" || excluded.has(group.name) || upstreams.has(group.name)) continue;
    if (group.filter || group["exclude-filter"] || group["exclude-type"]) continue;
    const choices = membersOf(group);
    const dynamic = hasDynamicNodes(group);
    if (dynamic && !choices.length) continue;
    if (!dynamic && choices.length && choices.every(p => builtins.has(p))) continue;
    prefer(group, aiName);
  }
  const selector = { name: aiName, type: "select", proxies: nodes };
  if (sources.length) selector.use = sources;
  config["proxy-groups"] = [selector, ...orderedGroups];
  return config;
}

// 字符串指定上游（空串清除），null 保留上游，undefined 表示也可能改为 AI。
function expressionDialer(expression) {
  const expr = typeof expression === "string" ? expression.trim() : "";
  const remove = /^del\s*\(\s*(\.[^(),]+?)\s*\)$/.exec(expr);
  const edit = remove || /^(\.[^|=+*]+?)\s*(\|=|[+*-]?=)(?!=)\s*([\s\S]+)$/.exec(expr);
  if (!edit) return;
  const path = edit[1].replace(
    /^\.(?:"([\w-]+)"|\[\s*"([\w-]+)"\s*\])/, (_, quoted, indexed) => "." + (quoted || indexed)
  );
  if (path === ".dialer-proxy") {
    if (remove) return "";
    const literal = /^"([^"\\]*)"$/.exec(edit[3]);
    if (literal && (edit[2] === "=" || edit[2] === "|=")) return literal[1];
    return;
  }
  if (!/^\.(?!dialer-proxy\b)[a-z_][\w-]*(?:\.[\w-]+|\[\d*\])*$/i.test(path)) return;
  // 单次改写其他字段保留上游，顶层管道可能继续改写整个节点。
  let depth = 0;
  for (const ch of (edit[3] || "").replace(/"(?:\\[\s\S]|[^"\\])*"/g, "")) {
    if ("([{".includes(ch)) depth++;
    else if (")]}".includes(ch)) depth--;
    else if (ch === "|" && depth === 0) return;
  }
  return null;
}
