//
//  ScheduleBackgroundImageView.swift
//  MySJTU
//
//  Created by boar on 2026/03/21.
//

import SwiftUI
import UIKit
import WidgetKit

struct ScheduleBackgroundImageView: View {
    private enum StorageError: LocalizedError {
        case documentsUnavailable
        case imageEncodeFailed

        var errorDescription: String? {
            switch self {
            case .documentsUnavailable:
                return "无法访问应用文稿目录。"
            case .imageEncodeFailed:
                return "图片保存失败，请尝试重新选择。"
            }
        }
    }

    private enum OrientationMode: String, CaseIterable, Identifiable {
        case portrait
        case landscape

        var id: String { rawValue }

        var title: String {
            switch self {
            case .portrait: return "竖屏"
            case .landscape: return "横屏"
            }
        }
    }

    @AppStorage("schedule.backgroundImage") private var backgroundImage: URL?
    @AppStorage("schedule.backgroundImage.transparency") private var backgroundImageTransparency: Double = ScheduleBackgroundEffectConfiguration.defaultTransparency
    @AppStorage("schedule.backgroundImage.blurRadius") private var backgroundImageBlurRadius: Double = ScheduleBackgroundEffectConfiguration.defaultBlurRadius
    @AppStorage("schedule.backgroundImage.parallaxEnabled") private var backgroundImageParallaxEnabled: Bool = ScheduleBackgroundEffectConfiguration.defaultParallaxEnabled

    @AppStorage("schedule.backgroundImage.landscape") private var landscapeBackgroundImage: URL?
    @AppStorage("schedule.backgroundImage.landscape.transparency") private var landscapeBackgroundImageTransparency: Double = ScheduleBackgroundEffectConfiguration.defaultTransparency
    @AppStorage("schedule.backgroundImage.landscape.blurRadius") private var landscapeBackgroundImageBlurRadius: Double = ScheduleBackgroundEffectConfiguration.defaultBlurRadius
    @AppStorage("schedule.backgroundImage.landscape.parallaxEnabled") private var landscapeBackgroundImageParallaxEnabled: Bool = ScheduleBackgroundEffectConfiguration.defaultParallaxEnabled

    @State private var showImagePicker = false
    @State private var pickedBackgroundImage: UIImage?
    @State private var errorMessage: String?
    @State private var contextScreen: UIScreen?
    @State private var selectedOrientation: OrientationMode = .portrait

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private let previewCornerRadius: CGFloat = 28
    private let fallbackViewportSize = CGSize(width: 390, height: 844)

    private var viewportSize: CGSize {
        let bounds = contextScreen?.bounds ?? CGRect(origin: .zero, size: fallbackViewportSize)
        guard bounds.width > 0, bounds.height > 0 else { return fallbackViewportSize }
        return bounds.size
    }

    private var effectiveViewportSize: CGSize {
        if selectedOrientation == .landscape {
            // Swap dimensions for landscape crop
            return CGSize(width: max(viewportSize.width, viewportSize.height),
                          height: min(viewportSize.width, viewportSize.height))
        }
        return viewportSize
    }

    private var activeBackgroundImage: URL? {
        selectedOrientation == .landscape ? landscapeBackgroundImage : backgroundImage
    }

    private var activeParallaxEnabled: Bool {
        selectedOrientation == .landscape ? landscapeBackgroundImageParallaxEnabled : backgroundImageParallaxEnabled
    }

    private var activeTransparency: Double {
        get { selectedOrientation == .landscape ? landscapeBackgroundImageTransparency : backgroundImageTransparency }
    }

    private var activeBlurRadius: Double {
        get { selectedOrientation == .landscape ? landscapeBackgroundImageBlurRadius : backgroundImageBlurRadius }
    }

    private var activeTransparencyBinding: Binding<Double> {
        selectedOrientation == .landscape
        ? $landscapeBackgroundImageTransparency
        : $backgroundImageTransparency
    }

    private var activeBlurRadiusBinding: Binding<Double> {
        selectedOrientation == .landscape
        ? $landscapeBackgroundImageBlurRadius
        : $backgroundImageBlurRadius
    }

