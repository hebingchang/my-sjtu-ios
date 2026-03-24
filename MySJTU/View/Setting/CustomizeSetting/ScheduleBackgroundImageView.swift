//
//  ScheduleBackgroundImageView.swift
//  MySJTU
//
//  Created by boar on 2026/03/21.
//

import SwiftUI
import UIKit

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

    @AppStorage("schedule.backgroundImage") private var backgroundImage: URL?
    @AppStorage("schedule.backgroundImage.transparency") private var backgroundImageTransparency: Double = ScheduleBackgroundEffectConfiguration.defaultTransparency
    @AppStorage("schedule.backgroundImage.blurRadius") private var backgroundImageBlurRadius: Double = ScheduleBackgroundEffectConfiguration.defaultBlurRadius
    @AppStorage("schedule.backgroundImage.parallaxEnabled") private var backgroundImageParallaxEnabled: Bool = ScheduleBackgroundEffectConfiguration.defaultParallaxEnabled

    @State private var showImagePicker = false
    @State private var pickedBackgroundImage: UIImage?
    @State private var errorMessage: String?

    private let previewCornerRadius: CGFloat = 28

    private var previewImage: UIImage? {
        guard let backgroundImage else { return nil }
        return UIImage(contentsOfFile: backgroundImage.path)
    }

    private var previewAspectRatio: CGFloat {
        guard let previewImage else {
            return ScheduleBackgroundEffectConfiguration.maximumBackgroundAspectRatio
        }
        return ScheduleBackgroundEffectConfiguration.constrainedBackgroundAspectRatio(for: previewImage.size)
    }

    private var backgroundCropHeight: CGFloat {
        min(UIScreen.main.bounds.height * 0.62, 520)
    }

    private var backgroundCropAspectRatio: CGFloat {
        backgroundImageParallaxEnabled
        ? ScheduleBackgroundEffectConfiguration.parallaxBackgroundAspectRatio
        : ScheduleBackgroundEffectConfiguration.maximumBackgroundAspectRatio
    }

    private var backgroundCropSize: CGSize {
        CGSize(
            width: max(backgroundCropHeight * backgroundCropAspectRatio, 120),
            height: backgroundCropHeight
        )
    }

    private var backgroundEffect: ScheduleBackgroundEffectConfiguration {
        .init(
            transparency: backgroundImageTransparency,
            blurRadius: backgroundImageBlurRadius
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
        return backgroundImageParallaxEnabled
    }

    private var previewParallaxStatusText: String {
        backgroundImageParallaxEnabled ? "开启" : "关闭"
    }

    private var usesDefaultSettings: Bool {
        backgroundEffect.usesDefaultValues
    }

    private var previewSummaryTitle: String {
        backgroundImage == nil ? "还没有设置背景图片" : "背景图片已准备好"
    }

    private var previewSummaryText: String {
        if backgroundImage == nil {
            return "点按卡片选择一张图片，裁切时可以直接决定是否开启视差滚动。"
        }
        return "当前图片会显示在课表页底层。点按卡片可以重新裁切或更换。"
    }

    private var previewCropModeText: String {
        backgroundImageParallaxEnabled ? "视差比例" : "屏幕比例"
    }

    private var previewTapHintText: String {
        backgroundImage == nil ? "点按选择图片" : "点按重新裁切或更换"
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
        backgroundImageTransparency = ScheduleBackgroundEffectConfiguration.defaultTransparency
        backgroundImageBlurRadius = ScheduleBackgroundEffectConfiguration.defaultBlurRadius
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
        let previousImageURL = backgroundImage

        do {
            let newImageURL = try savePhoto(image)
            backgroundImage = newImageURL
            backgroundImageParallaxEnabled = parallaxEnabled

            if let previousImageURL {
                try deletePhoto(at: previousImageURL)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeBackgroundImage() {
        guard let backgroundImage else { return }

        do {
            try deletePhoto(at: backgroundImage)
            self.backgroundImage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginImageSelection() {
        showImagePicker = true
    }

    var body: some View {
        List {
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
            Toggle(isOn: $backgroundImageParallaxEnabled) {
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
            replaceBackgroundImage(with: newImage, parallaxEnabled: backgroundImageParallaxEnabled)
            pickedBackgroundImage = nil
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
                Label(backgroundImage == nil ? "选择背景图片" : "更换背景图片", systemImage: "photo")
            }

            if backgroundImage != nil {
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
                    value: $backgroundImageTransparency,
                    in: ScheduleBackgroundEffectConfiguration.transparencyRange
                )
            }

            effectSliderRow(
                title: "模糊强度",
                valueText: blurRadiusText
            ) {
                Slider(
                    value: $backgroundImageBlurRadius,
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
