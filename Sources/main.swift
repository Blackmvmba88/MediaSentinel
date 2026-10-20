import Cocoa
import SwiftUI
import CoreAudio
import Darwin

struct Source: Identifiable {
    let id: Int32
    let name: String
    let detail: String
    let app: NSRunningApplication?
}

func scalar<T: FixedWidthInteger>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T? {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
    return value
}

final class Monitor: ObservableObject {
    @Published var sources: [Source] = []
    @Published var message = ""
    private var timer: Timer?
    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func refresh() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            message = "No se pudo consultar Core Audio."; return
        }
        guard size > 0 else { sources = []; return }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = objects.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, bytes.baseAddress!)
        }
        guard status == noErr else { message = "No se pudo leer la lista de audio (\(status))."; return }
        var found: [Int32: Source] = [:]
        for object in objects {
            guard scalar(object, kAudioProcessPropertyIsRunningOutput, UInt32(0)) == 1,
                  let pid = scalar(object, kAudioProcessPropertyPID, Int32(0)), pid > 1, pid != getpid() else { continue }
            var cursor = pid
            var app: NSRunningApplication?
            for _ in 0..<12 {
                if let candidate = NSRunningApplication(processIdentifier: cursor), candidate.activationPolicy == .regular {
                    app = candidate; break
                }
                var info = proc_bsdinfo()
                let count = proc_pidinfo(cursor, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
                guard count > 0, info.pbi_ppid > 1, Int32(info.pbi_ppid) != cursor else { break }
                cursor = Int32(info.pbi_ppid)
            }
            let owner = app?.processIdentifier ?? pid
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            proc_pidpath(pid, &path, UInt32(path.count))
            let executable = String(cString: path)
            found[owner] = Source(id: owner, name: app?.localizedName ?? URL(fileURLWithPath: executable).lastPathComponent, detail: "PID \(owner) · salida de audio activa", app: app)
        }
        sources = found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    func close(_ source: Source, force: Bool) {
        guard let app = source.app, !app.isTerminated else {
            message = "Este proceso no es una app visible. PID \(source.id); revísalo en Monitor de Actividad."; return
        }
        let ok = force ? app.forceTerminate() : app.terminate()
        message = ok ? "Solicitud enviada a \(source.name)." : "\(source.name) no aceptó el cierre. Puedes intentar forzar salida."
        refresh()
    }
}

struct Panel: View {
    @StateObject private var monitor = Monitor()
    @State private var pending: Source?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "waveform.circle.fill").font(.system(size: 42)).foregroundStyle(.purple)
                VStack(alignment: .leading) {
                    Text("Media Sentinel").font(.largeTitle.bold())
                    Text("Encuentra y cierra el origen del audio").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Actualizar") { monitor.refresh() }
            }
            Text("\(monitor.sources.count) aplicaciones con salida activa").font(.headline)
            if monitor.sources.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "speaker.slash").font(.system(size: 44))
                    Text("Sin salida de audio detectada").font(.title2)
                    Text("La lista se actualiza automáticamente cada 1.5 segundos.")
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(monitor.sources) { source in
                            HStack(spacing: 12) {
                                if let icon = source.app?.icon { Image(nsImage: icon).resizable().frame(width: 40, height: 40) }
                                VStack(alignment: .leading) {
                                    Text(source.name).font(.headline)
                                    Text(source.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let app = source.app {
                                    Button("Ver") { app.activate(options: [.activateAllWindows]) }
                                    Button("Cerrar") { monitor.close(source, force: false) }
                                    Button("Forzar…", role: .destructive) { pending = source }
                                } else {
                                    Button("Monitor de Actividad") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) }
                                }
                            }.padding().background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            Text(monitor.message).font(.callout).foregroundStyle(.secondary)
            Divider()
            Text("Cerrar termina toda la aplicación, incluidas sus pestañas. Usa Ver para pausar desde el reproductor. Core Audio indica actividad de salida: puede incluir silencio y no detecta videos mudos ni identifica canciones o pestañas.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth: 740, minHeight: 420)
        .alert("¿Forzar salida de \(pending?.name ?? "la aplicación")?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Cancelar", role: .cancel) { pending = nil }
            Button("Forzar salida", role: .destructive) { if let source = pending { monitor.close(source, force: true) }; pending = nil }
        } message: { Text("Se cerrará toda la aplicación y podrías perder cambios sin guardar.") }
    }
}

if CommandLine.arguments.contains("--diagnose") {
    let monitor = Monitor()
    print("Core Audio: \(monitor.message.isEmpty ? "OK" : monitor.message)")
    for source in monitor.sources { print("\(source.name) | \(source.detail)") }
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 500), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.title = "Media Sentinel"
    window.contentView = NSHostingView(rootView: Panel())
    window.center()
    window.makeKeyAndOrderFront(nil)
    let menu = NSMenu()
    let item = NSMenuItem()
    menu.addItem(item)
    let submenu = NSMenu()
    submenu.addItem(withTitle: "Salir de Media Sentinel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    item.submenu = submenu
    app.mainMenu = menu
    app.activate(ignoringOtherApps: true)
    app.run()
}
