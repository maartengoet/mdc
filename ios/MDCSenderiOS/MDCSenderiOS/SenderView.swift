import PhotosUI
import SwiftUI

struct SenderView: View {
    @EnvironmentObject private var model: SenderModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var showFitControls = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = proxy.safeAreaInsets.bottom
            let horizontalPadding: CGFloat = 18
            let contentWidth = max(size.width - (horizontalPadding * 2), 1)
            let topBarHeight: CGFloat = 58
            let bottomControlsHeight: CGFloat = showFitControls ? 244 : 86
            let topBarTop = max(safeTop - 52, CGFloat(18))
            let topBarCenterY = topBarTop + (topBarHeight / 2)
            let bottomControlsCenterY = size.height - safeBottom + 24 - (bottomControlsHeight / 2)
            let previewTop = max(safeTop + 132, topBarTop + topBarHeight + 72)
            let previewBottom = bottomControlsCenterY - (bottomControlsHeight / 2) - 28
            let panelRatio = CGFloat(model.settings.canvasWidth) / CGFloat(model.settings.canvasHeight)
            let maxPanelHeight = max(previewBottom - previewTop, 120)
            let panelWidth = min(contentWidth, maxPanelHeight * panelRatio, 620)
            let panelHeight = panelWidth / panelRatio
            let previewSlack = max((previewBottom - previewTop) - panelHeight, 0)
            let previewCenterY = previewTop + (panelHeight / 2) + (previewSlack * 0.35)
            let backgroundSize = CGSize(width: size.width + 96, height: size.height + safeTop + safeBottom + 560)

            ZStack {
                topBar
                    .frame(width: contentWidth, height: topBarHeight)
                    .position(x: size.width / 2, y: topBarCenterY)

                EpaperPreview(image: model.selectedImage, settings: model.settings)
                    .frame(width: panelWidth, height: panelHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .clipped()
                    .position(x: size.width / 2, y: previewCenterY)

                bottomControls
                    .frame(width: contentWidth, height: bottomControlsHeight, alignment: .bottom)
                    .position(x: size.width / 2, y: bottomControlsCenterY)
            }
            .frame(width: size.width, height: size.height)
            .background {
                Color(red: 0.15, green: 0.22, blue: 0.21)
                    .ignoresSafeArea()

                background(size: backgroundSize)
                    .offset(y: -220)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView()
                .environmentObject(model)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: pickerItem) { _, newValue in
            guard let newValue else { return }
            Task {
                await model.loadImage(from: newValue)
                pickerItem = nil
            }
        }
    }

    @ViewBuilder
    private func background(size: CGSize) -> some View {
        if let image = model.selectedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .blur(radius: 32, opaque: true)
                .saturation(1.18)
                .brightness(-0.08)
                .overlay(.black.opacity(0.18))
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.13, blue: 0.17),
                    Color(red: 0.17, green: 0.25, blue: 0.25),
                    Color(red: 0.42, green: 0.47, blue: 0.41)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: size.width, height: size.height)
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 0) {
            if showFitControls {
                FitControls(settings: $model.settings)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            bottomBar
        }
        .animation(.snappy(duration: 0.28), value: showFitControls)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MDC Sender")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text(model.settings.host.isEmpty ? "No display" : model.settings.host)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }
            .frame(minWidth: 116, maxWidth: .infinity, alignment: .leading)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)

            StatusPill(phase: model.phase)
                .frame(width: 144, alignment: .leading)

            Button {
                model.showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(IconGlassButtonStyle())
        }
    }

    private var bottomBar: some View {
        let photoButtonTitle = model.selectedImage == nil ? "Choose Photo" : "Change Photo"

        return GeometryReader { proxy in
            let spacing: CGFloat = 10
            let padding: CGFloat = 10
            let cropWidth: CGFloat = 54
            let idealSendWidth = proxy.size.width * 0.30
            let sendWidth = min(max(idealSendWidth, CGFloat(104)), CGFloat(118))
            let usedWidth = (padding * 2) + cropWidth + sendWidth + (spacing * 2)
            let photoWidth = max(proxy.size.width - usedWidth, CGFloat(118))

            HStack(spacing: spacing) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(photoButtonTitle, systemImage: "photo.on.rectangle.angled")
                        .font(.headline)
                        .frame(width: photoWidth, height: 54)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .background(.regularMaterial, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.isSending)

                Button {
                    showFitControls.toggle()
                } label: {
                    Image(systemName: "crop")
                }
                .buttonStyle(IconGlassButtonStyle())
                .disabled(model.selectedImage == nil || model.isSending)

                Button {
                    Task {
                        await model.sendSelectedImage()
                    }
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                        .lineLimit(1)
                }
                .buttonStyle(PrimaryGlassButtonStyle())
                .frame(width: sendWidth, height: 54)
                .disabled(model.selectedImage == nil || model.isSending)
            }
            .padding(padding)
            .frame(width: proxy.size.width, height: 74)
            .mdcGlass(RoundedRectangle(cornerRadius: 34, style: .continuous), interactive: true)
        }
        .frame(height: 74)
    }
}

