//
//  MPVPlayerBackend.swift
//  FlowVision
//

import Cocoa
import Darwin
import OpenGL.GL
import OpenGL.GL3

private let mpvFormatFlag: Int32 = 3
private let mpvFormatDouble: Int32 = 5

private let mpvRenderParamAPIType: Int32 = 1
private let mpvRenderParamOpenGLInitParams: Int32 = 2
private let mpvRenderParamOpenGLFBO: Int32 = 3
private let mpvRenderParamFlipY: Int32 = 4
private let mpvRenderParamDepth: Int32 = 5
private let mpvRenderParamAdvancedControl: Int32 = 10
private let mpvRenderUpdateFrame: UInt64 = 1

private struct MPVOpenGLInitParams {
    var getProcAddress: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?)?
    var getProcAddressCtx: UnsafeMutableRawPointer?
}

private struct MPVOpenGLFBO {
    var fbo: Int32
    var w: Int32
    var h: Int32
    var internalFormat: Int32
}

private struct MPVRenderParam {
    var type: Int32 = 0
    var data: UnsafeMutableRawPointer?
}

private final class LibMPV {
    typealias MPVCreate = @convention(c) () -> OpaquePointer?
    typealias MPVInitialize = @convention(c) (OpaquePointer?) -> Int32
    typealias MPVTerminateDestroy = @convention(c) (OpaquePointer?) -> Void
    typealias MPVCommand = @convention(c) (OpaquePointer?, UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> Int32
    typealias MPVSetOptionString = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32
    typealias MPVSetProperty = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int32, UnsafeMutableRawPointer?) -> Int32
    typealias MPVGetProperty = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int32, UnsafeMutableRawPointer?) -> Int32
    typealias MPVRenderContextCreate = @convention(c) (UnsafeMutablePointer<OpaquePointer?>?, OpaquePointer?, UnsafeMutableRawPointer?) -> Int32
    typealias MPVRenderContextSetUpdateCallback = @convention(c) (OpaquePointer?, (@convention(c) (UnsafeMutableRawPointer?) -> Void)?, UnsafeMutableRawPointer?) -> Void
    typealias MPVRenderContextUpdate = @convention(c) (OpaquePointer?) -> UInt64
    typealias MPVRenderContextRender = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Int32
    typealias MPVRenderContextReportSwap = @convention(c) (OpaquePointer?) -> Void
    typealias MPVRenderContextFree = @convention(c) (OpaquePointer?) -> Void

    let create: MPVCreate
    let initialize: MPVInitialize
    let terminateDestroy: MPVTerminateDestroy
    let command: MPVCommand
    let setOptionString: MPVSetOptionString
    let setProperty: MPVSetProperty
    let getProperty: MPVGetProperty
    let renderContextCreate: MPVRenderContextCreate
    let renderContextSetUpdateCallback: MPVRenderContextSetUpdateCallback
    let renderContextUpdate: MPVRenderContextUpdate
    let renderContextRender: MPVRenderContextRender
    let renderContextReportSwap: MPVRenderContextReportSwap
    let renderContextFree: MPVRenderContextFree

    private let handle: UnsafeMutableRawPointer

    private static let sharedLock = NSLock()
    private static var cachedShared: LibMPV?
    private static var didAttemptLoad = false

    static var shared: LibMPV? {
        sharedLock.lock()
        defer { sharedLock.unlock() }
        if !didAttemptLoad {
            cachedShared = LibMPV()
            didAttemptLoad = true
        }
        return cachedShared
    }

    /// A failed first lookup must not be permanent: the optional runtime can
    /// be downloaded while FlowVision is still running.
    static func reload() {
        sharedLock.lock()
        cachedShared = nil
        didAttemptLoad = false
        sharedLock.unlock()
    }

    private init?() {
        guard let loadedHandle = Self.openLibrary() else {
            log("libmpv not found. Bundle IINA's mpv runtime in Contents/Frameworks to enable mpv playback.", level: .warn)
            return nil
        }
        handle = loadedHandle

        guard
            let create: MPVCreate = Self.load("mpv_create", from: loadedHandle),
            let initialize: MPVInitialize = Self.load("mpv_initialize", from: loadedHandle),
            let terminateDestroy: MPVTerminateDestroy = Self.load("mpv_terminate_destroy", from: loadedHandle),
            let command: MPVCommand = Self.load("mpv_command", from: loadedHandle),
            let setOptionString: MPVSetOptionString = Self.load("mpv_set_option_string", from: loadedHandle),
            let setProperty: MPVSetProperty = Self.load("mpv_set_property", from: loadedHandle),
            let getProperty: MPVGetProperty = Self.load("mpv_get_property", from: loadedHandle),
            let renderContextCreate: MPVRenderContextCreate = Self.load("mpv_render_context_create", from: loadedHandle),
            let renderContextSetUpdateCallback: MPVRenderContextSetUpdateCallback = Self.load("mpv_render_context_set_update_callback", from: loadedHandle),
            let renderContextUpdate: MPVRenderContextUpdate = Self.load("mpv_render_context_update", from: loadedHandle),
            let renderContextRender: MPVRenderContextRender = Self.load("mpv_render_context_render", from: loadedHandle),
            let renderContextReportSwap: MPVRenderContextReportSwap = Self.load("mpv_render_context_report_swap", from: loadedHandle),
            let renderContextFree: MPVRenderContextFree = Self.load("mpv_render_context_free", from: loadedHandle)
        else {
            dlclose(handle)
            log("libmpv is present but render API symbols are missing.", level: .error)
            return nil
        }

        self.create = create
        self.initialize = initialize
        self.terminateDestroy = terminateDestroy
        self.command = command
        self.setOptionString = setOptionString
        self.setProperty = setProperty
        self.getProperty = getProperty
        self.renderContextCreate = renderContextCreate
        self.renderContextSetUpdateCallback = renderContextSetUpdateCallback
        self.renderContextUpdate = renderContextUpdate
        self.renderContextRender = renderContextRender
        self.renderContextReportSwap = renderContextReportSwap
        self.renderContextFree = renderContextFree
    }

    deinit {
        dlclose(handle)
    }

    private static func load<T>(_ symbol: String, from handle: UnsafeMutableRawPointer) -> T? {
        guard let pointer = dlsym(handle, symbol) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    private static func openLibrary() -> UnsafeMutableRawPointer? {
        // Prefer a runtime bundled with FlowVision. It is the only source that
        // is guaranteed to have been assembled and tested as one dependency
        // set.
        if let bundledDir = Bundle.main.privateFrameworksPath,
           let handle = openLibrary(in: bundledDir) {
            return handle
        }

        // An optional, FlowVision-managed runtime is installed after explicit
        // user consent and verified before this path becomes active.
        if let managedDir = MPVRuntimeManager.shared.activeFrameworksDirectory,
           let handle = openLibrary(in: managedDir) {
            return handle
        }

        // Used by the local repair acceptance test so it cannot accidentally
        // pass by finding a developer's Homebrew or IINA installation.
        if ProcessInfo.processInfo.environment["FLOWVISION_MPV_DISABLE_EXTERNAL_FALLBACKS"] == "1" {
            return nil
        }

        // A package-managed libmpv is a coherent keg and is safer than loading
        // arbitrary dylibs from another app bundle. In particular, a partially
        // updated IINA bundle can contain incompatible libmpv/libplacebo ABIs.
        for path in [
            "@rpath/libmpv.2.dylib",
            "@rpath/libmpv.dylib",
            "/opt/homebrew/lib/libmpv.2.dylib",
            "/opt/homebrew/lib/libmpv.dylib",
            "/usr/local/lib/libmpv.2.dylib",
            "/usr/local/lib/libmpv.dylib",
            "libmpv.2.dylib",
            "libmpv.dylib"
        ] {
            if let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) {
                return handle
            }
        }

        // Keep IINA as the final compatibility fallback only. openLibrary(in:)
        // returns nil when its dependency set cannot be resolved, allowing the
        // caller to show the existing external-player affordance safely.
        if let handle = openLibrary(in: "/Applications/IINA.app/Contents/Frameworks") {
            return handle
        }
        return nil
    }

    private static func openLibrary(in dir: String) -> UnsafeMutableRawPointer? {
        let libmpv = URL(fileURLWithPath: dir).appendingPathComponent("libmpv.2.dylib").path
        guard FileManager.default.fileExists(atPath: libmpv) else { return nil }

        let dylibs = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter {
                $0.hasSuffix(".dylib")
                    && $0 != "libmpv.2.dylib"
                    // IINA may bundle an older Swift runtime next to mpv.
                    // Loading it into FlowVision duplicates the system Swift
                    // classes and can make mpv initialization fail.
                    && !$0.hasPrefix("libswift_")
            }

        for _ in 0..<4 {
            for name in dylibs {
                // Keep mpv's FFmpeg dependency graph private. FlowVision also
                // embeds FFmpegKit; exporting either set globally lets the
                // other bind to an ABI-incompatible symbol on the next launch.
                _ = dlopen(URL(fileURLWithPath: dir).appendingPathComponent(name).path, RTLD_NOW | RTLD_LOCAL)
            }
        }
        // RTLD_FIRST makes lookups prefer libmpv and its own dependency graph
        // over same-named symbols already present in the application process.
        return dlopen(libmpv, RTLD_NOW | RTLD_LOCAL | RTLD_FIRST)
    }
}

