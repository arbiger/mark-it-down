import SwiftUI

struct ContentView: View {
    @Bindable var state: AppState
    let dropDelegate: ItemDropDelegate
    let onPickFolder: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onShowInFinder: () -> Void
    let onConvertAnother: () -> Void
    let onRecheckPython: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 520, height: 640)
    }

    private var header: some View {
        Text("Mark-It-Down")
            .font(.title)
            .bold()
    }

    @ViewBuilder
    private var content: some View {
        switch state.mode {
        case .empty:
            dropZone(message: "Drop a folder here\nor click to pick")
        case .noPython:
            noPythonView
        case .installing(let progress):
            installingView(progress: progress)
        case .installFailed(let message):
            installFailedView(message: message)
        case .preview:
            previewList
        case .converting:
            convertingList
        case .done(let succeeded, let failed):
            doneView(succeeded: succeeded, failed: failed)
        }
    }

    private var noPythonView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Python 3 not found").font(.headline)
            Text("Install via Homebrew (`brew install python`) or python.org, then click Recheck.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Recheck") { onRecheckPython() }
        }
    }

    private func installingView(progress: String) -> some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Installing markitdown…").font(.callout)
            Text(progress).font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }
    }

    private func installFailedView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Install failed").font(.headline).foregroundStyle(.red)
            Text(message).font(.caption).foregroundStyle(.secondary)
            Button("Recheck") { onRecheckPython() }
        }
    }

    private func doneView(succeeded: Int, failed: Int) -> some View {
        VStack(spacing: 8) {
            Text("Done").font(.title2).bold()
            Text("\(succeeded) succeeded · \(failed) failed")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            switch state.mode {
            case .empty, .noPython, .installing, .installFailed:
                EmptyView()
            case .preview:
                Button("Change folder") { onPickFolder() }
                Spacer()
                Button("Start") { onStart() }.keyboardShortcut(.defaultAction)
            case .converting:
                Spacer()
                Button("Stop") { onStop() }
            case .done:
                Button("Show in Finder") { onShowInFinder() }
                Spacer()
                Button("Convert another folder") { onConvertAnother() }
            }
        }
    }

    private func dropZone(message: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 36))
                Text(message).multilineTextAlignment(.center)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .onTapGesture { onPickFolder() }
        .onDrop(of: [.fileURL], delegate: dropDelegate)
    }

    @ViewBuilder
    private var previewList: some View {
        if let job = state.job {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(job.files.count) files found").font(.callout).bold()
                List(job.files) { file in
                    HStack {
                        Text(file.sourceURL.lastPathComponent).lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                        Text(file.outputURL.lastPathComponent).lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 220)
            }
        }
    }

    @ViewBuilder
    private var convertingList: some View {
        if let job = state.job {
            let total = job.files.count
            let done = job.files.filter {
                if case .done = $0.status { return true } else { return false }
            }.count
            let failed = job.files.filter {
                if case .failed = $0.status { return true } else { return false }
            }.count
            let completed = done + failed
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: Double(completed), total: Double(max(total, 1)))
                Text("\(completed) / \(total)").font(.caption).foregroundStyle(.secondary)
                List(job.files) { file in
                    HStack {
                        statusIcon(for: file.status)
                        Text(file.sourceURL.lastPathComponent).lineLimit(1)
                        Spacer()
                        Text(file.outputURL.lastPathComponent).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 260)
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for status: ConversionStatus) -> some View {
        switch status {
        case .pending: Image(systemName: "clock").foregroundStyle(.secondary)
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
