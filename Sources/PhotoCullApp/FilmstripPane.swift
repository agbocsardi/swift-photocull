import SwiftUI
import PhotoCullCore

struct FilmstripPane: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var thumbs: ThumbnailStore

    init() {
        // Observed store is injected in onAppear via the environment object.
        self._thumbs = ObservedObject(wrappedValue: ThumbnailStore())
    }

    var body: some View {
        FilmstripBody(thumbs: app.thumbs)
    }
}

private struct FilmstripBody: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var thumbs: ThumbnailStore

    var body: some View {
        PaneBox(number: 4, title: "Filmstrip", focused: app.focusedPane == .filmstrip,
                trailing: AnyView(
                    Text(app.pairs.isEmpty ? "" : "\(app.index + 1)/\(app.pairs.count)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(EF.subtle))) {
            if app.pairs.isEmpty {
                EmptyHint(text: "No photos in this session")
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 4) {
                            ForEach(Array(app.pairs.enumerated()), id: \.element.stem) { i, pair in
                                ThumbCell(pair: pair, index: i,
                                          decision: app.decision(for: pair.stem),
                                          crop: app.crop(for: pair.stem),
                                          isCurrent: i == app.index,
                                          thumbs: thumbs)
                                    .id(i)
                            }
                        }
                        .padding(5)
                    }
                    .onChange(of: app.index) { _, new in
                        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(new, anchor: .center) }
                    }
                }
            }
        }
    }
}

private struct ThumbCell: View {
    @EnvironmentObject var app: AppState
    let pair: FilePair
    let index: Int
    let decision: Decision
    let crop: CropRect?
    let isCurrent: Bool
    @ObservedObject var thumbs: ThumbnailStore

    private var isCropped: Bool { !(crop?.isFullFrame ?? true) }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(EF.bg1)
                if let cg = thumbs.cached(for: pair.jpg) ?? triggerLoad() {
                    Image(decorative: cg, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    ProgressView().controlSize(.mini).scaleEffect(0.5)
                }
            }
            .frame(width: 74, height: 56)
            .overlay(alignment: .topTrailing) {
                Text(decision.glyph)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(decision.color)
                    .padding(2)
                    .background(Circle().fill(EF.bg.opacity(0.8)))
                    .padding(2)
            }
            .overlay(alignment: .bottomLeading) {
                if isCropped {
                    Text("▣").font(.system(size: 9))
                        .foregroundStyle(EF.yellow)
                        .padding(2)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isCurrent ? EF.blue : EF.bg3.opacity(0.6),
                            lineWidth: isCurrent ? 2 : 1)
            )
            .overlay(alignment: .bottomTrailing) {
                if pair.hasRAW {
                    Text("R").font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(EF.aqua).padding(2)
                }
            }

            Text("\(index + 1)")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(isCurrent ? EF.text : EF.bg3)
        }
        .contentShape(Rectangle())
        .onTapGesture { app.setIndex(index) }
        .help("\(pair.stem).JPG")
    }

    private func triggerLoad() -> CGImage? {
        _ = thumbs.thumbnail(for: pair.jpg)
        return nil
    }
}
