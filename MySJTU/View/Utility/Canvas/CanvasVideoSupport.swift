//
//  CanvasVideoSupport.swift
//  MySJTU
//
//  Created by boar on 2026/03/29.
//

import Foundation
import Alamofire
import SwiftSoup

enum CanvasVideoBootstrapError: Error {
    case missingCanvasToken
    case missingCourseLegacyID
    case invalidSessionURL
    case missingLaunchForm
    case missingLaunchFormAction
    case missingTokenID
    case invalidAccessTokenResponse
    case missingCanvasCourseID
    case invalidVideoListResponse
    case missingAuthorizationPostFinalURL
    case unsupportedLaunchFormMethod
    case invalidVideoDetailResponse
    case invalidLiveListResponse
    case invalidLiveDetailResponse
    case invalidCourseSummaryResponse
    case invalidTranscriptResponse
    case invalidPPTSliceResponse
    case invalidSpriteImageResponse
}

struct CanvasVideoPlatformSession: Sendable {
    let jwtToken: String
    let canvasCourseID: String
    let courseName: String?

    func headers(contentType: String? = nil) -> HTTPHeaders {
        var headers: HTTPHeaders = [
            .accept("application/json"),
            HTTPHeader(name: "token", value: jwtToken)
        ]

        if let contentType {
            headers.add(.contentType(contentType))
        }

        return headers
    }
}

struct CanvasVideoListResult {
    let courseName: String?
    let session: CanvasVideoPlatformSession
    let videos: [CanvasVideoRecord]
    let liveStreams: [CanvasLiveVideoRecord]

    var isEmpty: Bool {
        videos.isEmpty && liveStreams.isEmpty
    }
}

struct CanvasVideoRecord: Decodable, Identifiable, Hashable {
    let classroomName: String?
    let courseBeginTime: String?
    let courseEndTime: String?
    let partClose: Bool
    let userName: String?
    let videoId: String
    let videoName: String

    var id: String {
        videoId
    }
}

struct CanvasLiveVideoRecord: Decodable, Identifiable, Hashable {
    let classroomName: String?
    let continuousCourseEndTime: String?
    let continuousCourseEndTimeTimestamp: Int?
    let courseBeginTime: String?
    let courseBeginTimeTimestamp: Int?
    let courseEndTime: String?
    let courseEndTimeTimestamp: Int?
    let courseId: Int?
    let courseName: String
    let liveId: String
    let subjectName: String?
    let teachingClassName: String?
    let userName: String?
    let videoPlayTime: Int?

    enum CodingKeys: String, CodingKey {
        case classroomName = "clroName"
        case continuousCourseEndTime
        case continuousCourseEndTimeTimestamp
        case courseBeginTime = "courBeginTime"
        case courseBeginTimeTimestamp
        case courseEndTime = "courEndTime"
        case courseEndTimeTimestamp
        case courseId = "courId"
        case courseName = "courName"
        case liveId = "id"
        case subjectName = "subjName"
        case teachingClassName = "teclName"
        case userName
        case videoPlayTime = "videPalyTime"
    }

    var id: String {
        liveId
    }

    var availabilityEndTimestamp: Int? {
        continuousCourseEndTimeTimestamp ?? courseEndTimeTimestamp
    }

    func isAvailable(referenceTimestamp: Int) -> Bool {
        guard let availabilityEndTimestamp else {
            return true
        }

        return availabilityEndTimestamp >= referenceTimestamp
    }
}

struct CanvasVideoInfo: Decodable {
    let videPlayTime: Int?
    let subjName: String?
    let courId: Int?
    let videCommentAverage: Double?
    let userAvatar: String?
    let videName: String?
    let courName: String?
    let videBeginTime: String?
    let lastWatchTime: Int?
    let id: Int
    let videSrtUrl: String?
    let vodurl: String?
    let organizationName: String?
    let teclId: Int?
    let subjCode: String?
    let videPlayCount: Int?
    let userName: String?
    let videVodId: Int?
    let clroName: String?
    let videEndTime: String?
    let videoPlayResponseVoList: [CanvasVideoPlaybackChannel]?
    let teclCode: String?
    let subjId: Int?
    let videCommentCount: Int?
    let remarks: String?