final class FlowMPVVideoView: NSView {
    fileprivate lazy var videoLayer = MPVRenderLayer()
    fileprivate weak var backend: MPVPlayerBackend?
    private var displayLink: CVDisplayLink?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = videoLayer
        videoLayer.owner = self
        autoresizingMask = [.width, .height]
        wantsBestResolutionOpenGLSurface = true
        wantsExtendedDynamicRangeOpenGLSurface = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer = videoLayer
        videoLayer.owner = self
    }

    override var isOpaque: Bool { true }

    func attach(_ backend: MPVPlayerBackend) {
        self.backend = backend
        videoLayer.backend = backend
        backend.initializeRendering(with: videoLayer)
        startDisplayLink()
        videoLayer.update(force: true)
    }

    func detach() {
        stopDisplayLink()
        backend = nil
        videoLayer.backend = nil
    }

    private func startDisplayLink() {
        if displayLink == nil {
            CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        }
        guard let displayLink, !CVDisplayLinkIsRunning(displayLink) else { return }
        CVDisplayLinkSetOutputCallback(displayLink, flowMPVDisplayLinkCallback, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(displayLink)
    }

    private func stopDisplayLink() {
        if let displayLink, CVDisplayLinkIsRunning(displayLink) {
            CVDisplayLinkStop(displayLink)
        }
    }

    fileprivate func reportSwap() {
        backend?.reportSwap()
    }
}

