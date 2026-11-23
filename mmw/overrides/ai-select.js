// 妙妙屋覆写脚本：转换为客户端配置前（post_fetch）。
const aiName = "⚡ AI 节点";
const nodeSelectionName = "🚀 节点选择";
const directGroups = new Set(["广告拦截", "国内服务", "私有网络"]);

function main(config) {
  const groups = config["proxy-groups"];
  if (!Array.isArray(groups)) return config;

  const aiGroup = groups.find(group => group.name === aiName);
  const nodeSelection = groups.find(group => group.name === nodeSelectionName);
  if (aiGroup && nodeSelection) {
    groups.splice(groups.indexOf(aiGroup), 1);
    groups.splice(groups.indexOf(nodeSelection), 0, aiGroup);
    insertAiCandidates(groups);
  }

  applyDirectDefaults(groups);
  return config;
}

function insertAiCandidates(groups) {
  for (const group of groups) {
    const members = membersOf(group);
    if (group.name === aiName || !members.includes(nodeSelectionName)) continue;

    const candidates = members.filter(name => name !== aiName);
    candidates.splice(candidates.indexOf(nodeSelectionName), 0, aiName);
    group.proxies = candidates;
  }
}

function applyDirectDefaults(groups) {
  for (const group of groups) {
    if (!directGroups.has(group.name)) continue;

    group.proxies = ["DIRECT", ...membersOf(group).filter(name => name !== "DIRECT")];
    group["default-selected"] = "DIRECT";
  }
}

function membersOf(group) {
  return Array.isArray(group.proxies) ? group.proxies : [];
}