    var playbackChannels: [CanvasVideoPlaybackChannel] {
        videoPlayResponseVoList ?? []
    }

    var playableStreams: [CanvasVideoPlayableStream] {
        canvasPlayableStreams(from: playbackChannels)
    }
}

struct CanvasVideoPlayableStream: Identifiable, Hashable {
    let id: Int
    let title: String
    let url: URL
    let format: CanvasVideoStreamFormat
}

enum CanvasVideoStreamFormat: Hashable {
    case hls
    case flv
    case file
    case unknown

    var supportsAVPlayer: Bool {
        self != .flv
    }
}

struct CanvasLiveVideoInfo: Decodable {
    let subjName: String?
    let continueLiveVideoInfoResponseVoList: [CanvasLiveContinuationSegment]?
    let livePlayTime: Int?
    let courName: String?
    let videoStreamingProtocol: String?
    let id: Int
    let courBeginTime: String?
    let courLivePlayAddTimeCourEndTime: Int?
    let subjCode: String?
    let userName: String?
    let userId: Int?
    let clroName: String?
    let currentTime: Int?
    let continueCourEndTime: Int?
    let clroId: Int?
    let videoPlayResponseVoList: [CanvasVideoPlaybackChannel]?
    let subjId: Int?
    let courEndTime: String?
    let remarks: String?

    var playbackChannels: [CanvasVideoPlaybackChannel] {
        videoPlayResponseVoList ?? []
    }

    var playableStreams: [CanvasVideoPlayableStream] {
        canvasPlayableStreams(
            from: playbackChannels,
            fallbackProtocol: videoStreamingProtocol
        )
    }
}

struct CanvasLiveContinuationSegment: Decodable, Identifiable, Hashable {
    let courBeginTime: Int?
    let id: Int
    let courEndTime: Int?
}

struct CanvasVideoPlaybackChannel: Decodable {
    let videPlayTime: Int?
    let rtmpUrlHdv: String?
    let rtmpUrlFluency: String?
    let rtmpUrlDefault: String?
    let rtmpUrlDistinct: String?
    let clientIpType: Int?
    let cdviChannelNum: Int?
    let id: Int?
    let cdviViewNum: Int?

    var streamURL: URL? {
        normalizedCanvasVideoURL(from: rtmpUrlHdv)
        ?? normalizedCanvasVideoURL(from: rtmpUrlDefault)
        ?? normalizedCanvasVideoURL(from: rtmpUrlFluency)
        ?? normalizedCanvasVideoURL(from: rtmpUrlDistinct)
    }
}

struct CanvasVideoCourseSummary: Decodable {
    let fullOverview: String?
    let keyPoints: [String]?
    let documentSkims: [CanvasVideoDocumentSkim]?
    let subjCode: String?
    let subjName: String?
    let teclName: String?
    let videoBeginTime: String?
    let videoEndTime: String?
}

struct CanvasVideoDocumentSkim: Decodable, Identifiable {
    let bg: Int?
    let content: String?
    let ed: Int?
    let overview: String?
    let time: String?

    var id: String {
        "\(bg ?? -1)-\(ed ?? -1)-\(time ?? "skim")"
    }
}

struct CanvasVideoTranscriptPayload: Decodable {
    let afterAssemblyList: [CanvasVideoTranscriptSegment]?
    let beforeAssemblyList: [CanvasVideoTranscriptSegment]?
    let originalList: [CanvasVideoTranscriptSegment]?

    var subtitleSegments: [CanvasVideoTranscriptSegment] {
        let preferredSegments = (beforeAssemblyList ?? []).filter { $0.text != nil }
        if !preferredSegments.isEmpty {
            return preferredSegments
        }

        let fallbackSegments = (originalList ?? afterAssemblyList ?? []).filter { $0.text != nil }
        return fallbackSegments
    }

