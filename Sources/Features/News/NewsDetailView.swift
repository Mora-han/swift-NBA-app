import SwiftUI
import NBAKit

/// 新闻正文：正文在 App 内原生渲染（文字段 + 配图 + 亮评），不跳浏览器。
///
/// 数据来自正文页 SSR 里的 `__NEXT_DATA__`（basketballapi 没有正文接口），
/// 由 `HupuClient.fetchThreadDetail` 抠出来，`ThreadContentParser` 拆成块后渲染。
struct NewsDetailView: View {
    let tid: String
    var previewTitle: String?
    var previewTime: String?
    var previewReplies: Int?

    @State private var model = NewsDetailModel()
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if model.isLoading && model.page == nil {
                    LoadingBlock()
                } else if let error = model.errorMessage, model.page == nil {
                    FailureBlock(message: error) { Task { await model.load(tid: tid, force: true) } }
                } else if let page = model.page {
                    articleBody(page.detail)
                    lightReplies(page)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 16)
            .pageWidth(820)
        }
        .frame(maxWidth: .infinity)
        .navigationTitle(previewTitle ?? model.page?.detail.title ?? "新闻")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let url = URL(string: "https://bbs.hupu.com/\(tid).html") { openURL(url) }
                } label: {
                    Image(systemName: "safari")
                }
                .help("用浏览器打开原帖")
            }
        }
        .task { await model.load(tid: tid) }
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.page?.detail.title ?? previewTitle ?? "加载中…")
                .font(.system(size: 24, weight: .bold))
                .lineSpacing(3)
                .textSelection(.enabled)

            HStack(spacing: 10) {
                if let author = model.page?.detail.user?.username, !author.isEmpty {
                    Text(author)
                } else {
                    Text("虎扑")
                }
                if let forum = model.page?.detail.f_info?.f_name, !forum.isEmpty {
                    Text("·")
                    Text(forum)
                }
                if let time = previewTime, !time.isEmpty {
                    Text("·")
                    Text(String(time.prefix(16))).monospacedDigit()
                }
                Spacer(minLength: 4)
                if let replies = model.page?.detail.repliesCount ?? previewReplies {
                    Label("\(replies)", systemImage: "bubble.right")
                }
                if let lights = model.page?.detail.lightsCount {
                    Label("\(lights)", systemImage: "hand.thumbsup")
                }
                if let hits = model.page?.detail.hitsCount {
                    Label("\(hits)", systemImage: "eye")
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)

            Divider()
        }
    }

    // MARK: 正文

    private func articleBody(_ detail: ThreadDetail) -> some View {
        let blocks = detail.blocks
        return VStack(alignment: .leading, spacing: 12) {
            if blocks.isEmpty {
                EmptyBlock(title: "正文为空", message: "这条内容可能只有视频或已删除")
            } else {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let text):
                        Text(text)
                            .font(.system(size: 16))
                            .lineSpacing(6)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .image(let url):
                        RemoteContentImage(urlString: url)
                    }
                }
            }
        }
    }

    // MARK: 亮评

    @ViewBuilder
    private func lightReplies(_ page: ThreadPage) -> some View {
        let replies = page.lightReplies.filter { !$0.plainText.isEmpty }
        if !replies.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "热门回复", subtitle: "\(replies.count) 条高赞")

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(replies.enumerated()), id: \.element.id) { index, reply in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text(reply.user?.username ?? "JR")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                                if let location = reply.location, !location.isEmpty {
                                    Text(location)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 4)
                                if let light = reply.lightCount {
                                    Label("\(light)", systemImage: "hand.thumbsup")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Text(reply.plainText)
                                .font(.system(size: 15))
                                .lineSpacing(4)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        if index < replies.count - 1 { Divider() }
                    }
                }
                .cardSurface()
            }
            .padding(.top, 6)
        }
    }
}

// MARK: - 模型

@MainActor
@Observable
final class NewsDetailModel {
    private(set) var page: ThreadPage?
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    private var loadedTid: String?
    private let client = HupuClient.shared

    func load(tid: String, force: Bool = false) async {
        guard !tid.isEmpty else {
            errorMessage = "缺少帖子 id，只能跳浏览器打开"
            isLoading = false
            return
        }
        guard force || loadedTid != tid else { return }
        if page == nil { isLoading = true }
        defer { isLoading = false }
        do {
            page = try await client.fetchThreadDetail(
                tid: tid, ttl: HupuConfig.TTL.thread, forceRefresh: force)
            loadedTid = tid
            errorMessage = nil
        } catch {
            errorMessage = "正文加载失败，可用右上角在浏览器打开"
        }
    }
}
