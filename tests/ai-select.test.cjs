const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const script = fs.readFileSync(path.join(__dirname, "../mmw/overrides/ai-select.js"), "utf8");
const override = vm.runInNewContext(script + "\nmain");
const ai = "AI";
const nodeSelection = "PROXY";

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

test("旧组名和已改名配置中的旧引用统一为 PROXY、FINAL、AUTO 和 AI", () => {
  const oldNames = ["🚀 节点选择", "⚡ AI 节点", "♻️ 自动选择", "🐟 漏网之鱼"];
  const [oldProxy, oldAi, oldAuto, oldFinal] = oldNames;
  const newNames = [nodeSelection, ai, "AUTO", "FINAL"];

  for (const [proxyName, aiName, autoName, finalName] of [oldNames, newNames]) {
    const result = configAfter({
      proxies: [{ name: "链式落地", "dialer-proxy": oldAuto }],
      "proxy-groups": [
        selectGroup(proxyName, ["DIRECT"]),
        { name: autoName, type: "url-test", proxies: ["DIRECT"] },
        {
          ...selectGroup(finalName, [oldProxy, oldAuto]),
          "default-selected": oldAuto,
          "empty-fallback": oldAuto
        },
        selectGroup(aiName, ["DIRECT"])
      ],
      rules: [
        `IP-CIDR,203.0.113.0/24,${oldAi},no-resolve`,
        `AND,((NETWORK,UDP),(DST-PORT,443)),${oldProxy}`,
        `SUB-RULE,(NETWORK,tcp),${oldFinal}`,
        `MATCH, ${oldFinal}`
      ],
      "sub-rules": { [oldFinal]: [`MATCH,${oldAuto}`] }
    });

    assert.deepEqual(result["proxy-groups"].map(group => group.name), newNames);
    assert.deepEqual(result["proxy-groups"][3], {
      ...selectGroup("FINAL", [nodeSelection, ai, "AUTO"]),
      "default-selected": "AUTO",
      "empty-fallback": "AUTO"
    });
    assert.equal(result.proxies[0]["dialer-proxy"], "AUTO");
    assert.deepEqual(result.rules, [
      "IP-CIDR,203.0.113.0/24,AI,no-resolve",
      "AND,((NETWORK,UDP),(DST-PORT,443)),PROXY",
      `SUB-RULE,(NETWORK,tcp),${oldFinal}`,
      "MATCH, FINAL"
    ]);
    assert.deepEqual(result["sub-rules"], { [oldFinal]: ["MATCH,AUTO"] });
  }
});

test("新组名被节点占用时继续使用原 AI 组", () => {
  const oldAi = "⚡ AI 节点";
  const groups = groupsAfter({
    proxies: [{ name: ai }],
    "proxy-groups": [
      selectGroup(nodeSelection, ["DIRECT"]),
      selectGroup(oldAi, ["DIRECT"]),
      selectGroup("AI 服务", [nodeSelection])
    ]
  });
  assert.deepEqual(Object.keys(groups), [nodeSelection, oldAi, "AI 服务"]);
  assert.deepEqual(groups["AI 服务"].proxies, [nodeSelection, oldAi]);
  assert.equal(groups["AI 服务"]["default-selected"], oldAi);
});

test("新旧组并存时优先使用 AI，并在两种节点选择后补齐候选", () => {
  const oldAi = "⚡ AI 节点";
  const oldProxy = "🚀 节点选择";
  const groups = groupsAfter({
    "proxy-groups": [
      selectGroup(oldProxy, ["DIRECT"]),
      selectGroup(oldAi, ["DIRECT"]),
      selectGroup(nodeSelection, ["DIRECT"]),
      selectGroup("FINAL", [nodeSelection, "DIRECT"]),
      selectGroup("旧服务组", [oldProxy, "DIRECT"]),
      selectGroup("AI 服务", [oldProxy, nodeSelection]),
      selectGroup(ai, ["DIRECT"])
    ]
  });

  assert.deepEqual(Object.keys(groups), [oldProxy, oldAi, nodeSelection, ai, "FINAL", "旧服务组", "AI 服务"]);
  assert.deepEqual(groups.FINAL.proxies, [nodeSelection, ai, "DIRECT"]);
  assert.deepEqual(groups["旧服务组"].proxies, [oldProxy, ai, "DIRECT"]);
  assert.deepEqual(groups["AI 服务"].proxies, [oldProxy, nodeSelection, ai]);
  assert.equal(groups["AI 服务"]["default-selected"], ai);
});