    var assembledSegments: [CanvasVideoTranscriptSegment] {
        let assembled = (afterAssemblyList ?? []).filter { $0.text != nil }
        if !assembled.isEmpty {
            return assembled
        }

        let fallback = (originalList ?? beforeAssemblyList ?? []).filter { $0.text != nil }
        return fallback
    }
}

struct CanvasVideoTranscriptSegment: Decodable, Identifiable, Hashable {
    let bg: Int?
    let ed: Int?
    let res: String?

    var id: String {
        "\(bg ?? -1)-\(ed ?? -1)-\(res ?? "segment")"
    }

    var text: String? {
        cleanedCanvasSubtitleText(from: res)
    }
}

struct CanvasVideoPPTSlide: Decodable, Identifiable {
    let createSec: String?
    let dupKeywords: [String]?
    let hide: Int?
    let key: String?
    let keywords: [String]?
    let pptImgUrl: String?

    var id: String {
        key ?? "\(createSec ?? "0")-\(pptImgUrl ?? "slide")"
    }

    var displayKeywords: [String] {
//        let source = (dupKeywords?.isEmpty == false ? dupKeywords : keywords) ?? []
        let source = keywords ?? []
        return source
    }
}

private struct CanvasVideoSessionTokenResponse: Decodable {
    let sessionURL: String

    enum CodingKeys: String, CodingKey {
        case sessionURL = "session_url"
    }
}

private struct CanvasVideoAccessTokenResponse: Decodable {
    let code: String
    let data: CanvasVideoAccessTokenPayload?
    let success: Bool
}

private struct CanvasVideoAccessTokenPayload: Decodable {
    let params: CanvasVideoAccessTokenParams?
    let token: String?
}

private struct CanvasVideoAccessTokenParams: Decodable {
    let courseName: String?
    let canvasCourseID: String?

    enum CodingKeys: String, CodingKey {
        case courseName
        case canvasCourseID = "courId"
    }
}

private struct CanvasVideoPayloadResponse<Payload: Decodable>: Decodable {
    let code: String
    let data: Payload?
    let success: Bool
}

private struct CanvasVideoSpriteImageResponse: Decodable {
    let code: String?
    let data: String?
    let message: String?
    let status: Int?
    let success: Bool
    let timestamp: Int?
}

private struct CanvasVideoListPayload: Decodable {
    let records: [CanvasVideoRecord]
}

private struct CanvasLiveVideoListPayload: Decodable {
    let records: [CanvasLiveVideoRecord]
}

private struct CanvasVideoLaunchForm {
    let actionURL: URL
    let method: HTTPMethod
    let fields: [CanvasVideoLaunchFormField]

    var parameters: [String: String] {
        Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value) })
    }
}

private struct CanvasVideoLaunchFormField: Identifiable {
    let name: String
    let value: String

    var id: String {
        "\(name)=\(value)"
    }
}

private struct CanvasVideoCourseDetailRequest: Encodable {
    let courseId: Int
    let platform: Int = 1
}

private struct CanvasLiveVideoListRequest: Encodable {
    let liveDays: Int = 3
    let pageIndex: Int = 1
    let pageSize: Int = 100
    let canvasCourseId: String
}

private let canvasSubtitleBoundaryCharacters: CharacterSet = {
    CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
        .union(.symbols)
        .union(CharacterSet(charactersIn: "，。！？；：、（）【】《》〈〉「」『』“”‘’…"))
}()

private func cleanedCanvasSubtitleText(from rawValue: String?) -> String? {
    guard let rawValue else {
        return nil
    }

    var scalars = Array(rawValue.unicodeScalars)

    while let first = scalars.first, canvasSubtitleBoundaryCharacters.contains(first) {
        scalars.removeFirst()
    }

    while let last = scalars.last, canvasSubtitleBoundaryCharacters.contains(last) {
        scalars.removeLast()
    }

    let cleanedValue = String(String.UnicodeScalarView(scalars))
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleanedValue.isEmpty ? nil : cleanedValue
}

