# Changelog

## Unreleased

- 增加 Windows Install、Customize、Start、Verify、Restore 五个入口。
- 增加 Microsoft Store/MSIX 包与 Codex 自身 Node.js 运行时身份校验。
- 增加基于 System.Drawing 的本地图片归一化和自动、部分、完整配色覆盖。
- 增加 Windows 静态/隔离测试、真机适配报告和谨慎部署指南。
- 增加逐级 reparse 防护、跨 Session 的当前用户 `Global` 互斥、同句柄温和/强制进程处理，以及可重试的选择性配置恢复。
- 增加配置与快捷方式 CAS、`pending`/`active` 备份所有权协议、中断安装/主题目录恢复、严格 UTF-8 子进程输出和安全的示例主题重置边界。
- 修复 Windows 新建对话页 composer 被 flex 自动外边距压缩的问题，并让 Verify 检查编辑区宽度、滚动宽度和控件边界。
- 修复 Windows PowerShell 5.1 无参数入口与已有快捷方式重装校验的空数组兼容问题。
- 对 Windows 上经过预期哈希复核的瞬时 `EPERM`/`EACCES`/`EBUSY` 原子重命名增加有界重试。

## 1.0.1 — 2026-07-17

- 修复部分 macOS 上安装器误报“The injector launchd job did not start”的启动竞态。
- 移除 `launchctl submit` 后多余的强制重启，避免触发 `launchd` 节流。
- 增加回归检查，防止后续再引入同类问题。

## 1.0.0 — 2026-07-15

- 发布 macOS 通用主题制作器，而不是固定角色皮肤。
- 加入 Finder 选图、自动 JPEG 转换、主题命名和高级配色参数。
- 主页使用独立横幅，任务页使用背景与磨砂层，完整保留原生交互。
- 改为复用并验证 Codex 官方签名 Node.js，不再附带大型运行时或依赖全局 Node。
- 增加独立安装目录、桌面启动/定制/验证/恢复入口。
- 增加官方签名、CDP 端口归属、PID 身份、刷新重注入和真实 DOM 自检。
- 增加原子配置备份、精确恢复、静态测试、安装恢复循环和发布打包脚本。
- 移除第三方角色示例，改为可复现的“晨雾”和“暖沙”抽象渐变主题。
