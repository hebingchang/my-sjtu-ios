//
//  CanvasLiveVideoDetailView.swift
//  MySJTU
//
//  Created by boar on 2026/03/30.
//

import SwiftUI

struct CanvasLiveVideoDetailView: View {
    let liveVideo: CanvasLiveVideoRecord
    let relatedLiveVideos: [CanvasLiveVideoRecord]
    let session: CanvasVideoPlatformSession

    @State private var liveInfo: CanvasLiveVideoInfo?
    @State private var isLoading: Bool = true
    @State private var loadErrorMessage: String?
    @State private var showFullscreenVideoPlayer: Bool = false
    @State private var contentOpacity: Double = 1

    private enum LoadViewState: Equatable {
        case loading
        case error
        case content
        case placeholder
    }

    private var loadViewState: LoadViewState {
        if isLoading && liveInfo == nil {
            return .loading
        }
        if loadErrorMessage != nil && liveInfo == nil {
            return .error
        }
        if liveInfo != nil {
            return .content
        }
        return .placeholder
    }

    var body: some View {
        Group {
            if isLoading && liveInfo == nil {
                CanvasLoadingView(title: "正在加载直播详情")
                    .transition(.opacity)
            } else if let loadErrorMessage, liveInfo == nil {
                errorState(message: loadErrorMessage)
                    .transition(.opacity)
            } else if let liveInfo {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        CanvasLiveHeroCard(
                            info: liveInfo,
                            fallbackLive: liveVideo,
                            session: session
                        )

                        CanvasLiveOpenPlayerCard(
                            hasPlayableStreams: !liveInfo.playableStreams.isEmpty
                        ) {
                            showFullscreenVideoPlayer = true
                        }

                        CanvasLiveInfoCard(
                            info: liveInfo,
                            fallbackLive: liveVideo
                        )

                        if !relatedLiveVideos.isEmpty
                            || !(liveInfo.continueLiveVideoInfoResponseVoList?.isEmpty ?? true) {
                            CanvasLiveContinuationCard(
                                liveVideos: relatedLiveVideos,
                                referenceTimestamp: liveInfo.currentTime,
                                segments: liveInfo.continueLiveVideoInfoResponseVoList ?? []
                            )
                        }
                    }
                    .padding(16)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .opacity(contentOpacity)
                .transition(.opacity)
            } else {
                ContentUnavailableView(
                    "暂无直播详情",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text("直播平台没有返回更多内容。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        .navigationTitle("直播详情")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.28), value: loadViewState)
        .fullScreenCover(isPresented: $showFullscreenVideoPlayer) {
            if let liveInfo {
                fullscreenPlayer(for: liveInfo)
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .task(id: liveVideo.liveId) {
            await loadDetail()
        }
    }

    @ViewBuilder
    private func fullscreenPlayer(for liveInfo: CanvasLiveVideoInfo) -> some View {
        let title = canvasLiveCleanedText(liveInfo.courName) ?? liveVideo.courseName
        let subtitle = canvasLiveCleanedText(liveInfo.subjName)
        ?? canvasLiveCleanedText(liveVideo.teachingClassName)
        ?? canvasLiveCleanedText(session.courseName)
        
        CanvasVideoFullscreenPlayerView(
            title: title,
            subtitle: subtitle,
            streams: liveInfo.playableStreams,
            subtitles: [],
            durationHintSeconds: nil,
            session: session,
            previewCourseID: nil
        )
    }

    @ViewBuilder
    private func errorState(message: String) -> some View {
        ContentUnavailableView {
            Label("无法获取直播详情", systemImage: "exclamationmark.triangle")
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
        if !force && liveInfo != nil {
            return
        }

        let shouldAnimateContent = liveInfo == nil
        if shouldAnimateContent {
            contentOpacity = 0
        }

        isLoading = true
        loadErrorMessage = nil

        do {
            let info = try await CanvasVideoPlatformAPI.fetchLiveVideoInfo(
                session: session,
                liveId: liveVideo.liveId
            )
            liveInfo = info

            if shouldAnimateContent {
                await Task.yield()
                withAnimation(.easeInOut(duration: 0.28)) {
                    contentOpacity = 1
                }
            } else {
                contentOpacity = 1
            }
        } catch {
            loadErrorMessage = detailErrorMessage(for: error)
        }

        isLoading = false
    }

    private func detailErrorMessage(for error: Error) -> String {
        switch error {
        case CanvasVideoBootstrapError.invalidLiveDetailResponse:
            return "视频平台返回了无效的直播详情数据，或当前课程未开放直播。"
        default:
            return "无法加载直播详情，请稍后重试。"
        }
    }
}

private struct CanvasLiveHeroCard: View {
    let info: CanvasLiveVideoInfo
    let fallbackLive: CanvasLiveVideoRecord
    let session: CanvasVideoPlatformSession

    private var titleText: String {
        canvasLiveCleanedText(info.courName) ?? fallbackLive.courseName
    }

    private var subtitleText: String {
        canvasLiveCleanedText(info.subjName)
        ?? canvasLiveCleanedText(fallbackLive.teachingClassName)
        ?? canvasLiveCleanedText(session.courseName)
        ?? "Canvas 课程直播"
    }

    private var statusPresentation: CanvasLiveStatusPresentation {
        let referenceTimestamp = info.currentTime ?? Int(Date().timeIntervalSince1970 * 1_000)
        let beginTimestamp = fallbackLive.courseBeginTimeTimestamp
        let endTimestamp = fallbackLive.availabilityEndTimestamp

        if let beginTimestamp, beginTimestamp > referenceTimestamp {
            return CanvasLiveStatusPresentation(title: "即将开始", tint: .blue)
        }

        if let endTimestamp, endTimestamp < referenceTimestamp {
            return CanvasLiveStatusPresentation(title: "已结束", tint: .secondary)
        }

        return CanvasLiveStatusPresentation(title: "直播中", tint: .red)
    }

    private var metadataItems: [CanvasMetadataItem] {
        var items: [CanvasMetadataItem] = []

        if let scheduleText = canvasLiveFormatSchedule(
            begin: info.courBeginTime ?? fallbackLive.courseBeginTime,
            end: info.courEndTime ?? fallbackLive.courseEndTime
        ) {
            items.append(
                CanvasMetadataItem(
                    systemImage: "calendar",
                    text: scheduleText
                )
            )
        }

        if let location = canvasLiveCleanedText(info.clroName) ?? canvasLiveCleanedText(fallbackLive.classroomName) {
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
                                    Color(red: 0.93, green: 0.20, blue: 0.20),
                                    Color(red: 0.79, green: 0.10, blue: 0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: "dot.radiowaves.left.and.right")
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
                        CanvasLivePill(
                            text: statusPresentation.title,
                            tint: statusPresentation.tint
                        )

                        if let code = canvasLiveCleanedText(info.subjCode) {
                            CanvasLivePill(text: code, tint: .blue)
                        }
                    }
                }
            }

            if !metadataItems.isEmpty {
                CanvasMetadataGroup(items: metadataItems)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05))
        }
    }
}

private struct CanvasLiveOpenPlayerCard: View {
    let hasPlayableStreams: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.18))

