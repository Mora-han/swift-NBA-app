import SwiftUI
import NBAKit

#if canImport(UIKit)
import UIKit
/// 统一跨平台图片类型别名（macOS 用 NSImage）
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

/// 远程队徽/球员图：两级缓存（内存 + 磁盘），自动升级 http → https，带淡入与占位骨架
struct RemoteImage: View {
    let urlString: String?
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat = 0
    var contentMode: ContentMode = .fit

    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        case success(PlatformImage)
        case empty

        var image: PlatformImage? {
            if case .success(let i) = self { return i }
            return nil
        }
    }

    var body: some View {
        Group {
            if let image = phase.image {
                imageView(image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .task(id: urlString) { await load() }
    }

    #if canImport(UIKit)
    private func imageView(_ image: PlatformImage) -> Image { Image(uiImage: image) }
    #else
    private func imageView(_ image: PlatformImage) -> Image { Image(nsImage: image) }
    #endif

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "basketball")
                    .font(.system(size: min(width, height) * 0.45))
                    .foregroundStyle(.tertiary)
            }
    }

    private func load() async {
        guard let url = HupuMedia.imageURL(urlString) else {
            phase = .empty
            return
        }
        if let cached = await ImageCache.shared.image(for: url) {
            withAnimation(.easeOut(duration: 0.15)) { phase = .success(cached) }
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = PlatformImage(data: data) else {
                phase = .empty
                return
            }
            await ImageCache.shared.store(image, for: url)
            withAnimation(.easeOut(duration: 0.15)) { phase = .success(image) }
        } catch {
            phase = .empty
        }
    }
}

/// 图片缓存（actor，线程安全，内存 200 张 + 磁盘）
actor ImageCache {
    static let shared = ImageCache()

    private var memory: [URL: PlatformImage] = [:]
    private var order: [URL] = []
    private let capacity = 200
    private let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("NBAImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func image(for url: URL) -> PlatformImage? {
        if let hit = memory[url] { return hit }
        let file = directory.appendingPathComponent(cacheKey(url))
        if let data = try? Data(contentsOf: file), let image = PlatformImage(data: data) {
            insert(image, for: url)
            return image
        }
        return nil
    }

    func store(_ image: PlatformImage, for url: URL) {
        insert(image, for: url)
        guard let data = pngData(image) else { return }
        try? data.write(to: directory.appendingPathComponent(cacheKey(url)), options: .atomic)
    }

    #if canImport(UIKit)
    private func pngData(_ image: PlatformImage) -> Data? { image.pngData() }
    #else
    private func pngData(_ image: PlatformImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
    #endif

    private func insert(_ image: PlatformImage, for url: URL) {
        memory[url] = image
        order.removeAll { $0 == url }
        order.append(url)
        if order.count > capacity {
            for key in order.prefix(order.count - capacity) {
                memory[key] = nil
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(cacheKey(key)))
            }
            order.removeFirst(order.count - capacity)
        }
    }

    private func cacheKey(_ url: URL) -> String {
        let name = url.absoluteString
        var hash: UInt64 = 5381
        for byte in name.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return String(hash, radix: 16)
    }
}