private final class MPVRenderLayer: CAOpenGLLayer {
    weak var owner: FlowMPVVideoView?
    weak var backend: MPVPlayerBackend?

    private let cglPixelFormat: CGLPixelFormatObj
    fileprivate let cglContext: CGLContextObj
    private let displayLock = NSRecursiveLock()
    private let renderQueue = DispatchQueue(label: "netdcy.FlowVision.mpv.render", qos: .userInteractive)
    private var needsFlip = false
    private var forceDraw = true
    private var fbo: GLint = 1
    private var bufferDepth: GLint = 8

    override init() {
        cglPixelFormat = MPVRenderLayer.createPixelFormat()
        cglContext = MPVRenderLayer.createContext(cglPixelFormat)
        super.init()
        autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        backgroundColor = NSColor.black.cgColor
        isAsynchronous = false
    }

    override init(layer: Any) {
        let previous = layer as! MPVRenderLayer
        cglPixelFormat = previous.cglPixelFormat
        cglContext = previous.cglContext
        backend = previous.backend
        owner = previous.owner
        super.init(layer: layer)
        autoresizingMask = previous.autoresizingMask
        backgroundColor = previous.backgroundColor
    }

    required init?(coder: NSCoder) {
        cglPixelFormat = MPVRenderLayer.createPixelFormat()
        cglContext = MPVRenderLayer.createContext(cglPixelFormat)
        super.init(coder: coder)
    }