test("AI 组移到节点选择的紧后一位", () => {
  for (const names of [
    ["前置组", nodeSelection, "后续组", ai],
    [ai, "前置组", nodeSelection, "后续组"]
  ]) {
    const result = configAfter({
      "proxy-groups": names.map(name => selectGroup(name, ["DIRECT"]))
    });
    assert.deepEqual(result["proxy-groups"].map(group => group.name), [
      "前置组", nodeSelection, ai, "后续组"
    ]);
  }
});

test("有节点选择的 select 组将 AI 候选移到它后面并去重，跳过非 select 组", () => {
  const groups = groupsAfter({
    proxies: [{ name: "固定节点" }],
    "proxy-groups": [
      selectGroup(ai, ["固定节点", nodeSelection]),
      selectGroup(nodeSelection, ["固定节点"]),
      {
        ...selectGroup("其他服务", ["DIRECT", ai, "固定节点", nodeSelection, ai, "REJECT"]),
        "default-selected": "固定节点"
      },
      selectGroup("TMO-WFC", [nodeSelection, "DIRECT"]),
      { name: "筛选测速组", type: "url-test", proxies: [nodeSelection], filter: "固定" },
      { name: "故障转移组", type: "fallback", proxies: [nodeSelection, "DIRECT"] },
      selectGroup("固定出口组", ["固定节点", "DIRECT"]),
      { name: "代理集合组", type: "select", use: ["订阅"] }
    ]
  });
  assert.deepEqual(groups[ai].proxies, ["固定节点", nodeSelection]);
  assert.deepEqual(groups["其他服务"].proxies, ["DIRECT", "固定节点", nodeSelection, ai, "REJECT"]);
  assert.equal(groups["其他服务"]["default-selected"], "固定节点");
  assert.deepEqual(groups["TMO-WFC"].proxies, [nodeSelection, ai, "DIRECT"]);
  assert.deepEqual(groups["筛选测速组"].proxies, [nodeSelection]);
  assert.deepEqual(groups["故障转移组"].proxies, [nodeSelection, "DIRECT"]);
  assert.deepEqual(groups["固定出口组"].proxies, ["固定节点", "DIRECT"]);
  assert.deepEqual(groups["代理集合组"], { name: "代理集合组", type: "select", use: ["订阅"] });
});

test("广告拦截默认 REJECT，国内服务和私有网络默认 DIRECT，并按节点选择的位置加入 AI", () => {
  const groups = groupsAfter({
    "proxy-groups": [
      selectGroup(nodeSelection, ["DIRECT"]),
      selectGroup(ai, [nodeSelection]),
      { ...selectGroup("广告拦截", ["DIRECT", nodeSelection, "REJECT", "REJECT"]), "default-selected": "DIRECT" },
      selectGroup("国内服务", [nodeSelection]),
      selectGroup("私有网络", ["REJECT"])
    ]
  });
  for (const [name, expected, policy] of [
    ["广告拦截", ["REJECT", "DIRECT", nodeSelection, ai], "REJECT"],
    ["国内服务", ["DIRECT", nodeSelection, ai], "DIRECT"],
    ["私有网络", ["DIRECT", "REJECT"], "DIRECT"]
  ]) {
    assert.deepEqual(groups[name].proxies, expected);
    assert.equal(groups[name]["default-selected"], policy);
  }
});

