import SwiftUI
import NBAKit

/// 接口数据加载骨架：负责请求、状态机、错误信息、TTL 刷新。
/// 视图层只关心 `state`，不直接碰网络。
@MainActor
@Observable
final class Loader<T: Sendable> {
    enum State {
        case idle
        case loading
        case loaded(T)
        case failed(String)
    }

    private(set) var state: State = .idle
    private var task: Task<Void, Never>?
    private let load: () async throws -> T

    init(_ load: @escaping () async throws -> T) {
        self.load = load
    }

    var value: T? {
        if case .loaded(let v) = state { return v }
        return nil
    }

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    var errorMessage: String? {
        if case .failed(let m) = state { return m }
        return nil
    }

    var isIdle: Bool {
        if case .idle = state { return true }
        return false
    }

    func run() {
        task?.cancel()
        state = .loading
        task = Task {
            do {
                let result = try await load()
                guard !Task.isCancelled else { return }
                state = .loaded(result)
            } catch is CancellationError {
                // 视图消失或依赖变化，忽略
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// 静默刷新：不切到 loading（避免列表闪烁），失败时保留旧数据
    func refresh() async {
        do {
            let result = try await load()
            guard !Task.isCancelled else { return }
            state = .loaded(result)
        } catch {
            // 静默失败，保留已有内容
        }
    }

    func cancel() {
        task?.cancel()
    }
}

extension Loader {
    /// 首次进入自动加载
    func runIfIdle() {
        if isIdle { run() }
    }
}

/// 带轮询的 loader（比分 / 直播）
@MainActor
@Observable
final class PollingLoader<T: Sendable> {
    private(set) var value: T?
    private(set) var errorMessage: String?
    private(set) var isInitialLoading = true

    private var pollTask: Task<Void, Never>?
    private let load: () async throws -> T
    private let interval: TimeInterval

    init(interval: TimeInterval, load: @escaping () async throws -> T) {
        self.interval = interval
        self.load = load
    }

    func start(interval overrideInterval: TimeInterval? = nil) {
        let period = overrideInterval ?? interval
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                do {
                    let result = try await load()
                    guard !Task.isCancelled else { return }
                    value = result
                    errorMessage = nil
                } catch is CancellationError {
                    return
                } catch {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
                isInitialLoading = false
                try? await Task.sleep(for: .seconds(period))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

}