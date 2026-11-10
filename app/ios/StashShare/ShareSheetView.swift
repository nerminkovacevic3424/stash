import SwiftUI

private let accent = Color(red: 0x5B / 255, green: 0x5B / 255, blue: 0xD6 / 255)

// Same palette as lib/ui/theme.dart.
private let folderColors: [Color] = [
    Color(red: 0.36, green: 0.36, blue: 0.84), Color(red: 0.90, green: 0.28, blue: 0.30),
    Color(red: 0.97, green: 0.42, blue: 0.08), Color(red: 1.00, green: 0.70, blue: 0.14),
    Color(red: 0.19, green: 0.64, blue: 0.42), Color(red: 0.07, green: 0.65, blue: 0.58),
    Color(red: 0.00, green: 0.56, blue: 1.00), Color(red: 0.84, green: 0.25, blue: 0.62),
]

/// The bottom sheet shown over Instagram/TikTok. The folder chip is the focus;
/// Save is the single primary action.
struct ShareSheetView: View {
    @ObservedObject var model: ShareModel
    @State private var pickerOpen = false
    @State private var noteOpen = false
    @State private var creating = false
    @State private var note = ""
    @State private var newFolder = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { model.close() }

            VStack(alignment: .leading, spacing: 0) {
                Capsule()
                    .fill(Color(.systemGray4))
                    .frame(width: 36, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 16)
            .frame(maxWidth: 560)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(.systemBackground))
                    .ignoresSafeArea(edges: .bottom)
            )
            .animation(.easeOut(duration: 0.18), value: pickerOpen)
            .animation(.easeOut(duration: 0.18), value: noteOpen)
        }
        .accentColor(accent)
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .saved:
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundColor(accent)
                Text("\(model.confirmation) ✓")
                    .font(.title3.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        case .invalid:
            message(
                title: "Nothing to save here",
                body: "Stash saves Instagram and TikTok posts. Share a post, reel or video link to file it.")
        case .setupNeeded:
            message(
                title: "Finish setup",
                body: "The App Group is not configured for this extension. See the README, then open Stash once.")
        case .ready, .saving:
            if let link = model.link {
                form(link: link)
            } else {
                Color.clear.frame(height: 120)
            }
        }
    }

    private func message(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.bold))
            Text(body).font(.subheadline).foregroundColor(.secondary)
            Button("Close") { model.close() }
                .buttonStyle(PrimaryButtonStyle(tonal: true))
                .padding(.top, 12)
        }
    }

    private func form(link: LinkInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            preview(link: link)

            if model.duplicate != nil {
                HStack(spacing: 10) {
                    Image(systemName: "bookmark.fill").font(.footnote)
                    Text("Already saved in \(model.duplicateFolderName). Pick another folder to move it.")
                        .font(.footnote)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.18)))
                .padding(.top, 14)
            }

            folderChip.padding(.top, 18)
            if pickerOpen { picker.padding(.top, 12) }

            if noteOpen {
                TextField("Why are you saving this?", text: $note)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                    .padding(.top, 12)
            } else {
                Button {
                    noteOpen = true
                } label: {
                    Label("Add note", systemImage: "plus").font(.subheadline)
                }
                .foregroundColor(.secondary)
                .padding(.top, 12)
            }

            Button {
                model.save(note: note)
            } label: {
                if model.stage == .saving {
                    ProgressView().tint(.white)
                } else {
                    Text(saveLabel)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!model.hasChoice || model.stage != .ready)
            .padding(.top, 14)
        }
    }

    private var saveLabel: String {
        if model.duplicate == nil { return "Save" }
        return model.duplicateInPlace ? "Keep in \(model.choiceName)" : "Move to \(model.choiceName)"
    }

    private func preview(link: LinkInfo) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Color(.secondarySystemBackground)
                if let thumb = model.meta?.thumbnailUrl, let url = URL(string: thumb) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.clear
                    }
                } else {
                    Image(systemName: "play.circle").foregroundColor(.secondary)
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: link.platform == "instagram" ? "camera.fill" : "music.note")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(link.platform == "instagram" ? Color.pink : Color.black))
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    .offset(x: 4, y: 4)
                    .accessibilityLabel(link.platform == "instagram" ? "Instagram" : "TikTok")
            }

            VStack(alignment: .leading, spacing: 5) {
                if let author = model.author {
                    Text("@\(author)").font(.subheadline.weight(.bold)).lineLimit(1)
                } else if model.metaLoading {
                    skeleton(width: 110)
                } else {
                    Text(link.platform == "instagram" ? "Instagram post" : "TikTok post").font(.subheadline.weight(.bold))
                }
                if let caption = model.aiDescription ?? model.meta?.caption, !caption.isEmpty {
                    Text(caption).font(.footnote).foregroundColor(.secondary).lineLimit(2)
                } else if model.metaLoading {
                    skeleton(width: 200)
                } else {
                    Text(link.url.replacingOccurrences(of: "https://", with: ""))
                        .font(.footnote).foregroundColor(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func skeleton(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6).fill(Color(.systemGray5)).frame(width: width, height: 12)
    }

    private var chipLabel: String {
        if model.suggesting { return "Finding the best folder…" }
        if model.duplicate != nil && !model.userPicked { return "Saved in" }
        if model.userPicked { return model.newName != nil ? "New folder" : "Save to" }
        if model.newName != nil { return "Suggested new folder" }
        if case .existing(_, let source)? = model.suggestion {
            switch source {
            case .lastUsed: return "Last used"
            case .unsorted: return "Save to"
            default: return "Suggested"
            }
        }
        return "Suggested"
    }

    private var folderChip: some View {
        Button {
            pickerOpen.toggle()
        } label: {
            HStack(spacing: 14) {
                if model.suggesting {
                    ProgressView().frame(width: 48, height: 48)
                } else {
                    Text(model.selected?.emoji ?? model.newEmoji)
                        .font(.system(size: 24))
                        .frame(width: 48, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(folderColors[(model.selected?.color ?? 0) % folderColors.count].opacity(0.18)))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(chipLabel).font(.caption).foregroundColor(.secondary)
                    if model.suggesting {
                        RoundedRectangle(cornerRadius: 6).fill(Color(.systemGray5)).frame(width: 120, height: 14)
                            .padding(.vertical, 6)
                    } else {
                        Text(model.choiceName).font(.title3.weight(.bold)).foregroundColor(.primary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Text("Change").font(.subheadline.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .rotationEffect(.degrees(pickerOpen ? 180 : 0))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(accent.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .foregroundColor(accent)
    }

    private var picker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.folders) { f in
                    let isSelected = model.newName == nil && model.selected?.id == f.id
                    Button {
                        model.pick(f)
                        pickerOpen = false
                    } label: {
                        Text("\(f.emoji)  \(f.name)")
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected ? accent.opacity(0.2) : Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                }
                if creating {
                    HStack(spacing: 4) {
                        TextField("Folder name", text: $newFolder)
                            .submitLabel(.done)
                            .onSubmit(createFolder)
                            .frame(width: 150)
                        Button(action: createFolder) {
                            Image(systemName: "checkmark").font(.subheadline.weight(.bold))
                        }
                        .accessibilityLabel("Use this folder")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                } else {
                    Button {
                        creating = true
                    } label: {
                        Label("New folder", systemImage: "plus")
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func createFolder() {
        guard !newFolder.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.pickNew(newFolder)
        newFolder = ""
        creating = false
        pickerOpen = false
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    var tonal = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundColor(tonal ? accent : .white)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tonal ? accent.opacity(0.14) : accent)
                    .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4))
    }
}
