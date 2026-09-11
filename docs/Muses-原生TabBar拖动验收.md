# iOS 26 原生 TabBar 拖动修正

## 录屏结论

用户提供的 16:41:06 是 TinyScan：长按选中项后，液态玻璃滑块连续跟随手指，放大、折射其下图标，再落到目标 tab。16:41:24 是 Muses：自定义按钮只是点击切换，选中底色由 matchedGeometryEffect 过渡，无系统拖动选择手势。

`.glassEffect` 提供材质与触控外观，不会自动把 HStack/Button 变成系统 tabbar。此前把原生玻璃材质等同于原生导航控件，判断错误。

## 最终实现

- iOS 26+：`NativeWorkspaceTabs: UIViewControllerRepresentable` 接入真正的 `UITabBarController`，四个业务页面继续由 SwiftUI + UIHostingController 承载。
- 系统负责底栏布局、选中胶囊、连续拖动和光学折射，不添加自制 DragGesture，不遍历或修改系统私有子视图。
- 中间留系统占位，但 delegate 拒绝选中该项。60pt 发布按钮仍以 SwiftUI 原生 glassEffect 绘制，固定于系统 tabbar 顶部向上 10pt，使用真实布局保证凸出区域可点击。
- 与 TinyScan 相机入口一致：发布是动作，打开独立全屏 SwiftUI 工作台；关闭后回到原 tab 的根页，避免恢复已被新建 SKU 操作覆盖的旧编辑上下文。
- 首次进入我的商品，不再默认选中中间空 tab。API Key 不拦截进入。
- iOS 17–25 使用兼容自定义栏；原生液态玻璃拖动仅针对 iOS 26+。

## 验证

2026-09-11，Xcode 26.6 / iPhone 17 Pro / iOS 26.5 Simulator。

- 改前：点击用例通过，新增原生拖动用例 3 个断言失败，复现用户录屏问题。
- 改后：2 个 UI 用例通过、0 失败。覆盖左侧相邻拖动、跨中间按钮拖动、右侧反向拖动、四 tab 切换、凸起区域点击、发布工作台关闭后的原 tab 恢复、占位项未被选中。
- 录屏逐帧确认拖动时系统玻璃滑块放大和折射，剪辑保存到 `output/Muses-tabbar/native-tabbar-drag.mp4`。
- 业务回归：无 Key 录入、图片导入、V1/V2 内容保留、图文直接生成、帖子数据保存和重载通过。

复验：

```sh
xcodebuild -project Muses.xcodeproj -scheme Muses -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/muses-derived CODE_SIGNING_ALLOWED=NO build
ruby checks/run-tabbar-ui-checks.rb <已安装最新构建的模拟器UDID>
python3 checks/run-workflow-checks.py <已启动模拟器UDID>
```

## ECC 交付自评

整体 4.2 / 5：本次证明的是系统控件的实际手势，而不只是外观。

| 维度 | 分数 | 证据与剩余改进 |
| --- | --- | --- |
| 准确性 | 4 | 拖动先失败后通过，录屏有系统折射；未在用户真机实测，需 Run 后核对。 |
| 完整性 | 4 | 两段录屏、参考代码、拖动/点击/跨中间/工作台关闭都覆盖；仅验收一个 iPhone 尺寸。 |
| 清晰度 | 5 | 明确区分玻璃材质和系统控件，明确 SwiftUI 与 UIKit 桥接边界。 |
| 可操作性 | 4 | 代码、可复现检查与效果视频已保存；用户设备仍需重新安装最新构建。 |
| 简洁性 | 4 | 仅桥接必要的系统容器；旧系统兼容栏仍占一定代码量，最低系统升到26后可删除。 |

优先改进：在用户真机复核拖动手感与安全区；后续扩展小屏设备验证。

自检：用户应能在录屏中直接确认拖动已恢复；不声称桥接为纯 SwiftUI，也不声称已在真机验证。
