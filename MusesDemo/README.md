# Muses iOS Demo

原生 SwiftUI、iOS 17+ 的端到端技术 Demo。实现范围依据：

- `../docs/Muses-Demo规格与验收.md`
- `../docs/Muses-技术架构与API契约.md`
- `../output/Muses-concept-ui/*.png`

## 已实现链路

`临时 Key → 商品图 → AI 商品事实 → 用户确认 → 生成图片 → 图片审核 → 异步 AI 动态 → 动态审核 → 小红书文案 → Live Photo / MP4 / 静态图 → 本地历史`

代码还覆盖逐字段商品事实确认、任务幂等键、不可变提示词重放、远端视频任务 ID 落盘、App 前后台轮询恢复、图片结果 URL 落盘与仅重试下载、下载失败与 Live Photo 失败降级、审核失败标签带入下一版本、Key 脱敏、本地项目删除。

## 打开工程

仓库已经包含 `MusesDemo.xcodeproj`，可直接用 Xcode 16+ 打开。`project.yml` 同时保留为可审阅、可重建的工程清单。根据全局 Apple 项目约定，Codex 没有执行工程生成、编译、依赖安装或模拟器/真机运行。

构建前请把 `PRODUCT_BUNDLE_IDENTIFIER` 改为自己的标识并选择签名 Team。

## 真实供应商配置

`MusesDemo/Resources/provider.config.json` 故意使用 `.invalid` 占位域名，且文本、视频模型为占位名。不要把 API Key 写入该文件。替换并校准：

- HTTPS `baseUrl` 和 `allowedHosts`
- 文本、图片、视频模型名
- 多参考图 multipart 字段
- 视频创建/查询路径、状态映射和结果路径
- 文本/图片/视频实际响应 JSONPath
- 结果 URL 是否为匿名签名地址；若下载需要鉴权，需在 Provider adapter 中配置专用请求
- 供应商是否真正支持 `Idempotency-Key`；不支持时不能把超时重试视为无重复计费风险

应用会阻止对占位地址测试连接，并允许进入“安全演示模式”。演示模式只用于体验 UI、状态、人工审核和文案编辑，不调用网络，也不会把示例媒体写入相册。注意：默认占位配置虽然允许 App 启动演示，但会被 Provider 客户端的严格校验拒绝，不能意外发出真实媒体请求。

## Xcode / 真机手工验收

- 用有效临时 Key 测试连接，确认无效 Key/额度不足不显示完整 Key。
- 用至少两种不同 SKU 各选 3–6 张图跑通完整链路。
- 图片/动态拒绝后确认返修只创建对应新任务；动态返修不重做已通过图片。
- 检查返修任务与同幂等键重试都重放任务绑定的同一份 PromptVersion。
- 在提交窗口和动态生成中分别强制终止并重启 App，确认残留 `submitting` 被归一化为 `submissionUnknown`，已有 `providerTaskID` 时只查询原任务。
- 确认生成图显示完整 3:4，无不必要裁切。
- 用错误画幅图片、有声/非 720p/超出 3–5 秒视频验证媒体规格门会拒绝进入审核。
- 在 Photos 验证 JPG、MP4，并长按播放有实况标志的 Live Photo。
- 拒绝相册权限，确认生成结果仍保留并给出可理解提示。
- 制造 Live Photo 配对失败，确认 MP4、静态图与文案仍可保存。
- 测试小红书已安装/未安装两种打开结果。
- 检查小屏 iPhone、Dynamic Type、VoiceOver 与“减少动态效果”。

真实 API、编译、签名、真机 Photos 以及小红书发布均尚未由 Codex 执行或验证。