private func normalizedCanvasVideoURL(from rawValue: String?) -> URL? {
    guard let rawValue else {
        return nil
    }

    let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedValue.isEmpty else {
        return nil
    }

    return URL(string: trimmedValue)
}

func normalizedCanvasAssetURL(from rawValue: String?) -> URL? {
    guard let rawValue,
          var components = URLComponents(string: rawValue) else {
        return nil
    }

    let isPresignedS3URL = components.queryItems?.contains(where: { $0.name == "X-Amz-Signature" }) == true
    let scheme = components.scheme?.lowercased()
    let hasDefaultPort =
        (scheme == "https" && components.port == 443)
        || (scheme == "http" && components.port == 80)

    if isPresignedS3URL && hasDefaultPort {
        // Some S3-compatible gateways validate the presigned `host` header without the default port.
        // Stripping :443/:80 keeps the request aligned with the signature that the server expects.
        components.port = nil
    }

    return components.url
}

private func canvasPlayableStreams(
    from channels: [CanvasVideoPlaybackChannel],
    fallbackProtocol: String? = nil
) -> [CanvasVideoPlayableStream] {
    channels.enumerated().compactMap { index, channel in
        guard let streamURL = channel.streamURL else {
            return nil
        }

//        let title: String
//        if let channelNumber = channel.cdviChannelNum {
//            title = "机位 \(channelNumber + 1)"
//        } else {
//            title = index == 0 ? "主机位" : "机位 \(index + 1)"
//        }

        let title: String
        title = index == 0 ? "主机位" : "机位 \(index + 1)"

        return CanvasVideoPlayableStream(
            id: channel.id ?? (-index - 1),
            title: title,
            url: streamURL,
            format: canvasVideoStreamFormat(
                for: streamURL,
                fallbackProtocol: fallbackProtocol
            )
        )
    }
}

private func canvasVideoStreamFormat(
    for url: URL,
    fallbackProtocol: String? = nil
) -> CanvasVideoStreamFormat {
    let lowercasePath = url.path.lowercased()
    let lowercaseAbsoluteString = url.absoluteString.lowercased()
    let pathExtension = url.pathExtension.lowercased()

    if pathExtension == "m3u8" || lowercaseAbsoluteString.contains(".m3u8") {
        return .hls
    }

    if pathExtension == "flv" || lowercaseAbsoluteString.contains(".flv") {
        return .flv
    }

    if ["mp4", "mov", "m4v", "ts", "mp3", "aac"].contains(pathExtension) {
        return .file
    }

    let normalizedProtocol = fallbackProtocol?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

    if let normalizedProtocol {
        if normalizedProtocol.contains("hls") || normalizedProtocol.contains("m3u8") {
            return .hls
        }

        if normalizedProtocol.contains("flv") {
            return .flv
        }
    }

    if lowercasePath.contains("/hls/") {
        return .hls
    }

    if lowercasePath.contains("/flv/") {
        return .flv
    }

    return .unknown
}

extension CanvasAPI {
    func fetchCanvasVideoList(courseLegacyID: String) async throws -> CanvasVideoListResult {
        let session = try await bootstrapCanvasVideoSession(courseLegacyID: courseLegacyID)
        async let videosResult: Result<[CanvasVideoRecord], Error> = canvasCaptureResult {
            try await CanvasVideoPlatformAPI.fetchVideoList(session: session)
        }
        async let liveStreamsResult: Result<[CanvasLiveVideoRecord], Error> = canvasCaptureResult {
            try await CanvasVideoPlatformAPI.fetchLiveList(session: session)
        }

        let resolvedVideos = await videosResult
        let resolvedLiveStreams = await liveStreamsResult

        let videos: [CanvasVideoRecord]
        let liveStreams: [CanvasLiveVideoRecord]

        switch resolvedVideos {
        case let .success(value):
            videos = value
        case let .failure(videoError):
            switch resolvedLiveStreams {
            case let .success(liveValue):
                videos = []
                liveStreams = liveValue

                return CanvasVideoListResult(
                    courseName: session.courseName,
                    session: session,
                    videos: videos,
                    liveStreams: liveStreams
                )
            case .failure:
                throw videoError
            }
        }

        switch resolvedLiveStreams {
        case let .success(value):
            liveStreams = value
        case .failure:
            liveStreams = []
        }

        return CanvasVideoListResult(
            courseName: session.courseName,
            session: session,
            videos: videos,
            liveStreams: liveStreams
        )
    }