    override func canDraw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj, forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) -> Bool {
        forceDraw || backend?.shouldRenderUpdateFrame() == true
    }

    override func draw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj, forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) {
        needsFlip = false
        forceDraw = false

        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

        guard let backend else {
            glClearColor(0, 0, 0, 1)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
            glFlush()
            return
        }

        var currentFBO: GLint = 0
        glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &currentFBO)
        if currentFBO != 0 { fbo = currentFBO }

        var viewport: [GLint] = [0, 0, 0, 0]
        glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)

        var flip: CInt = 1
        var fboData = MPVOpenGLFBO(
            fbo: Int32(fbo),
            w: Int32(viewport[2]),
            h: Int32(viewport[3]),
            internalFormat: 0
        )
        var depth = bufferDepth

        withUnsafeMutablePointer(to: &fboData) { fboPointer in
            withUnsafeMutablePointer(to: &flip) { flipPointer in
                withUnsafeMutablePointer(to: &depth) { depthPointer in
                    var params = [
                        MPVRenderParam(type: mpvRenderParamOpenGLFBO, data: UnsafeMutableRawPointer(fboPointer)),
                        MPVRenderParam(type: mpvRenderParamFlipY, data: UnsafeMutableRawPointer(flipPointer)),
                        MPVRenderParam(type: mpvRenderParamDepth, data: UnsafeMutableRawPointer(depthPointer)),
                        MPVRenderParam()
                    ]
                    backend.render(params: &params)
                }
            }
        }
        glFlush()
    }

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        cglPixelFormat
    }

    override func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj {
        cglContext
    }

    func update(force: Bool = false) {
        renderQueue.async { [weak self] in
            guard let self else { return }
            if force { self.forceDraw = true }
            self.needsFlip = true
            self.displayLock.lock()
            CATransaction.begin()
            self.display()
            CATransaction.commit()
            CATransaction.flush()
            self.displayLock.unlock()
        }
    }

    private static func createPixelFormat() -> CGLPixelFormatObj {
        let attrs: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
            kCGLPFAAccelerated,
            kCGLPFADoubleBuffer,
            kCGLPFAAllowOfflineRenderers,
            kCGLPFASupportsAutomaticGraphicsSwitching,
            _CGLPixelFormatAttribute(rawValue: 0)
        ]
        var pixelFormat: CGLPixelFormatObj?
        var pixelCount: GLint = 0
        CGLChoosePixelFormat(attrs, &pixelFormat, &pixelCount)
        if let pixelFormat { return pixelFormat }

        let fallback: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(kCGLOGLPVersion_Legacy.rawValue),
            kCGLPFAAccelerated,
            kCGLPFADoubleBuffer,
            _CGLPixelFormatAttribute(rawValue: 0)
        ]
        CGLChoosePixelFormat(fallback, &pixelFormat, &pixelCount)
        return pixelFormat!
    }

    private static func createContext(_ pixelFormat: CGLPixelFormatObj) -> CGLContextObj {
        var context: CGLContextObj?
        CGLCreateContext(pixelFormat, nil, &context)
        var swapInterval: GLint = 1
        CGLSetParameter(context!, kCGLCPSwapInterval, &swapInterval)
        CGLEnable(context!, kCGLCEMPEngine)
        return context!
    }
}

final class MPVPlayerBackend {
    private static let subtitleExtensions = ["srt", "ass", "ssa", "vtt", "sub", "idx", "smi", "sami"]

    private let lib: LibMPV
    private var handle: OpaquePointer?
    private var renderContext: OpaquePointer?
    private weak var renderView: FlowMPVVideoView?
    private weak var renderLayer: MPVRenderLayer?
    private let renderContextLock = NSRecursiveLock()
    private let teardownQueue = DispatchQueue(label: "netdcy.FlowVision.mpv.teardown", qos: .userInitiated)
    private var progressTimer: Timer?
    private var endHandler: (() -> Void)?
    private var abRange: ClosedRange<Double>?
    private var isStopping = false

    var isActive: Bool { handle != nil }
    var isPlaying: Bool { !getFlag("pause") && isActive }
    var currentTime: Double { getDouble("time-pos") }
    var duration: Double { getDouble("duration") }

    static func reloadRuntime() {
        LibMPV.reload()
    }

    var volume: Float {
        get { Float(max(0, min(100, getDouble("volume"))) / 100.0) }
        set {
            let mpvVolume = Double(max(0, min(1, newValue)) * 100)
            setDouble("volume", mpvVolume)
        }
    }

    init?(renderView: FlowMPVVideoView) {
        guard let lib = LibMPV.shared else { return nil }
        self.lib = lib
        self.renderView = renderView
    }

