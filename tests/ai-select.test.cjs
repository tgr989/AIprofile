const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const script = fs.readFileSync(path.join(__dirname, "../mmw/overrides/ai-select.js"), "utf8");
const override = vm.runInNewContext(script + "\nmain");
const ai = "⚡ AI 节点";
const nodeSelection = "🚀 节点选择";

function selectGroup(name, proxies) {
  return { name, type: "select", proxies };
}

function configAfter(config) {
  const result = structuredClone(override(config));
  assert.deepEqual(structuredClone(override(structuredClone(result))), result);
  return result;
}

function groupsAfter(config) {
  return Object.fromEntries(configAfter(config)["proxy-groups"].map(group => [group.name, group]));
}

test("AI 组移到节点选择的紧前一位", () => {
  for (const names of [
    ["前置组", nodeSelection, "后续组", ai],
    [ai, "前置组", nodeSelection, "后续组"]
  ]) {
    const result = configAfter({
      "proxy-groups": names.map(name => selectGroup(name, ["DIRECT"]))
    });
    assert.deepEqual(result["proxy-groups"].map(group => group.name), [
      "前置组", ai, nodeSelection, "后续组"
    ]);
  }
});

test("有节点选择的组将 AI 候选移到它前面并去重", () => {
  const groups = groupsAfter({
    proxies: [{ name: "固定节点" }],
    "proxy-groups": [
      selectGroup(ai, ["固定节点", nodeSelection]),
      selectGroup(nodeSelection, ["固定节点"]),
      {
        ...selectGroup("AI 服务", ["DIRECT", ai, "固定节点", nodeSelection, ai, "REJECT"]),
        "default-selected": "固定节点"
      },
      selectGroup("TMO-WFC", [nodeSelection, "DIRECT"]),
      { name: "筛选测速组", type: "url-test", proxies: [nodeSelection], filter: "固定" },
      selectGroup("固定出口组", ["固定节点", "DIRECT"]),
      { name: "代理集合组", type: "select", use: ["订阅"] }
    ]
  });
  assert.deepEqual(groups[ai].proxies, ["固定节点", nodeSelection]);
  assert.deepEqual(groups["AI 服务"].proxies, ["DIRECT", "固定节点", ai, nodeSelection, "REJECT"]);
  assert.equal(groups["AI 服务"]["default-selected"], "固定节点");
  assert.deepEqual(groups["TMO-WFC"].proxies, [ai, nodeSelection, "DIRECT"]);
  assert.deepEqual(groups["筛选测速组"].proxies, [ai, nodeSelection]);
  assert.deepEqual(groups["固定出口组"].proxies, ["固定节点", "DIRECT"]);
  assert.deepEqual(groups["代理集合组"], { name: "代理集合组", type: "select", use: ["订阅"] });
});

test("三个直连组将 DIRECT 置顶设为默认，并按节点选择的位置加入 AI", () => {
  const groups = groupsAfter({
    "proxy-groups": [
      selectGroup(nodeSelection, ["DIRECT"]),
      selectGroup(ai, [nodeSelection]),
      { ...selectGroup("广告拦截", ["REJECT", nodeSelection, "DIRECT", "DIRECT"]), "default-selected": "REJECT" },
      selectGroup("国内服务", [nodeSelection]),
      selectGroup("私有网络", ["REJECT"])
    ]
  });
  for (const [name, expected] of [
    ["广告拦截", ["DIRECT", "REJECT", ai, nodeSelection]],
    ["国内服务", ["DIRECT", ai, nodeSelection]],
    ["私有网络", ["DIRECT", "REJECT"]]
  ]) {
    assert.deepEqual(groups[name].proxies, expected);
    assert.equal(groups[name]["default-selected"], "DIRECT");
  }
});

test("缺少 AI 组或节点选择组时仍设置直连默认项", () => {
  for (const present of [ai, nodeSelection]) {
    const groups = groupsAfter({
      "proxy-groups": [
        selectGroup(present, ["DIRECT"]),
        selectGroup("广告拦截", ["REJECT", present]),
        selectGroup("其他服务", [present])
      ]
    });
    assert.deepEqual(Object.keys(groups), [present, "广告拦截", "其他服务"]);
    assert.deepEqual(groups["广告拦截"].proxies, ["DIRECT", "REJECT", present]);
    assert.equal(groups["广告拦截"]["default-selected"], "DIRECT");
    assert.deepEqual(groups["其他服务"].proxies, [present]);
  }
});