    private func bootstrapCanvasVideoSession(courseLegacyID: String) async throws -> CanvasVideoPlatformSession {
        guard let token else {
            throw CanvasVideoBootstrapError.missingCanvasToken
        }

        guard let returnToURL = URL(
            string: "https://oc.sjtu.edu.cn/courses/\(courseLegacyID)/external_tools/8329?display=borderless"
        ) else {
            throw CanvasVideoBootstrapError.invalidSessionURL
        }

        let response = try await AF.request(
            "https://oc.sjtu.edu.cn/login/session_token",
            method: .get,
            parameters: [
                "return_to": returnToURL.absoluteString
            ],
            encoding: URLEncoding(destination: .queryString),
            headers: [
                "Authorization": "Bearer \(token)"
            ]
        )
        .validate()
        .serializingDecodable(CanvasVideoSessionTokenResponse.self)
        .value

        guard let sessionURL = URL(string: response.sessionURL) else {
            throw CanvasVideoBootstrapError.invalidSessionURL
        }

        let sessionResponse = await AF.request(sessionURL)
            .validate()
            .serializingString()
            .response

        if let error = sessionResponse.error {
            throw error
        }

        let sessionHTML = sessionResponse.value ?? ""
        let sessionFinalURL = sessionResponse.response?.url
        let launchForm = try CanvasVideoLaunchFormParser.parse(
            html: sessionHTML,
            baseURL: sessionFinalURL ?? sessionURL
        )
        let launchResponse = await performLaunchFormRequest(
            launchForm,
            refererURL: sessionFinalURL ?? sessionURL
        )

        if let error = launchResponse.error {
            throw error
        }

        let launchFinalPageURL = launchResponse.response?.url
        let launchFinalPageHTML = launchResponse.value ?? ""
        let authorizationForm = try CanvasVideoLaunchFormParser.parse(
            html: launchFinalPageHTML,
            baseURL: launchFinalPageURL ?? launchForm.actionURL
        )
        let authorizationResponse = await performLaunchFormRequest(
            authorizationForm,
            refererURL: launchFinalPageURL ?? launchForm.actionURL
        )

        if let error = authorizationResponse.error {
            throw error
        }

        guard let authorizationPostFinalURL = authorizationResponse.response?.url else {
            throw CanvasVideoBootstrapError.missingAuthorizationPostFinalURL
        }

        guard let tokenID = authorizationPostFinalURL.queryValue(for: "tokenId"), !tokenID.isEmpty else {
            throw CanvasVideoBootstrapError.missingTokenID
        }

        let accessTokenResponse = try await AF.request(
            "https://v.sjtu.edu.cn/jy-application-canvas-sjtu/lti3/getAccessTokenByTokenId",
            method: .get,
            parameters: [
                "tokenId": tokenID
            ],
            encoding: URLEncoding(destination: .queryString)
        )
        .validate()
        .serializingDecodable(CanvasVideoAccessTokenResponse.self)
        .value

        guard
            accessTokenResponse.success,
            accessTokenResponse.code == "0",
            let accessTokenPayload = accessTokenResponse.data,
            let jwtToken = accessTokenPayload.token,
            !jwtToken.isEmpty
        else {
            throw CanvasVideoBootstrapError.invalidAccessTokenResponse
        }

        guard
            let canvasCourseID = accessTokenPayload.params?.canvasCourseID,
            !canvasCourseID.isEmpty
        else {
            throw CanvasVideoBootstrapError.missingCanvasCourseID
        }

        return CanvasVideoPlatformSession(
            jwtToken: jwtToken,
            canvasCourseID: canvasCourseID,
            courseName: accessTokenPayload.params?.courseName
        )
    }

