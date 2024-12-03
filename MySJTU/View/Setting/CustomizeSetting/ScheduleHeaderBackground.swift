//
//  ScheduleHeaderBackground.swift
//  MySJTU
//
//  Created by boar on 2024/11/26.
//

import SwiftUI
import PhotosUI
import SwiftyCrop

struct ScheduleHeaderBackground: View {
    @State private var selectedImage: UIImage?
    @State private var showPhotosPicker: Bool = false
    @AppStorage("schedule.headerImage") var headerImage: URL?

    private func savePhoto(data: Data) throws -> URL? {
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let destURL = documentsURL.appendingPathComponent(UUID().uuidString + ".png")
            try data.write(to: destURL, options: .atomic)
            return destURL
        } else {
            return nil
        }
    }

    private func deletePhoto(url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    var body: some View {
        List {
            Section(header: Text("当前背景")) {
                if headerImage == nil {
                    Button {
                        showPhotosPicker = true
                    } label: {
                        GeometryReader { geometry in
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color(UIColor.secondaryLabel), style: StrokeStyle(lineWidth: 1, dash: [6]))
                                .frame(width: geometry.size.width, height: geometry.size.width / 2)
                                .overlay {
                                    Text("没有设置自定义背景")
                                        .foregroundStyle(Color(UIColor.secondaryLabel))
                                }
                        }
                        .frame(height: UIScreen.main.bounds.width / 2)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
                } else {
                    Menu {
                        Button {
                            do {
                                if let headerImage {
                                    try deletePhoto(url: headerImage)
                                    self.headerImage = nil
                                }
                            } catch {
                                print(error)
                            }
                        } label: {
                            Label("移除背景", systemImage: "trash")
                        }
                        Button {
                            showPhotosPicker = true
                        } label: {
                            Label("更换图片", systemImage: "photo")
                        }
                    } label: {
                        GeometryReader { geometry in
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.clear)
                            // .background(.ultraThinMaterial)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color(UIColor.systemBackground).opacity(0.8))
                                )
                                .background(
                                    AsyncImage(
                                        url: headerImage!,
                                        transaction: Transaction(animation: .easeInOut)
                                    ) { phase in
                                        if let image = phase.image {
                                            image.resizable()
                                                .aspectRatio(contentMode: .fit)
                                        }
                                    }
                                )
                                .frame(width: geometry.size.width, height: geometry.size.width / 2)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .frame(height: UIScreen.main.bounds.width / 2)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
                }
            }
        }
        .navigationBarTitle("导航栏背景图")
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: Binding(
                get: { nil },
                set: {
                    if let photo = $0 {
                        photo.loadTransferable(type: Data.self) { result in
                            switch result {
                            case .success(let image?):
                                selectedImage = UIImage(data: image)
                            case .success(.none):
                                break
                            case .failure(_):
                                break
                            }
                        }
                    }
                }
            ),
            matching: .any(of: [.images, .screenshots])
        )
        .fullScreenCover(isPresented: Binding(
            get: { selectedImage != nil },
            set: { if $0 == false { selectedImage = nil } }
        )) {
            NavigationView {
                SwiftyCropView(
                    imageToCrop: selectedImage!,
                    maskShape: .rectangle,
                    configuration: SwiftyCropConfiguration(
                        rectAspectRatio: 2/1,
                        texts: SwiftyCropConfiguration.Texts(
                            cancelButton: "取消",
                            interactionInstructions: "移动并缩放",
                            saveButton: "完成"
                        )
                    )
                ) { croppedImage in
                    DispatchQueue.main.async {
                        if let image = croppedImage, let data = image.jpegData(compressionQuality: 1) {
                            do {
                                headerImage = try savePhoto(data: data)
                            } catch {
                                print(error)
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ScheduleHeaderBackground()
}