test("四个服务组默认选择 AI 节点，缺少候选时前置补齐", () => {
  const groups = groupsAfter({
    "proxy-groups": [
      selectGroup(nodeSelection, ["DIRECT"]),
      selectGroup(ai, [nodeSelection]),
      { ...selectGroup("AI 服务", [nodeSelection, "DIRECT"]), "default-selected": nodeSelection },
      selectGroup("谷歌服务", [ai, "DIRECT", nodeSelection, ai]),
      selectGroup("苹果服务", ["DIRECT"]),
      { name: "云服务", type: "select", use: ["订阅"] }
    ]
  });
  for (const [name, expected] of [
    ["AI 服务", [nodeSelection, ai, "DIRECT"]],
    ["谷歌服务", ["DIRECT", nodeSelection, ai]],
    ["苹果服务", [ai, "DIRECT"]],
    ["云服务", [ai]]
  ]) {
    assert.deepEqual(groups[name].proxies, expected);
    assert.equal(groups[name]["default-selected"], ai);
  }
  assert.deepEqual(groups["云服务"].use, ["订阅"]);
});

test("默认策略独立生效，服务组默认项需要 AI 组", () => {
  for (const present of [ai, nodeSelection]) {
    const groups = groupsAfter({
      "proxy-groups": [
        selectGroup(present, ["DIRECT"]),
        selectGroup("广告拦截", ["DIRECT", present, "REJECT"]),
        selectGroup("其他服务", [present]),
        selectGroup("AI 服务", ["DIRECT"])
      ]
    });
    assert.deepEqual(Object.keys(groups), [present, "广告拦截", "其他服务", "AI 服务"]);
    assert.deepEqual(groups["广告拦截"].proxies, ["REJECT", "DIRECT", present]);
    assert.equal(groups["广告拦截"]["default-selected"], "REJECT");
    assert.deepEqual(groups["其他服务"].proxies, [present]);
    assert.deepEqual(groups["AI 服务"], present === ai
      ? { ...selectGroup("AI 服务", [ai, "DIRECT"]), "default-selected": ai }
      : selectGroup("AI 服务", ["DIRECT"]));
  }
});

test("排除 AI 上游分组与链式拨号依赖，并清理已有循环引用", () => {
  const groups = groupsAfter({
    proxies: [
      { name: "固定节点" },
      { name: "链式落地", "dialer-proxy": "前置入口" }
    ],
    "proxy-providers": {
      订阅集: { type: "http", override: { "dialer-proxy": "云服务" } }
    },
    "proxy-groups": [
      { ...selectGroup(nodeSelection, [ai]), "default-selected": ai },
      { ...selectGroup(ai, [ai, nodeSelection, "美国手选", "链式落地"]), use: ["订阅集"] },
      selectGroup("美国手选", [nodeSelection, "固定节点"]),
      selectGroup("前置入口", [nodeSelection, "DIRECT"]),
      { ...selectGroup("云服务", [ai, "固定节点"]), "default-selected": ai },
      selectGroup("AI 服务", [nodeSelection, "DIRECT"])
    ]
  });
  assert.deepEqual(groups[nodeSelection], selectGroup(nodeSelection, ["DIRECT"]));
  assert.deepEqual(groups[ai].proxies, [nodeSelection, "美国手选", "链式落地"]);
  assert.deepEqual(groups["美国手选"].proxies, [nodeSelection, "固定节点"]);
  assert.deepEqual(groups["前置入口"].proxies, [nodeSelection, "DIRECT"]);
  assert.deepEqual(groups["云服务"], selectGroup("云服务", ["固定节点"]));
  assert.deepEqual(groups["AI 服务"].proxies, [nodeSelection, ai, "DIRECT"]);
  assert.equal(groups["AI 服务"]["default-selected"], ai);
});