    private func performLaunchFormRequest(
        _ launchForm: CanvasVideoLaunchForm,
        refererURL: URL
    ) async -> DataResponse<String, AFError> {
        var headers: HTTPHeaders = [
            .contentType("application/x-www-form-urlencoded; charset=utf-8"),
            .init(name: "Referer", value: refererURL.absoluteString)
        ]

        if let origin = refererURL.originString {
            headers.add(name: "Origin", value: origin)
        }

        let encoding: ParameterEncoding
        switch launchForm.method {
        case .get:
            encoding = URLEncoding(destination: .queryString)
        case .post:
            encoding = URLEncoding.httpBody
        default:
            encoding = URLEncoding.default
        }

        return await AF.request(
            launchForm.actionURL,
            method: launchForm.method,
            parameters: launchForm.parameters,
            encoding: encoding,
            headers: headers
        )
        .validate()
        .serializingString()
        .response
    }
}

enum CanvasVideoPlatformAPI {
    static func fetchVideoList(session: CanvasVideoPlatformSession) async throws -> [CanvasVideoRecord] {
        let encodedCanvasCourseID = session.canvasCourseID
            .addingPercentEncoding(withAllowedCharacters: .rfc3986Unreserved)
            ?? session.canvasCourseID

        let response = try await AF.request(
            "https://v.sjtu.edu.cn/jy-application-canvas-sjtu/directOnDemandPlay/findVodVideoList",
            method: .post,
            parameters: [
                "canvasCourseId": encodedCanvasCourseID
            ],
            encoder: JSONParameterEncoder.default,
            headers: session.headers(contentType: "application/json")
        )
        .validate()
        .serializingDecodable(CanvasVideoPayloadResponse<CanvasVideoListPayload>.self)
        .value

        guard
            response.success,
            response.code == "0",
            let payload = response.data
        else {
            throw CanvasVideoBootstrapError.invalidVideoListResponse
        }

        return payload.records
    }

    static func fetchVideoInfo(
        session: CanvasVideoPlatformSession,
        videoId: String
    ) async throws -> CanvasVideoInfo {
        let response = try await AF.request(
            "https://v.sjtu.edu.cn/jy-application-canvas-sjtu/directOnDemandPlay/getVodVideoInfos",
            method: .post,
            parameters: [
                "playTypeHls": "true",
                "isAudit": "true",
                "id": videoId
            ],
            encoding: URLEncoding.httpBody,
            headers: session.headers(contentType: "application/x-www-form-urlencoded; charset=utf-8")
        )
        .validate()
        .serializingDecodable(CanvasVideoPayloadResponse<CanvasVideoInfo>.self)
        .value
                
        guard
            response.success,
            response.code == "0",
            let payload = response.data
        else {
            throw CanvasVideoBootstrapError.invalidVideoDetailResponse
        }

        return payload
    }

    static func fetchLiveList(session: CanvasVideoPlatformSession) async throws -> [CanvasLiveVideoRecord] {
        let encodedCanvasCourseID = session.canvasCourseID
            .addingPercentEncoding(withAllowedCharacters: .rfc3986Unreserved)
            ?? session.canvasCourseID

        let response = try await AF.request(
            "https://v.sjtu.edu.cn/jy-application-canvas-sjtu/directOnDemandPlay/findLiveList",
            method: .post,
            parameters: CanvasLiveVideoListRequest(canvasCourseId: encodedCanvasCourseID),
            encoder: JSONParameterEncoder.default,
            headers: session.headers(contentType: "application/json")
        )
        .validate()
        .serializingDecodable(CanvasVideoPayloadResponse<CanvasLiveVideoListPayload>.self)
        .value

        guard
            response.success,
            response.code == "0",
            let payload = response.data
        else {
            throw CanvasVideoBootstrapError.invalidLiveListResponse
        }

        let nowTimestamp = Int(Date().timeIntervalSince1970 * 1_000)
        return payload.records.filter { $0.isAvailable(referenceTimestamp: nowTimestamp) }
    }