    deinit {
        stop()
    }

    func load(url: URL, startTime: Double?, volume: Float, rate: Float, rotation: Int, abRange: ClosedRange<Double>?, loop: Bool, endHandler: (() -> Void)?) -> Bool {
        stop(destroyHandle: true)

        guard let mpv = lib.create() else {
            log("mpv_create failed.", level: .error)
            return false
        }
        handle = mpv
        self.endHandler = endHandler
        self.abRange = abRange

        setOption("terminal", "no")
        setOption("msg-level", "all=warn")
        setOption("osc", "no")
        setOption("input-default-bindings", "no")
        setOption("input-vo-keyboard", "no")
        setOption("vo", "libmpv")
        setOption("hwdec", "auto-safe")
        setOption("gpu-api", "opengl")
        setOption("gpu-hwdec-interop", "auto")
        setOption("vd-lavc-dr", "yes")
        setOption("video-sync", "display-resample")
        setOption("interpolation", "yes")
        setOption("opengl-swapinterval", "1")
        setOption("force-window", "no")
        setOption("keep-open", "yes")
        setOption("sub-auto", "no")
        // Mounted SMB paths look like local files to mpv, so force a bounded
        // read-ahead cache instead of relying on small on-demand reads.
        let isNetworkVolume = VolumeManager.shared.isNetworkVolume(url)
        let readAheadSeconds = isNetworkVolume ? 12 : 5
        setOption("cache", "yes")
        setOption("cache-on-disk", "no")
        setOption("cache-secs", "\(readAheadSeconds)")
        setOption("cache-pause", "yes")
        setOption("cache-pause-initial", isNetworkVolume ? "yes" : "no")
        setOption("cache-pause-wait", isNetworkVolume ? "3" : "1")
        setOption("demuxer-readahead-secs", "\(readAheadSeconds)")
        setOption("demuxer-max-bytes", "134217728")
        setOption("demuxer-max-back-bytes", "33554432")
        setOption("volume", "\(Int(max(0, min(1, volume)) * 100))")
        setOption("speed", "\(rate)")
        if rotation != 0 {
            setOption("video-rotate", "\(rotation * 90)")
        }

        guard lib.initialize(mpv) >= 0 else {
            log("mpv_initialize failed; falling back to AVPlayer.", level: .error)
            stop(destroyHandle: true)
            return false
        }

        renderView?.attach(self)
        guard renderContext != nil else {
            log("mpv render context failed; falling back to AVPlayer.", level: .error)
            stop(destroyHandle: true)
            return false
        }

        var args: [String?] = ["loadfile", url.path, "replace"]
        if let startTime, startTime > 0 {
            args.append("start=\(startTime)")
        } else if let abStart = abRange?.lowerBound {
            args.append("start=\(abStart)")
        }
        guard command(args) >= 0 else {
            stop(destroyHandle: true)
            return false
        }
        loadExternalSubtitles(for: url)
        setPaused(false)
        startProgressTimer(loop: loop)
        return true
    }

    fileprivate func initializeRendering(with layer: MPVRenderLayer) {
        guard renderContext == nil, let handle else { return }
        renderLayer = layer
        CGLLockContext(layer.cglContext)
        CGLSetCurrentContext(layer.cglContext)
        defer { CGLUnlockContext(layer.cglContext) }

        renderContextLock.lock()
        defer { renderContextLock.unlock() }

        var initParams = MPVOpenGLInitParams(getProcAddress: flowMPVGetOpenGLProcAddress, getProcAddressCtx: nil)
        var advanced: CInt = 1
        "opengl".withCString { api in
            withUnsafeMutablePointer(to: &initParams) { initPointer in
                withUnsafeMutablePointer(to: &advanced) { advancedPointer in
                    var params = [
                        MPVRenderParam(type: mpvRenderParamAPIType, data: UnsafeMutableRawPointer(mutating: api)),
                        MPVRenderParam(type: mpvRenderParamOpenGLInitParams, data: UnsafeMutableRawPointer(initPointer)),
                        MPVRenderParam(type: mpvRenderParamAdvancedControl, data: UnsafeMutableRawPointer(advancedPointer)),
                        MPVRenderParam()
                    ]
                    var context: OpaquePointer?
                    let result = params.withUnsafeMutableBufferPointer { buffer in
                        lib.renderContextCreate(&context, handle, UnsafeMutableRawPointer(buffer.baseAddress))
                    }
                    if result >= 0 {
                        renderContext = context
                        lib.renderContextSetUpdateCallback(context, flowMPVRenderUpdateCallback, Unmanaged.passUnretained(layer).toOpaque())
                    }
                }
            }
        }
    }

