import PhotosUI
import SwiftUI

/// SPEC §4 Capture: document camera or photo picker, up to 3 pages, thumbnails with reorder/delete, Extract.
struct CaptureView: View {
    @Bindable var flow: AddRecipeFlow
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isScanning = false
    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        // PhotosPicker's label closure is @Sendable, so it can't read main-actor state; compute its text here.
        let pickerTitle = flow.pages.isEmpty ? "Choose photos" : "Add more photos"
        List {
            Section {
                Text("Photograph the page with the ingredient list. If the list runs over a page turn, add the next page too — up to \(AddRecipeFlow.maxPages) pages.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            if !flow.pages.isEmpty {
                Section("Pages") {
                    ForEach(Array(flow.pages.enumerated()), id: \.element.id) { index, page in
                        PageRow(index: index, page: page)
                    }
                    .onMove { from, to in flow.pages.move(fromOffsets: from, toOffset: to) }
                    .onDelete { offsets in flow.pages.remove(atOffsets: offsets) }
                }
            }

            if flow.remainingSlots > 0 {
                Section {
                    if DocumentScannerView.isSupported {
                        Button {
                            isScanning = true
                        } label: {
                            Label("Scan pages", systemImage: "doc.viewfinder")
                        }
                    }
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: flow.remainingSlots, matching: .images) {
                        Label(pickerTitle, systemImage: "photo.on.rectangle")
                    }
                } footer: {
                    if !DocumentScannerView.isSupported {
                        Text("Scanning with the camera needs a real device.")
                    }
                }
            }
        }
        .navigationTitle("Add recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if flow.pages.count > 1 {
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                flow.extract()
            } label: {
                Text(flow.pages.isEmpty ? "Extract" : "Extract \(flow.pages.count == 1 ? "1 page" : "\(flow.pages.count) pages")")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!flow.canExtract || isImporting)
            .padding()
            .background(.bar)
        }
        .overlay {
            if isImporting {
                ProgressView("Preparing pages…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .fullScreenCover(isPresented: $isScanning) {
            DocumentScannerView(maxPages: flow.remainingSlots) { images in
                isScanning = false
                importScans(images)
            } onCancel: {
                isScanning = false
            } onError: { error in
                isScanning = false
                importError = error.localizedDescription
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            importPickerItems(items)
        }
        .alert("Couldn't add that photo", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private func importPickerItems(_ items: [PhotosPickerItem]) {
        isImporting = true
        Task {
            defer { isImporting = false }
            var pages: [CapturedPage] = []
            for item in items {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                    let page = try await Task.detached(priority: .userInitiated) { try ImageProcessing.makePage(fromImageData: data) }.value
                    pages.append(page)
                } catch {
                    importError = "That image couldn't be read. Try another photo."
                }
            }
            flow.add(pages)
        }
    }

    private func importScans(_ images: [UIImage]) {
        isImporting = true
        Task {
            defer { isImporting = false }
            let pages = await Task.detached(priority: .userInitiated) {
                images.compactMap { try? ImageProcessing.makePage(from: $0) }
            }.value
            flow.add(pages)
        }
    }
}

private struct PageRow: View {
    let index: Int
    let page: CapturedPage

    var body: some View {
        HStack(spacing: 12) {
            PageThumbnail(data: page.jpegData)
                .frame(width: 56, height: 72)
            VStack(alignment: .leading) {
                Text("Page \(index + 1)")
                    .font(.headline)
                Text("\(Int(page.pixelSize.width)) × \(Int(page.pixelSize.height)) · \(page.jpegData.count / 1024) KB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Decodes a page JPEG for display at thumbnail size.
struct PageThumbnail: View {
    let data: Data

    var body: some View {
        Group {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