    static func fetchLiveVideoInfo(
        session: CanvasVideoPlatformSession,
        liveId: String
    ) async throws -> CanvasLiveVideoInfo {
        let response = try await AF.request(
            "https://v.sjtu.edu.cn/jy-application-canvas-sjtu/directOnDemandPlay/getLiveVideoInfos",
            method: .post,
            parameters: [
                "id": liveId,
                "playTypeHls": "true",
                "clroLiveVodvideoRight": "liveRight"
            ],
            encoding: URLEncoding.httpBody,
            headers: session.headers(contentType: "application/x-www-form-urlencoded; charset=utf-8")
        )
        .validate()
        .serializingDecodable(CanvasVideoPayloadResponse<CanvasLiveVideoInfo>.self)
        .value

        guard
            response.success,
            response.code == "0",
            let payload = response.data
        else {
            throw CanvasVideoBootstrapError.invalidLiveDetailResponse
        }

        return payload
    }

    static func fetchCourseSummary(
        session: CanvasVideoPlatformSession,
        courseId: Int
    ) async throws -> CanvasVideoCourseSummary? {
        let response = try await AF.request(
            "https://v.sjtu.edu.cn/jy-application-canvas-sjtu/course/summary/canvas/detail",
            method: .post,
            parameters: CanvasVideoCourseDetailRequest(courseId: courseId),
            encoder: JSONParameterEncoder.default,
            headers: session.headers(contentType: "application/json")
        )
        .validate()
        .serializingDecodable(CanvasVideoPayloadResponse<CanvasVideoCourseSummary>.self)
        .value

        guard response.success, response.code == "0" else {
            throw CanvasVideoBootstrapError.invalidCourseSummaryResponse
        }

        return response.data
    }

    static func fetchTranscript(
        session: CanvasVideoPlatformSession,
        courseId: Int
    ) async throws -> CanvasVideoTranscriptPayload? {
        let response = try await AF.request(
            "https://v.sjtu.edu.cn/jy-application-canvas-sjtu/transfer/translate/detail",
            method: .post,
            parameters: CanvasVideoCourseDetailRequest(courseId: courseId),
            encoder: JSONParameterEncoder.default,
            headers: session.headers(contentType: "application/json")
        )
        .validate()
        .serializingDecodable(CanvasVideoPayloadResponse<CanvasVideoTranscriptPayload>.self)
        .value

        guard response.success, response.code == "0" else {
            throw CanvasVideoBootstrapError.invalidTranscriptResponse
        }

        return response.data
    }

    static func fetchPPTSlides(
        session: CanvasVideoPlatformSession,
        courseId: Int
    ) async throws -> [CanvasVideoPPTSlide] {
        let response = try await AF.request(
            "https://v.sjtu.edu.cn/jy-application-canvas-sjtu/directOnDemandPlay/vod-analysis/query-ppt-slice-es",
            method: .get,
            parameters: [
                "ivsVideoId": String(courseId)
            ],
            encoding: URLEncoding(destination: .queryString),
            headers: session.headers()
        )
        .validate()
        .serializingDecodable(CanvasVideoPayloadResponse<[CanvasVideoPPTSlide]>.self)
        .value

        guard response.success, response.code == "0" else {
            throw CanvasVideoBootstrapError.invalidPPTSliceResponse
        }

        return response.data ?? []
    }

    static func fetchSpriteImageURL(
        session: CanvasVideoPlatformSession,
        courseId: Int,
        spriteIndex: Int
    ) async throws -> URL {
        let response = try await AF.request(
            "https://v.sjtu.edu.cn/jy-application-canvas-sjtu/sprite-image/get/ivs/\(courseId)/\(spriteIndex)",
            method: .get,
            headers: session.headers()
        )
        .validate()
        .serializingDecodable(CanvasVideoSpriteImageResponse.self)
        .value

        guard
            response.success,
            let rawURL = response.data?.trimmingCharacters(in: .whitespacesAndNewlines),
            !rawURL.isEmpty,
            let url = normalizedCanvasAssetURL(from: rawURL)
        else {
            throw CanvasVideoBootstrapError.invalidSpriteImageResponse
        }

        return url
    }
}