    func stop(destroyHandle: Bool = true) {
        progressTimer?.invalidate()
        progressTimer = nil
        abRange = nil
        endHandler = nil
        isStopping = true
        renderView?.detach()

        do {
            renderContextLock.lock()
            defer { renderContextLock.unlock() }

            if let renderContext {
                lib.renderContextSetUpdateCallback(renderContext, nil, nil)
                lib.renderContextFree(renderContext)
                self.renderContext = nil
            }
            renderLayer = nil
        }

        guard let handle else {
            isStopping = false
            return
        }
        if destroyHandle {
            self.handle = nil
            // libmpv can wait for demuxer/decoder threads here, especially for
            // an SMB URL that was removed while playing. Release the UI-facing
            // state above, then destroy the handle off the main thread.
            let lib = self.lib
            teardownQueue.async {
                lib.terminateDestroy(handle)
            }
        } else {
            _ = command(["stop"])
        }
        isStopping = false
    }

    func setPaused(_ paused: Bool) {
        var value: Int32 = paused ? 1 : 0
        setProperty("pause", format: mpvFormatFlag, value: &value)
    }

    func setRate(_ rate: Float) {
        setDouble("speed", Double(rate))
    }

    func seek(to seconds: Double) {
        _ = command(["seek", "\(boundedTime(seconds))", "absolute", "exact"])
    }

    /// Saves the decoded video frame that mpv is currently displaying. Using
    /// mpv's own screenshot path keeps the capture aligned with playback even
    /// when hardware decoding or a network-backed source is active.
    func captureCurrentVideoFrame(to outputURL: URL) -> Bool {
        guard outputURL.isFileURL, isActive else { return false }
        return command(["screenshot-to-file", outputURL.path, "video"]) >= 0
    }

    func reportSwap() {
        renderContextLock.lock()
        defer { renderContextLock.unlock() }

        guard let renderContext else { return }
        lib.renderContextReportSwap(renderContext)
    }

    func shouldRenderUpdateFrame() -> Bool {
        renderContextLock.lock()
        defer { renderContextLock.unlock() }

        guard let renderContext else { return false }
        return (lib.renderContextUpdate(renderContext) & mpvRenderUpdateFrame) != 0
    }

    fileprivate func render(params: inout [MPVRenderParam]) {
        renderContextLock.lock()
        defer { renderContextLock.unlock() }

        guard let renderContext, let layer = renderLayer else { return }
        CGLLockContext(layer.cglContext)
        defer { CGLUnlockContext(layer.cglContext) }

        CGLSetCurrentContext(layer.cglContext)
        _ = params.withUnsafeMutableBufferPointer { buffer in
            lib.renderContextRender(renderContext, UnsafeMutableRawPointer(buffer.baseAddress))
        }
    }

