import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { chromium } = require("/Users/mccree/gstack/node_modules/playwright");

const baseUrl = process.env.AGENTPING_SITE_URL || "http://127.0.0.1:8088";

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function pageText(page) {
  return page.locator("body").innerText();
}

async function checkPage(page, path, expectedTexts) {
  await page.goto(`${baseUrl}/${path}`, { waitUntil: "networkidle" });
  const text = await pageText(page);
  for (const expected of expectedTexts) {
    assert(text.includes(expected), `${path} missing text: ${expected}`);
  }
  const navCount = await page.locator(".nav-links a").count();
  assert(navCount === 4, `${path} should have 4 nav links`);
  assert(await page.locator(".brand-logo").count() === 1, `${path} should show TranFu brand logo`);
  assert(await page.locator("link[rel='manifest'][href='site.webmanifest']").count() === 1, `${path} should link manifest`);
  assert(await page.locator("link[rel='apple-touch-icon']").count() === 1, `${path} should link apple touch icon`);
  const ogImage = await page.locator("meta[property='og:image']").getAttribute("content");
  assert(ogImage === "https://tranfu.com/brand/logo/social/og-image-1200x630.png", `${path} should use TranFu social preview image`);
  const twitterImage = await page.locator("meta[name='twitter:image']").getAttribute("content");
  assert(twitterImage === ogImage, `${path} should sync twitter image with og image`);
  assert(await page.locator(".motion-item").count() > 0, `${path} should initialize motion targets`);
}

const browser = await chromium.launch({ headless: true });

try {
  const desktop = await browser.newPage({ viewport: { width: 1440, height: 1000 } });

  await checkPage(desktop, "index.html", ["Ageng网络医生", "下载监控工具", "现在还能不能跑 Agent", "你现在可能要做的 3 件事"]);
  await desktop.screenshot({ path: "/private/tmp/agentping-home-desktop.png", fullPage: true });

  await checkPage(desktop, "tool.html", ["下载 Ageng网络医生", "下载菜单栏工具", "它会看哪些链路", "复制诊断报告", "下一版会重点打磨"]);
  await desktop.screenshot({ path: "/private/tmp/agentping-tool-desktop.png", fullPage: true });
  const downloadResponse = await desktop.request.get(`${baseUrl}/downloads/AgentPing.app.zip`);
  assert(downloadResponse && downloadResponse.ok(), "download zip should be reachable");

  await checkPage(desktop, "articles.html", ["Claude Code 一直没输出", "OpenAI 能用，Claude 不行", "Codex 卡住时", "Cursor 换模型后表现不一样"]);
  await desktop.screenshot({ path: "/private/tmp/agentping-articles-desktop.png", fullPage: true });

  await desktop.goto(`${baseUrl}/vpn.html`, { waitUntil: "networkidle" });
  let text = await pageText(desktop);
  assert(text.includes("输入团队访问码"), "VPN page should show access gate");
  assert(!text.includes("团队 VPS"), "VPN details should be hidden before access");
  await desktop.locator("input[aria-label='访问码']").fill("wrong-code");
  await desktop.locator("button[type='submit']").click();
  text = await pageText(desktop);
  assert(text.includes("访问码不正确"), "VPN page should reject wrong code");
  await desktop.locator("input[aria-label='访问码']").fill("agentping-team");
  await desktop.locator("button[type='submit']").click();
  await desktop.waitForTimeout(300);
  text = await pageText(desktop);
  assert(text.includes("团队 VPS"), "VPN details should appear after access");
  assert(text.includes("Tokyo Agent 01"), "VPN page should show team node cards");
  assert(text.includes("新成员按这 4 步接入"), "VPN page should show onboarding steps");
  assert(text.includes("Clash Verge Rev"), "VPN page should show Clash download channels");
  await desktop.screenshot({ path: "/private/tmp/agentping-vpn-unlocked.png", fullPage: true });

  const mobile = await browser.newPage({ viewport: { width: 390, height: 844 } });
  for (const path of ["index.html", "tool.html", "vpn.html", "articles.html"]) {
    await mobile.goto(`${baseUrl}/${path}`, { waitUntil: "networkidle" });
    const overflow = await mobile.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    assert(!overflow, `mobile ${path} should not overflow horizontally`);
    if (path === "index.html") {
      await mobile.screenshot({ path: "/private/tmp/agentping-home-mobile.png", fullPage: true });
    }
  }

  console.log(JSON.stringify({
    ok: true,
    screenshots: [
      "/private/tmp/agentping-home-desktop.png",
      "/private/tmp/agentping-tool-desktop.png",
      "/private/tmp/agentping-articles-desktop.png",
      "/private/tmp/agentping-vpn-unlocked.png",
      "/private/tmp/agentping-home-mobile.png"
    ]
  }, null, 2));
} finally {
  await browser.close();
}