private func canvasCaptureResult<T>(
    _ operation: @escaping () async throws -> T
) async -> Result<T, Error> {
    do {
        return .success(try await operation())
    } catch {
        return .failure(error)
    }
}

private enum CanvasVideoLaunchFormParser {
    static func parse(html: String, baseURL: URL) throws -> CanvasVideoLaunchForm {
        let document = try SwiftSoup.parse(html, baseURL.absoluteString)
        guard let form = try document.select("form#tool_form, form[data-message-type=tool_launch], form").first() else {
            throw CanvasVideoBootstrapError.missingLaunchForm
        }

        let action = try form.attr("action").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !action.isEmpty else {
            throw CanvasVideoBootstrapError.missingLaunchFormAction
        }

        guard let actionURL = URL(string: action, relativeTo: baseURL)?.absoluteURL else {
            throw CanvasVideoBootstrapError.missingLaunchFormAction
        }

        let methodValue = try form.attr("method").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let method: HTTPMethod
        if methodValue.isEmpty || methodValue == HTTPMethod.get.rawValue {
            method = .get
        } else if methodValue == HTTPMethod.post.rawValue {
            method = .post
        } else {
            throw CanvasVideoBootstrapError.unsupportedLaunchFormMethod
        }

        var fields: [CanvasVideoLaunchFormField] = []

        for element in try form.select("input[name], textarea[name], select[name]") {
            if element.hasAttr("disabled") {
                continue
            }

            let name = try element.attr("name").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                continue
            }

            let tagName = element.tagNameNormal()
            switch tagName {
            case "input":
                let type = try element.attr("type").lowercased()

                if ["submit", "button", "image", "file", "reset"].contains(type) {
                    continue
                }

                if ["checkbox", "radio"].contains(type), !element.hasAttr("checked") {
                    continue
                }

                fields.append(
                    CanvasVideoLaunchFormField(
                        name: name,
                        value: try element.attr("value")
                    )
                )
            case "textarea":
                fields.append(
                    CanvasVideoLaunchFormField(
                        name: name,
                        value: try element.text()
                    )
                )
            case "select":
                let selectedOption = try element.select("option[selected]").first() ?? element.select("option").first()
                guard let selectedOption else {
                    continue
                }

                let value = try selectedOption.attr("value")
                fields.append(
                    CanvasVideoLaunchFormField(
                        name: name,
                        value: value.isEmpty ? try selectedOption.text() : value
                    )
                )
            default:
                continue
            }
        }

        return CanvasVideoLaunchForm(
            actionURL: actionURL,
            method: method,
            fields: fields
        )
    }
}

private extension URL {
    var originString: String? {
        guard let scheme, let host else {
            return nil
        }

        if let port {
            return "\(scheme)://\(host):\(port)"
        }

        return "\(scheme)://\(host)"
    }

    func queryValue(for name: String) -> String? {
        let components = URLComponents(url: self, resolvingAgainstBaseURL: false)

        if let value = components?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
        {
            return value
        }

        if
            let fragment = components?.fragment,
            let questionMarkIndex = fragment.firstIndex(of: "?")
        {
            var fragmentComponents = URLComponents()
            fragmentComponents.query = String(fragment[fragment.index(after: questionMarkIndex)...])

            if let value = fragmentComponents.queryItems?.first(where: { $0.name == name })?.value {
                return value
            }
        }

        guard let valueRange = absoluteString.range(of: "\(name)=") else {
            return nil
        }

        let rawValue = absoluteString[valueRange.upperBound...]
            .split(separator: "&", maxSplits: 1)
            .first
            .map(String.init)

        return rawValue?.removingPercentEncoding ?? rawValue
    }
}
