//
//  CanvasVideoDetailView.swift
//  MySJTU
//
//  Created by boar on 2026/03/29.
//

import SwiftUI

struct CanvasVideoDetailView: View {
    let video: CanvasVideoRecord
    let session: CanvasVideoPlatformSession

    @State private var videoInfo: CanvasVideoInfo?
    @State private var courseSummary: CanvasVideoCourseSummary?
    @State private var transcriptSegments: [CanvasVideoTranscriptSegment] = []
    @State private var subtitleSegments: [CanvasVideoTranscriptSegment] = []
    @State private var pptSlides: [CanvasVideoPPTSlide] = []
    @State private var isLoading: Bool = true
    @State private var isLoadingEnhancements: Bool = false
    @State private var loadErrorMessage: String?
    @State private var supplementaryNotice: String?
    @State private var showFullscreenVideoPlayer: Bool = false
    @State private var contentOpacity: Double = 1

    private enum LoadViewState: Equatable {
        case loading
        case error
        case content
        case placeholder
    }

    private var loadViewState: LoadViewState {
        if isLoading && videoInfo == nil {
            return .loading
        }
        if loadErrorMessage != nil && videoInfo == nil {
            return .error
        }
        if videoInfo != nil {
            return .content
        }
        return .placeholder
    }

    var body: some View {
        Group {
            if isLoading && videoInfo == nil {
                CanvasLoadingView(title: "正在加载视频详情")
                    .transition(.opacity)
            } else if let loadErrorMessage, videoInfo == nil {
                errorState(message: loadErrorMessage)
                    .transition(.opacity)
            } else if let videoInfo {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        CanvasVideoHeroCard(
                            info: videoInfo,
                            fallbackVideo: video,
                            session: session
                        )

                        CanvasVideoOpenPageCard(
                            hasVideoPageURL: cleanedText(videoInfo.vodurl) != nil
                        ) {
                            showFullscreenVideoPlayer = true
                        }

                        if let supplementaryNotice {
                            CanvasVideoNoticeCard(message: supplementaryNotice)
                        }

                        CanvasVideoInfoCard(info: videoInfo)

                        CanvasVideoSummaryCard(
                            summary: courseSummary,
                            isLoading: isLoadingEnhancements
                        )

                        CanvasVideoTimelineCard(
                            items: courseSummary?.documentSkims ?? [],
                            isLoading: isLoadingEnhancements
                        )

                        CanvasVideoSlidesCard(
                            slides: pptSlides,
                            isLoading: isLoadingEnhancements
                        )

                        CanvasVideoTranscriptCard(
                            segments: transcriptSegments,
                            isLoading: isLoadingEnhancements
                        )
                    }
                    .padding(16)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .opacity(contentOpacity)
                .transition(.opacity)
            } else {
                ContentUnavailableView(
                    "暂无视频详情",
                    systemImage: "play.tv",
                    description: Text("视频平台没有返回更多内容。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        .navigationTitle("视频详情")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.28), value: loadViewState)
        .fullScreenCover(isPresented: $showFullscreenVideoPlayer) {
            if let videoInfo {
                CanvasVideoFullscreenPlayerView(
                    title: cleanedText(videoInfo.videName) ?? video.videoName,
                    subtitle: cleanedText(videoInfo.subjName)
                    ?? cleanedText(videoInfo.courName)
                    ?? cleanedText(session.courseName),
                    streams: videoInfo.playableStreams,
                    subtitles: subtitleSegments,
                    durationHintSeconds: videoInfo.videPlayTime,
                    session: session,
                    previewCourseID: videoInfo.courId
                )
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .task(id: video.videoId) {
            await loadDetail()
        }
    }

    @ViewBuilder
    private func errorState(message: String) -> some View {
        ContentUnavailableView {
            Label("无法获取视频详情", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重试") {
                Task {
                    await loadDetail(force: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func loadDetail(force: Bool = false) async {
        if !force && videoInfo != nil {
            return
        }

        let shouldAnimateContent = videoInfo == nil
        if shouldAnimateContent {
            contentOpacity = 0
        }

        isLoading = true
        loadErrorMessage = nil

        do {
            let info = try await CanvasVideoPlatformAPI.fetchVideoInfo(
                session: session,
                videoId: video.videoId
            )
            videoInfo = info

            if shouldAnimateContent {
                await Task.yield()
                withAnimation(.easeInOut(duration: 0.28)) {
                    contentOpacity = 1
                }
            } else {
                contentOpacity = 1
            }

            isLoading = false
            await loadEnhancements(for: info)
        } catch {
            if videoInfo != nil {
                isLoading = false
                supplementaryNotice = "刷新失败，当前显示的是上一次成功加载的内容。"
            } else {
                loadErrorMessage = detailErrorMessage(for: error)
                isLoading = false
            }
        }
    }

    @MainActor
    private func loadEnhancements(for info: CanvasVideoInfo) async {
        guard let courseId = info.courId else {
            courseSummary = nil
            transcriptSegments = []
            subtitleSegments = []
            pptSlides = []
            supplementaryNotice = "未解析到课程标识，摘要、字幕与课件预览暂时不可用。"
            return
        }

        isLoadingEnhancements = true
        supplementaryNotice = nil

        async let summaryResult: Result<CanvasVideoCourseSummary?, Error> = captureResult {
            try await CanvasVideoPlatformAPI.fetchCourseSummary(
                session: session,
                courseId: courseId
            )
        }
        async let transcriptResult: Result<CanvasVideoTranscriptPayload?, Error> = captureResult {
            try await CanvasVideoPlatformAPI.fetchTranscript(
                session: session,
                courseId: courseId
            )
        }
        async let slideResult: Result<[CanvasVideoPPTSlide], Error> = captureResult {
            try await CanvasVideoPlatformAPI.fetchPPTSlides(
                session: session,
                courseId: courseId
            )
        }

        let resolvedSummary = await summaryResult
        let resolvedTranscript = await transcriptResult
        let resolvedSlides = await slideResult

        var failedParts: [String] = []

        switch resolvedSummary {
        case let .success(summary):
            courseSummary = summary
        case .failure:
            courseSummary = nil
            failedParts.append("课程摘要")
        }

        switch resolvedTranscript {
        case let .success(transcript):
            transcriptSegments = transcript?.assembledSegments ?? []
            subtitleSegments = transcript?.subtitleSegments ?? []
        case .failure:
            transcriptSegments = []
            subtitleSegments = []
            failedParts.append("字幕摘录")
        }

        switch resolvedSlides {
        case let .success(slides):
            pptSlides = slides.filter { $0.hide != 1 }
        case .failure:
            pptSlides = []
            failedParts.append("课件预览")
        }

        isLoadingEnhancements = false

        if !failedParts.isEmpty {
            supplementaryNotice = "以下增强信息暂时不可用：\(failedParts.joined(separator: "、"))。"
        }
    }

    private func detailErrorMessage(for error: Error) -> String {
        switch error {
        case CanvasVideoBootstrapError.invalidVideoDetailResponse:
            return "视频平台返回了无效的详情数据，或任课教师已关闭课程点播。"
        default:
            return "无法加载视频详情，请稍后重试。"
        }
    }
}

private struct CanvasVideoHeroCard: View {
    let info: CanvasVideoInfo
    let fallbackVideo: CanvasVideoRecord
    let session: CanvasVideoPlatformSession

    private var titleText: String {
        cleanedText(info.videName) ?? fallbackVideo.videoName
    }

    private var subtitleText: String {
        cleanedText(info.subjName)
        ?? cleanedText(info.courName)
        ?? cleanedText(session.courseName)
        ?? "Canvas 课程视频"
    }

    private var progressValue: Double? {
        guard let duration = info.videPlayTime, duration > 0 else {
            return nil
        }

        let watchedSeconds = min(max(info.lastWatchTime ?? 0, 0), duration)
        return Double(watchedSeconds) / Double(duration)
    }

    private var metadataItems: [CanvasMetadataItem] {
        var items: [CanvasMetadataItem] = []

        if let duration = info.videPlayTime {
            items.append(
                CanvasMetadataItem(
                    systemImage: "timer",
                    text: formatDuration(seconds: duration)
                )
            )
        }

        if let beginEndText = formatSchedule(begin: info.videBeginTime, end: info.videEndTime) {
            items.append(
                CanvasMetadataItem(
                    systemImage: "calendar",
                    text: beginEndText
                )
            )
        }

        if let location = cleanedText(info.clroName) {
            items.append(
                CanvasMetadataItem(
                    systemImage: "building.2",
                    text: location
                )
            )
        }

        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.97, green: 0.44, blue: 0.18),
                                    Color(red: 0.86, green: 0.18, blue: 0.24)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: fallbackVideo.partClose ? "play.slash.fill" : "play.square.stack.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 8) {
                    Text(titleText)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text(subtitleText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        if fallbackVideo.partClose {
                            CanvasVideoPill(text: "已关闭", tint: .secondary)
                        } else {
                            CanvasVideoPill(text: "可播放", tint: .orange)
                        }

                        if let code = cleanedText(info.subjCode) {
                            CanvasVideoPill(text: code, tint: .blue)
                        }
                    }
                }
            }

            if let progressValue {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("观看进度")
                            .font(.subheadline.weight(.medium))

                        Spacer()

                        Text(progressText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: progressValue)
                        .tint(Color.orange)
                }
            } else if let duration = info.videPlayTime {
                VStack(alignment: .leading, spacing: 4) {
                    Text("视频总时长")
                        .font(.subheadline.weight(.medium))

                    Text(formatDuration(seconds: duration))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !metadataItems.isEmpty {
                CanvasMetadataGroup(items: metadataItems)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05))
        }
    }

    private var progressText: String {
        let watched = max(info.lastWatchTime ?? 0, 0)
        let duration = max(info.videPlayTime ?? watched, 0)
        return "\(formatDuration(seconds: watched)) / \(formatDuration(seconds: duration))"
    }
}

private struct CanvasVideoOpenPageCard: View {
    let hasVideoPageURL: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.18))

                    Image(systemName: "arrow.up.right.video.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 5) {
                    Text("播放录像")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("开始播放课堂录像")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.06, green: 0.42, blue: 0.77),
                                Color(red: 0.04, green: 0.60, blue: 0.67)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CanvasVideoNoticeCard: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct CanvasVideoInfoCard: View {
    let info: CanvasVideoInfo

    var body: some View {
        CanvasVideoSectionCard {
            CanvasSectionHeader(
                title: "课程信息",
                subtitle: "视频所属课程、授课教师与播放信息",
                systemImage: "rectangle.stack.person.crop",
                tint: .blue
            )

            VStack(spacing: 12) {
                if let teacher = cleanedText(info.userName) {
                    CanvasInfoRow(title: "授课教师", value: teacher)
                }

                if let organization = cleanedText(info.organizationName) {
                    CanvasInfoRow(title: "开课单位", value: organization, multiline: true)
                }

                if let location = cleanedText(info.clroName) {
                    CanvasInfoRow(title: "上课地点", value: location)
                }

                if let schedule = formatSchedule(begin: info.videBeginTime, end: info.videEndTime) {
                    CanvasInfoRow(title: "授课时间", value: schedule, multiline: true)
                }

                if !info.playbackChannels.isEmpty {
                    CanvasInfoRow(title: "可用机位", value: "\(info.playbackChannels.count)")
                }

                if let remarks = cleanedText(info.remarks) {
                    VStack(alignment: .leading, spacing: 6) {
                        Divider()

                        Text("备注")
                            .font(.subheadline.weight(.medium))

                        Text(remarks)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct CanvasVideoSummaryCard: View {
    let summary: CanvasVideoCourseSummary?
    let isLoading: Bool

    var body: some View {
        CanvasVideoSectionCard {
            CanvasSectionHeader(
                title: "课程速览",
                subtitle: "课程摘要与关键知识点",
                systemImage: "sparkles.rectangle.stack",
                tint: .orange
            )

            if let summary {
                if let overview = cleanedText(summary.fullOverview) {
                    Text(overview)
                        .font(.body)
                        .foregroundStyle(.primary)
                }

                if let keyPoints = summary.keyPoints, !keyPoints.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(keyPoints, id: \.self) { point in
                                Text(point)
                                    .font(.footnote.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.orange.opacity(0.12), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                    .padding(.horizontal, -18)
                } else if cleanedText(summary.fullOverview) == nil {
                    CanvasVideoPlaceholderContent(
                        title: "暂无课程摘要",
                        systemImage: "text.page.slash",
                        description: "视频平台还没有生成该节课的摘要内容。"
                    )
                }
            } else if isLoading {
                CanvasVideoLoadingContent(title: "正在加载课程摘要")
            } else {
                CanvasVideoPlaceholderContent(
                    title: "暂无课程摘要",
                    systemImage: "text.page.slash",
                    description: "视频平台还没有生成该节课的摘要内容。"
                )
            }
        }
    }
}

private struct CanvasVideoTimelineCard: View {
    let items: [CanvasVideoDocumentSkim]
    let isLoading: Bool
    private let previewLimit = 2

    private var previewItems: [CanvasVideoDocumentSkim] {
        Array(items.prefix(previewLimit))
    }

    private var showsAllButton: Bool {
        items.count > previewLimit
    }

    var body: some View {
        CanvasVideoSectionCard {
            CanvasSectionHeader(
                title: "分段速览",
                subtitle: "根据课程内容切分的重点段落",
                systemImage: "list.bullet.rectangle.portrait",
                tint: .green
            )

            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(previewItems) { item in
                        CanvasVideoTimelineItemView(item: item)

                        if item.id != previewItems.last?.id {
                            Divider()
                        }
                    }

                    if showsAllButton {
                        NavigationLink {
                            CanvasVideoTimelineListView(items: items)
                        } label: {
                            CanvasVideoShowAllRow(
                                title: "查看全部分段速览",
                                subtitle: "共 \(items.count) 个片段",
                                tint: .green
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if isLoading {
                CanvasVideoLoadingContent(title: "正在加载章节内容")
            } else {
                CanvasVideoPlaceholderContent(
                    title: "暂无章节速览",
                    systemImage: "list.bullet.rectangle",
                    description: "当前视频还没有可展示的章节切分。"
                )
            }
        }
    }
}

private struct CanvasVideoSlidesCard: View {
    let slides: [CanvasVideoPPTSlide]
    let isLoading: Bool
    private let previewLimit = 3

    private var previewSlides: [CanvasVideoPPTSlide] {
        Array(slides.prefix(previewLimit))
    }

    private var showsAllButton: Bool {
        slides.count > previewLimit
    }

    var body: some View {
        CanvasVideoSectionCard {
            CanvasSectionHeader(
                title: "课件预览",
                subtitle: "课件关键词与截图预览",
                systemImage: "photo.on.rectangle.angled",
                tint: .purple
            )

            if !slides.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(previewSlides) { slide in
                            CanvasVideoSlideCard(slide: slide)
                        }

                        if showsAllButton {
                            NavigationLink {
                                CanvasVideoSlidesListView(slides: slides)
                            } label: {
                                CanvasVideoShowAllSlideCard(totalCount: slides.count)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 2)
                }
                .padding(.horizontal, -18)
            } else if isLoading {
                CanvasVideoLoadingContent(title: "正在加载课件截图")
            } else {
                CanvasVideoPlaceholderContent(
                    title: "暂无课件预览",
                    systemImage: "photo.slash",
                    description: "当前视频还没有返回可显示的课件截图。"
                )
            }
        }
    }
}

private struct CanvasVideoTranscriptCard: View {
    let segments: [CanvasVideoTranscriptSegment]
    let isLoading: Bool
    private let previewLimit = 3

    private var previewSegments: [CanvasVideoTranscriptSegment] {
        Array(segments.prefix(previewLimit))
    }

    private var showsAllButton: Bool {
        segments.count > previewLimit
    }

    var body: some View {
        CanvasVideoSectionCard {
            CanvasSectionHeader(
                title: "字幕摘录",
                subtitle: "课程字幕时间线",
                systemImage: "captions.bubble",
                tint: .pink
            )

            if !segments.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(previewSegments) { segment in
                        CanvasVideoTranscriptSegmentView(segment: segment)

                        if segment.id != previewSegments.last?.id {
                            Divider()
                        }
                    }

                    if showsAllButton {
                        NavigationLink {
                            CanvasVideoTranscriptListView(segments: segments)
                        } label: {
                            CanvasVideoShowAllRow(
                                title: "查看全部字幕摘录",
                                subtitle: "共 \(segments.count) 条字幕",
                                tint: .pink
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if isLoading {
                CanvasVideoLoadingContent(title: "正在加载字幕摘录")
            } else {
                CanvasVideoPlaceholderContent(
                    title: "暂无字幕摘录",
                    systemImage: "captions.bubble.fill",
                    description: "当前视频还没有整理好的字幕内容。"
                )
            }
        }
    }
}

private struct CanvasVideoTimelineListView: View {
    let items: [CanvasVideoDocumentSkim]

    var body: some View {
        ScrollView {
            CanvasVideoSectionCard {
                CanvasSectionHeader(
                    title: "全部分段速览",
                    subtitle: "共 \(items.count) 个片段",
                    systemImage: "list.bullet.rectangle.portrait",
                    tint: .green
                )

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(items) { item in
                        CanvasVideoTimelineItemView(item: item)

                        if item.id != items.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("分段速览")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CanvasVideoSlidesListView: View {
    let slides: [CanvasVideoPPTSlide]

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 14, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CanvasVideoSectionCard {
                    CanvasSectionHeader(
                        title: "全部课件预览",
                        subtitle: "共 \(slides.count) 张截图",
                        systemImage: "photo.on.rectangle.angled",
                        tint: .purple
                    )

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(slides) { slide in
                            CanvasVideoSlideCard(slide: slide)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("课件预览")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CanvasVideoTranscriptListView: View {
    let segments: [CanvasVideoTranscriptSegment]

    var body: some View {
        ScrollView {
            CanvasVideoSectionCard {
                CanvasSectionHeader(
                    title: "全部字幕摘录",
                    subtitle: "共 \(segments.count) 条字幕",
                    systemImage: "captions.bubble",
                    tint: .pink
                )

                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(segments) { segment in
                        CanvasVideoTranscriptSegmentView(segment: segment)

                        if segment.id != segments.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("字幕摘录")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CanvasVideoTimelineItemView: View {
    let item: CanvasVideoDocumentSkim

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let time = formatTimeRange(beginMS: item.bg, endMS: item.ed) {
                Text(time)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.12), in: Capsule())
            }

            if let overview = cleanedText(item.overview) {
                Text(overview)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }

            if let content = cleanedText(item.content) {
                Text(content)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CanvasVideoTranscriptSegmentView: View {
    let segment: CanvasVideoTranscriptSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let time = formatTimeRange(beginMS: segment.bg, endMS: segment.ed) {
                Text(time)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.pink)
            }

            if let text = segment.text {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.primary)
            }
        }
    }
}

private struct CanvasVideoSlideCard: View {
    let slide: CanvasVideoPPTSlide
    @State private var loadedImage: UIImage?
    @State private var imageOpacity: Double = 0
    @State private var isImageLoading: Bool = false
    @State private var imageLoadFailed: Bool = false

    private static let maxImageRetryCount: Int = 2

    private var imageURL: URL? {
        normalizedCanvasAssetURL(from: slide.pptImgUrl)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                        .frame(width: 220, height: 128)

                if let imageURL {
                    Group {
                        if let loadedImage {
                            Image(uiImage: loadedImage)
                                .resizable()
                                .scaledToFill()
                                .opacity(imageOpacity)
                        } else if imageLoadFailed {
                            CanvasVideoSlidePlaceholder(systemImage: "photo.badge.exclamationmark")
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(width: 220, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .onAppear {
                        prefetchImageIfNeeded(url: imageURL)
                    }
                    .task(id: imageURL) {
                        await loadImageIfNeeded(url: imageURL)
                    }
                } else {
                    CanvasVideoSlidePlaceholder(systemImage: "photo")
                        .frame(width: 220, height: 128)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                if let time = formatSlideMoment(slide.createSec) {
                    Text(time)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(10)
                }
            }

            if !slide.displayKeywords.isEmpty {
                Text(slide.displayKeywords.joined(separator: " / "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .leading)
            }
        }
    }

    @MainActor
    private func prefetchImageIfNeeded(url: URL) {
        guard loadedImage == nil else { return }

        Task.detached(priority: .utility) {
            await CanvasVideoSlideImageLoader.shared.prefetch(
                url: url,
                maxRetryCount: Self.maxImageRetryCount
            )
        }
    }

    @MainActor
    private func loadImageIfNeeded(url: URL) async {
        guard loadedImage == nil, !isImageLoading else {
            return
        }

        if let cachedImage = await CanvasVideoSlideImageLoader.shared.cachedImage(for: url) {
            showImageWithFadeIn(cachedImage)
            imageLoadFailed = false
            return
        }

        isImageLoading = true
        imageLoadFailed = false

        defer {
            isImageLoading = false
        }

        do {
            let image = try await CanvasVideoSlideImageLoader.shared.image(
                for: url,
                maxRetryCount: Self.maxImageRetryCount
            )
            guard !Task.isCancelled else { return }
            showImageWithFadeIn(image)
            imageLoadFailed = false
        } catch is CancellationError {
            // Keep state unchanged. Loading can continue in the shared detached task.
        } catch {
            imageLoadFailed = true
        }
    }

    @MainActor
    private func showImageWithFadeIn(_ image: UIImage) {
        loadedImage = image
        imageOpacity = 0
        withAnimation(.easeInOut(duration: 0.28)) {
            imageOpacity = 1
        }
    }
}

private struct CanvasVideoShowAllRow: View {
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right.circle.fill")
                .font(.title3)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(0.1))
        )
    }
}

private struct CanvasVideoShowAllSlideCard: View {
    let totalCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 220, height: 128)

                VStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.title2)
                        .foregroundStyle(.purple)

                    Text("查看全部")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("共 \(totalCount) 张截图")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("继续浏览完整课件内容")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 220, alignment: .leading)
        }
    }
}

private actor CanvasVideoSlideImageLoader {
    static let shared = CanvasVideoSlideImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private var inFlightTasks: [URL: Task<UIImage, Error>] = [:]

    func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func prefetch(url: URL, maxRetryCount: Int) {
        _ = task(for: url, maxRetryCount: maxRetryCount)
    }

    func image(for url: URL, maxRetryCount: Int) async throws -> UIImage {
        if let cachedImage = cache.object(forKey: url as NSURL) {
            return cachedImage
        }

        let task = task(for: url, maxRetryCount: maxRetryCount)
        return try await task.value
    }

    private func task(for url: URL, maxRetryCount: Int) -> Task<UIImage, Error> {
        if let existingTask = inFlightTasks[url] {
            return existingTask
        }

        let task = Task.detached(priority: .utility) {
            try await CanvasVideoSlideImageLoader.fetchImage(
                from: url,
                maxRetryCount: maxRetryCount
            )
        }

        inFlightTasks[url] = task

        Task.detached(priority: .utility) {
            do {
                let image = try await task.value
                await CanvasVideoSlideImageLoader.shared.finish(
                    result: .success(image),
                    for: url
                )
            } catch {
                await CanvasVideoSlideImageLoader.shared.finish(
                    result: .failure(error),
                    for: url
                )
            }
        }

        return task
    }

    private func finish(result: Result<UIImage, Error>, for url: URL) {
        inFlightTasks[url] = nil

        if case let .success(image) = result {
            cache.setObject(image, forKey: url as NSURL)
        }
    }

    private static func fetchImage(from url: URL, maxRetryCount: Int) async throws -> UIImage {
        var attempt = 0

        while true {
            do {
                return try await requestImage(from: url)
            } catch {
                guard attempt < maxRetryCount else {
                    throw error
                }

                let backoffSeconds = UInt64(1 << attempt)
                attempt += 1
                try await Task.sleep(nanoseconds: backoffSeconds * 1_000_000_000)
            }
        }
    }

    private static func requestImage(from url: URL) async throws -> UIImage {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw CanvasVideoSlideImageLoaderError.badResponse(url)
        }
        guard let image = UIImage(data: data) else {
            throw CanvasVideoSlideImageLoaderError.invalidImageData(url)
        }
        return image
    }
}

private enum CanvasVideoSlideImageLoaderError: Error {
    case badResponse(URL)
    case invalidImageData(URL)
}

private struct CanvasVideoSlidePlaceholder: View {
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
            Text("课件截图")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CanvasVideoPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct CanvasVideoSectionCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05))
        }
    }
}

private struct CanvasVideoLoadingContent: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CanvasVideoPlaceholderContent: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))

            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private func captureResult<T>(
    _ operation: @escaping () async throws -> T
) async -> Result<T, Error> {
    do {
        return .success(try await operation())
    } catch {
        return .failure(error)
    }
}

private func cleanedText(_ value: String?) -> String? {
    guard let value else {
        return nil
    }

    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedValue.isEmpty ? nil : trimmedValue
}

private func formatDuration(seconds: Int) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
    formatter.zeroFormattingBehavior = [.pad]
    return formatter.string(from: TimeInterval(max(seconds, 0))) ?? "00:00"
}

private func formatTimeRange(beginMS: Int?, endMS: Int?) -> String? {
    switch (beginMS, endMS) {
    case let (begin?, end?):
        return "\(formatMilliseconds(begin)) - \(formatMilliseconds(end))"
    case let (begin?, nil):
        return formatMilliseconds(begin)
    case let (nil, end?):
        return formatMilliseconds(end)
    default:
        return nil
    }
}

private func formatSlideMoment(_ rawValue: String?) -> String? {
    guard let rawValue, let integerValue = Int(rawValue) else {
        return nil
    }

    let milliseconds = integerValue > 10_000 ? integerValue : integerValue * 1_000
    return formatMilliseconds(milliseconds)
}

private func formatMilliseconds(_ value: Int) -> String {
    let seconds = max(value / 1_000, 0)
    return formatDuration(seconds: seconds)
}

private func formatSchedule(begin: String?, end: String?) -> String? {
    let beginDate = begin.flatMap(parseVideoDate)
    let endDate = end.flatMap(parseVideoDate)

    switch (beginDate, endDate) {
    case let (beginDate?, endDate?):
        if Calendar.current.isDate(beginDate, inSameDayAs: endDate) {
            return "\(beginDate.formatted(date: .abbreviated, time: .shortened)) - \(endDate.formatted(date: .omitted, time: .shortened))"
        }

        return "\(beginDate.formatted(date: .abbreviated, time: .shortened)) - \(endDate.formatted(date: .abbreviated, time: .shortened))"
    case let (beginDate?, nil):
        return beginDate.formatted(date: .abbreviated, time: .shortened)
    case let (nil, endDate?):
        return endDate.formatted(date: .abbreviated, time: .shortened)
    default:
        return cleanedText(begin) ?? cleanedText(end)
    }
}

private func parseVideoDate(_ value: String) -> Date? {
    Date.fromFormat("yyyy-MM-dd HH:mm:ss", dateStr: value)
}
