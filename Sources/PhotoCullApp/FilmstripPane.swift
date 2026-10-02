import SwiftUI
import PhotoCullCore

/// Native horizontal filmstrip of the current session's photos.
struct FilmstripPane: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(text: "Filmstrip", number: 4,
                          focused: app.focusedPane == .filmstrip,
                          trailing: {
                Text(app.pairs.isEmpty ? "" : "\(app.index + 1) of \(app.pairs.count)")
                    .font(Typo.number)
                    .foregroundStyle(Palette.tertiary)
            })

            if app.pairs.isEmpty {
                EmptyState(icon: "film",
                           title: "No photos",
                           message: "This session has no JPG files.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        // Non-lazy on purpose. LazyHStack + programmatic
                        // scrollTo misbehaves on macOS: cells materialize
                        // blank when navigating back and forth, and scrollTo
                        // can no-op on ids that aren't materialized yet, so
                        // far jumps don't center. Thumbnails are capped at
                        // 256px and sessions hold ~150 photos max (~30MB),
                        // so mounting every cell is cheap and stays
                        // subscription-safe: every cell re-renders on cache
                        // changes instead of only the recycled window.
                        HStack(spacing: Metric.elementGap) {
                            ForEach(Array(app.pairs.enumerated()), id: \.element.jpg) { i, pair in
                                ThumbCell(pair: pair, index: i,
                                          decision: app.decision(for: pair.stem),
                                          crop: app.crop(for: pair.stem),
                                          isCurrent: i == app.index,
                                          onSelect: { app.setIndex(i) },
                                          thumbs: app.thumbs)
                            }
                        }
                        .padding(.horizontal, Metric.paneInset)
                        .padding(.bottom, Metric.elementGap)
                    }
                    .onChange(of: app.index) { _, new in
                        guard app.pairs.indices.contains(new) else { return }
                        withAnimation(Motion.fast) { proxy.scrollTo(app.pairs[new].jpg, anchor: .center) }
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
    let pair: FilePair
    let index: Int
    let decision: Decision
    let crop: CropRect?
    let isCurrent: Bool
    /// Tap handler passed down by the pane, so cells don't subscribe to the
    /// app-wide object for a single method call.
    let onSelect: () -> Void
    @ObservedObject var thumbs: ThumbnailStore

    @StateObject private var hover = ViewState(false)

    private var isCropped: Bool { !(crop?.isFullFrame ?? true) }

    /// The cache is already EXIF-orientated. Fit its actual dimensions in the
    /// filmstrip slot, so neither the photo nor its selection ring is cropped.
    private var imageSize: CGSize {
        guard let cg = thumbs.cached(for: pair.jpg) else {
            return CGSize(width: Metric.thumbHeight * 2 / 3, height: Metric.thumbHeight)
        }
        let scale = min(Metric.thumbWidth / CGFloat(cg.width),
                        Metric.thumbHeight / CGFloat(cg.height))
        return CGSize(width: CGFloat(cg.width) * scale,
                      height: CGFloat(cg.height) * scale)
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Rectangle().fill(Palette.quaternary.opacity(0.25))
                if let cg = thumbs.cached(for: pair.jpg) {
                    Image(decorative: cg, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else if thumbs.isFailed(pair.jpg) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(Typo.iconSmall)
                        .foregroundStyle(Palette.warning)
                        .help("Could not read this file's preview")
                } else {
                    ProgressView().controlSize(.mini).scaleEffect(0.5)
                }
            }
            .frame(width: imageSize.width, height: imageSize.height)
            .clipShape(RoundedRectangle(cornerRadius: Metric.radiusThumb, style: .continuous))
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
            .shadowSubtle(isCurrent || hover.value)
            .scaleEffect(isCurrent ? 1.0 : (hover.value ? 1.02 : 1.0))
            .animation(Motion.fast, value: hover.value)
            .animation(Motion.fast, value: isCurrent)
            // Keep every index in a stable-width slot, but draw the ring only
            // around the visible photo, never the empty sides of that slot.
            .frame(width: Metric.thumbWidth, height: Metric.thumbHeight)

            Text("\(index + 1)")
                .font(Typo.number)
                .foregroundStyle(isCurrent ? Palette.label : Palette.quaternary)
        }
        .contentShape(Rectangle())
        .onHover { hover.value = $0 }
        .onTapGesture { onSelect() }
        .help("\(pair.stem).JPG")
        // Reload when this slot's photo changes. Cell identity is the photo's
        // full URL (see the ForEach above), so a session switch rebuilds every
        // cell and this runs fresh; it also covers in-place photo changes.
        // A cell whose thumbnail was LRU-evicted while off-screen heals here
        // too, because lazy remounting re-runs this task on re-appear.
        .task(id: pair.jpg) { _ = thumbs.thumbnail(for: pair.jpg) }
    }
}
