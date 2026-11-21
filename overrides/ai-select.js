// 妙妙屋覆写脚本：转换为客户端配置前（post_fetch）。
function main(config) {
  var name = "🚀 AI 节点组";
  var mainName = "🚀 节点选择";
  var groups = config["proxy-groups"];
  if (groups === undefined) groups = [];
  if (!Array.isArray(groups)) return config;

  var proxies = config.proxies || [];
  var providers = config["proxy-providers"] || {};
  if (proxies.some(function(p) { return p.name === name; })) return config;

  function hasDynamicNodes(g) {
    return (g.use && g.use.length) || g["include-all"] ||
      g["include-all-proxies"] || g["include-all-providers"];
  }
  var mainGroup = groups.find(function(g) { return g.name === mainName; });
  var otherGroups = groups.filter(function(g) { return g.name !== name && g.name !== mainName; });
  if (mainGroup && Array.isArray(mainGroup.proxies) && mainGroup.proxies.indexOf(name) >= 0) {
    var candidates = mainGroup.proxies.filter(function(p) { return p !== name; });
    if (!candidates.length && !hasDynamicNodes(mainGroup)) candidates.push("DIRECT");
    mainGroup = Object.assign({}, mainGroup, { proxies: candidates });
  }

  // 记录通用选择器和链式拨号依赖的节点池，保留这些组原有的候选顺序。
  var dependencies = new Map();
  otherGroups.forEach(function(g) { dependencies.set(g.name, g.proxies || []); });
  if (mainGroup) dependencies.set(mainName, mainGroup.proxies || []);
  proxies.forEach(function(p) {
    if (p["dialer-proxy"]) dependencies.set(p.name, [p["dialer-proxy"]]);
  });
  var upstreams = new Map();
  function upstreamUsesAI(target) {
    if (target === name) return true;
    if (!dependencies.has(target)) return false;
    if (!upstreams.has(target)) {
      upstreams.set(target, false);
      dependencies.get(target).forEach(function(candidate) {
        if (upstreamUsesAI(candidate)) upstreams.set(target, true);
      });
    }
    return upstreams.get(target);
  }

  if (mainGroup) upstreamUsesAI(mainName);
  var nodes = proxies.filter(function(p) {
    return !upstreamUsesAI(p["dialer-proxy"]);
  }).map(function(p) { return p.name; });
  var sources = Object.keys(providers).filter(function(key) {
    var override = providers[key].override || {};
    return !upstreamUsesAI(override["dialer-proxy"]);
  });
  if (!nodes.length && !sources.length) return config;

  var selector = { name: name, type: "select", proxies: nodes };
  if (sources.length) selector.use = sources;

  var excluded = new Set([
    "🛑 广告拦截", "🏠 私有网络", "🔒 国内服务",
    "📶 TMO-WFC", "📶 GG-WFC", "🎞️ PT 站点", "🔗 PT Tracker",
    "🛡️ ESET", "📍 苹果定位"
  ]);
  var builtins = new Set(["DIRECT", "REJECT", "REJECT-DROP", "REJECT-TINYGIF", "PASS", "COMPATIBLE"]);
  otherGroups.forEach(function(g) {
    if (g.type !== "select" || excluded.has(g.name) || upstreams.has(g.name)) return;
    if (g.filter || g["exclude-filter"] || g["exclude-type"]) return;
    var candidates = Array.isArray(g.proxies) ? g.proxies : [];
    var dynamic = hasDynamicNodes(g);
    if (dynamic && !candidates.length) return;
    if (!dynamic && candidates.length && candidates.every(function(p) { return builtins.has(p); })) return;
    g.proxies = [name].concat(candidates.filter(function(p) { return p !== name; }));
  });

  var selectors = mainGroup ? [selector, mainGroup] : [selector];
  config["proxy-groups"] = selectors.concat(otherGroups);
  return config;
}