    private func startProgressTimer(loop: Bool) {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            guard let self, self.isActive, !self.isStopping else { return }
            if let range = self.abRange, self.currentTime >= range.upperBound {
                if loop {
                    self.seek(to: range.lowerBound)
                    self.setPaused(false)
                } else {
                    self.setPaused(true)
                    self.endHandler?()
                }
                return
            }
            if self.getFlag("eof-reached") {
                if loop {
                    self.seek(to: self.abRange?.lowerBound ?? 0)
                    self.setPaused(false)
                } else {
                    self.endHandler?()
                }
            }
        }
    }

    private func boundedTime(_ seconds: Double) -> Double {
        var target = seconds
        if let range = abRange {
            target = max(range.lowerBound, min(range.upperBound, target))
        } else {
            let total = duration
            target = total.isFinite && total > 0 ? max(0, min(total, target)) : max(0, target)
        }
        return target
    }

    private func loadExternalSubtitles(for videoURL: URL) {
        let subtitles = Self.matchingSubtitleURLs(for: videoURL)
        for (index, subtitle) in subtitles.enumerated() {
            _ = command(["sub-add", subtitle.path, index == 0 ? "select" : "auto"])
        }
    }

    private static func matchingSubtitleURLs(for videoURL: URL) -> [URL] {
        let directory = videoURL.deletingLastPathComponent()
        let videoBaseName = videoURL.deletingPathExtension().lastPathComponent.lowercased()
        guard !videoBaseName.isEmpty,
              let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              )
        else {
            return []
        }

        let subtitleExtensionRank = Dictionary(uniqueKeysWithValues: subtitleExtensions.enumerated().map { ($0.element, $0.offset) })
        let candidates = contents.compactMap { fileURL -> (url: URL, matchRank: Int, extensionRank: Int)? in
            let ext = fileURL.pathExtension.lowercased()
            guard let extensionRank = subtitleExtensionRank[ext] else { return nil }

            let baseName = fileURL.deletingPathExtension().lastPathComponent.lowercased()
            let matchRank: Int
            if baseName == videoBaseName {
                matchRank = 0
            } else if baseName.hasPrefix(videoBaseName + ".") || baseName.hasPrefix(videoBaseName + " ") {
                matchRank = 1
            } else {
                return nil
            }

            return (fileURL, matchRank, extensionRank)
        }

        return candidates
            .sorted {
                if $0.matchRank != $1.matchRank { return $0.matchRank < $1.matchRank }
                if $0.extensionRank != $1.extensionRank { return $0.extensionRank < $1.extensionRank }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
            .map(\.url)
    }

    private func setOption(_ name: String, _ value: String) {
        guard let handle else { return }
        _ = lib.setOptionString(handle, name, value)
    }

    private func command(_ args: [String?]) -> Int32 {
        guard let handle else { return -1 }
        let mutableArgs: [UnsafeMutablePointer<CChar>?] = args.map { $0.map { strdup($0) } }
        var cargs: [UnsafePointer<CChar>?] = mutableArgs.map { $0.map { UnsafePointer($0) } }
        cargs.append(nil)
        defer {
            for pointer in mutableArgs where pointer != nil {
                free(pointer)
            }
        }
        return cargs.withUnsafeMutableBufferPointer { buffer in
            lib.command(handle, buffer.baseAddress)
        }
    }

    private func setDouble(_ name: String, _ value: Double) {
        var value = value
        setProperty(name, format: mpvFormatDouble, value: &value)
    }

    private func setProperty<T>(_ name: String, format: Int32, value: inout T) {
        guard let handle else { return }
        withUnsafeMutablePointer(to: &value) { pointer in
            _ = lib.setProperty(handle, name, format, pointer)
        }
    }

    private func getDouble(_ name: String) -> Double {
        guard let handle else { return 0 }
        var value = 0.0
        let result = lib.getProperty(handle, name, mpvFormatDouble, &value)
        return result >= 0 && value.isFinite ? value : 0
    }

    private func getFlag(_ name: String) -> Bool {
        guard let handle else { return false }
        var value: Int32 = 0
        let result = lib.getProperty(handle, name, mpvFormatFlag, &value)
        return result >= 0 && value != 0
    }
}

private func flowMPVGetOpenGLProcAddress(_ ctx: UnsafeMutableRawPointer?, _ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    let symbolName = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.ASCII.rawValue)
    guard let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString) else { return nil }
    return CFBundleGetFunctionPointerForName(bundle, symbolName)
}

private func flowMPVRenderUpdateCallback(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let layer = Unmanaged<MPVRenderLayer>.fromOpaque(context).takeUnretainedValue()
    layer.update()
}

private func flowMPVDisplayLinkCallback(
    _ displayLink: CVDisplayLink,
    _ inNow: UnsafePointer<CVTimeStamp>,
    _ inOutputTime: UnsafePointer<CVTimeStamp>,
    _ flagsIn: CVOptionFlags,
    _ flagsOut: UnsafeMutablePointer<CVOptionFlags>,
    _ context: UnsafeMutableRawPointer?
) -> CVReturn {
    guard let context else { return kCVReturnSuccess }
    let view = Unmanaged<FlowMPVVideoView>.fromOpaque(context).takeUnretainedValue()
    view.reportSwap()
    return kCVReturnSuccess
}