    private var activeParallaxEnabledBinding: Binding<Bool> {
        selectedOrientation == .landscape
        ? $landscapeBackgroundImageParallaxEnabled
        : $backgroundImageParallaxEnabled
    }

    private var previewImage: UIImage? {
        guard let activeBackgroundImage else { return nil }
        return UIImage(contentsOfFile: activeBackgroundImage.path)
    }

    private var previewAspectRatio: CGFloat {
        if selectedOrientation == .landscape {
            guard let previewImage else {
                return ScheduleBackgroundEffectConfiguration.landscapeBackgroundAspectRatio(for: viewportSize)
            }
            let imageAR = ScheduleBackgroundEffectConfiguration.imageAspectRatio(for: previewImage.size)
                ?? ScheduleBackgroundEffectConfiguration.landscapeBackgroundAspectRatio(for: viewportSize)
            return max(imageAR, ScheduleBackgroundEffectConfiguration.landscapeBackgroundAspectRatio(for: viewportSize))
        }
        guard let previewImage else {
            return ScheduleBackgroundEffectConfiguration.maximumBackgroundAspectRatio(for: viewportSize)
        }
        return ScheduleBackgroundEffectConfiguration.constrainedBackgroundAspectRatio(
            for: previewImage.size,
            viewportSize: viewportSize
        )
    }

    private var backgroundCropHeight: CGFloat {
        if selectedOrientation == .landscape {
            return min(viewportSize.height * 0.42, 340)
        }
        return min(viewportSize.height * 0.62, 520)
    }

    private var backgroundCropAspectRatio: CGFloat {
        if selectedOrientation == .landscape {
            return activeParallaxEnabled
            ? ScheduleBackgroundEffectConfiguration.landscapeParallaxBackgroundAspectRatio(for: viewportSize)
            : ScheduleBackgroundEffectConfiguration.landscapeBackgroundAspectRatio(for: viewportSize)
        }
        return activeParallaxEnabled
        ? ScheduleBackgroundEffectConfiguration.parallaxBackgroundAspectRatio(for: viewportSize)
        : ScheduleBackgroundEffectConfiguration.maximumBackgroundAspectRatio(for: viewportSize)
    }

    private var backgroundCropSize: CGSize {
        CGSize(
            width: max(backgroundCropHeight * backgroundCropAspectRatio, 120),
            height: backgroundCropHeight
        )
    }

    private var backgroundEffect: ScheduleBackgroundEffectConfiguration {
        .init(
            transparency: activeTransparency,
            blurRadius: activeBlurRadius
        )
    }

    private var transparencyText: String {
        "\(Int((backgroundEffect.clampedTransparency * 100).rounded()))%"
    }

    private var blurRadiusText: String {
        "\(Int(backgroundEffect.clampedBlurRadius.rounded()))"
    }

    private var effectiveParallaxEnabled: Bool {
        guard previewImage != nil else { return false }
        return activeParallaxEnabled
    }

    private var previewParallaxStatusText: String {
        activeParallaxEnabled ? "开启" : "关闭"
    }

    private var usesDefaultSettings: Bool {
        backgroundEffect.usesDefaultValues
    }

    private var previewSummaryTitle: String {
        activeBackgroundImage == nil ? "还没有设置背景图片" : "背景图片已准备好"
    }

    private var previewSummaryText: String {
        if activeBackgroundImage == nil {
            return "点按卡片选择一张图片，裁切时可以直接决定是否开启视差滚动。"
        }
        return "当前图片会显示在课表页底层。点按卡片可以重新裁切或更换。"
    }

    private var previewCropModeText: String {
        activeParallaxEnabled ? "视差比例" : "屏幕比例"
    }

    private var previewTapHintText: String {
        activeBackgroundImage == nil ? "点按选择图片" : "点按重新裁切或更换"
    }

    private var previewArtworkSize: CGSize {
        let height: CGFloat = 176
        return CGSize(
            width: max(height * previewAspectRatio, 104),
            height: height
        )
    }

