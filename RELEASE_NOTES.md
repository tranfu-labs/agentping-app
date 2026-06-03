# Ageng网络医生 v0.1.3

macOS 下载包修复版本，重点处理下载后提示“已损坏，无法打开”的问题。

## 内容

- 重新打包 macOS App，补上完整签名结构。
- 下载 zip 改为干净压缩包，去掉多余 macOS 元数据。
- 工具页补充 macOS 下载隔离导致打不开时的处理方式。
- 保留官网下载入口：`website/downloads/AgentPing.app.zip`。

## 部署

官网静态文件位于 `website/`，线上域名规划为：

```text
https://agentping-app.tranfu.com/
```
