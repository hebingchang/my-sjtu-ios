//
//  CanvasVideosView.swift
//  MySJTU
//
//  Created by boar on 2026/03/28.
//

import SwiftUI
import Apollo
import Alamofire

struct CanvasVideosView: View {
    let courseID: String
    let courseLegacyID: String?

    @AppStorage("accounts") private var accounts: [WebAuthAccount] = []
    @State private var videoListResult: CanvasVideoListResult?
    @State private var isLoading: Bool = true
    @State private var loadErrorMessage: String?
    @State private var contentOpacity: Double = 1

    private enum LoadViewState: Equatable {
        case loading
        case error
        case content
        case placeholder
    }

    init(courseID: String, courseLegacyID: String? = nil) {
        self.courseID = courseID
        self.courseLegacyID = courseLegacyID
    }

    private var canvasToken: String? {
        accounts.jaccountCanvasToken
    }

    private var normalizedCourseLegacyID: String? {
        guard let courseLegacyID else {
            return nil
        }

        let trimmedCourseLegacyID = courseLegacyID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCourseLegacyID.isEmpty else {
            return nil
        }

        return trimmedCourseLegacyID
    }

    private var loadViewState: LoadViewState {
        if isLoading && videoListResult == nil {
            return .loading
        }
        if loadErrorMessage != nil && videoListResult == nil {
            return .error
        }
        if videoListResult != nil {
            return .content
        }
        return .placeholder
    }

