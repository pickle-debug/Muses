# Realm MVP 数据结构

本次提供模型和数据库打开入口。现有页面仍使用 `AppSnapshot` / `SnapshotStore`，尚未执行 JSON 导入或切换业务读写。

| 对象 | 保存内容 |
|---|---|
| `Setting` | 一条 `id = default` 的个人、店铺及提示词偏好；不保存凭证 |
| `SKU` | 商品编号、名称、真实卖点、事实字段、源图相对路径 |
| `Post` | 保存的文案、所选标题、采用的图片/视频相对路径 |
| `Job` | 一次供应商调用、幂等键、任务/请求 ID、实际提示词和结果 |
| `Link`（嵌入） | 一个 Post 对应的一条平台帖子链接 |
| `Stat`（嵌入） | 一条链接在某个时间点的累计指标 |

关系为 `SKU → Post → Link → Stat`；一个 Post 的所有任务用 `Job.postID` 查询。一次请求返回多张图片仍是一条 Job；分别提交的请求是多条 Job。

## 使用约定

- 使用 `try RealmDatabase.open()`，在主线程短事务内读写。不要将 Realm 或受管理对象传给后台 Task。
- 文件位于 App 沙盒 `Application Support/Muses/muses.realm`；目录或数据库打开失败会抛出错误，由页面处理。此入口会创建默认 Setting，不会导入旧数据。
- `SKU.code` 的索引不代表唯一约束；接入保存逻辑时，在同一写事务内检查规范化后的编号不能重复。
- `skuID` / `postID` 是普通 UUID 字段，不是数据库外键；写入时确认归属，删除时显式处理 Job。Realm 会随 Post 删除其 Link 和 Stat。
- `PostDraft` 是值类型。保留编辑前的副本即可撤回，放弃修改不会影响已保存 Post；只在内存的编辑会在进程退出后丢失。
- 新草稿的 Job 可以先使用 `PostDraft.id` 作为 `postID`，保存 Post 时沿用这个 ID。撤回草稿不能把未确认取消的远端任务改成 cancelled。
- Job 状态沿用现有 `JobStatus.rawValue`，包括提交结果未知的 `submission_unknown`；重试保留原幂等键和提示词。`providerTaskID` 用于供应商支持的轮询，`providerRequestID` 只用于请求追踪。
- 每次更新追加 Stat，旧采样不覆盖。`nil` 表示未获取，`0` 表示真实零值；写入前校验非负值，允许平台纠正后的累计值比上一次低。不同币种不可直接相加。
- Setting 保存的偏好只影响新 Job；实际 Prompt 和 `systemPromptVersion` 随 Job 保存。系统提示词仍由 App 代码维护。

## 升级和旧数据

- 首个 Realm schema 为 1，与旧 JSON 的 schemaVersion 2 无关。结构或转换逻辑变化时递增 `RealmDatabase.schemaVersion`，在 `migrationBlock` 中按实际旧版本写独立分支；必须覆盖用户跳版本升级。
- 当前没有已发布的旧 Realm schema，所以没有虚构迁移步骤。禁止开启 `deleteRealmIfMigrationNeeded`，也不自动降级数据库。
- 后续接入时，JSON 导入和 `Setting.legacyImportedAt` 必须在一个 Realm 写事务内提交，成功后才标记导入完成，并保留源 JSON 备份。当前仅预留标记。
- 切换业务读写前还需处理原模型里的快照、审核、素材元数据、导出记录等信息，不能直接丢弃旧 JSON。切换后只保留一个可写数据源。

## Xcode 手动检查

1. 在 Xcode 编译，确认 `RealmModels.swift` 和 `RealmDatabase.swift` 自动归属 Muses target，RealmSwift 包使用当前 community 分支。
2. 将 `checks/RealmChecks.swift` 加入同模块的调试检查入口，在主线程调用 `try RealmChecks.run()`。它只使用 UUID 命名的临时目录，验证写入重开、多任务、多链接、历史指标、默认设置和草稿副本隔离。
3. 本次未运行构建或检查代码。旧 `run-workflow-checks.py` 仍只检查 JSON 流程，明确排除新 Realm 文件。
4. 发布下一版 schema 前保留真实 v1 数据库样本，验证 v1 直升目标版后主键、远端任务 ID 和历史指标仍在；当前检查不是跨版本迁移测试。
