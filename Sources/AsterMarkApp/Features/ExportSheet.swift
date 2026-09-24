import AppKit
import AsterCore
import SwiftUI

/// ⌘E: choose outputs, scope and destination, then export in the background.
struct ExportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let session: AlbumSession

    @State private var selected: Set<UUID> = []
    @State private var scope: ExportScope = .album
    @State private var folder: URL?
    @AppStorage("export.subfolders") private var subfolders = true
    @State private var editing: Recipe?
    @State private var confirmWarnings: [String] = []

    var body: some View {
        let recipes = model.library.recipes
        VStack(alignment: .leading, spacing: 0) {
            Text("Export").font(.title2.weight(.semibold)).padding([.horizontal, .top], 20)

            Form {
                Section("Outputs") {
                    ForEach(recipes) { recipe in
                        HStack {
                            Toggle(isOn: Binding(
                                get: { selected.contains(recipe.id) },
                                set: { on in if on { selected.insert(recipe.id) } else { selected.remove(recipe.id) } }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recipe.name)
                                    Text(summary(recipe)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Edit…") { editing = recipe }
                                .buttonStyle(.borderless)
                        }
                        .contextMenu {
                            Button("Duplicate") { _ = try? model.library.duplicateRecipe(id: recipe.id); model.syncSets() }
                            Button("Delete", role: .destructive) {
                                try? model.library.removeRecipe(id: recipe.id)
                                selected.remove(recipe.id)
                                model.syncSets()
                            }
                            .disabled(recipes.count <= 1)
                        }
                    }
                    Button("New Output…") { editing = Recipe(name: "New Output") }
                        .buttonStyle(.borderless)
                }

                Section("Photos") {
                    Picker("Export", selection: $scope) {
                        ForEach(ExportScope.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    let photos = model.export.photos(for: scope, in: session)
                    let excluded = photos.count { session.editor.project.edit(for: $0.relativePath).isExcluded }
                    Text(countText(photos: photos.count - excluded, outputs: selected.count, excluded: excluded))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section("Destination") {
                    LabeledContent("Folder") {
                        HStack {
                            Text(folder?.path ?? "Not chosen")
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(folder == nil ? .secondary : .primary)
                            Button("Choose…") { model.export.chooseFolder { folder = $0 ?? folder } }
                        }
                    }
                    Toggle("Put each output in its own folder", isOn: $subfolders)
                    if session.needsReviewCount > 0 {
                        Label("\(session.needsReviewCount) photos are flagged for review.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export") { startExport(confirmed: false) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty || folder == nil)
            }
            .padding(20)
        }
        .frame(width: 560, height: 620)
        .onAppear {
            folder = model.export.savedFolder
            let saved = Set(session.editor.project.selectedRecipeIDs).intersection(recipes.map(\.id))
            selected = saved.isEmpty ? Set(recipes.map(\.id)) : saved
            if session.selection.count > 1 { scope = .selection }
        }
        .sheet(item: $editing) { recipe in
            RecipeEditor(recipe: recipe, presets: session.presets, sets: model.library.sets) { saved in
                if model.library.recipe(id: saved.id) == nil {
                    _ = try? model.library.addRecipe(saved)
                    selected.insert(saved.id)
                } else {
                    try? model.library.updateRecipe(saved)
                }
                model.syncSets()
            }
        }
        .alert("Export anyway?", isPresented: Binding(get: { !confirmWarnings.isEmpty }, set: { if !$0 { confirmWarnings = [] } })) {
            Button("Export") { startExport(confirmed: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmWarnings.joined(separator: "\n\n"))
        }
    }

    private func summary(_ recipe: Recipe) -> String {
        var parts: [String] = []
        switch recipe.settings.format {
        case .sameAsSource: parts.append("Same format")
        case let .jpeg(q): parts.append("JPEG \(Int(q * 100))")
        case .png: parts.append("PNG")
        case let .tiff(depth, _): parts.append("TIFF \(depth)-bit")
        }
        switch recipe.settings.render.sizeMode {
        case .original: parts.append(recipe.cropPresetID == nil ? "full size" : "full-size crop")
        case let .longEdge(px): parts.append("\(px) px long edge")
        case let .shortEdge(px): parts.append("\(px) px short edge")
        case let .exact(w, h): parts.append("\(w) × \(h)")
        case let .percentage(p): parts.append("\(Int(p))%")
        case let .megapixels(mp): parts.append("\(mp) MP")
        }
        if let preset = session.preset(id: recipe.cropPresetID) { parts.append(preset.name) }
        if recipe.settings.colorSpace == .sRGB { parts.append("sRGB") }
        if recipe.settings.metadata.removeLocation { parts.append("no GPS") }
        return parts.joined(separator: " · ")
    }

    private func countText(photos: Int, outputs: Int, excluded: Int) -> String {
        let files = photos * outputs
        var text = "\(photos) photo\(photos == 1 ? "" : "s") × \(outputs) output\(outputs == 1 ? "" : "s") = \(files) file\(files == 1 ? "" : "s")"
        if excluded > 0 { text += " (\(excluded) excluded)" }
        return text
    }

    private func startExport(confirmed: Bool) {
        guard let folder else { return }
        let recipes = model.library.recipes.filter { selected.contains($0.id) }
        let photos = model.export.photos(for: scope, in: session)
        let targets = model.export.targets(for: recipes, folder: folder, subfolders: subfolders)
        if !confirmed {
            let warnings = model.export.warnings(photos: photos, targets: targets, session: session)
            if !warnings.isEmpty { confirmWarnings = warnings; return }
        }
        session.editor.setSelectedRecipes(recipes.map(\.id))
        model.export.start(photos: photos, targets: targets, session: session, folderAccess: folder)
        dismiss()
    }
}

/// Edits one output recipe.
struct RecipeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var recipe: Recipe
    let presets: [SizePreset]
    let sets: [WatermarkSet]
    let onSave: (Recipe) -> Void

    init(recipe: Recipe, presets: [SizePreset], sets: [WatermarkSet], onSave: @escaping (Recipe) -> Void) {
        _recipe = State(initialValue: recipe)
        self.presets = presets
        self.sets = sets
        self.onSave = onSave
    }

    private enum FormatChoice: String, CaseIterable { case same, jpeg, png, tiff8, tiff16 }
    private enum SizeChoice: String, CaseIterable { case original, platform, longEdge, shortEdge, percentage }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $recipe.name)
                }
                Section("Format") {
                    Picker("Format", selection: formatChoice) {
                        Text("Same as original").tag(FormatChoice.same)
                        Text("JPEG").tag(FormatChoice.jpeg)
                        Text("PNG").tag(FormatChoice.png)
                        Text("TIFF 8-bit").tag(FormatChoice.tiff8)
                        Text("TIFF 16-bit").tag(FormatChoice.tiff16)
                    }
                    if case let .jpeg(quality) = recipe.settings.format {
                        LabeledContent("Quality") {
                            HStack {
                                Slider(value: Binding(get: { quality }, set: { recipe.settings.format = .jpeg(quality: $0) }), in: 0.5...1)
                                Text("\(Int(quality * 100))").monospacedDigit().frame(width: 30)
                            }
                        }
                        Toggle("Limit file size", isOn: Binding(
                            get: { recipe.settings.maxBytes != nil },
                            set: { recipe.settings.maxBytes = $0 ? 8_000_000 : nil }
                        ))
                        if let bytes = recipe.settings.maxBytes {
                            Stepper("Up to \(bytes / 1_000_000) MB", value: Binding(
                                get: { bytes / 1_000_000 }, set: { recipe.settings.maxBytes = max($0, 1) * 1_000_000 }
                            ), in: 1...50)
                        }
                    }
                    Picker("Colour", selection: $recipe.settings.colorSpace) {
                        Text("Keep original profile").tag(OutputColorSpace.source)
                        Text("sRGB (web & social)").tag(OutputColorSpace.sRGB)
                        Text("Display P3").tag(OutputColorSpace.displayP3)
                    }
                }
                Section("Crop & size") {
                    Picker("Crop", selection: $recipe.cropPresetID) {
                        Text("No crop").tag(String?.none)
                        ForEach(presets.filter { $0.aspect != nil }) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Size", selection: sizeChoice) {
                        Text("Original resolution").tag(SizeChoice.original)
                        Text("Platform size").tag(SizeChoice.platform)
                        Text("Long edge").tag(SizeChoice.longEdge)
                        Text("Short edge").tag(SizeChoice.shortEdge)
                        Text("Percentage").tag(SizeChoice.percentage)
                    }
                    sizeDetail
                    Picker("Sharpen for screen", selection: $recipe.settings.render.sharpening) {
                        Text("None").tag(OutputSharpening.none)
                        Text("Low").tag(OutputSharpening.low)
                        Text("Standard").tag(OutputSharpening.standard)
                        Text("High").tag(OutputSharpening.high)
                    }
                    Toggle("Allow enlarging", isOn: $recipe.settings.render.allowUpscale)
                }
                Section("Watermarks & destination") {
                    Picker("Layout", selection: $recipe.watermarkSetID) {
                        Text("Album layout").tag(UUID?.none)
                        ForEach(sets) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .help("Photos without their own layout use this saved layout for this output")
                    LabeledContent("Folder") {
                        HStack {
                            Text(recipe.destinationPath ?? "Export folder / \(recipe.name)")
                                .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                            if recipe.destinationBookmark != nil {
                                Button("Reset") { recipe.destinationBookmark = nil; recipe.destinationPath = nil }
                            }
                            Button("Choose…") { chooseFolder() }
                        }
                    }
                }
                Section("Metadata") {
                    Picker("Keep", selection: $recipe.settings.metadata.mode) {
                        Text("Everything").tag(MetadataPolicy.Mode.keepAll)
                        Text("Copyright & capture date only").tag(MetadataPolicy.Mode.copyrightOnly)
                        Text("Nothing").tag(MetadataPolicy.Mode.stripAll)
                    }
                    Toggle("Remove location", isOn: $recipe.settings.metadata.removeLocation)
                        .disabled(recipe.settings.metadata.mode != .keepAll)
                    Toggle("Remove camera serial numbers", isOn: $recipe.settings.metadata.removeCameraSerials)
                        .disabled(recipe.settings.metadata.mode != .keepAll)
                    Toggle("Add my name and copyright", isOn: $recipe.settings.metadata.embedProfile)
                        .disabled(recipe.settings.metadata.mode == .stripAll)
                }
                Section("File names") {
                    TextField("Pattern", text: $recipe.namingTemplate, prompt: Text("{name}_web"))
                    let template = NamingTemplate(recipe.namingTemplate)
                    let example = template.render(.init(name: "IMG_0042", sequence: 1, recipe: recipe.name, date: Date(),
                                                        width: 1080, height: 1440))
                    Text("Example: \(example).\(recipe.settings.format.fileExtension)")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(template.problems, id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
                    Text("Tokens: {name} {seq:3} {recipe} {date} {date:yyyy-MM-dd} {w} {h}")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("If a file exists", selection: $recipe.conflictPolicy) {
                        Text("Add a number").tag(ConflictPolicy.addSuffix)
                        Text("Replace it").tag(ConflictPolicy.overwrite)
                        Text("Skip").tag(ConflictPolicy.skip)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { onSave(recipe); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(recipe.name.trimmingCharacters(in: .whitespaces).isEmpty
                              || !NamingTemplate(recipe.namingTemplate).problems.filter { !$0.hasPrefix("Include") }.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 520, height: 680)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Always export “\(recipe.name)” to this folder."
        panel.begin { response in
            guard response == .OK, let url = panel.url, let data = try? Bookmarks.create(for: url) else { return }
            recipe.destinationBookmark = data
            recipe.destinationPath = url.path
        }
    }

    @ViewBuilder
    private var sizeDetail: some View {
        switch recipe.settings.render.sizeMode {
        case let .longEdge(px):
            Stepper("\(px) px", value: Binding(get: { px }, set: { recipe.settings.render.sizeMode = .longEdge($0) }),
                    in: 256...12000, step: 64)
        case let .shortEdge(px):
            Stepper("\(px) px", value: Binding(get: { px }, set: { recipe.settings.render.sizeMode = .shortEdge($0) }),
                    in: 256...12000, step: 64)
        case let .percentage(p):
            Stepper("\(Int(p))%", value: Binding(get: { p }, set: { recipe.settings.render.sizeMode = .percentage($0) }),
                    in: 5...100, step: 5)
        case let .exact(w, h):
            Text("\(w) × \(h) px (from the crop preset)").foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private var formatChoice: Binding<FormatChoice> {
        Binding(
            get: {
                switch recipe.settings.format {
                case .sameAsSource: .same
                case .jpeg: .jpeg
                case .png: .png
                case let .tiff(depth, _): depth > 8 ? .tiff16 : .tiff8
                }
            },
            set: { choice in
                switch choice {
                case .same: recipe.settings.format = .sameAsSource
                case .jpeg: recipe.settings.format = .jpeg(quality: 0.9)
                case .png: recipe.settings.format = .png
                case .tiff8: recipe.settings.format = .tiff(bitDepth: 8, compressed: true)
                case .tiff16: recipe.settings.format = .tiff(bitDepth: 16, compressed: true)
                }
            }
        )
    }

    private var sizeChoice: Binding<SizeChoice> {
        Binding(
            get: {
                switch recipe.settings.render.sizeMode {
                case .original: .original
                case .exact: .platform
                case .longEdge: .longEdge
                case .shortEdge: .shortEdge
                case .percentage, .megapixels: .percentage
                }
            },
            set: { choice in
                switch choice {
                case .original: recipe.settings.render.sizeMode = .original
                case .platform:
                    let preset = presets.first { $0.id == recipe.cropPresetID }
                    if let w = preset?.pixelWidth, let h = preset?.pixelHeight {
                        recipe.settings.render.sizeMode = .exact(width: w, height: h)
                    } else {
                        recipe.settings.render.sizeMode = .longEdge(preset?.longEdge ?? 2048)
                    }
                case .longEdge: recipe.settings.render.sizeMode = .longEdge(2048)
                case .shortEdge: recipe.settings.render.sizeMode = .shortEdge(1080)
                case .percentage: recipe.settings.render.sizeMode = .percentage(50)
                }
            }
        )
    }
}

/// Shown after an export with failures (or when cancelled).
struct ExportReportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let report: ExportReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(report.cancelled ? "Export cancelled" : "Some photos couldn't be exported")
                .font(.title3.weight(.semibold))
            Text("\(report.written.count) saved · \(report.failures.count) failed · \(report.skipped) skipped")
                .foregroundStyle(.secondary)
            if !report.failures.isEmpty {
                List(report.failures) { failure in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(failure.photo) — \(failure.recipe)")
                        Text(failure.message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 160)
            }
            HStack {
                Button("Show in Finder") { model.export.revealLastExport() }
                    .disabled(report.written.isEmpty)
                Spacer()
                if !report.failures.isEmpty, let session = model.session {
                    Button("Retry Failed") { model.export.retryFailed(session: session) }
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