    var body: some View {
        Group {
            if isLoading && videoListResult == nil {
                CanvasLoadingView(title: "正在获取视频列表")
                    .transition(.opacity)
            } else if let loadErrorMessage, videoListResult == nil {
                ContentUnavailableView {
                    Label("无法准备视频页面", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadErrorMessage)
                } actions: {
                    if canvasToken != nil {
                        Button("重试") {
                            Task {
                                await loadVideoList(force: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            } else if let videoListResult {
                if videoListResult.isEmpty {
                    ContentUnavailableView(
                        "暂无可用视频",
                        systemImage: "play.slash",
                        description: Text(videoListResult.courseName ?? "当前课程暂未返回视频或直播列表。")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(contentOpacity)
                    .transition(.opacity)
                } else {
                    List {
                        if let courseName = videoListResult.courseName {
                            Section {
                                Text(courseName)
                                    .font(.headline)
                                    .padding(.vertical, 4)
                            }
                        }

                        if let primaryLiveStream = videoListResult.liveStreams.first {
                            let liveStatus = canvasLiveStatus(for: primaryLiveStream)
                            Section("直播") {
                                NavigationLink {
                                    CanvasLiveVideoDetailView(
                                        liveVideo: primaryLiveStream,
                                        relatedLiveVideos: videoListResult.liveStreams,
                                        session: videoListResult.session
                                    )
                                } label: {
                                    CanvasLiveVideoRecordRow(
                                        liveVideo: primaryLiveStream,
                                        liveStatus: liveStatus
                                    )
                                }
                                .disabled(!liveStatus.allowsDetailNavigation)
                            }
                        }

                        if !videoListResult.videos.isEmpty {
                            Section("录像 \(videoListResult.videos.count)") {
                                ForEach(videoListResult.videos) { video in
                                    NavigationLink {
                                        CanvasVideoDetailView(
                                            video: video,
                                            session: videoListResult.session
                                        )
                                    } label: {
                                        CanvasVideoRecordRow(video: video)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .contentMargins(.top, 8, for: .scrollContent)
                    .opacity(contentOpacity)
                    .transition(.opacity)
                }
            } else {
                ContentUnavailableView(
                    "视频功能建设中",
                    systemImage: "play.rectangle",
                    description: Text("页面占位已准备好，后续我们可以继续接入课程视频内容。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        .navigationTitle("视频")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.28), value: loadViewState)
        .task(id: courseID) {
            await loadVideoList()
        }
    }

    @MainActor
    private func loadVideoList(force: Bool = false) async {
        if !force && videoListResult != nil {
            return
        }

        let shouldAnimateContent = videoListResult == nil
        if shouldAnimateContent {
            contentOpacity = 0
        }

        guard let token = canvasToken else {
            loadErrorMessage = "Canvas 令牌不可用，请在账户设置中重新启用。"
            isLoading = false
            return
        }

        isLoading = true
        loadErrorMessage = nil

        if force {
            videoListResult = nil
        }

        defer {
            isLoading = false
        }

        do {
            let resolvedCourseLegacyID = try await resolveCourseLegacyID(token: token)
            let api = CanvasAPI(token: token)
            videoListResult = try await api.fetchCanvasVideoList(
                courseLegacyID: resolvedCourseLegacyID
            )

            if shouldAnimateContent {
                await Task.yield()
                withAnimation(.easeInOut(duration: 0.28)) {
                    contentOpacity = 1
                }
            } else {
                contentOpacity = 1
            }
        } catch ResponseCodeInterceptor.ResponseCodeError.invalidResponseCode {
            loadErrorMessage = "Canvas 令牌可能已失效，请在账户设置中重新启用。"
        } catch {
            loadErrorMessage = videoListErrorMessage(for: error)
        }
    }

    private func resolveCourseLegacyID(token: String) async throws -> String {
        if let normalizedCourseLegacyID {
            return normalizedCourseLegacyID
        }

        let api = CanvasAPI(token: token)
        guard let course = try await api.getClass(classId: courseID) else {
            throw CanvasVideoBootstrapError.missingCourseLegacyID
        }

        let trimmedCourseLegacyID = course._id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCourseLegacyID.isEmpty else {
            throw CanvasVideoBootstrapError.missingCourseLegacyID
        }

        return trimmedCourseLegacyID
    }

    private func videoListErrorMessage(for error: Error) -> String {
        switch error {
        case let afError as AFError where afError.responseCode == 401 || afError.responseCode == 403:
            return "Canvas 令牌可能已失效，请在账户设置中重新启用。"
        case CanvasVideoBootstrapError.missingCourseLegacyID:
            return "暂时无法确定当前 Canvas 课程信息，请稍后再试。"
        case CanvasVideoBootstrapError.missingLaunchForm:
            return "已获取 Canvas 页面，但未找到用于继续登录的视频表单。"
        case CanvasVideoBootstrapError.missingLaunchFormAction:
            return "已找到视频表单，但无法解析其提交地址。"
        case CanvasVideoBootstrapError.unsupportedLaunchFormMethod:
            return "视频表单使用了暂不支持的提交方式。"
        case CanvasVideoBootstrapError.missingTokenID:
            return "视频认证已完成，但无法获取令牌，请稍后再试。"
        case CanvasVideoBootstrapError.invalidAccessTokenResponse:
            return "视频平台未返回可用的访问令牌。"
        case CanvasVideoBootstrapError.missingCanvasCourseID:
            return "视频平台未返回课程标识，暂时无法加载视频列表。"
        case CanvasVideoBootstrapError.invalidVideoListResponse:
            return "视频平台返回了无效的视频列表数据。"
        case CanvasVideoBootstrapError.invalidLiveListResponse:
            return "视频平台返回了无效的直播列表数据。"
        case CanvasVideoBootstrapError.missingAuthorizationPostFinalURL:
            return "视频认证已完成，但无法获取最终目标地址。"
        default:
            return "视频认证初始化失败，请稍后重试。"
        }
    }
}

#Preview {
    NavigationStack {
        CanvasVideosView(courseID: "course-id")
    }
}

private struct CanvasLiveVideoRecordRow: View {
    let liveVideo: CanvasLiveVideoRecord
    let liveStatus: CanvasLiveStatus

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(liveVideo.courseName)
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.leading)

                if let scheduleText = scheduleText {
                    CanvasVideoRowMetadata(
                        systemImage: "clock",
                        text: scheduleText,
                        font: .footnote
                    )
                }

                if let detailText = detailText {
                    CanvasVideoRowMetadata(
                        systemImage: "person",
                        text: detailText,
                        font: .caption
                    )
                }
            }

            Spacer(minLength: 0)

            Text(liveStatus.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(liveStatus.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(liveStatus.tint.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 4)
    }

    private var scheduleText: String? {
        let beginText = liveVideo.courseBeginTime?.trimmingCharacters(in: .whitespacesAndNewlines)
        let endText = liveVideo.courseEndTime?.trimmingCharacters(in: .whitespacesAndNewlines)
        let beginDate = beginText.flatMap(parseCanvasVideoRowDate)
        let endDate = endText.flatMap(parseCanvasVideoRowDate)

        if let beginDate, let endDate {
            if Calendar.current.isDate(beginDate, inSameDayAs: endDate) {
                return "\(beginDate.formatted(date: .abbreviated, time: .shortened)) - \(endDate.formatted(date: .omitted, time: .shortened))"
            }

            return "\(beginDate.formatted(date: .abbreviated, time: .shortened)) - \(endDate.formatted(date: .abbreviated, time: .shortened))"
        }

        if let beginDate {
            return beginDate.formatted(date: .abbreviated, time: .shortened)
        }

        if let endDate {
            return endDate.formatted(date: .abbreviated, time: .shortened)
        }

        switch (beginText, endText) {
        case let (begin?, end?):
            return "\(stripSeconds(from: begin)) - \(stripSeconds(from: end))"
        case let (begin?, nil):
            return stripSeconds(from: begin)
        case let (nil, end?):
            return stripSeconds(from: end)
        default:
            return nil
        }
    }

    private var detailText: String? {
        let parts = [liveVideo.userName, liveVideo.classroomName]
            .compactMap { value -> String? in
                guard let value else {
                    return nil
                }

                let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedValue.isEmpty ? nil : trimmedValue
            }

        guard !parts.isEmpty else {
            return nil
        }

        return parts.joined(separator: " · ")
    }
}

private enum CanvasLiveStatus {
    case upcoming
    case live
    case ended

    var title: String {
        switch self {
        case .upcoming:
            return "即将开始"
        case .live:
            return "直播中"
        case .ended:
            return "已结束"
        }
    }

    var tint: Color {
        switch self {
        case .upcoming:
            return .blue
        case .live:
            return .red
        case .ended:
            return .secondary
        }
    }

    var allowsDetailNavigation: Bool {
        self != .upcoming
    }
}

private struct CanvasVideoRecordRow: View {
    let video: CanvasVideoRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(video.videoName)
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.leading)

                if let scheduleText = scheduleText {
                    CanvasVideoRowMetadata(
                        systemImage: "clock",
                        text: scheduleText,
                        font: .footnote
                    )
                }

                if let detailText = detailText {
                    CanvasVideoRowMetadata(
                        systemImage: "person",
                        text: detailText,
                        font: .caption
                    )
                }
            }

            Spacer(minLength: 0)

            if video.partClose {
                Text("已关闭")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    private var scheduleText: String? {
        let beginText = video.courseBeginTime?.trimmingCharacters(in: .whitespacesAndNewlines)
        let endText = video.courseEndTime?.trimmingCharacters(in: .whitespacesAndNewlines)
        let beginDate = beginText.flatMap(parseCanvasVideoRowDate)
        let endDate = endText.flatMap(parseCanvasVideoRowDate)

        if let beginDate, let endDate {
            if Calendar.current.isDate(beginDate, inSameDayAs: endDate) {
                return "\(beginDate.formatted(date: .abbreviated, time: .shortened)) - \(endDate.formatted(date: .omitted, time: .shortened))"
            }

            return "\(beginDate.formatted(date: .abbreviated, time: .shortened)) - \(endDate.formatted(date: .abbreviated, time: .shortened))"
        }

        if let beginDate {
            return beginDate.formatted(date: .abbreviated, time: .shortened)
        }

        if let endDate {
            return endDate.formatted(date: .abbreviated, time: .shortened)
        }

        switch (beginText, endText) {
        case let (begin?, end?):
            return "\(stripSeconds(from: begin)) - \(stripSeconds(from: end))"
        case let (begin?, nil):
            return stripSeconds(from: begin)
        case let (nil, end?):
            return stripSeconds(from: end)
        default:
            return nil
        }
    }

    private var detailText: String? {
        let parts = [video.userName, video.classroomName]
            .compactMap { value -> String? in
                guard let value else {
                    return nil
                }

                let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedValue.isEmpty ? nil : trimmedValue
            }

        guard !parts.isEmpty else {
            return nil
        }

        return parts.joined(separator: " · ")
    }
}

private struct CanvasVideoRowMetadata: View {
    let systemImage: String
    let text: String
    let font: Font

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 10)

            Text(text)
                .font(font)
                .foregroundStyle(.secondary)
        }
    }
}

private func canvasLiveStatus(
    for liveVideo: CanvasLiveVideoRecord,
    referenceTimestamp: Int? = nil
) -> CanvasLiveStatus {
    let referenceTimestamp = referenceTimestamp ?? Int(Date().timeIntervalSince1970 * 1_000)
    let beginTimestamp = liveVideo.courseBeginTimeTimestamp
        ?? canvasLiveTimestamp(from: liveVideo.courseBeginTime)
    let endTimestamp = liveVideo.availabilityEndTimestamp
        ?? canvasLiveTimestamp(from: liveVideo.continuousCourseEndTime)
        ?? canvasLiveTimestamp(from: liveVideo.courseEndTime)

    if let beginTimestamp, beginTimestamp > referenceTimestamp {
        return .upcoming
    }

    if let endTimestamp, endTimestamp < referenceTimestamp {
        return .ended
    }

    return .live
}

private func canvasLiveTimestamp(from value: String?) -> Int? {
    guard let rawValue = value else {
        return nil
    }

    let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedValue.isEmpty, let date = parseCanvasVideoRowDate(trimmedValue) else {
        return nil
    }

    return Int(date.timeIntervalSince1970 * 1_000)
}

private func parseCanvasVideoRowDate(_ value: String) -> Date? {
    Date.fromFormat("yyyy-MM-dd HH:mm:ss", dateStr: value)
}

private func stripSeconds(from value: String) -> String {
    guard value.count >= 16 else {
        return value
    }

    return String(value.prefix(16))
}
