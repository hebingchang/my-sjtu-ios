import SwiftUI
import SceneKit
import UIKit
import Foundation
import CoreMotion

// MARK: - Model

struct PanoramaHotspot: Identifiable {
    let id: String
    let title: String
    let pan: Float
    let tilt: Float
}

struct PanoramaConfig {
    struct MultiResLevel {
        let width: Int
        let height: Int
    }

    var tileURLs: [Int: String] = [:]
    var multiResTileTemplate: String?
    var multiResTileSize: Int?
    var multiResLevels: [MultiResLevel] = []
    var levelingPitch: Float = 0
    var levelingRoll: Float = 0

    var startPan: Float = 0
    var startTilt: Float = 0
    var startFov: CGFloat = 70

    var minTilt: Float = -85
    var maxTilt: Float = 85

    var minFov: CGFloat = 30
    var maxFov: CGFloat = 90

    var hotspots: [PanoramaHotspot] = []

    var preferredMultiResLevels: [Int] {
        guard !multiResLevels.isEmpty else { return [0] }
        return Array((0..<multiResLevels.count).reversed())
    }

    func previewTilePath() -> String? {
        previewTilePaths().first
    }

    func previewTilePaths() -> [String] {
        if let firstTilePath = tileURLs.sorted(by: { $0.key < $1.key }).first?.value {
            return [firstTilePath]
        }

        guard multiResTileTemplate != nil else { return [] }

        var candidates: [String] = []
        for level in preferredMultiResLevels {
            for faceIndex in 0...5 {
                if let candidate = multiResTilePath(faceIndex: faceIndex, level: level, x: 0, y: 0) {
                    candidates.append(candidate)
                }
            }
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    func multiResTilePath(faceIndex: Int, level: Int, x: Int, y: Int) -> String? {
        guard let multiResTileTemplate else { return nil }

        return multiResTileTemplate
            .replacingOccurrences(of: "%c", with: "\(faceIndex)")
            .replacingOccurrences(of: "%l", with: "\(level)")
            .replacingOccurrences(of: "%x", with: "\(x)")
            .replacingOccurrences(of: "%y", with: "\(y)")
    }

    func expectedFaceSize(forLevel level: Int) -> CGSize? {
        guard !multiResLevels.isEmpty else { return nil }

        // Pano2VR 的 <level> 列表通常按高到低给出，URL 里的 l_0 是最低分辨率。
        let mappedIndex = multiResLevels.count - 1 - level
        guard multiResLevels.indices.contains(mappedIndex) else { return nil }

        let descriptor = multiResLevels[mappedIndex]
        guard descriptor.width > 0, descriptor.height > 0 else { return nil }
        return CGSize(width: descriptor.width, height: descriptor.height)
    }
}

enum PanoramaParserError: Error {
    case invalidXML
    case invalidImageData(URL)
}

enum PanoramaLoadingState: Equatable {
    case loading(message: String, progress: Double?)
    case ready
    case failed(message: String)

    var statusText: String {
        switch self {
        case .loading(let message, _):
            return message
        case .ready:
            return "拖动即可浏览全景"
        case .failed(let message):
            return message
        }
    }
}

struct PanoramaControlState: Equatable {
    var resetToken: Int = 0
    var zoomInToken: Int = 0
    var zoomOutToken: Int = 0
    var reloadToken: Int = 0
}

extension Float {
    var radians: Float { self * .pi / 180 }
}

// MARK: - XML Parser

final class PanoramaXMLParser: NSObject, XMLParserDelegate {
    private var config = PanoramaConfig()
    private var targetPanoramaID: String?
    private var selectedPanoramaID: String?
    private var currentPanoramaID: String?
    private var parsingCurrentPanorama = true

    static func parse(data: Data) throws -> PanoramaConfig {
        let parser = XMLParser(data: data)
        let delegate = PanoramaXMLParser()
        parser.delegate = delegate

        guard parser.parse() else {
            throw parser.parserError ?? PanoramaParserError.invalidXML
        }
        return delegate.config
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        let element = elementName.lowercased()
        let attributes = normalizedAttributes(from: attributeDict)

        switch element {
        case "tour":
            targetPanoramaID = trimmed(attributes["start"])

        case "panorama":
            handlePanoramaStart(attributes: attributes)
            return

        default:
            break
        }

        guard shouldParseCurrentElement else { return }

        switch element {
        case "input":
            for i in 0...5 {
                if let value = attributes["tile\(i)url"], !value.isEmpty {
                    config.tileURLs[i] = value
                }
            }

            config.levelingPitch = parseFloat(attributes["levelingpitch"], fallback: 0)
            config.levelingRoll = parseFloat(attributes["levelingroll"], fallback: 0)

            if let levelTileURL = trimmed(attributes["leveltileurl"]), !levelTileURL.isEmpty {
                config.multiResTileTemplate = levelTileURL
            }

            if let levelTileSize = parseInt(attributes["leveltilesize"]), levelTileSize > 0 {
                config.multiResTileSize = levelTileSize
            }

        case "level":
            if let width = parseInt(attributes["width"]),
               let height = parseInt(attributes["height"]),
               width > 0,
               height > 0 {
                config.multiResLevels.append(.init(width: width, height: height))
            }

        case "start":
            config.startPan = parseFloat(attributes["pan"], fallback: 0)
            config.startTilt = parseFloat(attributes["tilt"], fallback: 0)
            config.startFov = parseCGFloat(attributes["fov"], fallback: 70)

        case "min":
            config.minTilt = parseFloat(attributes["tilt"], fallback: -85)
            if let minFov = parseCGFloat(attributes["fov"]) {
                config.minFov = minFov
            }

        case "max":
            config.maxTilt = parseFloat(attributes["tilt"], fallback: 85)
            config.maxFov = parseCGFloat(attributes["fov"], fallback: 90)

        case "hotspot":
            let id = trimmed(attributes["id"]) ?? UUID().uuidString
            let title = trimmed(attributes["title"]) ?? id
            let pan = parseFloat(attributes["pan"], fallback: 0)
            let tilt = parseFloat(attributes["tilt"], fallback: 0)

            config.hotspots.append(
                PanoramaHotspot(id: id, title: title, pan: pan, tilt: tilt)
            )

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName.lowercased() == "panorama" {
            currentPanoramaID = nil
            parsingCurrentPanorama = true
        }
    }

    private var shouldParseCurrentElement: Bool {
        guard currentPanoramaID != nil else { return true }
        return parsingCurrentPanorama
    }

    private func handlePanoramaStart(attributes: [String: String]) {
        let panoramaID = trimmed(attributes["id"])
        currentPanoramaID = panoramaID

        if let targetPanoramaID, !targetPanoramaID.isEmpty {
            let isTarget = panoramaID == targetPanoramaID
            if isTarget {
                selectedPanoramaID = panoramaID
            }
            parsingCurrentPanorama = isTarget
            return
        }

        if let selectedPanoramaID {
            parsingCurrentPanorama = panoramaID == selectedPanoramaID
            return
        }

        if let panoramaID {
            selectedPanoramaID = panoramaID
        }
        parsingCurrentPanorama = true
    }

    private func normalizedAttributes(from attributes: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        result.reserveCapacity(attributes.count)

        for (key, value) in attributes {
            result[key.lowercased()] = value
        }
        return result
    }

    private func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseFloat(_ rawValue: String?, fallback: Float) -> Float {
        guard let parsed = parseFloat(rawValue) else { return fallback }
        return parsed
    }

    private func parseFloat(_ rawValue: String?) -> Float? {
        guard let value = trimmed(rawValue), !value.isEmpty else { return nil }
        return Float(value)
    }

    private func parseCGFloat(_ rawValue: String?, fallback: CGFloat) -> CGFloat {
        guard let parsed = parseCGFloat(rawValue) else { return fallback }
        return parsed
    }

    private func parseCGFloat(_ rawValue: String?) -> CGFloat? {
        guard let value = trimmed(rawValue), !value.isEmpty, let parsed = Double(value) else {
            return nil
        }
        return CGFloat(parsed)
    }

    private func parseInt(_ rawValue: String?) -> Int? {
        guard let value = trimmed(rawValue), !value.isEmpty else { return nil }
        if let parsed = Int(value) {
            return parsed
        }
        if let parsed = Double(value) {
            return Int(parsed)
        }
        return nil
    }
}

// MARK: - Image Loader

actor RemoteImageLoader {
    static let shared = RemoteImageLoader()

    private let cache = NSCache<NSURL, UIImage>()

    func image(for url: URL) async throws -> UIImage {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode,
              let image = UIImage(data: data) else {
            throw PanoramaParserError.invalidImageData(url)
        }

        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

// MARK: - SwiftUI Wrapper

struct PanoramaNativeView: UIViewRepresentable {
    let xmlURL: URL
    var controlState: PanoramaControlState = PanoramaControlState()
    var gyroscopeEnabled: Bool = false
    var onLoadingStateChange: ((PanoramaLoadingState) -> Void)? = nil
    var onHotspotTap: ((PanoramaHotspot) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> SCNView {
        context.coordinator.makeView()
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.setGyroscopeEnabled(gyroscopeEnabled)
        context.coordinator.handleControlState(controlState)
        context.coordinator.update(xmlURL: xmlURL)
    }

    final class Coordinator: NSObject {
        var parent: PanoramaNativeView

        private let scene = SCNScene()
        private let cameraNode = SCNNode()
        private let camera = SCNCamera()
        private let panoramaRootNode = SCNNode()

        private weak var scnView: SCNView?

        private var lastXMLURL: URL?
        private var lastControlState = PanoramaControlState()
        private var loadTask: Task<Void, Never>?

        private var config = PanoramaConfig()

        private var yaw: Float = 0
        private var pitch: Float = 0
        private var fov: CGFloat = 70
        private var pinchStartFov: CGFloat = 70

        private struct HotspotTapSample {
            let offset: CGPoint
            let radius: CGFloat
        }

        private var hotspotMap: [String: PanoramaHotspot] = [:]
        private let hotspotCategoryBitMask = 1 << 2
        private let hotspotRootNodePrefix = "hotspot:"
        private let hotspotHitNodePrefix = "hotspot-hit:"
        private let hotspotTouchTargetRadius: CGFloat = 28
        private let comfortableInitialFov: CGFloat = 78
        private lazy var hotspotTapSamples: [HotspotTapSample] = makeHotspotTapSamples()

        private var displayLink: CADisplayLink?
        private var angularVelocityYaw: Float = 0      // degrees / second
        private var angularVelocityPitch: Float = 0    // degrees / second
        private let decelerationPerFrame: Float = 0.92
        
        private let motionManager = CMMotionManager()
        private let motionQueue: OperationQueue = {
            let q = OperationQueue()
            q.name = "panorama.motion"
            q.qualityOfService = .userInteractive
            return q
        }()

        private var useGyroscope = true

        private var motionReferenceAttitude: CMAttitude?
        private var motionReferenceLookDirection = SIMD3<Float>(0, 0, -1)
        private var motionReferenceYaw: Float = 0
        private var motionReferencePitch: Float = 0

        private var motionBaseYaw: Float = 0
        private var motionBasePitch: Float = 0

        private var gestureYawOffset: Float = 0
        private var gesturePitchOffset: Float = 0
        
        func setGyroscopeEnabled(_ enabled: Bool) {
            guard useGyroscope != enabled else { return }

            useGyroscope = enabled

            if enabled {
                gestureYawOffset = 0
                gesturePitchOffset = 0
                motionBaseYaw = yaw
                motionBasePitch = pitch
                motionReferenceAttitude = nil
                startMotion()
            } else {
                stopMotion()
                motionReferenceAttitude = nil
            }
        }
        
        init(parent: PanoramaNativeView) {
            self.parent = parent
        }

        deinit {
            loadTask?.cancel()
            stopInertia()
            stopMotion()
        }

        func makeView() -> SCNView {
            let view = SCNView(frame: .zero)
            view.scene = scene
            view.backgroundColor = .black
            view.antialiasingMode = .multisampling4X
            view.isPlaying = true
            view.rendersContinuously = true
            view.autoenablesDefaultLighting = false
            view.allowsCameraControl = false

            setupCamera()
            view.pointOfView = cameraNode
            addGestures(to: view)

            self.scnView = view
            setGyroscopeEnabled(parent.gyroscopeEnabled)
            update(xmlURL: parent.xmlURL)
            
            return view
        }

        private func handleDeviceMotion(_ motion: CMDeviceMotion) {
            guard useGyroscope else { return }

            // 第一次收到数据时，记住“当前设备姿态”和“当前全景视线方向”
            if motionReferenceAttitude == nil {
                motionReferenceAttitude = motion.attitude.copy() as? CMAttitude
                motionReferenceLookDirection = worldDirection(pan: yaw, tilt: pitch)
                motionReferenceYaw = yaw
                motionReferencePitch = pitch
            }

            guard
                let reference = motionReferenceAttitude,
                let relativeAttitude = motion.attitude.copy() as? CMAttitude
            else {
                return
            }

            // 当前姿态相对“起始姿态”的变化
            relativeAttitude.multiply(byInverseOf: reference)

            let q = relativeAttitude.quaternion
            let relativeRotation = simd_quatf(
                ix: Float(q.x),
                iy: Float(q.y),
                iz: Float(q.z),
                r:  Float(q.w)
            )

            // 用相对旋转去转动“起始视线方向”
            let lookDirection = normalize(
                relativeRotation.act(motionReferenceLookDirection)
            )

            let target = yawPitchFromDirection(lookDirection)
            let yawDelta = shortestAngleDelta(from: motionReferenceYaw, to: target.yaw)
            let pitchDelta = target.pitch - motionReferencePitch

            motionBaseYaw = motionReferenceYaw + yawDelta
            // Panorama uses the opposite sign convention for vertical look changes,
            // so we invert only the motion delta to keep the initial view stable.
            motionBasePitch = motionReferencePitch - pitchDelta

            yaw = motionBaseYaw + gestureYawOffset
            pitch = motionBasePitch + gesturePitchOffset
            pitch = min(config.maxTilt, max(config.minTilt, pitch))

            applyCamera()
        }

        private enum PanoramaLoadError: Error {
            case invalidResponse
            case badStatus(Int)
        }

        private struct CubeLoadSummary {
            let expected: Int
            let loaded: Int
            let failed: Int
        }

        private struct MultiResTile {
            let x: Int
            let y: Int
            let image: UIImage
        }

        func handleControlState(_ state: PanoramaControlState) {
            if state.reloadToken != lastControlState.reloadToken {
                forceReload()
            }
            if state.resetToken != lastControlState.resetToken {
                resetView(animated: true)
            }
            if state.zoomInToken != lastControlState.zoomInToken {
                zoomIn()
            }
            if state.zoomOutToken != lastControlState.zoomOutToken {
                zoomOut()
            }

            lastControlState = state
        }
        
        func update(xmlURL: URL) {
            guard lastXMLURL != xmlURL else { return }
            lastXMLURL = xmlURL

            loadTask?.cancel()
            loadTask = Task { [weak self] in
                guard let self else { return }
                await loadRemotePanorama(from: xmlURL)
            }
        }

        private func forceReload() {
            lastXMLURL = nil
            update(xmlURL: parent.xmlURL)
        }

        @MainActor
        private func reportLoadingState(_ state: PanoramaLoadingState) {
            parent.onLoadingStateChange?(state)
        }

        private func adjustedStartFov(for panoramaConfig: PanoramaConfig) -> CGFloat {
            let widened = max(panoramaConfig.startFov, comfortableInitialFov)
            return min(max(widened, panoramaConfig.minFov), panoramaConfig.maxFov)
        }

        private func setupCamera() {
            camera.zNear = 0.01
            camera.zFar = 100
            camera.fieldOfView = comfortableInitialFov
            cameraNode.camera = camera
            scene.rootNode.addChildNode(cameraNode)
        }

        @MainActor
        private func resetSceneForLoading() {
            hotspotMap.removeAll()
            panoramaRootNode.childNodes.forEach { $0.removeFromParentNode() }
            for node in scene.rootNode.childNodes where node !== cameraNode {
                node.removeFromParentNode()
            }
        }

        private func loadRemotePanorama(from xmlURL: URL) async {
            await MainActor.run {
                reportLoadingState(.loading(message: "正在连接全景资源...", progress: nil))
                resetSceneForLoading()
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: xmlURL)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse else {
                    throw PanoramaLoadError.invalidResponse
                }
                guard 200..<300 ~= http.statusCode else {
                    throw PanoramaLoadError.badStatus(http.statusCode)
                }

                let parsed = try PanoramaXMLParser.parse(data: data)
                try Task.checkCancellation()

                await MainActor.run {
                    var adjustedConfig = parsed
                    adjustedConfig.startFov = adjustedStartFov(for: parsed)

                    self.config = adjustedConfig
                    self.yaw = adjustedConfig.startPan
                    self.pitch = adjustedConfig.startTilt
                    self.fov = adjustedConfig.startFov
                    self.gestureYawOffset = 0
                    self.gesturePitchOffset = 0
                    self.motionBaseYaw = self.yaw
                    self.motionBasePitch = self.pitch
                    self.motionReferenceAttitude = nil
                    self.applyCamera()
                    self.buildCubePlaceholders()
                    self.addHotspots()
                    self.reportLoadingState(.loading(message: "正在渲染全景图...", progress: 0))
                }

                let summary = await loadCubeImages(baseXMLURL: xmlURL)
                try Task.checkCancellation()

                await MainActor.run {
                    if summary.expected > 0, summary.loaded == 0 {
                        reportLoadingState(.failed(message: "全景图片加载失败，请重试"))
                    } else {
                        reportLoadingState(.ready)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                print("Failed loading remote panorama:", error)
                await MainActor.run {
                    reportLoadingState(.failed(message: errorMessage(for: error)))
                }
            }
        }

        @MainActor
        private func buildCubePlaceholders() {
            panoramaRootNode.name = "panoramaRoot"
            panoramaRootNode.simdOrientation = panoramaLevelingOrientation()

            let cubeNode = makeCubeNode(cubeSize: 20)
            cubeNode.name = "panoramaCube"
            panoramaRootNode.addChildNode(cubeNode)
            scene.rootNode.addChildNode(panoramaRootNode)
        }

        private func loadCubeImages(baseXMLURL: URL) async -> CubeLoadSummary {
            let baseURL = baseXMLURL.deletingLastPathComponent()

            let directFaceIndices = (0...5).filter { config.tileURLs[$0] != nil }
            if !directFaceIndices.isEmpty {
                return await loadDirectCubeImages(faceIndices: directFaceIndices, baseURL: baseURL)
            }

            if config.multiResTileTemplate != nil {
                return await loadMultiResCubeImages(baseURL: baseURL)
            }

            return CubeLoadSummary(expected: 0, loaded: 0, failed: 0)
        }

        private func loadDirectCubeImages(faceIndices: [Int], baseURL: URL) async -> CubeLoadSummary {
            var loaded = 0
            var failed = 0
            var finished = 0

            for index in faceIndices {
                if Task.isCancelled {
                    break
                }

                guard let relativePath = config.tileURLs[index],
                      let imageURL = URL(string: relativePath, relativeTo: baseURL)?.absoluteURL else {
                    failed += 1
                    finished += 1
                    continue
                }

                do {
                    let image = try await RemoteImageLoader.shared.image(for: imageURL)
                    await MainActor.run {
                        self.applyImage(image, toFaceAt: index)
                    }
                    loaded += 1
                } catch {
                    print("Failed loading face \(index):", error)
                    failed += 1
                }

                finished += 1
                let progress = Double(finished) / Double(faceIndices.count)
                await MainActor.run {
                    reportLoadingState(.loading(message: "正在渲染全景图...", progress: progress))
                }
            }

            return CubeLoadSummary(expected: faceIndices.count, loaded: loaded, failed: failed)
        }

        private func loadMultiResCubeImages(baseURL: URL) async -> CubeLoadSummary {
            let faceIndices = Array(0...5)
            var loaded = 0
            var failed = 0
            var finished = 0

            for faceIndex in faceIndices {
                if Task.isCancelled {
                    break
                }

                do {
                    if let stitchedImage = try await stitchedFaceImage(faceIndex: faceIndex, baseURL: baseURL) {
                        await MainActor.run {
                            self.applyImage(stitchedImage, toFaceAt: faceIndex)
                        }
                        loaded += 1
                    } else {
                        failed += 1
                    }
                } catch {
                    print("Failed loading multi-res face \(faceIndex):", error)
                    failed += 1
                }

                finished += 1
                let progress = Double(finished) / Double(faceIndices.count)
                await MainActor.run {
                    reportLoadingState(.loading(message: "正在渲染全景图...", progress: progress))
                }
            }

            return CubeLoadSummary(expected: faceIndices.count, loaded: loaded, failed: failed)
        }

        private func stitchedFaceImage(faceIndex: Int, baseURL: URL) async throws -> UIImage? {
            for level in config.preferredMultiResLevels {
                try Task.checkCancellation()

                let tiles = try await loadMultiResTiles(faceIndex: faceIndex, level: level, baseURL: baseURL)
                if let stitchedImage = makeStitchedImage(from: tiles, level: level) {
                    return stitchedImage
                }
            }

            return nil
        }

        private func loadMultiResTiles(faceIndex: Int, level: Int, baseURL: URL) async throws -> [MultiResTile] {
            if let expectedGrid = expectedTileGrid(level: level) {
                return try await loadMultiResTiles(
                    faceIndex: faceIndex,
                    level: level,
                    baseURL: baseURL,
                    xRange: 0..<expectedGrid.columns,
                    yRange: 0..<expectedGrid.rows,
                    stopWhenColumnMissing: false
                )
            }

            let probeLimit = 12
            return try await loadMultiResTiles(
                faceIndex: faceIndex,
                level: level,
                baseURL: baseURL,
                xRange: 0..<probeLimit,
                yRange: 0..<probeLimit,
                stopWhenColumnMissing: true
            )
        }

        private func loadMultiResTiles(
            faceIndex: Int,
            level: Int,
            baseURL: URL,
            xRange: Range<Int>,
            yRange: Range<Int>,
            stopWhenColumnMissing: Bool
        ) async throws -> [MultiResTile] {
            var tiles: [MultiResTile] = []

            for x in xRange {
                var foundTileInColumn = false

                for y in yRange {
                    try Task.checkCancellation()

                    guard let tileURL = multiResTileURL(
                        faceIndex: faceIndex,
                        level: level,
                        x: x,
                        y: y,
                        baseURL: baseURL
                    ) else {
                        continue
                    }

                    do {
                        let image = try await RemoteImageLoader.shared.image(for: tileURL)
                        tiles.append(MultiResTile(x: x, y: y, image: image))
                        foundTileInColumn = true
                    } catch {
                        if stopWhenColumnMissing {
                            break
                        }
                    }
                }

                if stopWhenColumnMissing, !foundTileInColumn {
                    break
                }
            }

            return tiles
        }

        private func multiResTileURL(faceIndex: Int, level: Int, x: Int, y: Int, baseURL: URL) -> URL? {
            guard let tilePath = config.multiResTilePath(faceIndex: faceIndex, level: level, x: x, y: y) else {
                return nil
            }

            return URL(string: tilePath, relativeTo: baseURL)?.absoluteURL
        }

        private func expectedTileGrid(level: Int) -> (columns: Int, rows: Int)? {
            guard let tileSize = config.multiResTileSize,
                  tileSize > 0,
                  let expectedFaceSize = config.expectedFaceSize(forLevel: level) else {
                return nil
            }

            let columns = Int(ceil(expectedFaceSize.width / CGFloat(tileSize)))
            let rows = Int(ceil(expectedFaceSize.height / CGFloat(tileSize)))
            guard columns > 0, rows > 0 else { return nil }
            return (columns, rows)
        }

        private func makeStitchedImage(from tiles: [MultiResTile], level: Int) -> UIImage? {
            guard !tiles.isEmpty else { return nil }

            let configuredStep = config.multiResTileSize.flatMap { $0 > 0 ? CGFloat($0) : nil }
            let maxTileWidth = tiles.map { $0.image.size.width }.max() ?? 0
            let maxTileHeight = tiles.map { $0.image.size.height }.max() ?? 0
            let drawStepX = configuredStep ?? max(maxTileWidth, 1)
            let drawStepY = configuredStep ?? max(maxTileHeight, 1)

            let fallbackWidth = tiles.reduce(CGFloat.zero) { partialResult, tile in
                max(partialResult, CGFloat(tile.x) * drawStepX + tile.image.size.width)
            }
            let fallbackHeight = tiles.reduce(CGFloat.zero) { partialResult, tile in
                max(partialResult, CGFloat(tile.y) * drawStepY + tile.image.size.height)
            }

            let expectedSize = config.expectedFaceSize(forLevel: level)
            let canvasSize = CGSize(
                width: max(expectedSize?.width ?? 0, fallbackWidth),
                height: max(expectedSize?.height ?? 0, fallbackHeight)
            )

            guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }

            let renderer = UIGraphicsImageRenderer(size: canvasSize)

            return renderer.image { _ in
                for tile in tiles {
                    let drawPoint = CGPoint(x: CGFloat(tile.x) * drawStepX, y: CGFloat(tile.y) * drawStepY)
                    tile.image.draw(at: drawPoint)
                }
            }
        }

        private func errorMessage(for error: Error) -> String {
            if let loadError = error as? PanoramaLoadError {
                switch loadError {
                case .invalidResponse:
                    return "服务返回异常，无法显示全景"
                case .badStatus(let statusCode):
                    return "服务暂时不可用（HTTP \(statusCode)）"
                }
            }

            if let parserError = error as? PanoramaParserError {
                switch parserError {
                case .invalidXML:
                    return "全景数据格式不受支持"
                case .invalidImageData:
                    return "全景图片解析失败，请稍后重试"
                }
            }

            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    return "网络连接不可用，请检查后重试"
                case .timedOut:
                    return "请求超时，请重试"
                default:
                    return "网络异常，请稍后重试"
                }
            }

            return "加载失败，请稍后重试"
        }

        @MainActor
        private func applyImage(_ image: UIImage, toFaceAt index: Int) {
            guard let cubeNode = panoramaRootNode.childNode(withName: "panoramaCube", recursively: false),
                  let faceNode = cubeNode.childNode(withName: "face_\(index)", recursively: false),
                  let material = faceNode.geometry?.firstMaterial else {
                return
            }

            material.diffuse.contents = image
        }

        private func applyCamera() {
            camera.fieldOfView = min(max(fov, config.minFov), config.maxFov)
            cameraNode.eulerAngles = SCNVector3(
                -pitch.radians,
                -yaw.radians,
                0
            )
        }

        // MARK: - Cube

        private func makeCubeNode(cubeSize: CGFloat) -> SCNNode {
            let root = SCNNode()
            let half = Float(cubeSize / 2)

            let topRoll: Float = 0
            let bottomRoll: Float = 0

            addFace(index: 0,
                    position: SCNVector3(0, 0, -half),
                    eulerAngles: SCNVector3(0, 0, 0),
                    cubeSize: cubeSize,
                    into: root)

            addFace(index: 1,
                    position: SCNVector3(half, 0, 0),
                    eulerAngles: SCNVector3(0, -Float.pi / 2, 0),
                    cubeSize: cubeSize,
                    into: root)

            addFace(index: 2,
                    position: SCNVector3(0, 0, half),
                    eulerAngles: SCNVector3(0, Float.pi, 0),
                    cubeSize: cubeSize,
                    into: root)

            addFace(index: 3,
                    position: SCNVector3(-half, 0, 0),
                    eulerAngles: SCNVector3(0, Float.pi / 2, 0),
                    cubeSize: cubeSize,
                    into: root)

            addFace(index: 4,
                    position: SCNVector3(0, half, 0),
                    eulerAngles: SCNVector3(.pi / 2, 0, topRoll),
                    cubeSize: cubeSize,
                    into: root)

            addFace(index: 5,
                    position: SCNVector3(0, -half, 0),
                    eulerAngles: SCNVector3(-.pi / 2, 0, bottomRoll),
                    cubeSize: cubeSize,
                    into: root)

            return root
        }

        private func addFace(
            index: Int,
            position: SCNVector3,
            eulerAngles: SCNVector3,
            cubeSize: CGFloat,
            into parent: SCNNode
        ) {
            let plane = SCNPlane(width: cubeSize, height: cubeSize)
            let material = SCNMaterial()

            material.lightingModel = .constant
            material.isDoubleSided = false
            material.diffuse.contents = UIColor.darkGray
            material.diffuse.wrapS = .clamp
            material.diffuse.wrapT = .clamp
            material.diffuse.magnificationFilter = .linear
            material.diffuse.minificationFilter = .linear
            material.diffuse.mipFilter = .linear

            plane.materials = [material]

            let node = SCNNode(geometry: plane)
            node.name = "face_\(index)"
            node.position = position
            node.eulerAngles = eulerAngles

            parent.addChildNode(node)
        }

        // MARK: - Hotspots

        @MainActor
        private func addHotspots() {
            hotspotMap.removeAll()
            let radius: Float = 9.4

            for hotspot in config.hotspots {
                let d = worldDirection(pan: hotspot.pan, tilt: hotspot.tilt)
                let node = makeHotspotNode(for: hotspot)
                node.position = SCNVector3(-d.x * radius, -d.y * radius, d.z * radius)
                panoramaRootNode.addChildNode(node)

                hotspotMap[hotspot.id] = hotspot
            }
        }

        private func makeHotspotNode(for hotspot: PanoramaHotspot) -> SCNNode {
            let rootNode = SCNNode()
            rootNode.name = hotspotNodeName(for: hotspot.id)
            rootNode.categoryBitMask = hotspotCategoryBitMask

            let billboard = SCNBillboardConstraint()
            billboard.freeAxes = .all
            rootNode.constraints = [billboard]

            let accentColor = UIColor.systemMint

            let centerCircle = SCNPlane(width: 0.13, height: 0.13)
            centerCircle.cornerRadius = 0.065
            let centerMaterial = SCNMaterial()
            centerMaterial.lightingModel = .constant
            centerMaterial.diffuse.contents = accentColor
            centerMaterial.emission.contents = accentColor.withAlphaComponent(0.16)
            centerMaterial.writesToDepthBuffer = false
            centerMaterial.readsFromDepthBuffer = false
            centerCircle.materials = [centerMaterial]
            let centerNode = SCNNode(geometry: centerCircle)
            centerNode.position = SCNVector3(0, 0, 0.002)
            centerNode.renderingOrder = 3

            let pulseCircle = SCNPlane(width: 0.33, height: 0.33)
            pulseCircle.cornerRadius = 0.165
            let pulseMaterial = SCNMaterial()
            pulseMaterial.lightingModel = .constant
            pulseMaterial.diffuse.contents = accentColor.withAlphaComponent(0.34)
            pulseMaterial.emission.contents = accentColor.withAlphaComponent(0.14)
            pulseMaterial.writesToDepthBuffer = false
            pulseMaterial.readsFromDepthBuffer = false
            pulseCircle.materials = [pulseMaterial]
            let pulseNode = SCNNode(geometry: pulseCircle)
            pulseNode.scale = SCNVector3(0.58, 0.58, 0.58)
            pulseNode.opacity = 0.74

            let expand = SCNAction.scale(to: 1.5, duration: 1.1)
            expand.timingMode = .easeOut
            let fade = SCNAction.fadeOut(duration: 1.1)
            let reset = SCNAction.group([
                SCNAction.scale(to: 0.58, duration: 0),
                SCNAction.fadeOpacity(to: 0.74, duration: 0)
            ])
            pulseNode.runAction(.repeatForever(.sequence([.group([expand, fade]), reset])))

            let hitSphere = SCNSphere(radius: 0.46)
            let hitMaterial = SCNMaterial()
            hitMaterial.lightingModel = .constant
            hitMaterial.diffuse.contents = UIColor.white
            hitMaterial.transparency = 0.001
            hitMaterial.colorBufferWriteMask = []
            hitMaterial.writesToDepthBuffer = false
            hitSphere.materials = [hitMaterial]

            let hitNode = SCNNode(geometry: hitSphere)
            hitNode.name = hotspotHitNodeName(for: hotspot.id)
            hitNode.categoryBitMask = hotspotCategoryBitMask

            rootNode.addChildNode(pulseNode)
            rootNode.addChildNode(centerNode)
            rootNode.addChildNode(hitNode)

            return rootNode
        }

        private func hotspotNodeName(for hotspotID: String) -> String {
            hotspotRootNodePrefix + hotspotID
        }

        private func hotspotHitNodeName(for hotspotID: String) -> String {
            hotspotHitNodePrefix + hotspotID
        }

        private func hotspotID(from node: SCNNode?) -> String? {
            var current = node

            while let inspectingNode = current {
                if let name = inspectingNode.name {
                    if name.hasPrefix(hotspotRootNodePrefix) {
                        return String(name.dropFirst(hotspotRootNodePrefix.count))
                    }
                    if name.hasPrefix(hotspotHitNodePrefix) {
                        return String(name.dropFirst(hotspotHitNodePrefix.count))
                    }
                }
                current = inspectingNode.parent
            }

            return nil
        }

        private func hotspot(for node: SCNNode?) -> PanoramaHotspot? {
            guard let hotspotID = hotspotID(from: node) else { return nil }
            return hotspotMap[hotspotID]
        }

        private func makeHotspotTapSamples() -> [HotspotTapSample] {
            var samples: [HotspotTapSample] = [HotspotTapSample(offset: .zero, radius: 0)]

            let ringRadii: [CGFloat] = [hotspotTouchTargetRadius * 0.5, hotspotTouchTargetRadius]
            let directionCount = 8

            for ringRadius in ringRadii {
                for step in 0..<directionCount {
                    let angle = (CGFloat(step) / CGFloat(directionCount)) * 2 * .pi
                    let offset = CGPoint(
                        x: cos(angle) * ringRadius,
                        y: sin(angle) * ringRadius
                    )
                    samples.append(HotspotTapSample(offset: offset, radius: ringRadius))
                }
            }

            return samples
        }

        private var hotspotHitTestOptions: [SCNHitTestOption: Any] {
            [
                .categoryBitMask: hotspotCategoryBitMask,
                .searchMode: SCNHitTestSearchMode.all.rawValue,
                .firstFoundOnly: false,
                .ignoreHiddenNodes: false
            ]
        }

        private func hotspotForTapPoint(_ point: CGPoint, in view: SCNView) -> PanoramaHotspot? {
            let bounds = view.bounds.insetBy(dx: -2, dy: -2)
            var bestMatch: (hotspot: PanoramaHotspot, score: CGFloat)?

            for sample in hotspotTapSamples {
                let samplePoint = CGPoint(
                    x: point.x + sample.offset.x,
                    y: point.y + sample.offset.y
                )

                guard bounds.contains(samplePoint) else { continue }

                let hits = view.hitTest(samplePoint, options: hotspotHitTestOptions)
                for hit in hits {
                    guard let hotspot = hotspot(for: hit.node) else { continue }

                    let world = hit.worldCoordinates
                    let depthScore = CGFloat(world.x * world.x + world.y * world.y + world.z * world.z)
                    let score = sample.radius * 100 + depthScore
                    if let existing = bestMatch, existing.score <= score {
                        continue
                    }
                    bestMatch = (hotspot, score)
                }

                if sample.radius == 0, let exactMatch = bestMatch {
                    return exactMatch.hotspot
                }
            }

            return bestMatch?.hotspot
        }

        private func worldDirection(pan: Float, tilt: Float) -> SIMD3<Float> {
            let yaw = pan.radians
            let pitch = tilt.radians

            let x = sin(yaw) * cos(pitch)
            let y = -sin(pitch)
            let z = -cos(yaw) * cos(pitch)

            return SIMD3<Float>(x, y, z)
        }

        // MARK: - Gestures

        private func addGestures(to view: SCNView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2

            // 避免双击时先触发单击热点
            tap.require(toFail: doubleTap)

            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(pinch)
            view.addGestureRecognizer(tap)
            view.addGestureRecognizer(doubleTap)
        }

        private func startMotion() {
            guard motionManager.isDeviceMotionAvailable else { return }

            motionManager.deviceMotionUpdateInterval = 1.0 / 60.0

            motionManager.startDeviceMotionUpdates(
                using: .xArbitraryZVertical,
                to: motionQueue
            ) { [weak self] motion, _ in
                guard let self, let motion else { return }

                DispatchQueue.main.async {
                    self.handleDeviceMotion(motion)
                }
            }
        }

        private func stopMotion() {
            motionManager.stopDeviceMotionUpdates()
        }
        
        @objc
        private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = scnView else { return }
            stopInertia()

            let point = gesture.location(in: view)

            let step: CGFloat = 0.7
            let nextFov = max(config.minFov, fov * step)

            if abs(nextFov - fov) < 0.5 {
                fov = min(max(config.startFov, config.minFov), config.maxFov)
            } else {
                fov = nextFov
            }
            
            if let target = targetAnglesForScreenPoint(point) {
                animateTo(yaw: target.yaw, pitch: target.pitch, fov: fov)
            } else {
                animateTo(yaw: yaw, pitch: pitch, fov: fov)
            }
        }

        private func resetView(animated: Bool) {
            stopInertia()

            let targetYaw = config.startPan
            let targetPitch = min(config.maxTilt, max(config.minTilt, config.startTilt))
            let targetFov = min(max(config.startFov, config.minFov), config.maxFov)

            if useGyroscope {
                gestureYawOffset = 0
                gesturePitchOffset = 0
                motionBaseYaw = targetYaw
                motionBasePitch = targetPitch
                motionReferenceAttitude = nil
            }

            if animated {
                animateTo(yaw: targetYaw, pitch: targetPitch, fov: targetFov)
            } else {
                yaw = targetYaw
                pitch = targetPitch
                fov = targetFov
                applyCamera()
            }
        }

        private func zoomIn() {
            stopInertia()
            animateToFov(fov * 0.82)
        }

        private func zoomOut() {
            stopInertia()
            animateToFov(fov * 1.22)
        }
        
        private func animateToFov(_ targetFov: CGFloat) {
            let clamped = min(max(targetFov, config.minFov), config.maxFov)
            fov = clamped

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.25
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            camera.fieldOfView = clamped

            SCNTransaction.commit()
        }
        
        
        private func stopInertia() {
            displayLink?.invalidate()
            displayLink = nil
            angularVelocityYaw = 0
            angularVelocityPitch = 0
        }

        private func startInertia(yawVelocity: Float, pitchVelocity: Float) {
            stopInertia()

            angularVelocityYaw = yawVelocity
            angularVelocityPitch = pitchVelocity

            let link = CADisplayLink(target: self, selector: #selector(handleInertia))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        @objc
        private func handleInertia(_ link: CADisplayLink) {
            let dt = Float(link.targetTimestamp - link.timestamp)

            if useGyroscope {
                gestureYawOffset += angularVelocityYaw * dt
                gesturePitchOffset += angularVelocityPitch * dt

                let combinedPitch = motionBasePitch + gesturePitchOffset
                let clampedPitch = min(config.maxTilt, max(config.minTilt, combinedPitch))
                gesturePitchOffset = clampedPitch - motionBasePitch

                yaw = motionBaseYaw + gestureYawOffset
                pitch = clampedPitch
            } else {
                yaw += angularVelocityYaw * dt
                pitch += angularVelocityPitch * dt
                pitch = min(config.maxTilt, max(config.minTilt, pitch))
            }

            applyCamera()

            let decay = pow(decelerationPerFrame, dt * 60)
            angularVelocityYaw *= decay
            angularVelocityPitch *= decay

            if abs(angularVelocityYaw) < 0.5, abs(angularVelocityPitch) < 0.5 {
                stopInertia()
            }
        }
        
        private var zoomSpeedFactor: Float {
            let referenceFov: Float = 70
            let factor = Float(fov) / referenceFov
            let adjusted = pow(factor, 1.25)
            return min(max(adjusted, 0.25), 1.8)
        }
        
        @objc
        private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = scnView else { return }

            let t = gesture.translation(in: view)
            let v = gesture.velocity(in: view)

            let baseSensitivity: Float = 0.1
            let baseInertiaScale: Float = 0.05

            let sensitivity = baseSensitivity * zoomSpeedFactor
            let inertiaScale = baseInertiaScale * zoomSpeedFactor

            switch gesture.state {
            case .began:
                stopInertia()

            case .changed:
                if useGyroscope {
                    gestureYawOffset -= Float(t.x) * sensitivity
                    gesturePitchOffset -= Float(t.y) * sensitivity

                    let combinedPitch = motionBasePitch + gesturePitchOffset
                    let clampedPitch = min(config.maxTilt, max(config.minTilt, combinedPitch))
                    gesturePitchOffset = clampedPitch - motionBasePitch

                    yaw = motionBaseYaw + gestureYawOffset
                    pitch = clampedPitch
                } else {
                    yaw -= Float(t.x) * sensitivity
                    pitch -= Float(t.y) * sensitivity
                    pitch = min(config.maxTilt, max(config.minTilt, pitch))
                }

                gesture.setTranslation(.zero, in: view)
                applyCamera()
                
            case .ended, .cancelled:
                let yawVelocity = -Float(v.x) * inertiaScale
                let pitchVelocity = -Float(v.y) * inertiaScale
                startInertia(yawVelocity: yawVelocity, pitchVelocity: pitchVelocity)

            default:
                break
            }
        }

        @objc
        private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                pinchStartFov = fov

            case .changed:
                fov = pinchStartFov / gesture.scale
                fov = min(config.maxFov, max(config.minFov, fov))
                applyCamera()

            default:
                break
            }
        }
        
        private func normalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
            let len = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
            guard len > 0.0001 else { return SIMD3<Float>(0, 0, -1) }
            return v / len
        }

        private func panoramaLevelingOrientation() -> simd_quatf {
            let pitch = simd_quatf(
                angle: -config.levelingPitch.radians,
                axis: SIMD3<Float>(1, 0, 0)
            )
            let roll = simd_quatf(
                angle: config.levelingRoll.radians,
                axis: SIMD3<Float>(0, 0, 1)
            )

            return pitch * roll
        }

        private func yawPitchFromDirection(_ d: SIMD3<Float>) -> (yaw: Float, pitch: Float) {
            let dir = normalize(d)

            // 与 worldDirection(pan:tilt:) 互逆
            let yaw = atan2(dir.x, -dir.z) * 180 / Float.pi
            let pitch = -asin(dir.y) * 180 / Float.pi

            return (yaw, pitch)
        }

        private func shortestAngleDelta(from current: Float, to target: Float) -> Float {
            var delta = target - current
            while delta > 180 { delta -= 360 }
            while delta < -180 { delta += 360 }
            return delta
        }
        
        private func targetAnglesForScreenPoint(_ point: CGPoint) -> (yaw: Float, pitch: Float)? {
            guard let view = scnView else { return nil }

            let hits = view.hitTest(point, options: [
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue
            ])

            // 只取打到 cube face 的结果，忽略 hotspot
            guard let hit = hits.first(where: { ($0.node.name ?? "").hasPrefix("face_") }) else {
                return nil
            }

            let p = hit.worldCoordinates
            let dir = SIMD3<Float>(p.x, p.y, p.z)

            return yawPitchFromDirection(dir)
        }
        
        private func animateTo(yaw targetYaw: Float, pitch targetPitch: Float, fov targetFov: CGFloat) {
            let clampedPitch = min(config.maxTilt, max(config.minTilt, targetPitch))
            let clampedFov = min(max(targetFov, config.minFov), config.maxFov)

            // 让 yaw 走最短路径，避免绕大圈
            let adjustedYaw = yaw + shortestAngleDelta(from: yaw, to: targetYaw)

            yaw = adjustedYaw
            pitch = clampedPitch
            fov = clampedFov

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.28
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            camera.fieldOfView = clampedFov
            cameraNode.eulerAngles = SCNVector3(
                -clampedPitch.radians,
                -adjustedYaw.radians,
                0
            )

            SCNTransaction.commit()
        }
        
        @objc
        private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = scnView else { return }

            let point = gesture.location(in: view)
            guard let hotspot = hotspotForTapPoint(point, in: view) else { return }

            parent.onHotspotTap?(hotspot)
        }
    }
}

