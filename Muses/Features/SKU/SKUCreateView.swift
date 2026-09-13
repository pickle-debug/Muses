import PhotosUI
import SwiftUI

struct SKUCreateView: View {
    @EnvironmentObject private var app: AppModel
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var previewAsset: LocalAsset?
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 28) {
                photoSection
                nameSection
            }
            .padding(16)
            .background(MusesTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            if case .failed(let message) = app.operation {
                InfoBanner(text: message, kind: .warning)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isNameFocused { actionSection }
        }
        .musesPage()
        .buttonStyle(.plain)
        .disabled(app.isWorking)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems,
                      maxSelectionCount: max(1, AppModel.maximumSourcePhotoCount - app.sourceAssets.count),
                      selectionBehavior: .ordered, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty, !app.isWorking else { return }
            Task {
                await app.addPhotos(from: items)
                photoItems = []
            }
        }
        .sheet(item: $previewAsset) { asset in
            NavigationStack {
                AssetImage(asset: asset, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .navigationTitle("商品图片")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("关闭") { previewAsset = nil }
                                .accessibilityIdentifier("sku.photo.preview.close")
                        }
                    }
            }
            .environmentObject(app)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 8) {
            Button {
                isNameFocused = false
                app.screen = .history
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("返回商品列表")
            .accessibilityIdentifier("sku.back")
            Text("添加商品").font(.headline)
            Spacer(minLength: 0)
            if isNameFocused {
                Button("完成输入") { isNameFocused = false }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("sku.input.done")
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 20)
        .foregroundStyle(MusesTheme.ink)
        .background(MusesTheme.background)
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("商品图片").font(.title3.weight(.bold))
                Spacer()
                Text("\(app.sourceAssets.count)/\(AppModel.maximumSourcePhotoCount)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(MusesTheme.secondaryInk)
                    .accessibilityLabel("已选择 \(app.sourceAssets.count) 张，最多 \(AppModel.maximumSourcePhotoCount) 张")
                    .accessibilityIdentifier("sku.photos.count")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(app.sourceAssets.enumerated()), id: \.element.id) { index, asset in
                        photoTile(asset, index: index)
                    }
                    if app.sourceAssets.count < AppModel.maximumSourcePhotoCount {
                        Button {
                            isNameFocused = false
                            showPhotoPicker = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2.weight(.light))
                                .foregroundStyle(MusesTheme.secondaryInk)
                                .frame(width: 92, height: 92)
                                .background(MusesTheme.background, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .accessibilityLabel("从相册添加商品图片")
                        .accessibilityIdentifier("sku.photo.add.\(app.sourceAssets.count + 1)")
                    }
                }
            }
            .frame(height: 92)
            .accessibilityIdentifier("sku.photos.row")
        }
    }

    private func photoTile(_ asset: LocalAsset, index: Int) -> some View {
        Button {
            isNameFocused = false
            previewAsset = asset
        } label: {
            AssetImage(asset: asset, contentMode: .fill)
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Text(index == 0 ? "主图" : "\(index + 1)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(6)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看第 \(index + 1) 张商品图片")
        .accessibilityIdentifier("sku.photo.preview.\(index + 1)")
        .contextMenu {
            Button("向前移动", systemImage: "arrow.left") { app.moveSource(asset, by: -1) }
                .disabled(index == 0)
            Button("向后移动", systemImage: "arrow.right") { app.moveSource(asset, by: 1) }
                .disabled(index == app.sourceAssets.count - 1)
            Button("删除", systemImage: "trash", role: .destructive) { app.removeSource(asset) }
        }
        .overlay(alignment: .topTrailing) {
            Button { app.removeSource(asset) } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MusesTheme.ink)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.95), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除第 \(index + 1) 张图片")
            .accessibilityIdentifier("sku.photo.remove.\(index + 1)")
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("商品名称").font(.title3.weight(.bold))
            TextField("请输入商品名称", text: $app.productName)
                .font(.body)
                .focused($isNameFocused)
                .submitLabel(.done)
                .onSubmit { isNameFocused = false }
                .frame(minHeight: 44)
                .accessibilityLabel("商品名称")
                .accessibilityIdentifier("sku.input.name")
        }
    }

    private var actionSection: some View {
        VStack(spacing: 10) {
            if case .working(let message) = app.operation {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(message).font(.caption)
                }
            }
            saveButton
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(MusesTheme.surface)
        .overlay(alignment: .top) { MusesTheme.line.frame(height: 0.5) }
    }

    private var saveButton: some View {
        Button { Task { await app.saveProductDraft() } } label: {
            Text("保存商品")
                .font(.body.weight(.semibold))
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(.white)
                .background(MusesTheme.coral, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.45)
        .accessibilityIdentifier("sku.save")
    }

    private var canSave: Bool {
        !app.isWorking && !app.productName.trimmed.isEmpty
    }
}

#if DEBUG
#Preview("SKU Create") {
    MusesPreview.environment(.sku) { SKUCreateView() }
}
#endif
