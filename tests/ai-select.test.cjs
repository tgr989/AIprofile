const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const script = fs.readFileSync(path.join(__dirname, "../mmw/overrides/ai-select.js"), "utf8");
const override = vm.runInNewContext(script + "\nmain");
const ai = "AI 节点组";

function node(name, dialer) {
  return { name, type: "socks5", server: "127.0.0.1", port: 1080, "dialer-proxy": dialer };
}

function groupsAfter(config) {
  const result = structuredClone(override(config));
  assert.deepEqual(structuredClone(override(structuredClone(result))), result);
  return Object.fromEntries(result["proxy-groups"].map(group => [group.name, group]));
}

function expressionProvider(expressions, dialer, payloadDialer) {
  return {
    type: "inline",
    payload: [node("订阅节点", payloadDialer)],
    override: { "dialer-proxy": dialer, "override-expr": expressions }
  };
}

test("三个专用手选组同时设置默认选项并保留其余候选顺序", () => {
  const groups = groupsAfter({
    proxies: [node("普通节点")],
    "proxy-groups": [
      { name: "广告拦截", type: "select", proxies: ["DIRECT", "REJECT", "普通节点", "REJECT"], "default-selected": "DIRECT" },
      { name: "国内服务", type: "select", proxies: ["普通节点", "DIRECT"], "default-selected": "普通节点" },
      { name: "私有网络", type: "select", proxies: ["REJECT"] },
      { name: "其他服务", type: "select", proxies: ["普通节点", "DIRECT"], "default-selected": "普通节点" }
    ]
  });
  for (const [name, expected] of [
    ["广告拦截", ["REJECT", "DIRECT", "普通节点"]],
    ["国内服务", ["DIRECT", "普通节点"]],
    ["私有网络", ["DIRECT", "REJECT"]]
  ]) {
    assert.deepEqual(groups[name].proxies, expected);
    assert.equal(groups[name]["default-selected"], expected[0]);
  }
  assert.equal(groups["其他服务"]["default-selected"], "普通节点");
});

test("表达式的最终拨号目标参与集合与链式节点的循环检查", () => {
  const groups = groupsAfter({
    proxies: [node("链式节点", "入口"), node("普通节点")],
    "proxy-providers": {
      间接循环: expressionProvider(['.["dialer-proxy"] = "回到 AI"'], "DIRECT"),
      安全集合: expressionProvider(['.dialer-proxy = "AI 节点组"', '."dialer-proxy" = "安全中转"'], ai),
      删除拨号: expressionProvider(['del(.["dialer-proxy"])'], ai, ai),
      清空拨号: expressionProvider(['.dialer-proxy = ""'], undefined, ai),
      仅改名: expressionProvider(['.["name"] = "港 | " + .name', '.name = (.name | trim | upcase)', '.udp = true']),
      保留原拨号: expressionProvider(['del(.skip-cert-verify)', '.name = "新名称"'], undefined, ai)
    },
    "proxy-groups": [
      { name: "入口", type: "select", use: ["间接循环"] },
      { name: "回到 AI", type: "select", proxies: [ai, "普通节点"] },
      { name: "安全中转", type: "select", proxies: ["普通节点", "DIRECT"] }
    ]
  });
  assert.deepEqual(groups[ai].proxies, ["普通节点"]);
  assert.deepEqual(groups[ai].use, ["安全集合", "删除拨号", "清空拨号", "仅改名"]);
  assert.deepEqual(groups["安全中转"].proxies, ["普通节点", "DIRECT"]);
});

test("动态拨号和整节点改写会连带排除依赖集合的链式节点", () => {
  for (const expr of [
    '.dialer-proxy = .name',
    '.dialer-proxy = "\\(.name)"',
    '(select(.port == 1080) | .dialer-proxy) = "AI 节点组"',
    '.name = "节点" | .["dialer-proxy"] = "AI 节点组"',
    '. = . + {"dialer-proxy": "AI 节点组"}'
  ]) {
    const groups = groupsAfter({
      proxies: [node("链式节点", "入口"), node("普通节点")],
      "proxy-providers": {
        动态集合: expressionProvider([expr], "原中转"),
        最终指定: expressionProvider([expr, '.dialer-proxy = "DIRECT"'])
      },
      "proxy-groups": [
        { name: "入口", type: "select", use: ["动态集合"] },
        { name: "原中转", type: "select", proxies: ["普通节点", "DIRECT"] }
      ]
    });
    assert.deepEqual(groups[ai].proxies, ["普通节点"], expr);
    assert.deepEqual(groups[ai].use, ["最终指定"], expr);
    assert.deepEqual(groups["原中转"].proxies, ["普通节点", "DIRECT"], expr);
  }
});