struct PanoramaScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Namespace private var namespace

    @State private var selectedHotspot: PanoramaHotspot?
    @State private var gyroscopeEnabled: Bool
    @State private var loadingState: PanoramaLoadingState = .loading(message: "正在加载全景图...", progress: nil)
    @State private var showGuide = true
    @State private var controlState = PanoramaControlState()
    @State private var hotspotDismissTask: Task<Void, Never>?
    @State private var guideDismissTask: Task<Void, Never>?

    let xmlURL: URL
    let title: String
    private let supportsGyroscope: Bool

    init(
        xmlURL: URL = URL(string: "https://etc.sjtu.edu.cn/vr/sy2026/115/pano.xml")!,
        title: String = "360°全景"
    ) {
        self.xmlURL = xmlURL
        self.title = title
        let motionAvailable = CMMotionManager().isDeviceMotionAvailable
        self.supportsGyroscope = motionAvailable
        self.gyroscopeEnabled = false
    }

    var body: some View {
        ZStack {
            PanoramaNativeView(
                xmlURL: xmlURL,
                controlState: controlState,
                gyroscopeEnabled: gyroscopeEnabled,
                onLoadingStateChange: { state in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        loadingState = state
                    }
                },
                onHotspotTap: { hotspot in
                    handleHotspotTap(hotspot)
                }
            )
            .ignoresSafeArea()
            .accessibilityLabel("360度全景预览")

            if case .loading(let message, let progress) = loadingState {
                loadingOverlay(message: message, progress: progress)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if case .failed(let message) = loadingState {
                errorOverlay(message: message)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { topControls }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomControls }
        .background(.black)
        .background(PanoramaTabBarVisibilityController(hidden: true).frame(width: 0, height: 0))
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task {
            scheduleGuideAutoDismiss()
        }
        .onDisappear {
            hotspotDismissTask?.cancel()
            guideDismissTask?.cancel()
        }
        .onChange(of: showGuide) { showGuide in
            if showGuide {
                scheduleGuideAutoDismiss()
            } else {
                guideDismissTask?.cancel()
            }
        }
    }

    private var topControls: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.headline.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("返回")
            .buttonBorderShape(.circle)
            .buttonStyle(.glass)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(loadingState.statusText)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)
            
            if supportsGyroscope {
                Button {
                    gyroscopeEnabled.toggle()
                } label: {
                    Image(systemName: "gyroscope")
                        .font(.headline.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(gyroscopeEnabled ? "关闭陀螺仪" : "开启陀螺仪")
                .accessibilityHint("开启后可通过移动设备控制视角")
                .buttonBorderShape(.circle)
                .tint(gyroscopeEnabled ? .blue : nil)
                .adaptiveButtonStyle(isProminent: gyroscopeEnabled)
            }

//            Button {
//                withAnimation(.easeInOut(duration: 0.2)) {
//                    showGuide.toggle()
//                }
//            } label: {
//                Image(systemName: showGuide ? "questionmark.circle.fill" : "questionmark.circle")
//                    .font(.headline.weight(.semibold))
//                    .frame(width: 32, height: 32)
//            }
//            .accessibilityLabel(showGuide ? "隐藏操作提示" : "显示操作提示")
//            .buttonBorderShape(.circle)
//            .buttonStyle(.glass)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var bottomControls: some View {
        VStack(spacing: 10) {
            if let selectedHotspot {
                hotspotBanner(for: selectedHotspot)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showGuide {
                guideCard
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("操作提示")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text("单指拖动可旋转视角，双指捏合可缩放，双击画面可快速放大，点击热点可查看说明。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func hotspotBanner(for hotspot: PanoramaHotspot) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(.yellow)

            Text(hotspot.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)

            Spacer()

            Button("关闭") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedHotspot = nil
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.blue)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func loadingOverlay(message: String, progress: Double?) -> some View {
        VStack(spacing: 10) {
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text("\(Int(progress * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }

            Text(message)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .padding(18)
        .frame(maxWidth: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func errorOverlay(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)

            Text("无法加载全景")
                .font(.headline)
                .foregroundStyle(.primary)

            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("重试") {
                controlState.reloadToken += 1
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding(18)
        .frame(maxWidth: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func handleHotspotTap(_ hotspot: PanoramaHotspot) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedHotspot = hotspot
        }

        hotspotDismissTask?.cancel()
        hotspotDismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedHotspot = nil
                }
            }
        }
    }

    private func scheduleGuideAutoDismiss() {
        guideDismissTask?.cancel()
        guideDismissTask = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showGuide = false
                }
            }
        }
    }
}

private struct PanoramaTabBarVisibilityController: UIViewControllerRepresentable {
    let hidden: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller(hidden: hidden)
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.hidden = hidden
        uiViewController.applyVisibility()
    }

    final class Controller: UIViewController {
        var hidden: Bool

        init(hidden: Bool) {
            self.hidden = hidden
            super.init(nibName: nil, bundle: nil)
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyVisibility()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyVisibility()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            setTabBarHidden(false)
        }

        func applyVisibility() {
            setTabBarHidden(hidden)
        }

        private func setTabBarHidden(_ isHidden: Bool) {
            tabBarController?.tabBar.isHidden = isHidden
        }
    }
}
