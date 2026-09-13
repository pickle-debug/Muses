# Muses

原生 SwiftUI iOS App。当前 SKU 流程为：商品列表 → 创建商品 → 保存 → 查看详情，也可从详情返回编辑。

创建页只填写商品名称，图片按横向一排显示，最多 9 张；SKU 编号自动生成。详情页显示名称与图片。事实确认、生成、审核和结果页面及其自动任务流程已移除。其他工作台入口与个人设置沿用现有实现。

## 本地存储

SKU 仍由 `AppModel` 调用 `SnapshotStore`，写入 App 沙盒的 `Application Support/Muses/snapshot-v2.json`。图片由 `AssetStore` 独立保存，JSON 记录图片引用。

`RealmDatabase.swift` 和 `RealmModels.swift` 已存在，但尚未接入 SKU 读写，也没有执行 JSON 到 Realm 的迁移。旧 JSON 数据结构保留，编辑商品不会移除历史字段。

## Xcode 验证

用 Xcode 打开 `Muses.xcodeproj`。Codex 只进行静态检查，不自动生成工程、安装依赖、编译或运行模拟器。

- 无图时仅显示一个加号；选择 N 张后显示 N+1 个框，满 9 张隐藏加号。
- 点击加号继续从相册添加；取消不改动草稿；删除后可再次添加。
- 空名称不能保存；只填名称即可保存并进入详情。
- 详情可左右查看全部图片，编辑后名称、图片顺序及自动 SKU 保持正确。
- 重启后检查商品仍可查看，删除一个商品不影响其他商品。
- 检查小屏、键盘、大字体及 VoiceOver 下的创建与详情布局。

`checks/WorkflowChecks.swift` 和 `checks/TabBarUITests.swift` 已随 SKU 流程调整；本轮未运行。
