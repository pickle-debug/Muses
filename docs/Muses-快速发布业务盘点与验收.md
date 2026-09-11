# Muses 业务盘点与本次实现

## 修改前的实际能力

| 需求 | 仓库原状 | 代码依据 |
| --- | --- | --- |
| 页面导航 | 单条创作流程；无底部导航，首次进入设置页 | `Muses/App/AppRootView.swift`、`AppModel.swift` |
| 商品录入 | 照片选择、名称、卖点；识别后才持久化 | `Features/Product/ProductInputView.swift` |
| AI 商品识别 | 已接 OpenAI 风格文本接口，识别后逐项人工确认 | `Services/Provider/OpenAIStyleProviderClient.swift` |
| 图片、动态、文案 | 图片审核后强制先生成动态，再生成文案 | `AppModel.swift`、`Features/Review/ReviewViews.swift` |
| 结果导出 | 静态图、MP4、Live Photo、复制文案、唤起小红书人工发布 | `Features/Result/ResultViews.swift` |
| 本地记录 | 商品快照、任务、提示词、审核、导出记录 | `Domain/Models.swift`、`Services/Persistence/SnapshotStore.swift` |
| SKU 文件导入 | 没有 CSV/TSV/JSON 解析或批量导入 | 原规格明确排除批量导入 |
| 版本与销售跟进 | 没有可见的 V1/V2、帖子链接、数据历史和转化计算 | 原规格将帖子数据回填列为后续规划 |

## 本次实现

1. 四个普通 tab + 中间快速发布按钮：AI选品、我的商品、快速发布、销售跟进、个人设置。默认进入我的商品；中间快速发布按钮独立打开工作台。原生拖动实现与最新验收见 `Muses-原生TabBar拖动验收.md`。
2. 移除首次 API Key 拦截。先初始化本地存储，AI 配置缺失不阻挡本地业务。实际调用模型前提示配置。
3. 手动录入 SKU、名称、卖点，可无图片先保存；图片可从相册或文件添加。真实 AI 生成沿用至少 3 张参考图的限制。
4. 批量导入 UTF-8 CSV / TSV / JSON，最多 500 个 SKU、文件不超过 2 MB。必填 SKU、名称、卖点，重复 SKU 或无效格式整批拒绝，不覆盖已有商品。
5. 商品详情按 V1、V2 展示内容。一次完成一个版本后再升级，可填写优化方向；旧商品快照、生成内容和跟进数据保留。旧版本及已登记帖子的文案只读。
6. 图片审核通过可直接生成小红书文案；动态保留为可选入口。无动态也能单独保存图片。
7. 每版本登记一个帖子链接与发布时间，持续追加累计数据：浏览、赞、藏、评论、咨询、订单、成交额、备注。展示历史记录；转化率为订单数 ÷ 浏览量，零浏览显示「—」。
8. AI选品提供独立待开放页面；我的商品提供搜索和版本入口；个人设置承接已有 AI 服务配置。
9. 修复原素材文件保存时扩展名变为 `.bin` 的问题，并对新增商品图片验证格式与 30 MB 大小上限。

## 边界

- 尚无小红书登录、自动发布、平台数据自动同步或订单归因接口；使用保存素材 + 复制文案 + 人工发布，跟进数据由用户录入和核实。
- 文件导入包括商品资料，图片逐个补充；Excel 需导出 UTF-8 CSV，不直接解析 `.xlsx`。
- 当前每版生成 1 张图、3 个候选标题及正文/话题。预览版本明确标注，不用于真实帖子跟进。
- 本地存储沿用 schema 2，新增字段为可选，兼容旧数据。没有新增依赖。

## 验证

2026-09-11：Xcode 26.6，iOS Simulator Debug 构建通过。iPhone 17 Pro / iOS 26.5 首次启动可视检查通过：首页直接显示快速发布和五个入口。

```sh
xcodebuild -project Muses.xcodeproj -scheme Muses -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/muses-derived CODE_SIGNING_ALLOWED=NO build
xcrun swiftc -module-cache-path /tmp/muses-swift-cache Muses/Domain/Models.swift Muses/Domain/SKUImport.swift checks/SKUImportChecks.swift -o /tmp/muses-import-checks
/tmp/muses-import-checks
python3 checks/run-workflow-checks.py <已启动的专用模拟器UDID>
```

检查覆盖 CSV/TSV 引号、逗号、换行、BOM、JSON、空字段、重复 SKU、坏格式拒绝；旧 Creation JSON 兼容；转化计算与负数拒绝；无 Key 保存商品；图片扩展名；避免重复创建版本；V1→V2 独立快照；图片直接生成文案；旧版内容查看；帖子历史仅归属对应版本；重载恢复。

真实供应商生成、系统相册授权、唤起小红书仍需有效配置与真机验收。本次流程检查通过预览模式运行，没有调用收费模型或向系统相册写入媒体。
