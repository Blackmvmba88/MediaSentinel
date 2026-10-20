import Cocoa
import SwiftUI
import CoreAudio
import Darwin

struct Source: Identifiable {
    let id: Int32
    let name: String
    let detail: String
    let app: NSRunningApplication?
    let identity: String
}

func processIdentity(_ pid: Int32) -> String? {
    var info = proc_bsdinfo()
    guard pid > 1, pid != getpid(),
          proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
          info.pbi_uid == getuid() else { return nil }
    return "\(info.pbi_start_tvsec):\(info.pbi_start_tvusec)"
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
            found[owner] = Source(id: owner, name: app?.localizedName ?? URL(fileURLWithPath: executable).lastPathComponent, detail: "PID \(owner) · salida de audio activa", app: app, identity: processIdentity(owner) ?? "")
        }
        sources = found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    func close(_ source: Source, force: Bool) {
        refresh()
        guard !source.identity.isEmpty, processIdentity(source.id) == source.identity,
              sources.contains(where: { $0.id == source.id && $0.identity == source.identity }) else {
            message = "La fuente ya terminó, cambió o no pertenece a tu usuario. Actualiza la lista."; return
        }
        if source.app == nil {
            let result = kill(source.id, force ? SIGKILL : SIGTERM)
            message = result == 0 ? "Solicitud de detener audio enviada a \(source.name)." : "No se pudo detener \(source.name): \(String(cString: strerror(errno)))."
            refresh()
            return
        }
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
    @State private var forcePending = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                if let icon = NSImage(named: "AppIcon") {
                    Image(nsImage: icon).resizable().frame(width: 56, height: 56)
                } else {
                    Image(systemName: "waveform.circle.fill").font(.system(size: 42)).foregroundStyle(.purple)
                }
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
                                    Button("Forzar…", role: .destructive) { forcePending = true; pending = source }
                                } else {
                                    Button("Detener audio", systemImage: "stop.fill") { forcePending = false; pending = source }
                                        .buttonStyle(.borderedProminent).tint(.purple)
                                    Button("Forzar…", role: .destructive) { forcePending = true; pending = source }
                                }
                            }.padding().background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            Text(monitor.message).font(.callout).foregroundStyle(.secondary)
            Divider()
            Text("Detener audio cierra el proceso de reproducción, incluida la vista previa de Quick Look. Cerrar termina toda la aplicación. Forzar puede perder cambios sin guardar. La salida activa puede incluir silencio; no se identifican pestañas ni videos mudos.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth: 740, minHeight: 420)
        .alert("¿\(forcePending ? "Forzar salida" : "Detener audio") de \(pending?.name ?? "la aplicación")?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Cancelar", role: .cancel) { pending = nil }
            Button(forcePending ? "Forzar salida" : "Detener audio", role: .destructive) { if let source = pending { monitor.close(source, force: forcePending) }; pending = nil }
        } message: { Text(pending?.app == nil ? "Se cerrará el proceso de reproducción seleccionado. En Quick Look se cerrará la vista previa; el archivo original se conserva." : "Se cerrará toda la aplicación y podrías perder cambios sin guardar.") }
    }
}

if CommandLine.arguments.contains("--self-test-stop") {
    let player = Process()
    player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
    player.arguments = ["-r", "0.1", "/System/Library/Sounds/Glass.aiff"]
    do {
        try player.run()
        defer { if player.isRunning { player.terminate() } }
        Thread.sleep(forTimeInterval: 0.4)
        let monitor = Monitor()
        guard let source = monitor.sources.first(where: { $0.id == player.processIdentifier }) else { print("FAIL: reproducción de prueba no detectada"); exit(1) }
        monitor.close(source, force: false)
        Thread.sleep(forTimeInterval: 0.3)
        guard !player.isRunning else { print("FAIL: el proceso continúa activo"); exit(1) }
        print("PASS: reproducción detectada y detenida mediante SIGTERM")
    } catch { print("FAIL: \(error)"); exit(1) }
} else if CommandLine.arguments.contains("--diagnose") {
    let monitor = Monitor()
    print("Core Audio: \(monitor.message.isEmpty ? "OK" : monitor.message)")
    for source in monitor.sources { print("\(source.name) | \(source.detail)") }
} else {
    let app = NSApplication.shared
    if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: iconURL) {
        app.applicationIconImage = icon
    }
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
