//
//  ImagePicker.swift
//  MySJTU
//
//  Created by 何炳昌 on 2024/12/26.
//

import SwiftUI
import UIKit
import PhotosUI

enum Crop: Equatable {
    case circle
    case roundedRectangle(size: CGSize, cornerRadius: CGFloat, style: RoundedCornerStyle)
    
    func size() -> CGSize {
        switch self {
        case .circle:
            return .init(width: 300, height: 300)
        case .roundedRectangle(size: let size, cornerRadius: _, style: _):
            return size
        }
    }
}

extension View {
    @ViewBuilder
    func cropImagePicker(cropType: Crop, show: Binding<Bool>, croppedImage: Binding<UIImage?>) -> some View {
        CustomImagePicker(
            cropType: cropType,
            show: show,
            croppedImage: croppedImage,
            cropOptions: nil
        ) {
            self
        }
    }

    @ViewBuilder
    func cropImagePicker<CropOptions: View>(
        cropType: Crop,
        show: Binding<Bool>,
        croppedImage: Binding<UIImage?>,
        @ViewBuilder cropOptions: @escaping () -> CropOptions
    ) -> some View {
        CustomImagePicker(
            cropType: cropType,
            show: show,
            croppedImage: croppedImage,
            cropOptions: AnyView(cropOptions())
        ) {
            self
        }
    }
    
    @ViewBuilder
    func frame(_ size: CGSize) -> some View {
        self
            .frame(width: size.width, height: size.height)
    }
    
