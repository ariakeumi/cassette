// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct DiscoverView: View {
    @Environment(\.appContainer) private var container
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @State private var vm: DiscoverViewModel?
    @Namespace private var recentlyPlayedNS
    @Namespace private var mostPlayedNS

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CassetteSpacing.l) {
                if let vm {
                    if vm.isErrorState {
                        errorBanner(vm: vm)
                    } else {
                        recentlyPlayedSection(vm: vm)
                        mostPlayedSection(vm: vm)
                    }
                    smartShuffleSection
                }
            }
            .padding(.vertical, CassetteSpacing.m)
        }
        .cassetteContentWidth()
        .navigationTitle("Discover")
        .task {
            guard let container else { return }
            if vm == nil {
                vm = DiscoverViewModel(libraryService: container.libraryService)
            }
            await vm?.load()
        }
        .refreshable {
            await vm?.load(forceRefresh: true)
        }
    }

    // MARK: - Sections

    private func recentlyPlayedSection(vm: DiscoverViewModel) -> some View {
        Group {
            if vm.isInitialLoading {
                section(title: "Recently Played") { skeletonScroll() }
            } else if vm.recentlyPlayed.isEmpty {
                section(title: "Recently Played") {
                    emptyStateMessage("No history yet — start playing some tracks.")
                }
            } else {
                CarouselSection(title: "Recently Played") {
                    ForEach(vm.recentlyPlayed, id: \.id) { album in
                        CarouselAlbumCard(album: album)
                    }
                }
            }
        }
    }

    private func mostPlayedSection(vm: DiscoverViewModel) -> some View {
        Group {
            if vm.isInitialLoading {
                section(title: "Most Played") { skeletonScroll() }
            } else if vm.mostPlayed.isEmpty {
                section(title: "Most Played") {
                    emptyStateMessage("No frequent plays yet — your top tracks will appear here.")
                }
            } else {
                CarouselSection(title: "Most Played") {
                    ForEach(vm.mostPlayed, id: \.id) { album in
                        CarouselAlbumCard(album: album)
                    }
                }
            }
        }
    }

    private var smartShuffleSection: some View {
        section(title: "Smart Shuffle") {
            Button {
                Task { await triggerSmartShuffle() }
            } label: {
                HStack(spacing: CassetteSpacing.s) {
                    Image(systemName: "shuffle.circle.fill")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rediscover Your Library")
                            .font(.cassetteCellTitle)
                        Text("A random mix from your library")
                            .font(.cassetteCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(CassetteSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cassetteAccent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.standard, style: .continuous))
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, CassetteSpacing.m)
        }
    }

    private func triggerSmartShuffle() async {
        guard let container else { return }
        do {
            try await container.playerService.playSmartShuffle()
        } catch {
            container.toastService.showError(smartShuffleErrorMessage(from: error))
        }
    }

    private func smartShuffleErrorMessage(from error: Error) -> String {
        if case CassetteError.smartShuffleEmpty = error {
            return "Smart Shuffle unavailable — try playing some tracks first or download more music for offline use."
        }
        return "Smart Shuffle failed. Please try again."
    }

    // MARK: - Helpers

    private func section<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            Text(title)
                .font(.cassetteSectionTitle)
                .padding(.horizontal, CassetteSpacing.m)
            content()
        }
    }

    private func horizontalAlbumScroll(albums: [AlbumID3], namespace: Namespace.ID) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: CassetteSpacing.s) {
                ForEach(albums, id: \.id) { album in
                    NavigationLink {
                        AlbumDetailMacOS(albumId: album.id, albumName: album.name, coverArtId: album.coverArt)
                    } label: {
                        AlbumCard(album: album)
                            .cassetteMatchedTransitionSource(id: album.id, in: namespace)
                            .task(id: album.id) {
                                await artworkImageCache.load(coverArtId: album.coverArt ?? album.id)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, CassetteSpacing.m)
        }
    }

    private func errorBanner(vm: DiscoverViewModel) -> some View {
        VStack(alignment: .leading, spacing: CassetteSpacing.s) {
            HStack(spacing: CassetteSpacing.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow) // warning state — not brand accent
                Text("Unable to load Discover")
                    .font(.cassetteCellTitle)
            }
            if let message = vm.loadError?.localizedDescription {
                Text(message)
                    .font(.cassetteCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Button {
                Task { await vm.load(forceRefresh: true) }
            } label: {
                Text("Retry")
                    .font(.cassetteCellTitle)
                    .padding(.horizontal, CassetteSpacing.m)
                    .padding(.vertical, CassetteSpacing.s)
                    .background(Color.cassetteAccent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.standard, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(CassetteSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.12)) // warning state — not brand accent
        .clipShape(RoundedRectangle(cornerRadius: CassetteCornerRadius.standard, style: .continuous))
        .padding(.horizontal, CassetteSpacing.m)
    }

    private func skeletonScroll() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: CassetteSpacing.s) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: CassetteSpacing.xs) {
                        SkeletonBlock(width: 140, height: 140, cornerRadius: CassetteCornerRadius.standard)
                        SkeletonBlock(width: 110, height: 12)
                        SkeletonBlock(width: 80, height: 10)
                    }
                    .frame(width: 140)
                }
            }
            .padding(.horizontal, CassetteSpacing.m)
        }
        .allowsHitTesting(false)
    }

    private func emptyStateMessage(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.cassetteCaption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, CassetteSpacing.l)
            .padding(.horizontal, CassetteSpacing.m)
    }
}
