//
//  UnicodeView.swift
//  MySJTU
//
//  Created by boar on 2024/09/28.
//

import SwiftUI
import QRCode
import Lottie
import PhotosUI
import SwiftyCrop

struct DataUrl: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .data) { data in
            SentTransferredFile(data.url)
        } importing: { received in
            Self(url: received.file)
        }
    }
}

struct UnicodeView: View {
    private enum UnicodeStatus {
        case loading
        case noValidAccount
        case normal
    }

    @AppStorage("accounts") var accounts: [WebAuthAccount] = []
    @AppStorage("unicode.customAvatar") var customAvatar: URL?
    @State private var status: UnicodeStatus = .loading
    @State private var unicode: Unicode?
    @State private var qrShape: QRCodeShape?
    @State private var user: WebAuthUser?
    @State private var originalBrightness: CGFloat?
    @State private var showPhotosPicker: Bool = false
    @State private var selectedImage: UIImage?
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject private var appConfig: AppConfig

    let timer = Timer.publish(every: 40, on: .main, in: .common).autoconnect()

    private func loadUnicode() async throws {
        if appConfig.appStatus == .review {
            user = WebAuthUser(account: "test_user", name: "测试用户", code: "524030910001")
            let response: OpenApiResponse<Unicode> = try await getUnicodeSample()
            if let code = response.entities[0].code {
                self.qrShape = try QRCodeShape(
                    text: code,
                    errorCorrection: .medium,
                    shape: .init(
                        onPixels: QRCode.PixelShape.RoundedPath(cornerRadiusFraction: 1, hasInnerCorners: true),
                        eye: QRCode.EyeShape.RoundedRect()
                    )
                )

                status = .normal
            }
            return
        }
        
        let rawAccounts = UserDefaults.standard.string(forKey: "accounts")
        if let rawAccounts {
            if var accounts = Array<WebAuthAccount>(rawValue: rawAccounts) {
                for i in 0..<accounts.count {
                    if accounts[i].provider == .jaccount {
                        user = accounts[i].user

                        for j in 0..<accounts[i].tokens.count {
                            if accounts[i].tokens[j].scopes.contains("unicode") {
                                if accounts[i].tokens[j].accessToken.isExpired {
                                    accounts[i].tokens[j].accessToken = try await accounts[i].tokens[j].accessToken.refresh()
                                    // UserDefaults.standard.set(accounts.rawValue, forKey: "accounts")
                                    self.accounts = accounts
                                }
                                let token = accounts[i].tokens[j].accessToken
                                let api = SJTUOpenAPI(token: token)
                                self.unicode = try await api.getUnicode()

                                if unicode?.status == -1 {
                                    // 未开通思源码
                                } else if let code = unicode?.code {
                                    self.qrShape = try QRCodeShape(
                                        text: code,
                                        errorCorrection: .medium,
                                        shape: .init(
                                            onPixels: QRCode.PixelShape.RoundedPath(cornerRadiusFraction: 1, hasInnerCorners: true),
                                            eye: QRCode.EyeShape.RoundedRect()
                                        )
                                    )

                                    status = .normal
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private enum FSError: Error {
        case documentsURLNotFound
    }
    
    private func copyPhoto(url: URL) throws -> URL {
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let ext = url.pathExtension
            let destURL = documentsURL.appendingPathComponent(UUID().uuidString + ".\(ext)")
            try FileManager.default.copyItem(at: url, to: destURL)
            return destURL
        } else {
            throw FSError.documentsURLNotFound
        }
    }
    
    private func savePNGPhoto(data: Data) throws -> URL {
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let destURL = documentsURL.appendingPathComponent(UUID().uuidString + ".png")
            try data.write(to: destURL)
            return destURL
        } else {
            throw FSError.documentsURLNotFound
        }
    }
    
    private func deletePhoto(url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    var body: some View {
        Group {
            if status == .normal {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(maxHeight: .infinity)
                    
                    ZStack(alignment: .top) {
                        VStack {
                            if let qrShape {
                                qrShape
                                    .fill(LinearGradient(gradient: Gradient(colors: [Color(hex: "#283c86"), Color(hex: "#45a247")]), startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .padding([.leading, .trailing, .bottom], 48)
                            }
                        }
                        .background(Color.white)
                        .frame(width: 300, height: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 48, style: .continuous))
                        
                        Menu {
                            if let customAvatar {
                                Button {
                                    do {
                                        try deletePhoto(url: customAvatar)
                                    } catch {
                                        print(error)
                                    }
                                    self.customAvatar = nil
                                } label: {
                                    Label("恢复默认头像", systemImage: "person.circle")
                                }
                                Divider()
                            }
                            Button {
                                showPhotosPicker = true
                            } label: {
                                Label("自定义头像", systemImage: "photo")
                            }
                        } label: {
                            AsyncImage(
                                url: customAvatar != nil ? customAvatar : URL(string: user?.photo ?? ""),
                                transaction: Transaction(animation: .easeInOut)
                            ) { phase in
                                if let image = phase.image {
                                    image.resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else if phase.error != nil {
                                    Image(uiImage: UIImage(named: "avatar_placeholder")!)
                                        .resizable()
                                } else {
                                    ProgressView()
                                }
                            }
                        }
                        .frame(width: 96, height: 96)
                        .background(Color.white)
                        .clipShape(Circle())
                        .offset(y: -64)
                        
                        VStack(spacing: 0) {
                            Text(user?.name ?? "")
                                .font(.custom("ChillRoundGothic_Bold", size: 24))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(hex: "#4F8061"), Color(hex: "#45a247")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text(user?.code ?? "")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(hex: "#4F8061"), Color(hex: "#45a247")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .offset(y: 270)
                    }

                    VStack {
                        HStack {
                            Image(systemName: "info.circle")
                                .font(.footnote)
                            Text("此二维码为身份码。")
                                .font(.footnote)
                        }
                        
                        Text("可用于闸机认证等用途，但不可用于支付。")
                            .font(.footnote)
                    }
                    .frame(maxHeight: .infinity)
                }
                .background {
                    LottieView {
                        try await DotLottieFile.named("QrBackgroundLight")
                    }
                    .looping()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                    .frame(maxWidth: .infinity)
                    .blur(radius: 100)
                }
                .onAppear() {
                    originalBrightness = UIScreen.main.brightness
                    UIScreen.main.setBrightness(to: CGFloat(1.0))
                }
                .onDisappear() {
                    if let originalBrightness {
                        UIScreen.main.setBrightness(to: originalBrightness)
                    }
                    originalBrightness = nil
                }
                .onChange(of: scenePhase) {
                    switch scenePhase {
                    case .active:
                        originalBrightness = UIScreen.main.brightness
                        UIScreen.main.setBrightness(to: CGFloat(1.0))
                    case .background:
                        if let originalBrightness {
                            UIScreen.main.setBrightness(to: originalBrightness)
                        }
                        originalBrightness = nil
                    case .inactive:
                        if let originalBrightness {
                            UIScreen.main.setBrightness(to: originalBrightness)
                        }
                        originalBrightness = nil
                    default:
                        break
                    }
                }
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
                            maskShape: .circle,
                            configuration: SwiftyCropConfiguration(
                                maskRadius: UIScreen.main.bounds.size.width,
                                zoomSensitivity: 8.0,
                                texts: SwiftyCropConfiguration.Texts(
                                    cancelButton: "取消",
                                    interactionInstructions: "移动并缩放",
                                    saveButton: "完成"
                                )
                            )
                        ) { croppedImage in
                            DispatchQueue.main.async {
                                if let image = croppedImage, let data = image.pngData() {
                                    do {
                                        if let customAvatar {
                                            try deletePhoto(url: customAvatar)
                                        }
                                        customAvatar = try savePNGPhoto(data: data)
                                    } catch {
                                        print(error)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .animation(.easeInOut, value: status)
        .task {
            do {
                try await loadUnicode()
            } catch {
                print(error)
            }
        }
        .onReceive(timer) { input in
            Task {
                do {
                    try await loadUnicode()
                } catch {
                    print(error)
                }
            }
        }
    }
}

#Preview {
    UnicodeView()
}