    func haptics(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

fileprivate struct CustomImagePicker<Content: View>: View {
    var content: Content
    var cropType: Crop
    var cropOptions: AnyView?
    @Binding var show: Bool
    @Binding var croppedImage: UIImage?
    
    init(
        cropType: Crop,
        show: Binding<Bool>,
        croppedImage: Binding<UIImage?>,
        cropOptions: AnyView?,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.content = content()
        self._show = show
        self._croppedImage = croppedImage
        self.cropType = cropType
        self.cropOptions = cropOptions
    }
    
    @State private var photosItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    
    var body: some View {
        content
            .photosPicker(
                isPresented: $show,
                selection: $photosItem,
                matching: .any(of: [.images, .screenshots])
            )
            .onChange(of: photosItem) {
                if let photosItem {
                    Task {
                        if let imageData = try? await photosItem.loadTransferable(type: Data.self), let image = UIImage(data: imageData) {
                            selectedImage = image
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { selectedImage != nil },
                set: { if $0 == false { selectedImage = nil } }
            )) {
                photosItem = nil
                selectedImage = nil
            } content: {
                NavigationStack {
                    CropView(crop: cropType, image: selectedImage, cropOptions: cropOptions) { croppedImage, status in
                        if let croppedImage {
                            self.croppedImage = croppedImage
                        }
                    }
                }
            }
    }
}

struct VisualEffectView: UIViewRepresentable {
    var effect: UIVisualEffect?
    func makeUIView(context: UIViewRepresentableContext<Self>) -> UIVisualEffectView { UIVisualEffectView() }
    func updateUIView(_ uiView: UIVisualEffectView, context: UIViewRepresentableContext<Self>) { uiView.effect = effect }
}

struct CropView: View {
    var crop: Crop
    var image: UIImage?
    var cropOptions: AnyView?
    var onCrop: (UIImage?, Bool) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme: ColorScheme

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 0
    @State private var offset: CGSize = .zero
    @State private var lastStoredOffset: CGSize = .zero
    @GestureState private var isInteracting: Bool = false

    private var cropWindowVerticalOffset: CGFloat {
        cropOptions == nil ? 0 : -36
    }
    
    var body: some View {
        ZStack {
            ImageView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    colorScheme == .light ? Color.white : Color.black
                }
                .overlay {
                    if !isInteracting {
                        VisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .mask {
                                ZStack {
                                    Rectangle()
                                        .fill(.white)
                                    
                                    cropCutoutShape(for: crop)
                                        .frame(crop.size())
                                        .offset(y: cropWindowVerticalOffset)
                                        .blendMode(.destinationOut)
                                }
                                .compositingGroup()
                            }
                            .compositingGroup()
                            .allowsHitTesting(false)
                    } else {
                        cropStrokeShape(for: crop)
                            .frame(crop.size())
                            .offset(y: cropWindowVerticalOffset)
                    }
                }
                .ignoresSafeArea()
                .animation(.easeInOut, value: isInteracting)
//                .toolbar {
//                    ToolbarItem(placement: .topBarTrailing) {
//                        Button {
//                            let renderer = ImageRenderer(content: ImageView())
//                            renderer.proposedSize = .init(crop.size())
//                            if let image = renderer.uiImage {
//                                onCrop(image, true)
//                            } else {
//                                onCrop(nil, false)
//                            }
//                            dismiss()
//                        } label: {
//                            Image(systemName: "checkmark")
//                                .font(.callout)
//                                .fontWeight(.semibold)
//                        }
//                    }
//                    
//                    ToolbarItem(placement: .topBarLeading) {
//                        Button {
//                            dismiss()
//                        } label: {
//                            Image(systemName: "xmark")
//                                .font(.callout)
//                                .fontWeight(.semibold)
//                        }
//                    }
//                }
            VStack {
                VStack {
                    Text("移动并缩放")
                }
                Spacer()
                if let cropOptions {
                    cropOptions
                        .padding(.horizontal)
                }
                HStack {
                    Button("取消") {
                        dismiss()
                    }
                    .buttonStyle(.glass)
                    Spacer()
                    Button("完成") {
                        if let croppedImage = cropImageFromOriginalSource() {
                            onCrop(croppedImage, true)
                        } else {
                            onCrop(nil, false)
                        }
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                }
                .padding()
            }
        }
    }
    
    @ViewBuilder
    func ImageView() -> some View {
        let cropSize = crop.size()
        
        GeometryReader {
            let size = $0.size
            
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(size)
            }
        }
        .scaleEffect(scale)
        .offset(offset)
        .coordinateSpace(.named("CROPVIEW"))
        .gesture(
            DragGesture()
                .updating($isInteracting) { _, out, _ in
                    out = true
                }
                .onChanged { value in
                    guard let image else { return }
                    let cropSize = crop.size()
                    let translation = value.translation
                    let proposedOffset = CGSize(
                        width: translation.width + lastStoredOffset.width,
                        height: translation.height + lastStoredOffset.height
                    )
                    offset = clampedOffset(
                        for: proposedOffset,
                        sourceImageSize: image.size,
                        cropSize: cropSize,
                        scale: scale
                    )
                }
                .onEnded { _ in
                    lastStoredOffset = offset
                }
        )
        .gesture(
            MagnifyGesture()
                .updating($isInteracting, body: { _, out, _ in
                    out = true
                })
                .onChanged({ value in
                    guard let image else { return }
                    let cropSize = crop.size()
                    let updatedScale = value.magnification + value.magnification * lastScale
                    let clampedUpdatedScale = max(updatedScale, 1)
                    scale = clampedUpdatedScale
                    let proposedOffset = CGSize(
                        width: value.magnification * lastStoredOffset.width,
                        height: value.magnification * lastStoredOffset.height
                    )
                    offset = clampedOffset(
                        for: proposedOffset,
                        sourceImageSize: image.size,
                        cropSize: cropSize,
                        scale: clampedUpdatedScale
                    )
                })
                .onEnded({ _ in
                    scale = max(scale, 1)
                    if let image {
                        offset = clampedOffset(
                            for: offset,
                            sourceImageSize: image.size,
                            cropSize: crop.size(),
                            scale: scale
                        )
                    }
                    lastStoredOffset = offset
                    lastScale = scale - 1
                })
        )
        .frame(cropSize)
        .offset(y: cropWindowVerticalOffset)
        // .cornerRadius(crop == .circle ? cropSize.height / 2 : 0)
    }

    @ViewBuilder
    private func cropCutoutShape(for crop: Crop) -> some View {
        switch crop {
        case .circle:
            Circle()
        case .roundedRectangle(_, let cornerRadius, let style):
            RoundedRectangle(cornerRadius: cornerRadius, style: style)
        }
    }

    @ViewBuilder
    private func cropStrokeShape(for crop: Crop) -> some View {
        switch crop {
        case .circle:
            Circle()
                .stroke(Color.white, lineWidth: 0.5)
        case .roundedRectangle(_, let cornerRadius, let style):
            RoundedRectangle(cornerRadius: cornerRadius, style: style)
                .stroke(Color.white, lineWidth: 0.5)
        }
    }

    private func cropImageFromOriginalSource() -> UIImage? {
        guard let sourceImage = image else { return nil }
        let normalizedImage = normalizedImage(sourceImage)
        guard let sourceCGImage = normalizedImage.cgImage else { return nil }

        let cropRectInImage = cropRectInSourceImage(for: normalizedImage)
        let imageBounds = CGRect(origin: .zero, size: normalizedImage.size)
        let boundedCropRect = cropRectInImage.standardized.intersection(imageBounds)
        guard boundedCropRect.width > 0, boundedCropRect.height > 0 else { return nil }

        let pixelScaleX = CGFloat(sourceCGImage.width) / normalizedImage.size.width
        let pixelScaleY = CGFloat(sourceCGImage.height) / normalizedImage.size.height
        var pixelCropRect = CGRect(
            x: boundedCropRect.origin.x * pixelScaleX,
            y: boundedCropRect.origin.y * pixelScaleY,
            width: boundedCropRect.width * pixelScaleX,
            height: boundedCropRect.height * pixelScaleY
        ).integral

        let pixelBounds = CGRect(
            x: 0,
            y: 0,
            width: sourceCGImage.width,
            height: sourceCGImage.height
        )
        pixelCropRect = pixelCropRect.intersection(pixelBounds)

        guard pixelCropRect.width > 0, pixelCropRect.height > 0,
              let croppedCGImage = sourceCGImage.cropping(to: pixelCropRect) else {
            return nil
        }

        return UIImage(cgImage: croppedCGImage, scale: normalizedImage.scale, orientation: .up)
    }

    private func cropRectInSourceImage(for sourceImage: UIImage) -> CGRect {
        let cropSize = crop.size()
        let sourceSize = sourceImage.size

        guard cropSize.width > 0, cropSize.height > 0,
              sourceSize.width > 0, sourceSize.height > 0 else {
            return .zero
        }

        let baseFillScale = max(
            cropSize.width / sourceSize.width,
            cropSize.height / sourceSize.height
        )
        let effectiveScale = max(scale, 1)
        let displayedImageSize = CGSize(
            width: sourceSize.width * baseFillScale * effectiveScale,
            height: sourceSize.height * baseFillScale * effectiveScale
        )

        let imageOriginInCropSpace = CGPoint(
            x: (cropSize.width - displayedImageSize.width) / 2 + offset.width,
            y: (cropSize.height - displayedImageSize.height) / 2 + offset.height
        )

        return CGRect(
            x: (-imageOriginInCropSpace.x / displayedImageSize.width) * sourceSize.width,
            y: (-imageOriginInCropSpace.y / displayedImageSize.height) * sourceSize.height,
            width: (cropSize.width / displayedImageSize.width) * sourceSize.width,
            height: (cropSize.height / displayedImageSize.height) * sourceSize.height
        )
    }

    private func clampedOffset(
        for proposedOffset: CGSize,
        sourceImageSize: CGSize,
        cropSize: CGSize,
        scale: CGFloat
    ) -> CGSize {
        guard sourceImageSize.width > 0,
              sourceImageSize.height > 0,
              cropSize.width > 0,
              cropSize.height > 0 else {
            return .zero
        }

        let effectiveScale = max(scale, 1)
        let baseFillScale = max(
            cropSize.width / sourceImageSize.width,
            cropSize.height / sourceImageSize.height
        )

        let displayedImageSize = CGSize(
            width: sourceImageSize.width * baseFillScale * effectiveScale,
            height: sourceImageSize.height * baseFillScale * effectiveScale
        )

        let maxOffsetX = max((displayedImageSize.width - cropSize.width) / 2, 0)
        let maxOffsetY = max((displayedImageSize.height - cropSize.height) / 2, 0)

        return CGSize(
            width: min(max(proposedOffset.width, -maxOffsetX), maxOffsetX),
            height: min(max(proposedOffset.height, -maxOffsetY), maxOffsetY)
        )
    }

    private func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }

        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: rendererFormat)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
