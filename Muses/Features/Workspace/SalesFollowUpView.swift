import SwiftUI

struct SalesFollowUpView: View {
    @EnvironmentObject private var app: AppModel
    @State private var selectedCreation: Creation?
    private var versions: [Creation] {
        app.snapshot.creations.filter { [.ready, .saved].contains($0.status) && $0.isPreview != true }
            .sorted { $0.createdAt > $1.createdAt }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                WorkspaceHeading(title: "销售跟进", subtitle: "每一篇帖子，都对应一个商品内容版本。")
                InfoBanner(text: "手动登记小红书帖子和累计数据。转化率 = 订单数 ÷ 浏览量；订单与成交额由你核实，本页尚未自动同步平台数据。", kind: .neutral)
                if versions.isEmpty {
                    ContentUnavailableView("暂无跟进记录", systemImage: "chart.line.uptrend.xyaxis")
                    PrimaryButton(title: "查看我的商品", icon: "shippingbox") { app.selectTab(.products) }
                }
                ForEach(versions) { creation in
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(productName(creation)).font(.headline)
                                    Text("\(app.versionLabel(creation)) · \(creation.tracking == nil ? "待登记帖子" : "已登记帖子")")
                                        .font(.caption).foregroundStyle(MusesTheme.secondaryInk)
                                }
                                Spacer()
                                Image(systemName: "chart.bar.xaxis").foregroundStyle(MusesTheme.coral)
                            }
                            if let metrics = creation.tracking?.samples.last { MetricsSummary(metrics: metrics) }
                            SecondaryButton(title: creation.tracking == nil ? "登记帖子与数据" : "更新数据 / 查看记录", icon: "square.and.pencil") {
                                selectedCreation = creation
                            }
                        }
                    }
                }
            }.frame(maxWidth: 720).padding(20)
        }
        .musesPage()
        .sheet(item: $selectedCreation) { creation in PostTrackingSheet(creationID: creation.id) }
    }
    private func productName(_ creation: Creation) -> String {
        let id = app.snapshot.productSnapshots.first { $0.id == creation.productSnapshotID }?.productID
        return app.snapshot.products.first { $0.id == id }?.name ?? "商品"
    }
}

struct MetricsSummary: View {
    let metrics: PostMetrics
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                metric("浏览", value: "\(metrics.views)")
                metric("订单", value: "\(metrics.orders)")
                metric("转化率", value: metrics.conversionRate.map { String(format: "%.2f%%", $0 * 100) } ?? "—")
            }
            Text("赞 \(metrics.likes) · 收藏 \(metrics.saves) · 评论 \(metrics.comments) · 咨询 \(metrics.inquiries)")
                .font(.caption).foregroundStyle(MusesTheme.secondaryInk)
            Text("成交额 ¥\(metrics.revenue, specifier: "%.2f")")
                .font(.subheadline.weight(.semibold))
            Text("更新于 \(metrics.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2).foregroundStyle(MusesTheme.secondaryInk)
        }
    }
    private func metric(_ name: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(MusesTheme.ink)
            Text(name).font(.caption).foregroundStyle(MusesTheme.secondaryInk)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PostTrackingSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let creationID: MusesID
    @State private var postURL = ""
    @State private var publishedAt = Date.now
    @State private var views = "0"
    @State private var likes = "0"
    @State private var saves = "0"
    @State private var comments = "0"
    @State private var inquiries = "0"
    @State private var orders = "0"
    @State private var revenue = "0"
    @State private var note = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    private var creation: Creation? { app.snapshot.creations.first { $0.id == creationID } }

    var body: some View {
        NavigationStack {
            Form {
                Section("帖子信息") {
                    TextField("粘贴小红书帖子链接", text: $postURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    DatePicker("发布时间", selection: $publishedAt, in: ...Date.now)
                }
                Section {
                    numberField("浏览量", text: $views)
                    numberField("点赞", text: $likes)
                    numberField("收藏", text: $saves)
                    numberField("评论", text: $comments)
                    numberField("咨询人数", text: $inquiries)
                    numberField("订单数", text: $orders)
                    HStack {
                        Text("成交额（元）")
                        TextField("0.00", text: $revenue).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                    }
                    TextField("归因依据或本次观察", text: $note, axis: .vertical).lineLimit(2...4)
                } header: { Text("本次累计数据") } footer: {
                    Text("填写截至目前的累计值，每次保存均保留历史。转化率为订单数 / 浏览量，浏览量为 0 时不计算。")
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(MusesTheme.coral) } }
                if let tracking = creation?.tracking, !tracking.samples.isEmpty {
                    Section("历史跟进 · \(tracking.samples.count) 次") {
                        ForEach(tracking.samples.reversed()) { sample in
                            VStack(alignment: .leading, spacing: 8) {
                                MetricsSummary(metrics: sample)
                                if !sample.note.isEmpty { Text(sample.note).font(.caption) }
                            }.padding(.vertical, 6)
                        }
                    }
                }
            }
            .navigationTitle("\(creation.map { app.versionLabel($0) } ?? "") 帖子跟进")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中…" : "保存") { Task { await save() } }.disabled(isSaving || postURL.isEmpty)
                }
            }
            .onAppear(perform: load)
            .interactiveDismissDisabled(isSaving)
        }.tint(MusesTheme.coral)
    }

    private func numberField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            TextField("0", text: text).multilineTextAlignment(.trailing).keyboardType(.numberPad)
        }
    }
    private func load() {
        guard let tracking = creation?.tracking else { return }
        postURL = tracking.postURL; publishedAt = tracking.publishedAt
        guard let metrics = tracking.samples.last else { return }
        views = String(metrics.views); likes = String(metrics.likes); saves = String(metrics.saves)
        comments = String(metrics.comments); inquiries = String(metrics.inquiries); orders = String(metrics.orders)
        revenue = String(format: "%.2f", metrics.revenue)
    }
    private func save() async {
        guard let views = Int(views.trimmed), let likes = Int(likes.trimmed), let saves = Int(saves.trimmed),
              let comments = Int(comments.trimmed), let inquiries = Int(inquiries.trimmed), let orders = Int(orders.trimmed),
              let revenue = Double(revenue.trimmed) else {
            errorMessage = "请填写完整数字，成交额可以保留小数。"
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await app.saveTracking(creationID: creationID, postURL: postURL, publishedAt: publishedAt,
                metrics: PostMetrics(views: views, likes: likes, saves: saves, comments: comments, inquiries: inquiries, orders: orders, revenue: revenue, note: note.trimmed))
            dismiss()
        } catch { errorMessage = AppAlert.from(error).message }
    }
}
