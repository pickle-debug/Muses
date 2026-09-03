import SwiftUI

struct FactConfirmationView: View {
    @EnvironmentObject private var app: AppModel
    @State private var showMore = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PageHeader(title: "确认商品信息", subtitle: "AI 只负责预填，最终商品事实由你确认", step: "2 / 4  商品信息", backAction: { app.screen = .product })
                InfoBanner(text: "AI 已识别，请逐项核对并修正不确定信息。")

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 16) {
                            AssetImage(asset: app.sourceAssets.first)
                                .frame(width: 110, height: 130)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            VStack(alignment: .leading, spacing: 7) {
                                Text(app.productName).font(.title3.weight(.bold))
                                Text(app.sellingPoint).font(.subheadline).foregroundStyle(MusesTheme.secondaryInk)
                                StatusPill(text: "AI 识别，待确认", tone: .warning)
                            }
                        }

                        EditableFactRow(label: "材质", field: .material, text: $app.material, required: true, allowsNotApplicable: true)
                        EditableFactRow(label: "颜色", field: .colors, text: $app.colorsText, required: true)
                        EditableFactRow(label: "图案", field: .patterns, text: $app.patternsText, allowsNotApplicable: true)
                        EditableFactRow(label: "规格", field: .specification, text: $app.specification, allowsNotApplicable: true)

                        DisclosureGroup("更多商品信息", isExpanded: $showMore) {
                            VStack(spacing: 0) {
                                EditableFactRow(label: "类目", field: .category, text: $app.category, allowsNotApplicable: true)
                                EditableFactRow(label: "包装文字", field: .visibleText, text: $app.visibleText, allowsNotApplicable: true)
                            }
                            .padding(.top, 8)
                        }
                        .font(.headline)
                    }
                }

                SurfaceCard {
                    VStack(spacing: 0) {
                        EditableFactRow(label: "目标人群", field: .audience, text: $app.audience, allowsNotApplicable: true)
                        EditableFactRow(label: "真实卖点", field: .sellingPoint, text: $app.sellingPoint, required: true)
                        EditableFactRow(label: "禁止改变特征", field: .lockedFeatures, text: $app.lockedFeaturesText, required: true)
                    }
                }

                if !app.uncertainFields.isEmpty {
                    InfoBanner(text: "AI 无法确定：\(app.uncertainFields.joined(separator: "、"))。请修改，或明确保留为“不确定/不适用”。", kind: .warning)
                }

                Button { app.rightsConfirmed.toggle() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: app.rightsConfirmed ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(app.rightsConfirmed ? MusesTheme.coral : MusesTheme.secondaryInk)
                        Text("我确认拥有这些素材及营销用途的使用权")
                            .foregroundStyle(MusesTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(18)
                    .background(MusesTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)

                InfoBanner(text: "高成本操作：下一步将用 \(app.imageModelName) 生成 1 张 3:4 图片。", kind: .neutral)
                PrimaryButton(title: "确认并生成", icon: "sparkles", disabled: !app.canConfirmFacts) {
                    Task { await app.confirmFactsAndGenerate() }
                }
                .padding(.bottom, 24)
            }
            .frame(maxWidth: 700)
            .padding(20)
        }
        .musesPage()
    }
}

private struct EditableFactRow: View {
    @EnvironmentObject private var app: AppModel
    let label: String
    let field: FactField
    @Binding var text: String
    var required = false
    var allowsNotApplicable = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(label).font(.subheadline.weight(.bold))
                    FactStatusPill(status: app.factStatus(for: field))
                }
                .frame(width: 108, alignment: .leading)
                TextField(allowsNotApplicable ? "请输入，或选择不适用" : "请输入", text: $text, axis: .vertical)
                    .lineLimit(1...3)
                    .onChange(of: text) { oldValue, newValue in
                        guard oldValue != newValue else { return }
                        app.markFactEdited(field, value: newValue)
                    }
                Image(systemName: "pencil").foregroundStyle(MusesTheme.secondaryInk)
            }
            .frame(minHeight: 50)
            HStack(spacing: 10) {
                Spacer().frame(width: 108)
                Button("确认此项") { app.setFactStatus(.confirmed, for: field) }
                    .font(.caption.weight(.bold))
                    .disabled(!app.canConfirmFact(field))
                if allowsNotApplicable {
                    Button("不确定 / 不适用") { app.setFactStatus(.notApplicable, for: field) }
                        .font(.caption.weight(.semibold))
                }
                Spacer()
            }
            .padding(.bottom, 7)
            if required && app.factStatus(for: field) == .pending {
                Text("请填写并确认此项")
                    .font(.caption)
                    .foregroundStyle(MusesTheme.coral)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 120)
                    .padding(.bottom, 5)
            }
            Divider().foregroundStyle(MusesTheme.line)
        }
    }
}

private struct FactStatusPill: View {
    let status: FactConfirmationStatus

    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(status == .pending ? MusesTheme.secondaryInk : MusesTheme.success)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(status == .pending ? MusesTheme.coralSoft : MusesTheme.successSoft, in: Capsule())
    }

    private var label: String {
        switch status {
        case .pending: "AI 识别，待确认"
        case .confirmed: "用户确认"
        case .notApplicable: "不确定 / 不适用"
        }
    }
}

#if DEBUG
#Preview("Fact Confirmation") {
    MusesPreview.environment(.factConfirmation) { FactConfirmationView() }
}
#endif