                    Image(systemName: hasPlayableStreams ? "play.tv.fill" : "play.slash.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 5) {
                    Text("进入直播")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(hasPlayableStreams ? "开始播放当前课堂直播" : "视频平台暂未返回可用直播流")
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
                            colors: hasPlayableStreams
                            ? [
                                Color(red: 0.86, green: 0.15, blue: 0.16),
                                Color(red: 0.72, green: 0.08, blue: 0.20)
                            ]
                            : [
                                Color(red: 0.48, green: 0.48, blue: 0.50),
                                Color(red: 0.34, green: 0.34, blue: 0.36)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasPlayableStreams)
    }
}

private struct CanvasLiveNoticeCard: View {
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

private struct CanvasLiveInfoCard: View {
    let info: CanvasLiveVideoInfo
    let fallbackLive: CanvasLiveVideoRecord

    var body: some View {
        CanvasLiveSectionCard {
            CanvasSectionHeader(
                title: "直播信息",
                subtitle: "直播所属课程、授课教师与播放信息",
                systemImage: "dot.radiowaves.left.and.right",
                tint: .red
            )

            VStack(spacing: 12) {
                if let teacher = canvasLiveCleanedText(info.userName) ?? canvasLiveCleanedText(fallbackLive.userName) {
                    CanvasInfoRow(title: "授课教师", value: teacher)
                }

                if let location = canvasLiveCleanedText(info.clroName) ?? canvasLiveCleanedText(fallbackLive.classroomName) {
                    CanvasInfoRow(title: "上课地点", value: location)
                }

                if let schedule = canvasLiveFormatSchedule(
                    begin: info.courBeginTime ?? fallbackLive.courseBeginTime,
                    end: info.courEndTime ?? fallbackLive.courseEndTime
                ) {
                    CanvasInfoRow(title: "授课时间", value: schedule, multiline: true)
                }

                if !info.playbackChannels.isEmpty {
                    CanvasInfoRow(title: "可用机位", value: "\(info.playbackChannels.count)")
                }

                if let remarks = canvasLiveCleanedText(info.remarks) {
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

private struct CanvasLiveContinuationCard: View {
    let liveVideos: [CanvasLiveVideoRecord]
    let referenceTimestamp: Int?
    let segments: [CanvasLiveContinuationSegment]

    private var orderedLiveVideos: [CanvasLiveVideoRecord] {
        liveVideos.sorted { lhs, rhs in
            let lhsDate = canvasLiveContinuationSortDate(for: lhs)
            let rhsDate = canvasLiveContinuationSortDate(for: rhs)
            return canvasCompareDates(lhsDate, rhsDate, order: .ascending, fallback: lhs.id < rhs.id)
        }
    }

    private var showsDetailedLiveVideos: Bool {
        !orderedLiveVideos.isEmpty
    }

    var body: some View {
        CanvasLiveSectionCard {
            CanvasSectionHeader(
                title: "连续直播安排",
                subtitle: showsDetailedLiveVideos ? "当前课程可用的全部直播安排" : "当前直播链路下的连续课程时段",
                systemImage: "rectangle.stack.badge.play",
                tint: .blue
            )

            VStack(alignment: .leading, spacing: 14) {
                if showsDetailedLiveVideos {
                    ForEach(Array(orderedLiveVideos.enumerated()), id: \.element.id) { index, liveVideo in
                        CanvasLiveContinuationItem(
                            index: index + 1,
                            liveVideo: liveVideo,
                            referenceTimestamp: referenceTimestamp
                        )

                        if liveVideo.id != orderedLiveVideos.last?.id {
                            Divider()
                        }
                    }
                } else {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("第 \(index + 1) 节")
                                .font(.subheadline.weight(.medium))

                            Text(canvasLiveFormatTimestampRange(begin: segment.courBeginTime, end: segment.courEndTime) ?? "时间待定")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if segment.id != segments.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct CanvasLiveContinuationItem: View {
    let index: Int
    let liveVideo: CanvasLiveVideoRecord
    let referenceTimestamp: Int?

    private var titleText: String {
        canvasLiveCleanedText(liveVideo.teachingClassName)
        ?? canvasLiveCleanedText(liveVideo.subjectName)
        ?? liveVideo.courseName
    }

    private var subtitleText: String? {
        let subtitle = canvasLiveCleanedText(liveVideo.courseName)
        guard subtitle != titleText else {
            return nil
        }

        return subtitle
    }

    private var metadataItems: [CanvasMetadataItem] {
        var items: [CanvasMetadataItem] = []

        if let scheduleText = canvasLiveFormatSchedule(
            begin: liveVideo.courseBeginTime,
            end: liveVideo.courseEndTime
        ) ?? canvasLiveFormatTimestampRange(
            begin: liveVideo.courseBeginTimeTimestamp,
            end: liveVideo.availabilityEndTimestamp
        ) {
            items.append(
                CanvasMetadataItem(
                    systemImage: "calendar",
                    text: scheduleText
                )
            )
        }

        return items
    }

    private var statusPresentation: CanvasLiveStatusPresentation {
        canvasLiveStatusPresentation(for: liveVideo, referenceTimestamp: referenceTimestamp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("第 \(index) 场")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)

                    Text(subtitleText ?? titleText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)

                CanvasLivePill(
                    text: statusPresentation.title,
                    tint: statusPresentation.tint
                )
            }

            if !metadataItems.isEmpty {
                CanvasMetadataGroup(items: metadataItems)
            }
        }
    }
}

private struct CanvasLiveSectionCard<Content: View>: View {
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

private struct CanvasLivePill: View {
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

private struct CanvasLiveStatusPresentation {
    let title: String
    let tint: Color
}

private func canvasLiveCleanedText(_ value: String?) -> String? {
    guard let value else {
        return nil
    }

    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedValue.isEmpty ? nil : trimmedValue
}

private func canvasLiveFormatSchedule(begin: String?, end: String?) -> String? {
    let beginDate = begin.flatMap(canvasLiveParseDate)
    let endDate = end.flatMap(canvasLiveParseDate)

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
        return canvasLiveCleanedText(begin) ?? canvasLiveCleanedText(end)
    }
}

private func canvasLiveFormatTimestampRange(begin: Int?, end: Int?) -> String? {
    let beginDate = begin.map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) }
    let endDate = end.map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) }

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
        return nil
    }
}

private func canvasLiveParseDate(_ value: String) -> Date? {
    Date.fromFormat("yyyy-MM-dd HH:mm:ss", dateStr: value)
}

private func canvasLiveContinuationSortDate(for liveVideo: CanvasLiveVideoRecord) -> Date? {
    if let beginTimestamp = liveVideo.courseBeginTimeTimestamp {
        return Date(timeIntervalSince1970: TimeInterval(beginTimestamp) / 1_000)
    }

    if let beginText = liveVideo.courseBeginTime {
        return canvasLiveParseDate(beginText)
    }

    return nil
}

private func canvasLiveStatusPresentation(
    for liveVideo: CanvasLiveVideoRecord,
    referenceTimestamp: Int?
) -> CanvasLiveStatusPresentation {
    let referenceTimestamp = referenceTimestamp ?? Int(Date().timeIntervalSince1970 * 1_000)

    if let beginTimestamp = liveVideo.courseBeginTimeTimestamp, beginTimestamp > referenceTimestamp {
        return CanvasLiveStatusPresentation(title: "即将开始", tint: .blue)
    }

    if let endTimestamp = liveVideo.availabilityEndTimestamp, endTimestamp < referenceTimestamp {
        return CanvasLiveStatusPresentation(title: "已结束", tint: .secondary)
    }

    return CanvasLiveStatusPresentation(title: "直播中", tint: .red)
}
