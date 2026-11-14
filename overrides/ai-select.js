// 妙妙屋覆写脚本：转换为客户端配置前（post_fetch）。
function main(config) {
  var name = "🚀 AI 选择";
  var groups = config["proxy-groups"];
  if (!Array.isArray(groups)) return config;

  // 收集实际节点及代理集合，不引用其他代理组。
  var nodes = (config.proxies || []).map(function(p) {
    return p.name;
  });
  var providers = Object.keys(config["proxy-providers"] || {});
  if (!nodes.length && !providers.length) return config;

  var selector = {
    name: name,
    type: "select",
    proxies: nodes
  };
  if (providers.length) selector.use = providers;

  // 更新或创建同名组，并放到广告拦截之前。
  var index = groups.findIndex(function(g) {
    return g.name === name;
  });
  if (index >= 0) groups.splice(index, 1);
  var adsIndex = groups.findIndex(function(g) {
    return g.name === "🛑 广告拦截";
  });
  var insertIndex = adsIndex >= 0 ? adsIndex : (index >= 0 ? index : 0);
  groups.splice(insertIndex, 0, selector);

  // 加入服务组候选，保留原有候选顺序。
  var targets = [
    "🤖 AI 服务",
    "🔍 谷歌服务",
    "🍏 苹果服务",
    "🌍 非中国",
    "🐟 漏网之鱼"
  ];
  groups.forEach(function(g) {
    if (targets.indexOf(g.name) < 0 || g.type !== "select") return;
    if (!Array.isArray(g.proxies)) g.proxies = [];
    if (g.proxies.indexOf(name) < 0) g.proxies.push(name);
  });

  return config;
}