test("只有动态拨号集合时已有的 AI 组回退到 REJECT", () => {
  const groups = groupsAfter({
    "proxy-providers": { 动态集合: expressionProvider(['.dialer-proxy = .name']) },
    "proxy-groups": [{ name: ai, type: "select", use: ["动态集合"] }]
  });
  assert.deepEqual(groups[ai], { name: ai, type: "select", proxies: ["REJECT"] });
});

for (const members of [{ use: ["中转订阅"] }, { "include-all-providers": true }, { "include-all": true }]) {
  test("排除通过集合回到 AI 的链式节点 " + JSON.stringify(members), () => {
    const groups = groupsAfter({
      proxies: [node("链式节点", "中转池"), node("普通节点")],
      "proxy-providers": {
        中转订阅: { type: "inline", payload: [node("上游")], override: { "dialer-proxy": ai } },
        独立订阅: { type: "inline", payload: [node("独立上游")] }
      },
      "proxy-groups": [
        { name: ai, type: "select", proxies: ["普通节点"] },
        { name: "中转池", type: "select", proxies: ["普通节点"], ...members },
        { name: "AI 服务", type: "select", proxies: ["普通节点"] }
      ]
    });
    assert.deepEqual(groups[ai].proxies, ["普通节点"]);
    assert.deepEqual(groups[ai].use, ["独立订阅"]);
    assert.deepEqual(groups["中转池"].proxies, ["普通节点"]);
    assert.equal(groups["AI 服务"].proxies[0], ai);
  });
}

test("集合中的拨号依赖、显式覆写和同名出站分别处理", () => {
  const payload = [node("订阅节点", ai)];
  const groups = groupsAfter({
    proxies: [node("同名"), node("链式节点", "安全池")],
    "proxy-providers": {
      同名: { type: "inline", payload },
      独立订阅: { type: "inline", payload, "dialer-proxy": ai, override: { "dialer-proxy": "" } },
      级联订阅: { type: "inline", payload: [node("上游", "中转池")] }
    },
    "proxy-groups": [
      { name: "中转池", type: "select", use: ["同名"] },
      { name: "安全池", type: "select", proxies: ["同名"], use: ["独立订阅"] }
    ]
  });
  assert.deepEqual(groups[ai].proxies, ["同名", "链式节点"]);
  assert.deepEqual(groups[ai].use, ["独立订阅"]);
  assert.deepEqual(groups["安全池"].proxies, ["同名"]);
});

test("自动引入的静态节点也参与拨号检查", () => {
  const groups = groupsAfter({
    proxies: [node("借用节点池", "节点池"), node("借用 AI", ai), node("普通节点")],
    "proxy-groups": [{ name: "节点池", type: "select", "include-all-proxies": true }]
  });
  assert.deepEqual(groups[ai].proxies, ["普通节点"]);
});

test("共享中转路径的判断与节点声明顺序无关", () => {
  const chained = [node("甲节点", "甲池"), node("乙节点", "乙池")];
  for (const ordered of [chained, chained.slice().reverse()]) {
    const groups = groupsAfter({
      proxies: [...ordered, node("普通节点")],
      "proxy-providers": {
        中转订阅: { type: "inline", payload: [node("上游", "甲池")] }
      },
      "proxy-groups": [
        { name: ai, type: "select", proxies: ["普通节点"] },
        { name: "甲池", type: "select", proxies: ["普通节点", "乙池", ai] },
        { name: "乙池", type: "select", use: ["中转订阅"] }
      ]
    });
    assert.deepEqual(groups[ai].proxies, ["普通节点"]);
    assert.equal(groups[ai].use, undefined);
  }
});

test("修复已有 AI 组的循环时保留可用候选，再无可用候选时拒绝连接", () => {
  for (const saved of [[], ["DIRECT", "REJECT"]]) {
    const groups = groupsAfter({
      proxies: [node("链式节点", "中转池")],
      "proxy-providers": { 中转订阅: { type: "inline", payload: [node("上游", ai)] } },
      "proxy-groups": [
        { name: ai, type: "select", proxies: ["链式节点", ...saved], "include-all": true },
        { name: "中转池", type: "select", use: ["中转订阅"] },
        { name: "其他服务", type: "select", proxies: ["链式节点", "DIRECT"] }
      ]
    });
    assert.deepEqual(groups[ai], { name: ai, type: "select", proxies: saved.length ? saved : ["REJECT"] });
    assert.deepEqual(groups["其他服务"].proxies, ["链式节点", "DIRECT"]);
  }
});