    private var previewThumbnailFrameSize: CGSize {
        previewArtworkSize
    }

    private func resetEffect() {
        if selectedOrientation == .landscape {
            landscapeBackgroundImageTransparency = ScheduleBackgroundEffectConfiguration.defaultTransparency
            landscapeBackgroundImageBlurRadius = ScheduleBackgroundEffectConfiguration.defaultBlurRadius
        } else {
            backgroundImageTransparency = ScheduleBackgroundEffectConfiguration.defaultTransparency
            backgroundImageBlurRadius = ScheduleBackgroundEffectConfiguration.defaultBlurRadius
        }
    }

    private func savePhoto(_ image: UIImage) throws -> URL {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw StorageError.documentsUnavailable
        }

        guard let data = image.jpegData(compressionQuality: 0.92) else {
            throw StorageError.imageEncodeFailed
        }

        let destinationURL = documentsURL.appendingPathComponent("schedule-background-\(UUID().uuidString).jpg")
        try data.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    private func deletePhoto(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func replaceBackgroundImage(with image: UIImage, parallaxEnabled: Bool) {
        let previousImageURL = activeBackgroundImage

        do {
            let newImageURL = try savePhoto(image)

            if selectedOrientation == .landscape {
                landscapeBackgroundImage = newImageURL
                landscapeBackgroundImageParallaxEnabled = parallaxEnabled
            } else {
                backgroundImage = newImageURL
                backgroundImageParallaxEnabled = parallaxEnabled
            }

            if let previousImageURL {
                try deletePhoto(at: previousImageURL)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeBackgroundImage() {
        guard let activeBackgroundImage else { return }

        do {
            try deletePhoto(at: activeBackgroundImage)
            if selectedOrientation == .landscape {
                landscapeBackgroundImage = nil
            } else {
                backgroundImage = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginImageSelection() {
        showImagePicker = true
    }

    var body: some View {
        List {
            if isIPad {
                orientationPickerSection
            }
            previewSection
            actionSection
            effectSection
        }
        .navigationTitle("背景图片")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "无法设置背景图片",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("好") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .cropImagePicker(
            cropType: .roundedRectangle(
                size: backgroundCropSize,
                cornerRadius: previewCornerRadius,
                style: .continuous
            ),
            show: $showImagePicker,
            croppedImage: $pickedBackgroundImage
        ) {
            Toggle(isOn: activeParallaxEnabledBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("滚动视差")
                    Text("开启后会使用更高的裁切画幅，滚动时会有轻微位移。")
                        .font(.caption)
                        .foregroundStyle(Color(UIColor.secondaryLabel))
                }
            }
            .padding(16)
            .glassEffect(in: .rect(cornerRadius: 16.0, style: .continuous))
        }
        .onChange(of: pickedBackgroundImage) { _, newImage in
            guard let newImage else { return }
            replaceBackgroundImage(with: newImage, parallaxEnabled: activeParallaxEnabled)
            pickedBackgroundImage = nil
        }
        .onContextScreenChange { screen in
            contextScreen = screen
        }
    }

    private var orientationPickerSection: some View {
        Section {
            Picker("方向", selection: $selectedOrientation) {
                ForEach(OrientationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        } footer: {
            Text("你可以分别为竖屏和横屏设置不同的背景图片。")
                .font(.footnote)
                .foregroundStyle(Color(UIColor.secondaryLabel))
        }
    }

    private var previewSection: some View {
        previewCard
            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
    }

    private var actionSection: some View {
        Section("操作") {
            Button {
                beginImageSelection()
            } label: {
                Label(activeBackgroundImage == nil ? "选择背景图片" : "更换背景图片", systemImage: "photo")
            }

            if activeBackgroundImage != nil {
                Button(role: .destructive) {
                    removeBackgroundImage()
                } label: {
                    Label("移除背景图片", systemImage: "trash")
                }
            }
        }
    }

    private var effectSection: some View {
        Section {
            effectSliderRow(
                title: "透明度",
                valueText: transparencyText
            ) {
                Slider(
                    value: activeTransparencyBinding,
                    in: ScheduleBackgroundEffectConfiguration.transparencyRange
                )
            }

            effectSliderRow(
                title: "模糊强度",
                valueText: blurRadiusText
            ) {
                Slider(
                    value: activeBlurRadiusBinding,
                    in: ScheduleBackgroundEffectConfiguration.blurRadiusRange,
                    step: 1
                )
            }

            Button {
                resetEffect()
            } label: {
                Label("恢复默认效果", systemImage: "arrow.counterclockwise")
            }
            .disabled(usesDefaultSettings)
        } header: {
            Text("效果")
        }
    }

    private func effectSliderRow<Control: View>(
        title: String,
        valueText: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(Color(UIColor.secondaryLabel))
                    .monospacedDigit()
            }

            control()
        }
    }

    private func previewInfoChip(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
            Text(title)
                .foregroundStyle(Color(UIColor.secondaryLabel))
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(UIColor.secondarySystemBackground), in: Capsule())
        .foregroundStyle(Color(UIColor.label))
    }

    private var previewArtworkContent: some View {
        Group {
            if let previewImage {
                ScheduleBackgroundArtwork(
                    image: previewImage,
                    effect: backgroundEffect
                )
            } else {
                LinearGradient(
                    colors: [
                        Color("AccentColor").opacity(0.24),
                        Color(UIColor.secondarySystemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            Color(UIColor.separator).opacity(0.3),
                            style: StrokeStyle(lineWidth: 1, dash: [8, 6])
                        )
                }
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title3.weight(.semibold))
                        Text("选择背景图片")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(Color(UIColor.secondaryLabel))
                }
            }
        }
        .frame(width: previewArtworkSize.width, height: previewArtworkSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var previewParallaxBadge: some View {
        Image(systemName: "rectangle.expand.vertical")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(4)
        .background(Color.black.opacity(0.24), in: Capsule())
    }

    private var previewThumbnail: some View {
        previewArtworkContent
            .frame(width: previewThumbnailFrameSize.width, height: previewThumbnailFrameSize.height)
            .overlay(alignment: .topTrailing) {
                if effectiveParallaxEnabled {
                    previewParallaxBadge
                        .padding(10)
                }
            }
    }

    private var previewCard: some View {
        HStack(spacing: 18) {
            previewThumbnail
                .onTapGesture {
                    beginImageSelection()
                }

            VStack(alignment: .leading, spacing: 12) {
                Text("课表背景预览")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text(previewSummaryTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(UIColor.label))

                    Text(previewSummaryText)
                        .font(.subheadline)
                        .foregroundStyle(Color(UIColor.secondaryLabel))
                }

                HStack(spacing: 8) {
                    previewInfoChip(
                        title: "裁切",
                        value: previewCropModeText,
                        systemImage: "crop"
                    )
                    previewInfoChip(
                        title: "视差",
                        value: previewParallaxStatusText,
                        systemImage: "rectangle.expand.vertical"
                    )
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Image(systemName: "hand.tap.fill")
                    Text(previewTapHintText)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color("AccentColor"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        ScheduleBackgroundImageView()
    }
}

private enum WidgetBackgroundStorageError: LocalizedError {
    case sharedContainerUnavailable
    case imageEncodeFailed

    var errorDescription: String? {
        switch self {
        case .sharedContainerUnavailable:
            return "无法访问小组件共享目录。"
        case .imageEncodeFailed:
            return "图片保存失败，请尝试重新选择。"
        }
    }
}

private enum WidgetBackgroundStorage {
    private static let imageCompressionQuality: CGFloat = 0.88
    private static let maximumImagePixelLength: CGFloat = 1800

    static func imageURL(for filename: String) -> URL? {
        SharedContainerDirectory.widgetBackgroundURL(for: filename)
    }

    static func image(for filename: String) -> UIImage? {
        guard let imageURL = imageURL(for: filename) else { return nil }
        return UIImage(contentsOfFile: imageURL.path)
    }

    static func save(
        _ image: UIImage,
        for slot: WidgetBackgroundSlot,
        replacing previousFilename: String
    ) throws -> String {
        let fileManager = FileManager.default

        guard let directoryURL = SharedContainerDirectory.widgetBackgroundsURL(fileManager: fileManager) else {
            throw WidgetBackgroundStorageError.sharedContainerUnavailable
        }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let preparedImage = prepareForStorage(image)

        guard let imageData = preparedImage.jpegData(compressionQuality: imageCompressionQuality) else {
            throw WidgetBackgroundStorageError.imageEncodeFailed
        }

        let newFilename = "widget-background-\(slot.rawValue)-\(UUID().uuidString).jpg"
        let destinationURL = directoryURL.appendingPathComponent(newFilename, isDirectory: false)

        try imageData.write(to: destinationURL, options: .atomic)

        if let previousURL = imageURL(for: previousFilename),
           fileManager.fileExists(atPath: previousURL.path) {
            try? fileManager.removeItem(at: previousURL)
        }

        return newFilename
    }

    static func remove(filename: String) throws {
        guard let imageURL = imageURL(for: filename) else { return }

        if FileManager.default.fileExists(atPath: imageURL.path) {
            try FileManager.default.removeItem(at: imageURL)
        }
    }

    private static func prepareForStorage(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let longestSide = max(width, height)

        guard longestSide > maximumImagePixelLength else { return image }

        let scale = maximumImagePixelLength / longestSide
        let targetSize = CGSize(width: width * scale, height: height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            UIImage(
                cgImage: cgImage,
                scale: image.scale,
                orientation: image.imageOrientation
            )
            .draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private extension WidgetBackgroundSlot {
    static let listIndicatorContainerWidth: CGFloat = 52
    private static let defaultViewportSize = CGSize(width: 390, height: 844)

    private static func resolvedViewportSize(_ viewportSize: CGSize) -> CGSize {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return defaultViewportSize }
        return viewportSize
    }

    var previewDesignSize: CGSize {
        switch self {
        case .systemSmall:
            return CGSize(width: 170, height: 170)
        case .systemMedium:
            return CGSize(width: 364, height: 170)
        case .systemLarge:
            return CGSize(width: 364, height: 382)
        }
    }

    var listIndicatorWidth: CGFloat {
        switch self {
        case .systemSmall:
            return 26
        case .systemMedium:
            return 44
        case .systemLarge:
            return 36
        }
    }

    var listIndicatorSize: CGSize {
        CGSize(width: listIndicatorWidth, height: listIndicatorWidth / aspectRatio)
    }

    private static func editorPreviewScale(in viewportSize: CGSize) -> CGFloat {
        let viewportSize = resolvedViewportSize(viewportSize)
        let largestWidgetSize = systemLarge.previewDesignSize
        let maxPreviewWidth = min(viewportSize.width - 36, 340)
        let maxPreviewHeight = min(viewportSize.height * 0.42, 360)

        return min(
            maxPreviewWidth / largestWidgetSize.width,
            maxPreviewHeight / largestWidgetSize.height
        )
    }

    func editorPreviewSize(in viewportSize: CGSize) -> CGSize {
        let previewScale = Self.editorPreviewScale(in: viewportSize)
        return CGSize(
            width: previewDesignSize.width * previewScale,
            height: previewDesignSize.height * previewScale
        )
    }

    func cropSize(in viewportSize: CGSize) -> CGSize {
        let viewportSize = Self.resolvedViewportSize(viewportSize)
        let screenWidth = viewportSize.width

        switch self {
        case .systemSmall:
            let width = min(screenWidth - 56, 300)
            return CGSize(width: width, height: width)
        case .systemMedium:
            let width = min(screenWidth - 36, 340)
            return CGSize(width: width, height: width / aspectRatio)
        case .systemLarge:
            let height = min(viewportSize.height * 0.42, 340)
            return CGSize(width: height * aspectRatio, height: height)
        }
    }

    var cornerRadius: CGFloat {
        30
    }

    var previewTitle: String {
        switch self {
        case .systemSmall:
            return "适合把下一节课的简略信息放在桌面最醒目的位置。"
        case .systemMedium:
            return "适合横向排布，信息密度和留白比较平衡。"
        case .systemLarge:
            return "适合展示更多课程卡片，同时保留背景氛围。"
        }
    }
}

struct WidgetBackgroundImageSettingsView: View {
    var body: some View {
        List {
            Section {
                ForEach(WidgetBackgroundSlot.allCases) { slot in
                    NavigationLink {
                        WidgetBackgroundSlotEditorView(slot: slot)
                    } label: {
                        WidgetBackgroundSlotRow(slot: slot)
                    }
                }
            } header: {
                Text("尺寸")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("可分别为桌面上的小号、中号和大号课程小组件设置背景。为了保持锁屏、待机和系统清透/着色模式下的可读性，配件类小组件仍会使用系统背景。")
                    Text("建议选择主体简洁、明暗对比不过强的图片，这样课程信息会更清晰。")
                }
                .font(.footnote)
                .foregroundStyle(Color(UIColor.secondaryLabel))
            }
        }
        .navigationTitle("桌面小组件背景")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WidgetBackgroundSlotRow: View {
    let slot: WidgetBackgroundSlot

    @AppStorage private var storedFilename: String

    init(slot: WidgetBackgroundSlot) {
        self.slot = slot
        _storedFilename = AppStorage(
            wrappedValue: "",
            slot.storageKey,
            store: UserDefaults.shared
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            WidgetBackgroundSizeIndicator(slot: slot)
                .frame(
                    width: WidgetBackgroundSlot.listIndicatorContainerWidth,
                    alignment: .leading
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(slot.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(UIColor.label))

                Text(slot.subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color(UIColor.secondaryLabel))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(storedFilename.isEmpty ? "未设置" : "已设置")
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    storedFilename.isEmpty
                    ? Color(UIColor.secondaryLabel)
                    : Color("AccentColor")
                )
        }
        .padding(.vertical, 6)
    }
}

private struct WidgetBackgroundSizeIndicator: View {
    let slot: WidgetBackgroundSlot

    private var size: CGSize {
        slot.listIndicatorSize
    }

    private var cornerRadius: CGFloat {
        max(8, min(size.width, size.height) * 0.28)
    }

    private var contentInset: CGFloat {
        max(4, min(size.width, size.height) * 0.18)
    }

    private var markerSize: CGFloat {
        max(4, min(size.width, size.height) * 0.16)
    }

    private var lineHeight: CGFloat {
        max(2.5, min(size.width, size.height) * 0.1)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(UIColor.secondarySystemFill))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color(UIColor.separator).opacity(0.42))

            VStack(alignment: .leading, spacing: lineHeight) {
                RoundedRectangle(cornerRadius: markerSize * 0.35, style: .continuous)
                    .fill(Color("AccentColor").opacity(0.35))
                    .frame(width: markerSize, height: markerSize)

                Spacer(minLength: 0)

                Capsule()
                    .fill(Color(UIColor.secondaryLabel).opacity(0.18))
                    .frame(width: size.width * 0.5, height: lineHeight)

                Capsule()
                    .fill(Color(UIColor.secondaryLabel).opacity(0.1))
                    .frame(width: size.width * 0.32, height: lineHeight)
            }
            .padding(contentInset)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

private struct WidgetBackgroundSlotEditorView: View {
    let slot: WidgetBackgroundSlot

    @AppStorage private var storedFilename: String
    @AppStorage private var backgroundTransparency: Double
    @AppStorage private var backgroundBlurRadius: Double
    @State private var showImagePicker = false
    @State private var pickedImage: UIImage?
    @State private var errorMessage: String?
    @State private var contextScreen: UIScreen?

    init(slot: WidgetBackgroundSlot) {
        self.slot = slot
        _storedFilename = AppStorage(
            wrappedValue: "",
            slot.storageKey,
            store: UserDefaults.shared
        )
        _backgroundTransparency = AppStorage(
            wrappedValue: WidgetBackgroundEffectConfiguration.defaultTransparency,
            slot.transparencyKey,
            store: UserDefaults.shared
        )
        _backgroundBlurRadius = AppStorage(
            wrappedValue: WidgetBackgroundEffectConfiguration.defaultBlurRadius,
            slot.blurRadiusKey,
            store: UserDefaults.shared
        )
    }

    private var previewImage: UIImage? {
        WidgetBackgroundStorage.image(for: storedFilename)
    }

    private var viewportSize: CGSize {
        let fallbackSize = CGSize(width: 390, height: 844)
        let bounds = contextScreen?.bounds ?? CGRect(origin: .zero, size: fallbackSize)
        guard bounds.width > 0, bounds.height > 0 else { return fallbackSize }
        return bounds.size
    }

    private var backgroundEffect: WidgetBackgroundEffectConfiguration {
        .init(
            transparency: backgroundTransparency,
            blurRadius: backgroundBlurRadius
        )
    }

    private var transparencyText: String {
        "\(Int((backgroundEffect.clampedTransparency * 100).rounded()))%"
    }

    private var blurRadiusText: String {
        "\(Int(backgroundEffect.clampedBlurRadius.rounded()))"
    }

    private var usesDefaultSettings: Bool {
        backgroundEffect.usesDefaultValues
    }

    private var previewSummaryTitle: String {
        storedFilename.isEmpty ? "还没有设置背景图片" : "背景图片已准备好"
    }

    private var previewSummaryText: String {
        if storedFilename.isEmpty {
            return "选择一张图片后，会按\(slot.title)的比例裁切并直接用于桌面预览。"
        }

        return "新的背景会应用到\(slot.title)，并尽量保持当前小组件的信息卡片风格不变。"
    }

    private func beginImageSelection() {
        showImagePicker = true
    }

    private func reloadWidgetTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func resetEffect() {
        backgroundTransparency = WidgetBackgroundEffectConfiguration.defaultTransparency
        backgroundBlurRadius = WidgetBackgroundEffectConfiguration.defaultBlurRadius
        reloadWidgetTimelines()
    }

    private func handleEffectSliderEditingChanged(_ isEditing: Bool) {
        guard !isEditing else { return }
        print("reload!")
        reloadWidgetTimelines()
    }

    private func replaceBackgroundImage(with image: UIImage) {
        do {
            let newFilename = try WidgetBackgroundStorage.save(
                image,
                for: slot,
                replacing: storedFilename
            )
            storedFilename = newFilename
            reloadWidgetTimelines()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeBackgroundImage() {
        do {
            try WidgetBackgroundStorage.remove(filename: storedFilename)
            storedFilename = ""
            reloadWidgetTimelines()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    WidgetBackgroundPreviewCard(
                        slot: slot,
                        image: previewImage,
                        effect: backgroundEffect,
                        size: slot.editorPreviewSize(in: viewportSize)
                    )
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        beginImageSelection()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(previewSummaryTitle)
                            .font(.headline)
                            .foregroundStyle(Color(UIColor.label))

                        Text(previewSummaryText)
                            .font(.subheadline)
                            .foregroundStyle(Color(UIColor.secondaryLabel))

                        Label("点按上方预览即可重新裁切或更换图片", systemImage: "hand.tap.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color("AccentColor"))
                            .padding(.top, 2)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)

            Section("操作") {
                Button {
                    beginImageSelection()
                } label: {
                    Label(storedFilename.isEmpty ? "选择背景图片" : "更换背景图片", systemImage: "photo")
                }

                if !storedFilename.isEmpty {
                    Button(role: .destructive) {
                        removeBackgroundImage()
                    } label: {
                        Label("移除背景图片", systemImage: "trash")
                    }
                }
            }

            Section {
                effectSliderRow(
                    title: "透明度",
                    valueText: transparencyText
                ) {
                    Slider(
                        value: $backgroundTransparency,
                        in: WidgetBackgroundEffectConfiguration.transparencyRange,
                        onEditingChanged: handleEffectSliderEditingChanged
                    )
                }

                effectSliderRow(
                    title: "模糊强度",
                    valueText: blurRadiusText
                ) {
                    Slider(
                        value: $backgroundBlurRadius,
                        in: WidgetBackgroundEffectConfiguration.blurRadiusRange,
                        step: 1,
                        onEditingChanged: handleEffectSliderEditingChanged
                    )
                }

                Button {
                    resetEffect()
                } label: {
                    Label("恢复默认效果", systemImage: "arrow.counterclockwise")
                }
                .disabled(usesDefaultSettings)
            } header: {
                Text("效果")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(slot.previewTitle)
                    Text("背景层会自动增加轻微模糊和遮罩，以保证课程标题、地点和时间在照片上依然清晰。")
                }
                .font(.footnote)
                .foregroundStyle(Color(UIColor.secondaryLabel))
            }
        }
        .navigationTitle(slot.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "无法设置背景图片",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("好") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .cropImagePicker(
            cropType: .roundedRectangle(
                size: slot.cropSize(in: viewportSize),
                cornerRadius: slot.cornerRadius,
                style: .continuous
            ),
            show: $showImagePicker,
            croppedImage: $pickedImage
        )
        .onChange(of: pickedImage) { _, newImage in
            guard let newImage else { return }
            replaceBackgroundImage(with: newImage)
            pickedImage = nil
        }
        .onContextScreenChange { screen in
            contextScreen = screen
        }
    }

    private func effectSliderRow<Control: View>(
        title: String,
        valueText: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(Color(UIColor.secondaryLabel))
                    .monospacedDigit()
            }

            control()
        }
    }
}

private struct WidgetBackgroundPreviewCard: View {
    let slot: WidgetBackgroundSlot
    let image: UIImage?
    let effect: WidgetBackgroundEffectConfiguration
    let size: CGSize
    var showsSelectionPrompt = true

    private var designSize: CGSize {
        slot.previewDesignSize
    }

    private var scale: CGFloat {
        min(size.width / designSize.width, size.height / designSize.height)
    }

    var body: some View {
        previewBody
            .frame(width: designSize.width, height: designSize.height)
            .scaleEffect(scale)
            .frame(width: size.width, height: size.height)
    }

    private var previewBody: some View {
        WidgetBackgroundCanvas(
            slot: slot,
            image: image,
            effect: effect,
            showsSelectionPrompt: showsSelectionPrompt
        )
        .clipShape(RoundedRectangle(cornerRadius: slot.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: slot.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12))
        }
        .shadow(color: Color.black.opacity(0.08), radius: 16, y: 8)
    }
}

private struct WidgetBackgroundCanvas: View {
    let slot: WidgetBackgroundSlot
    let image: UIImage?
    let effect: WidgetBackgroundEffectConfiguration
    var showsSelectionPrompt = true

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .opacity(effect.imageOpacity)
                    .blur(radius: effect.clampedBlurRadius)
                    .scaleEffect(1.05)
                    .overlay {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(UIColor.systemBackground).opacity(effect.topOverlayOpacity),
                                        Color(UIColor.systemBackground).opacity(effect.middleOverlayOpacity),
                                        Color(UIColor.systemBackground).opacity(effect.bottomOverlayOpacity)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .overlay {
                        Rectangle()
                            .fill(Color(UIColor.systemBackground).opacity(effect.flatOverlayOpacity))
                    }
            } else {
                LinearGradient(
                    colors: [
                        Color("AccentColor").opacity(0.26),
                        Color(UIColor.secondarySystemBackground),
                        Color(UIColor.tertiarySystemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    if showsSelectionPrompt {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.plus")
                                .font(.title3.weight(.semibold))
                            Text("选择背景图片")
                                .font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(Color(UIColor.secondaryLabel))
                    }
                }
            }
        }
    }
}

#Preview("Widget Background Settings") {
    NavigationStack {
        WidgetBackgroundImageSettingsView()
    }
}