struct EpaperPreview: View {
    let image: UIImage?
    let settings: DisplaySettings

    var body: some View {
        GeometryReader { proxy in
            let bezel = min(max(proxy.size.width * 0.026, 8), 11)
            let screenWidth = max(proxy.size.width - (bezel * 2), 1)
            let screenHeight = max(proxy.size.height - (bezel * 2), 1)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(white: 0.96))
                    .shadow(color: .black.opacity(0.20), radius: 24, y: 14)

                ZStack {
                    if let image {
                        FittedPreviewImage(image: image, settings: settings)
                    } else {
                        VStack(spacing: 14) {
                            Image(systemName: "photo")
                                .font(.system(size: 46, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("Samsung E-Paper")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: screenWidth, height: screenHeight)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(.black.opacity(0.05), lineWidth: 1)
                }
                .clipped()
            }
        }
        .accessibilityLabel("E-paper preview")
    }
}

struct FittedPreviewImage: View {
    let image: UIImage
    let settings: DisplaySettings

    var body: some View {
        GeometryReader { proxy in
            switch settings.imageFit {
            case .cover:
                positionedImage(in: proxy.size, mode: .cover)
            case .stretch:
                Image(uiImage: image)
                    .resizable()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            case .original, .contain:
                positionedImage(in: proxy.size, mode: .contain)
            }
        }
        .clipped()
    }

    private func positionedImage(in canvasSize: CGSize, mode: ImageFit) -> some View {
        let sourceSize = image.size
        let scale = mode == .cover
            ? max(canvasSize.width / sourceSize.width, canvasSize.height / sourceSize.height)
            : min(canvasSize.width / sourceSize.width, canvasSize.height / sourceSize.height)
        let imageSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let offsetX: CGFloat
        let offsetY: CGFloat

        if mode == .cover {
            offsetX = (0.5 - settings.cropX) * max(imageSize.width - canvasSize.width, 0)
            offsetY = (0.5 - settings.cropY) * max(imageSize.height - canvasSize.height, 0)
        } else {
            offsetX = (settings.cropX - 0.5) * max(canvasSize.width - imageSize.width, 0)
            offsetY = (settings.cropY - 0.5) * max(canvasSize.height - imageSize.height, 0)
        }

        return Image(uiImage: image)
            .resizable()
            .frame(width: imageSize.width, height: imageSize.height)
            .offset(x: offsetX, y: offsetY)
            .frame(width: canvasSize.width, height: canvasSize.height)
            .clipped()
    }
}

struct FitControls: View {
    @Binding var settings: DisplaySettings

    var body: some View {
        let focusEnabled = settings.imageFit == .cover || settings.imageFit == .contain

        VStack(spacing: 16) {
            Picker("Fit", selection: $settings.imageFit) {
                ForEach(ImageFit.allCases) { fit in
                    Text(fit.title).tag(fit)
                }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 10) {
                HStack {
                    Label("Horizontal focus", systemImage: "arrow.left.and.right")
                    Slider(value: $settings.cropX, in: 0...1)
                }
                HStack {
                    Label("Vertical focus", systemImage: "arrow.up.and.down")
                    Slider(value: $settings.cropY, in: 0...1)
                }
            }
            .font(.footnote.weight(.medium))
            .disabled(!focusEnabled)
            .opacity(focusEnabled ? 1 : 0.45)
        }
        .glassCard(cornerRadius: 28)
    }
}
