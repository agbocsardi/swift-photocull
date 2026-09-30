import SwiftUI
import PhotoCullCore

/// Native horizontal filmstrip of the current session's photos.
struct FilmstripPane: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(text: "Filmstrip", number: 4,
                          focused: app.focusedPane == .filmstrip,
                          trailing: AnyView(
                Text(app.pairs.isEmpty ? "" : "\(app.index + 1) of \(app.pairs.count)")
                    .font(Typo.number)
                    .foregroundStyle(Palette.tertiary)))

            if app.pairs.isEmpty {
                EmptyState(icon: "film",
                           title: "No photos",
                           message: "This session has no JPG files.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: Metric.elementGap) {
                            ForEach(Array(app.pairs.enumerated()), id: \.element.stem) { i, pair in
                                ThumbCell(pair: pair, index: i,
                                          decision: app.decision(for: pair.stem),
                                          crop: app.crop(for: pair.stem),
                                          isCurrent: i == app.index,
                                          thumbs: app.thumbs)
                                    .id(i)
                            }
                        }
                        .padding(.horizontal, Metric.paneInset)
                        .padding(.bottom, Metric.elementGap)
                    }
                    .onChange(of: app.index) { _, new in
                        withAnimation(Motion.fast) { proxy.scrollTo(new, anchor: .center) }
                    }
                }
            }
        }
        .background(Surface.chrome)
    }
}

/// One thumbnail. Current photo gets an accent ring; state is shown with a
/// small badge rather than recolouring the whole cell.
private struct ThumbCell: View {
    @EnvironmentObject var app: AppState
    let pair: FilePair
    let index: Int
    let decision: Decision
    let crop: CropRect?
    let isCurrent: Bool
    @ObservedObject var thumbs: ThumbnailStore

    @StateObject private var hover = ViewState(false)

    private var isCropped: Bool { !(crop?.isFullFrame ?? true) }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: Metric.radiusThumb, style: .continuous)
                    .fill(Palette.quaternary.opacity(0.25))
                if let cg = thumbs.cached(for: pair.jpg) {
                    Image(decorative: cg, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: Metric.radiusThumb,
                                                    style: .continuous))
                } else {
                    ProgressView().controlSize(.mini).scaleEffect(0.5)
                }
            }
            .frame(width: Metric.thumbWidth, height: Metric.thumbHeight)
            .overlay(alignment: .topTrailing) {
                if decision != .undecided {
                    Image(systemName: decision == .keep ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(decision.color)
                        .background(Circle().fill(.white).padding(2))
                        .padding(3)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if isCropped {
                    Image(systemName: "crop")
                        .font(Typo.iconTiny.weight(.bold))
                        .foregroundStyle(Palette.crop)
                        .padding(2)
                        .background(Circle().fill(.black.opacity(0.35)))
                        .padding(3)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if pair.hasRAW {
                    Text(pair.rawExt ?? "R")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Palette.raw)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(Capsule().fill(.black.opacity(0.35)))
                        .padding(3)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Metric.radiusThumb, style: .continuous)
                    .strokeBorder(isCurrent ? Palette.accent
                                            : (hover.value ? Palette.secondary : Palette.separator),
                                  lineWidth: isCurrent ? 2 : 0.5)
            )
            .shadowSubtle()
            .scaleEffect(isCurrent ? 1.0 : (hover.value ? 1.02 : 1.0))
            .animation(Motion.fast, value: hover.value)
            .animation(Motion.fast, value: isCurrent)

            Text("\(index + 1)")
                .font(Typo.number)
                .foregroundStyle(isCurrent ? Palette.label : Palette.quaternary)
        }
        .contentShape(Rectangle())
        .onHover { hover.value = $0 }
        .onTapGesture { app.setIndex(index) }
        .help("\(pair.stem).JPG")
        .onAppear { _ = thumbs.thumbnail(for: pair.jpg) }
    }
}
