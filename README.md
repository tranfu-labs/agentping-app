# Ageng网络医生

Ageng网络医生是给 Codex、Claude Code、Cursor 等 AI Agent 使用者准备的网络状态监测与诊断工具。Agent 一直没反应时，它先帮用户判断是 API 链路、代理规则、出口节点，还是工具本身卡住。

项目内部工具名保留为 `AgentPing`，用于命令、macOS App 文件名和安装包文件名。

官网域名规划：

```text
https://agentping-app.tranfu.com/
```

GitHub 仓库：

```text
https://github.com/tranfu-labs/agentping-app
```

## 项目内容

```text
website/                     官网静态页面
website/downloads/           官网下载文件
agentping.py                 命令行网络诊断工具
agentping                    命令行入口
Sources/AgentPingMenu/       macOS 菜单栏工具源码
Scripts/package_app.sh       macOS App 打包脚本
Scripts/verify_website.mjs   官网自动检查脚本
Assets/AgentPingIcon.icns    macOS App 图标
```

## 本地预览官网

```bash
python3 -m http.server 8088 --directory website
```

打开：

```text
http://127.0.0.1:8088/index.html
```

官网包含：

- 首页：产品完整说明。
- 工具说明页：工具介绍和下载入口。
- 团队网络页：访问验证后查看 VPN 信息和 Clash 下载渠道。
- 常见文章页：网络问题说明文章。

团队网络页当前演示访问码：

```text
agentping-team
```

## 本地检查官网

先启动本地预览服务，再运行：

```bash
node Scripts/verify_website.mjs
```

如果检查线上域名：

```bash
AGENTPING_SITE_URL=https://agentping-app.tranfu.com node Scripts/verify_website.mjs
```

检查内容包括页面关键文案、导航、品牌图、下载文件、VPN 访问码流程和手机端横向溢出。

## 官网部署文档

官网是纯静态页面，部署时把 `website/` 作为站点根目录即可。

Cloudflare Pages 推荐配置：

```text
Project name: agentping-app
Production branch: main
Build command: 留空
Build output directory: website
Root directory: 留空
```

Vercel 推荐配置：

```text
Framework Preset: Other
Root Directory: website
Build Command: 留空
Output Directory: .
```

Netlify 推荐配置：

```text
Base directory: website
Build command: 留空
Publish directory: website
```

域名绑定：

1. 在部署平台添加自定义域名 `agentping-app.tranfu.com`。
2. 按平台提示在 DNS 中添加 CNAME 记录。
3. 等证书签发完成后，访问 `https://agentping-app.tranfu.com/`。
4. 运行线上检查命令确认首页、下载入口和团队网络页都能正常打开。

## 命令行工具

运行一次检查：

```bash
./agentping check
```

查看详细结果：

```bash
./agentping check --verbose
```

增加自定义目标：

```bash
./agentping check --target "Claude=api.anthropic.com" --target "OpenAI=api.openai.com"
```

也可以直接用 Python 运行：

```bash
python3 agentping.py check
```

## macOS 菜单栏工具

开发构建：

```bash
swift build
.build/debug/AgentPingMenu
```

验证菜单栏程序能读取诊断结果：

```bash
.build/debug/AgentPingMenu --diagnose-once
```

打包成可双击启动的 App：

```bash
sh Scripts/package_app.sh
open dist/AgentPing.app
```

重新生成下载压缩包：

```bash
ditto -c -k --sequesterRsrc --keepParent dist/AgentPing.app website/downloads/AgentPing.app.zip
```

退出方式：点开菜单栏里的 Ageng网络医生，选择“退出 Ageng网络医生”。

## 发布流程

发布前先重新打包并检查：

```bash
swift build -c release
sh Scripts/package_app.sh
ditto -c -k --sequesterRsrc --keepParent dist/AgentPing.app website/downloads/AgentPing.app.zip
dist/AgentPing.app/Contents/MacOS/AgentPingMenu --diagnose-once
python3 -m http.server 8088 --directory website
node Scripts/verify_website.mjs
```

创建 tag 和 GitHub Release，下面的版本号按当次发布替换：

```bash
git tag -a v0.1.1 -m "Ageng网络医生 v0.1.1"
git push origin main --tags
gh release create v0.1.1 website/downloads/AgentPing.app.zip --repo tranfu-labs/agentping-app --title "Ageng网络医生 v0.1.1" --notes-file RELEASE_NOTES.md --latest
```

发布后核验：

```bash
gh release list --repo tranfu-labs/agentping-app --limit 5
gh release view v0.1.1 --repo tranfu-labs/agentping-app --json name,tagName,isPrerelease,assets,url
```

## 产品方案

完整产品方案见：

```text
AgentPing-产品方案.md
```

后续三个模块细化见：

```text
AgentPing-后续模块细化.md
```
