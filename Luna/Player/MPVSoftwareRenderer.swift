//
//  MPVSoftwareRenderer.swift
//  test
//
//  Created by Francesco on 28/09/25.
//

import UIKit
import Libmpv
import CoreMedia
import CoreVideo
import AVFoundation
import Metal
import MetalKit

protocol MPVSoftwareRendererDelegate: AnyObject {
    func renderer(_ renderer: MPVSoftwareRenderer, didUpdatePosition position: Double, duration: Double)
    func renderer(_ renderer: MPVSoftwareRenderer, didChangePause isPaused: Bool)
    func renderer(_ renderer: MPVSoftwareRenderer, didChangeLoading isLoading: Bool)
    func renderer(_ renderer: MPVSoftwareRenderer, didBecomeReadyToSeek: Bool)
    func renderer(_ renderer: MPVSoftwareRenderer, getSubtitleForTime time: Double) -> NSAttributedString?
    func renderer(_ renderer: MPVSoftwareRenderer, getSubtitleStyle: Void) -> SubtitleStyle
    func renderer(_ renderer: MPVSoftwareRenderer, subtitleTrackDidChange trackId: Int)
    func rendererDidChangeTracks(_ renderer: MPVSoftwareRenderer)
}

struct SubtitleStyle {
    let foregroundColor: UIColor
    let strokeColor: UIColor
    let strokeWidth: CGFloat
    let fontSize: CGFloat
    let isVisible: Bool
    
    static func fromSettings() -> SubtitleStyle {
        let settings = Settings.shared
        return SubtitleStyle(
            foregroundColor: .white,
            strokeColor: .black,
            strokeWidth: settings.subtitleSize.strokeWidth,
            fontSize: settings.subtitleSize.fontSize,
            isVisible: false
        )
    }
    
    static let `default` = SubtitleStyle(
        foregroundColor: .white,
        strokeColor: .black,
        strokeWidth: 3.5,
        fontSize: 48.0,
        isVisible: false
    )
}

private struct SubtitleRenderKey: Equatable {
    let text: String
    let fontSize: CGFloat
    let foreground: String
    let stroke: String
    let strokeWidth: CGFloat
    let maxWidth: CGFloat
}

private struct SubtitleRenderCache {
    let key: SubtitleRenderKey
    let image: CGImage
    let size: CGSize
}

final class MPVSoftwareRenderer {
    enum RendererError: Error {
        case mpvCreationFailed
        case mpvInitialization(Int32)
        case renderContextCreation(Int32)
    }
    
    private let displayLayer: AVSampleBufferDisplayLayer
    private let renderQueue = DispatchQueue(label: "mpv.software.render", qos: .userInitiated)
    private let eventQueue = DispatchQueue(label: "mpv.software.events", qos: .utility)
    private let stateQueue = DispatchQueue(label: "mpv.software.state", attributes: .concurrent)
    private let subtitleRenderQueue = DispatchQueue(label: "mpv.subtitle.render", qos: .utility)
    
    // Metal for GPU subtitle rendering
    private let metalDevice = MTLCreateSystemDefaultDevice()
    private var metalCommandQueue: MTLCommandQueue?
    private var metalPipelineState: MTLRenderPipelineState?
    private var metalSamplerState: MTLSamplerState?
    private let eventQueueGroup = DispatchGroup()
    private let renderQueueKey = DispatchSpecificKey<Void>()
    
    private var dimensionsArray = [Int32](repeating: 0, count: 2)
    private var renderParams = [mpv_render_param](repeating: mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil), count: 5)
    
    private var mpv: OpaquePointer?
    private var renderContext: OpaquePointer?
    private var videoSize: CGSize = .zero
    private var pixelBufferPool: CVPixelBufferPool?
    private var pixelBufferPoolAuxAttributes: CFDictionary?
    private var formatDescription: CMVideoFormatDescription?
    private var didFlushForFormatChange = false
    private var poolWidth: Int = 0
    private var poolHeight: Int = 0
    private var preAllocatedBuffers: [CVPixelBuffer] = []
    private let maxPreAllocatedBuffers = 12
    
    private var currentPreset: PlayerPreset?
    private var currentURL: URL?
    private var currentHeaders: [String: String]?
    
    private var disposeBag: [() -> Void] = []
    
    private var isRunning = false
    private var isStopping = false
    private var shouldClearPixelBuffer = false
    private let bgraFormatCString: [CChar] = Array("bgra\0".utf8CString)
    
    weak var delegate: MPVSoftwareRendererDelegate?
    private var cachedDuration: Double = 0
    private var cachedPosition: Double = 0
    private var isPaused: Bool = true
    private var isLoading: Bool = false
    private var isRenderScheduled = false
    private var lastRenderTime: CFTimeInterval = 0
    private var currentEmbeddedSubtitleText: String?
    private var minRenderInterval: CFTimeInterval
    private var isReadyToSeek: Bool = false
    private var lastSubtitleCheckTime: Double = -1.0
    private var cachedSubtitleText: NSAttributedString?
    private var subtitleRenderCache: SubtitleRenderCache?
    private var forceSubtitleRender: Bool = false
    private var lastRenderDimensions: CGSize = .zero
    private let subtitleUpdateInterval: Double = 1.0
    private var lastPixelBufferCreateWidth: Int = -1
    private var lastPixelBufferCreateHeight: Int = -1
    private var cachedVideoSize: CGSize = .zero
    private var lastVideoSizeCheckTime: CFTimeInterval = 0
    private var pendingSubtitleImage: (key: SubtitleRenderKey, image: CGImage, size: CGSize)?
    private let subtitleImageLock = NSLock()
    private let cachedColorSpace = CGColorSpaceCreateDeviceRGB()
    private var isAppActive: Bool = true
    private var lastForegroundTime: CFTimeInterval = 0
    
    var isPausedState: Bool {
        return isPaused
    }
    
    init(displayLayer: AVSampleBufferDisplayLayer) {
        guard
            let screen = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.screen })
                .first
        else {
            fatalError("⚠️ No active screen found — app may not have a visible window yet.")
        }
        
        self.displayLayer = displayLayer
        let maxFPS = screen.maximumFramesPerSecond
        // Cap at 24 FPS for aggressive thermal efficiency on mobile
        let cappedFPS = min(maxFPS, 24)
        self.minRenderInterval = 1.0 / CFTimeInterval(cappedFPS)
        
        renderQueue.setSpecific(key: renderQueueKey, value: ())
        
        // Observe app lifecycle for thermal optimization
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stop()
    }
    
    @objc private func handleAppDidEnterBackground() {
        isAppActive = false
        // Skip rendering while backgrounded to save battery/thermal load
    }
    
    @objc private func handleAppWillEnterForeground() {
        isAppActive = true
        lastForegroundTime = CACurrentMediaTime()
        // Debounce render scheduling on foreground to prevent burst rendering
    }
    
    func start() throws {
        guard !isRunning else { return }
        guard let handle = mpv_create() else {
            throw RendererError.mpvCreationFailed
        }
        mpv = handle
        setOption(name: "terminal", value: "yes")
        setOption(name: "msg-level", value: "status")
        setOption(name: "keep-open", value: "yes")
        setOption(name: "idle", value: "yes")
        setOption(name: "vo", value: "libmpv")
        setOption(name: "hwdec", value: "auto-safe")
        setOption(name: "gpu-api", value: "metal")
        setOption(name: "gpu-context", value: "metal")
        setOption(name: "demuxer-thread", value: "yes")
        setOption(name: "ytdl", value: "yes")
        setOption(name: "profile", value: "sw-fast")
        // Reduce threads to 2 for minimal thermal load
        setOption(name: "vd-lavc-threads", value: "2")
        setOption(name: "vd-lavc-skiploopfilter", value: "all")
        setOption(name: "vd-lavc-skipidct", value: "nonkey")
        setOption(name: "vd-lavc-fast", value: "yes")
        setOption(name: "cache", value: "yes")
        setOption(name: "demuxer-max-bytes", value: "30M")
        setOption(name: "demuxer-readahead-secs", value: "5")
        setOption(name: "framedrop", value: "vo")
        setOption(name: "video-sync", value: "audio")
        setOption(name: "subs-fallback", value: "yes")
        setOption(name: "sub-ass", value: "yes")
        setOption(name: "embeddedfonts", value: "yes")
        setOption(name: "sub-visibility", value: "yes")
        
        let initStatus = mpv_initialize(handle)
        guard initStatus >= 0 else {
            throw RendererError.mpvInitialization(initStatus)
        }
        
        mpv_request_log_messages(handle, "warn")
        
        // Initialize Metal rendering pipeline for subtitles
        setupMetalPipeline()
        
        try createRenderContext()
        observeProperties()
        installWakeupHandler()
        isRunning = true
    }
    
    func stop() {
        if isStopping { return }
        if !isRunning, mpv == nil { return }
        isRunning = false
        isStopping = true
        
        var handleForShutdown: OpaquePointer?
        
        renderQueue.sync { [weak self] in
            guard let self else { return }
            
            if let ctx = self.renderContext {
                mpv_render_context_set_update_callback(ctx, nil, nil)
                mpv_render_context_free(ctx)
                self.renderContext = nil
            }
            
            handleForShutdown = self.mpv
            if let handle = handleForShutdown {
                mpv_set_wakeup_callback(handle, nil, nil)
                self.command(handle, ["quit"])
                mpv_wakeup(handle)
            }
            
            self.formatDescription = nil
            self.preAllocatedBuffers.removeAll()
            self.pixelBufferPool = nil
            self.poolWidth = 0
            self.poolHeight = 0
            self.lastRenderDimensions = .zero
        }
        
        eventQueueGroup.wait()
        
        renderQueue.sync { [weak self] in
            guard let self else { return }
            
            if let handle = handleForShutdown {
                mpv_destroy(handle)
            }
            self.mpv = nil
            
            self.preAllocatedBuffers.removeAll()
            self.pixelBufferPool = nil
            self.pixelBufferPoolAuxAttributes = nil
            self.formatDescription = nil
            self.poolWidth = 0
            self.poolHeight = 0
            self.lastRenderDimensions = .zero
            
            self.disposeBag.forEach { $0() }
            self.disposeBag.removeAll()
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            
            if #available(iOS 18.0, *) {
                self.displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
            } else {
                self.displayLayer.flushAndRemoveImage()
            }
        }
        
        isStopping = false
    }
    
    func load(url: URL, with preset: PlayerPreset, headers: [String: String]? = nil) {
        currentPreset = preset
        currentURL = url
        currentHeaders = headers
        
        Logger.shared.log("MPVSoftwareRenderer: Loading \(url.absoluteString)", type: "Info")
        
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.isLoading = true
            self.isReadyToSeek = false
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.renderer(self, didChangeLoading: true)
            }
        }
        
        guard let handle = mpv else {
            Logger.shared.log("MPVSoftwareRenderer: MPV handle is nil, cannot load", type: "Error")
            return
        }
        
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.apply(commands: preset.commands, on: handle)
            self.command(handle, ["stop"])
            self.updateHTTPHeaders(headers)
            
            var finalURL = url
            if !url.isFileURL {
                finalURL = url
            }
            
            let target = finalURL.isFileURL ? finalURL.path : finalURL.absoluteString
            Logger.shared.log("MPVSoftwareRenderer: Sending loadfile command for \(target)", type: "Info")
            self.command(handle, ["loadfile", target, "replace"])
        }
    }
    
    func reloadCurrentItem() {
        guard let url = currentURL, let preset = currentPreset else { return }
        load(url: url, with: preset, headers: currentHeaders)
    }
    
    func applyPreset(_ preset: PlayerPreset) {
        currentPreset = preset
        guard let handle = mpv else { return }
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.apply(commands: preset.commands, on: handle)
        }
    }
    
    private func setOption(name: String, value: String) {
        guard let handle = mpv else { return }
        _ = value.withCString { valuePointer in
            name.withCString { namePointer in
                mpv_set_option_string(handle, namePointer, valuePointer)
            }
        }
    }
    
    private func setProperty(name: String, value: String) {
        guard let handle = mpv else { return }
        let status = value.withCString { valuePointer in
            name.withCString { namePointer in
                mpv_set_property_string(handle, namePointer, valuePointer)
            }
        }
        if status < 0 {
            Logger.shared.log("Failed to set property \(name)=\(value) (\(status))", type: "Warn")
        } else {
            // Log successful subtitle-related property changes
            if name == "sid" || name == "sub-visibility" {
                Logger.shared.log("MPV property set: \(name)=\(value)", type: "Info")
            }
        }
    }

    private func setPropertyWithStatus(name: String, value: String) -> Int32 {
        guard let handle = mpv else { return -1 }
        let status = value.withCString { valuePointer in
            name.withCString { namePointer in
                mpv_set_property_string(handle, namePointer, valuePointer)
            }
        }
        if status < 0 {
            let errString = String(cString: mpv_error_string(status))
            Logger.shared.log("Failed to set property \(name)=\(value) (status=\(status), error=\(errString))", type: "Error")
        } else {
            Logger.shared.log("MPV property set: \(name)=\(value) (status=\(status))", type: "Info")
        }
        return status
    }
    
    private func clearProperty(name: String) {
        guard let handle = mpv else { return }
        let status = name.withCString { namePointer in
            mpv_set_property(handle, namePointer, MPV_FORMAT_NONE, nil)
        }
        if status < 0 {
            Logger.shared.log("Failed to clear property \(name) (\(status))", type: "Warn")
        }
    }
    
    private func updateHTTPHeaders(_ headers: [String: String]?) {
        guard let headers, !headers.isEmpty else {
            clearProperty(name: "http-header-fields")
            return
        }
        
        let headerString = headers
            .map { key, value in
                "\(key): \(value)"
            }
            .joined(separator: "\r\n")
        setProperty(name: "http-header-fields", value: headerString)
    }
    
    private func createRenderContext() throws {
        guard let handle = mpv else { return }
        
        var apiType = MPV_RENDER_API_TYPE_SW
        let status = withUnsafePointer(to: &apiType) { apiTypePtr in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: apiTypePtr)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
            ]
            
            return params.withUnsafeMutableBufferPointer { pointer -> Int32 in
                pointer.baseAddress?.withMemoryRebound(to: mpv_render_param.self, capacity: pointer.count) { parameters in
                    return mpv_render_context_create(&renderContext, handle, parameters)
                } ?? -1
            }
        }
        
        guard status >= 0, renderContext != nil else {
            throw RendererError.renderContextCreation(status)
        }
        
        mpv_render_context_set_update_callback(renderContext, { context in
            guard let context = context else { return }
            let instance = Unmanaged<MPVSoftwareRenderer>.fromOpaque(context).takeUnretainedValue()
            instance.scheduleRender()
        }, Unmanaged.passUnretained(self).toOpaque())
    }
    
    private func observeProperties() {
        guard let handle = mpv else { return }
        let properties: [(String, mpv_format)] = [
            ("dwidth", MPV_FORMAT_INT64),
            ("dheight", MPV_FORMAT_INT64),
            ("duration", MPV_FORMAT_DOUBLE),
            ("time-pos", MPV_FORMAT_DOUBLE),
            ("pause", MPV_FORMAT_FLAG),
            ("sid", MPV_FORMAT_INT64),
            ("sub-visibility", MPV_FORMAT_FLAG),
            ("sub-text", MPV_FORMAT_STRING),
            ("track-list", MPV_FORMAT_NODE)
        ]
        
        for (name, format) in properties {
            _ = name.withCString { pointer in
                mpv_observe_property(handle, 0, pointer, format)
            }
        }
    }
    
    private func installWakeupHandler() {
        guard let handle = mpv else { return }
        mpv_set_wakeup_callback(handle, { userdata in
            guard let userdata else { return }
            let instance = Unmanaged<MPVSoftwareRenderer>.fromOpaque(userdata).takeUnretainedValue()
            instance.processEvents()
        }, Unmanaged.passUnretained(self).toOpaque())
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.disposeBag.append { [weak self] in
                guard let self, let handle = self.mpv else { return }
                mpv_set_wakeup_callback(handle, nil, nil)
            }
        }
    }
    
    private func scheduleRender() {
        renderQueue.async { [weak self] in
            guard let self, self.isRunning, !self.isStopping else { return }
            
            // Skip rendering when app is backgrounded (thermal optimization)
            guard self.isAppActive else { return }
            
            let currentTime = CACurrentMediaTime()
            let timeSinceLastRender = currentTime - self.lastRenderTime
            if timeSinceLastRender < self.minRenderInterval {
                let remaining = self.minRenderInterval - timeSinceLastRender
                if self.isRenderScheduled { return }
                self.isRenderScheduled = true
                
                self.renderQueue.asyncAfter(deadline: .now() + remaining) { [weak self] in
                    guard let self else { return }
                    self.lastRenderTime = CACurrentMediaTime()
                    self.performRenderUpdate()
                    self.isRenderScheduled = false
                }
                return
            }
            
            self.isRenderScheduled = true
            self.lastRenderTime = currentTime
            self.performRenderUpdate()
            self.isRenderScheduled = false
        }
    }
    
    private func performRenderUpdate() {
        guard let context = renderContext else {
            Logger.shared.log("MPVSoftwareRenderer: renderContext is nil in performRenderUpdate", type: "Warn")
            return
        }
        
        let status = mpv_render_context_update(context)
        
        let updateFlags = UInt32(status)
        
        var didRender = false

        // Render frame if there's a new frame AND video is playing (or new frame from seek)
        if updateFlags & MPV_RENDER_UPDATE_FRAME.rawValue != 0 {
            renderFrame()
            didRender = true
        } else if isPaused && forceSubtitleRender {
            // While paused, still render once to draw subtitles
            renderFrame()
            didRender = true
        }

        if didRender {
            forceSubtitleRender = false
        }

        // Only schedule future renders when playing (don't loop renders while paused)
        if status > 0 && !isPaused {
            scheduleRender()
        }
    }
    
    private func renderFrame() {
        guard let context = renderContext else { return }
        
        // Cache video size to avoid repeated mpv queries
        let currentTime = CACurrentMediaTime()
        if currentTime - lastVideoSizeCheckTime > 1.0 {
            cachedVideoSize = currentVideoSize()
            lastVideoSizeCheckTime = currentTime
        }
        let videoSize = cachedVideoSize
        
        guard videoSize.width > 0, videoSize.height > 0 else {
            Logger.shared.log("MPVSoftwareRenderer: Skipping render - video size not ready (\(videoSize.width)x\(videoSize.height))", type: "Debug")
            return
        }
        
        let targetSize = targetRenderSize(for: videoSize)
        let width = Int(targetSize.width)
        let height = Int(targetSize.height)
        guard width > 0, height > 0 else {
            Logger.shared.log("MPVSoftwareRenderer: Invalid target size \(width)x\(height)", type: "Warn")
            return
        }
        if lastRenderDimensions != targetSize {
            lastRenderDimensions = targetSize
            if targetSize != videoSize {
                Logger.shared.log("Rendering scaled output at \(width)x\(height) (source \(Int(videoSize.width))x\(Int(videoSize.height)))", type: "Info")
            } else {
                Logger.shared.log("Rendering output at native size \(width)x\(height)", type: "Info")
            }
        }
        
        if poolWidth != width || poolHeight != height {
            recreatePixelBufferPool(width: width, height: height)
        }
        
        var pixelBuffer: CVPixelBuffer?
        var status: CVReturn = kCVReturnError
        
        if !preAllocatedBuffers.isEmpty {
            pixelBuffer = preAllocatedBuffers.removeFirst()
            status = kCVReturnSuccess
        } else if let pool = pixelBufferPool {
            status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, pixelBufferPoolAuxAttributes, &pixelBuffer)
        }
        
        if status != kCVReturnSuccess || pixelBuffer == nil {
            // Cache dimension tracking to avoid allocating new attributes dictionary if size didn't change
            if lastPixelBufferCreateWidth != width || lastPixelBufferCreateHeight != height {
                lastPixelBufferCreateWidth = width
                lastPixelBufferCreateHeight = height
            }
            
            let attrs: [CFString: Any] = [
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
                kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
                kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!,
                kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue!,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
            ]
            status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
        }
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            Logger.shared.log("Failed to create pixel buffer for rendering (status: \(status))", type: "Error")
            return
        }
        
        let actualFormat = CVPixelBufferGetPixelFormatType(buffer)
        if actualFormat != kCVPixelFormatType_32BGRA {
            Logger.shared.log("Pixel buffer format mismatch: expected BGRA (0x42475241), got \(actualFormat)", type: "Error")
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return
        }
        
        if shouldClearPixelBuffer {
            let bufferDataSize = CVPixelBufferGetDataSize(buffer)
            memset(baseAddress, 0, bufferDataSize)
            shouldClearPixelBuffer = false
        }
        
        dimensionsArray[0] = Int32(width)
        dimensionsArray[1] = Int32(height)
        let stride = Int32(CVPixelBufferGetBytesPerRow(buffer))
        let expectedMinStride = Int32(width * 4)
        if stride < expectedMinStride {
            Logger.shared.log("Unexpected pixel buffer stride \(stride) < expected \(expectedMinStride) — skipping render to avoid memory corruption", type: "Error")
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return
        }
        
        let pointerValue = baseAddress
        dimensionsArray.withUnsafeMutableBufferPointer { dimsPointer in
            bgraFormatCString.withUnsafeBufferPointer { formatPointer in
                withUnsafePointer(to: stride) { stridePointer in
                    renderParams[0] = mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: UnsafeMutableRawPointer(dimsPointer.baseAddress))
                    renderParams[1] = mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: UnsafeMutableRawPointer(mutating: formatPointer.baseAddress))
                    renderParams[2] = mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: UnsafeMutableRawPointer(mutating: stridePointer))
                    renderParams[3] = mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: pointerValue)
                    renderParams[4] = mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                    
                    let rc = mpv_render_context_render(context, &renderParams)
                    if rc < 0 {
                        Logger.shared.log("mpv_render_context_render returned error \(rc)", type: "Error")
                    }
                }
            }
        }
        
        CVPixelBufferUnlockBaseAddress(buffer, [])
        
        if let style = delegate?.renderer(self, getSubtitleStyle: ()), style.isVisible {
            let currentTime = cachedPosition
            let timeDelta = abs(currentTime - lastSubtitleCheckTime)
            
            // Update subtitle text even when paused so overlays show on paused frames
            if timeDelta >= subtitleUpdateInterval {
                lastSubtitleCheckTime = currentTime
                // Check for external subtitle first
                cachedSubtitleText = delegate?.renderer(self, getSubtitleForTime: currentTime)
                
                // If no external subtitle, check for embedded subtitle
                if cachedSubtitleText == nil || cachedSubtitleText?.length == 0 {
                    if let embeddedText = currentEmbeddedSubtitleText, !embeddedText.isEmpty {
                        cachedSubtitleText = createAttributedString(from: embeddedText, style: style)
                    }
                }
            }
            
            // Burn cached subtitle image if text exists (works when paused and playing)
            if let attributedText = cachedSubtitleText, attributedText.length > 0 {
                if let cache = subtitleRenderCache {
                    // Quickly burn cached image without re-rendering
                    burnCachedSubtitle(into: buffer, cache: cache, style: style)
                } else {
                    // First render: generate and burn image
                    burnSubtitles(into: buffer, attributedText: attributedText, style: style)
                }
            } else {
                subtitleRenderCache = nil
            }
        } else {
            subtitleRenderCache = nil
            lastSubtitleCheckTime = -1.0
            cachedSubtitleText = nil
        }
        
        enqueue(buffer: buffer)
        
        // Delay buffer pre-allocation briefly after foreground return to avoid thermal burst
        let timeSinceForeground = CACurrentMediaTime() - lastForegroundTime
        let shouldPreAllocate = preAllocatedBuffers.count < 2 && (lastForegroundTime == 0 || timeSinceForeground > 2.0)
        
        if shouldPreAllocate {
            renderQueue.async { [weak self] in
                self?.preAllocateBuffers()
            }
        }
    }
    
    private func targetRenderSize(for videoSize: CGSize) -> CGSize {
        guard videoSize.width > 0, videoSize.height > 0 else { return videoSize }
        
        guard
            let screen = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.screen })
                .first
        else {
            fatalError("⚠️ No active screen found — app may not have a visible window yet.")
        }
        
        var scale = screen.scale
        if scale <= 0 { scale = 1 }
        let maxWidth = max(screen.bounds.width * scale, 1.0)
        let maxHeight = max(screen.bounds.height * scale, 1.0)
        if maxWidth <= 0 || maxHeight <= 0 {
            return videoSize
        }
        let widthRatio = videoSize.width / maxWidth
        let heightRatio = videoSize.height / maxHeight
        let ratio = max(widthRatio, heightRatio, 1)
        let targetWidth = max(1, Int(videoSize.width / ratio))
        let targetHeight = max(1, Int(videoSize.height / ratio))
        return CGSize(width: CGFloat(targetWidth), height: CGFloat(targetHeight))
    }
    
    private func burnCachedSubtitle(into pixelBuffer: CVPixelBuffer, cache: SubtitleRenderCache, style: SubtitleStyle) {
        let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
        let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
        
        guard bufferWidth > 0, bufferHeight > 0 else { return }
        
        // Use Metal GPU rendering for better thermal efficiency
        renderSubtitleWithMetal(cgImage: cache.image, into: pixelBuffer, style: style)
    }
    
    private func burnSubtitles(into pixelBuffer: CVPixelBuffer, attributedText: NSAttributedString, style: SubtitleStyle) {
        let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
        let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
        
        guard bufferWidth > 0, bufferHeight > 0 else {
            Logger.shared.log("Invalid buffer dimensions for subtitle: \(bufferWidth)x\(bufferHeight)", type: "Error")
            return
        }
        
        let highRes = bufferWidth >= 3840 || bufferHeight >= 2160
        let baseScale: CGFloat = highRes ? 0.5 : 1.0
        let cappedWidth = min(CGFloat(bufferWidth) * baseScale, 1920)
        let cappedHeight = min(CGFloat(bufferHeight) * baseScale, 1080)
        let effectiveWidth = Int(max(cappedWidth, 1))
        let effectiveHeight = Int(max(cappedHeight, 1))
        
        // Get subtitle image (uses cache or queues async rendering)
        guard let subtitleImage = makeSubtitleImage(from: attributedText, style: style, maxWidth: CGFloat(effectiveWidth) * 0.9) else {
            return
        }
        
        // Use Metal GPU rendering for better thermal efficiency
        renderSubtitleWithMetal(cgImage: subtitleImage.image, into: pixelBuffer, style: style)
    }
    
    private func makeSubtitleImage(from attributedText: NSAttributedString, style: SubtitleStyle, maxWidth: CGFloat) -> (image: CGImage, size: CGSize)? {
        guard maxWidth > 0, attributedText.length > 0 else { return nil }
        
        let key = SubtitleRenderKey(
            text: attributedText.string,
            fontSize: style.fontSize,
            foreground: colorKey(style.foregroundColor),
            stroke: colorKey(style.strokeColor),
            strokeWidth: style.strokeWidth,
            maxWidth: maxWidth
        )
        
        // Check if we have a cached image for this text
        subtitleImageLock.lock()
        if let cache = subtitleRenderCache, cache.key == key {
            let result = (cache.image, cache.size)
            subtitleImageLock.unlock()
            return result
        }
        
        // Check if we have a pending image for this text (from previous async work)
        if let pending = pendingSubtitleImage, pending.key == key {
            let result = (pending.image, pending.size)
            subtitleImageLock.unlock()
            return result
        }
        subtitleImageLock.unlock()
        
        // Queue async subtitle generation to reduce thermal load
        subtitleRenderQueue.async { [weak self] in
            self?.generateSubtitleImage(from: attributedText, style: style, maxWidth: maxWidth, key: key)
        }
        
        // For first frame: render synchronously as fallback to ensure subtitle appears
        // Subsequent frames will use cached or pending image
        return generateSubtitleImage(from: attributedText, style: style, maxWidth: maxWidth, key: key)
    }
    
    private func generateSubtitleImage(from attributedText: NSAttributedString, style: SubtitleStyle, maxWidth: CGFloat, key: SubtitleRenderKey) -> (image: CGImage, size: CGSize)? {
        // Early exit if another thread already rendered this (e.g., sync fallback completed before async work started)
        subtitleImageLock.lock()
        if let cache = subtitleRenderCache, cache.key == key {
            let result = (cache.image, cache.size)
            subtitleImageLock.unlock()
            return result
        }
        subtitleImageLock.unlock()
        
        return autoreleasepool {
            let mutable = NSMutableAttributedString(attributedString: attributedText)
            let fullRange = NSRange(location: 0, length: mutable.length)
            
            mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
                if let font = value as? UIFont {
                    let descriptor = font.fontDescriptor
                    let newFont = UIFont(descriptor: descriptor, size: style.fontSize)
                    mutable.addAttribute(.font, value: newFont, range: range)
                } else {
                    mutable.addAttribute(.font, value: UIFont.systemFont(ofSize: style.fontSize, weight: .semibold), range: range)
                }
            }
            
            mutable.addAttribute(.foregroundColor, value: style.foregroundColor, range: fullRange)
            
            if style.strokeWidth > 0 && style.strokeColor.cgColor.alpha > 0 {
                mutable.addAttribute(.strokeColor, value: style.strokeColor, range: fullRange)
                mutable.addAttribute(.strokeWidth, value: -style.strokeWidth, range: fullRange)
            } else {
                mutable.removeAttribute(.strokeColor, range: fullRange)
                mutable.removeAttribute(.strokeWidth, range: fullRange)
            }
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            paragraphStyle.lineBreakMode = .byWordWrapping
            paragraphStyle.lineHeightMultiple = 1.05
            mutable.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
            
            let constraint = CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)
            var boundingRect = mutable.boundingRect(with: constraint, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            boundingRect.origin = .zero
            boundingRect.size.width = ceil(boundingRect.width)
            boundingRect.size.height = ceil(boundingRect.height)
            
            guard boundingRect.width > 0, boundingRect.height > 0 else { return nil }
            
            let strokeRadius = max(style.strokeWidth, 0)
            let padding = strokeRadius > 0 ? strokeRadius * 2.0 : 2.0
            let paddedSize = CGSize(width: boundingRect.width + padding * 2.0, height: boundingRect.height + padding * 2.0)
            let textRect = CGRect(origin: CGPoint(x: padding, y: padding), size: boundingRect.size)
            
            // Reduced from 2.0x to 1.5x for thermal efficiency while maintaining crispness
            UIGraphicsBeginImageContextWithOptions(paddedSize, false, 1.5)
            defer { UIGraphicsEndImageContext() }
            
            if strokeRadius > 0, let ctx = UIGraphicsGetCurrentContext() {
                ctx.saveGState()
                // Reduced to 4 corner offsets (50% less work) for thermal efficiency
                let offsets: [CGPoint] = [
                    CGPoint(x: -strokeRadius, y: -strokeRadius),
                    CGPoint(x: strokeRadius, y: -strokeRadius),
                    CGPoint(x: -strokeRadius, y: strokeRadius),
                    CGPoint(x: strokeRadius, y: strokeRadius)
                ]
                let strokeText = NSMutableAttributedString(attributedString: mutable)
                strokeText.addAttribute(.foregroundColor, value: style.strokeColor, range: fullRange)
                strokeText.removeAttribute(.strokeColor, range: fullRange)
                strokeText.removeAttribute(.strokeWidth, range: fullRange)
                for offset in offsets {
                    let offsetRect = textRect.offsetBy(dx: offset.x, dy: offset.y)
                    strokeText.draw(with: offsetRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                }
                ctx.restoreGState()
            }
            
            mutable.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            
            guard let image = UIGraphicsGetImageFromCurrentImageContext()?.cgImage else {
                Logger.shared.log("Failed to create CGImage for subtitles", type: "Error")
                return nil
            }
            
            let cache = SubtitleRenderCache(key: key, image: image, size: paddedSize)
            let result = (image, paddedSize)
            subtitleImageLock.withLock {
                // Make result available immediately for next frame via pending image
                self.pendingSubtitleImage = (key: key, image: image, size: paddedSize)
                // Then update cache for future frames with same text
                self.subtitleRenderCache = cache
            }
            return result
        }
    }
    
    private func colorKey(_ color: UIColor) -> String {
        let cgColor = color.cgColor
        let converted = cgColor.converted(to: cachedColorSpace, intent: .defaultIntent, options: nil) ?? cgColor
        guard let components = converted.components else {
            return "unknown"
        }
        
        let r = components.count > 0 ? components[0] : 0
        let g = components.count > 1 ? components[1] : r
        let b = components.count > 2 ? components[2] : r
        let a = components.count > 3 ? components[3] : cgColor.alpha
        
        return String(format: "%.4f-%.4f-%.4f-%.4f", r, g, b, a)
    }
    
    private func createPixelBufferPool(width: Int, height: Int) {
        let pixelFormat = kCVPixelFormatType_32BGRA
        
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: pixelFormat,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!
        ]
        
        let poolAttrs: [CFString: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey: maxPreAllocatedBuffers,
            kCVPixelBufferPoolMaximumBufferAgeKey: 0
        ]
        
        let auxAttrs: [CFString: Any] = [
            kCVPixelBufferPoolAllocationThresholdKey: 8
        ]
        
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttrs as CFDictionary, attrs as CFDictionary, &pool)
        if status == kCVReturnSuccess, let pool {
            renderQueueSync {
                self.pixelBufferPool = pool
                self.pixelBufferPoolAuxAttributes = auxAttrs as CFDictionary
                self.poolWidth = width
                self.poolHeight = height
            }
            
            renderQueue.async { [weak self] in
                self?.preAllocateBuffers()
            }
        } else {
            Logger.shared.log("Failed to create CVPixelBufferPool (status: \(status))", type: "Error")
        }
    }
    
    private func recreatePixelBufferPool(width: Int, height: Int) {
        renderQueueSync {
            self.preAllocatedBuffers.removeAll()
            self.pixelBufferPool = nil
            self.formatDescription = nil
            self.poolWidth = 0
            self.poolHeight = 0
        }
        
        createPixelBufferPool(width: width, height: height)
    }
    
    private func preAllocateBuffers() {
        guard DispatchQueue.getSpecific(key: renderQueueKey) != nil else {
            renderQueue.async { [weak self] in
                self?.preAllocateBuffers()
            }
            return
        }
        
        guard let pool = pixelBufferPool else { return }
        
        let targetCount = min(maxPreAllocatedBuffers, 5)
        let currentCount = preAllocatedBuffers.count
        
        guard currentCount < targetCount else { return }
        
        let bufferCount = min(targetCount - currentCount, 2)
        
        for _ in 0..<bufferCount {
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
                kCFAllocatorDefault,
                pool,
                pixelBufferPoolAuxAttributes,
                &buffer
            )
            
            if status == kCVReturnSuccess, let buffer = buffer {
                if preAllocatedBuffers.count < maxPreAllocatedBuffers {
                    preAllocatedBuffers.append(buffer)
                }
            } else {
                if status != kCVReturnWouldExceedAllocationThreshold {
                    Logger.shared.log("Failed to pre-allocate buffer (status: \(status))", type: "Warn")
                }
                break
            }
        }
    }
    
    private func enqueue(buffer: CVPixelBuffer) {
        let needsFlush = updateFormatDescriptionIfNeeded(for: buffer)
        var shouldNotifyLoadingEnd = false
        renderQueueSync {
            if self.isLoading {
                self.isLoading = false
                shouldNotifyLoadingEnd = true
            }
        }
        var capturedFormatDescription: CMVideoFormatDescription?
        renderQueueSync {
            capturedFormatDescription = self.formatDescription
        }
        
        guard let formatDescription = capturedFormatDescription else {
            Logger.shared.log("Missing formatDescription when creating sample buffer — skipping frame", type: "Error")
            return
        }
        
        let presentationTime = CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: presentationTime, decodeTimeStamp: .invalid)
        
        var sampleBuffer: CMSampleBuffer?
        let result = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        
        guard result == noErr, let sample = sampleBuffer else {
            Logger.shared.log("Failed to create sample buffer (error: \(result), -12743 = invalid format)", type: "Error")
            
            let width = CVPixelBufferGetWidth(buffer)
            let height = CVPixelBufferGetHeight(buffer)
            let pixelFormat = CVPixelBufferGetPixelFormatType(buffer)
            Logger.shared.log("Buffer info: \(width)x\(height), format: \(pixelFormat)", type: "Error")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            
            let (status, error): (AVQueuedSampleBufferRenderingStatus?, Error?) = {
                if #available(iOS 18.0, *) {
                    return (
                        self.displayLayer.sampleBufferRenderer.status,
                        self.displayLayer.sampleBufferRenderer.error
                    )
                } else {
                    return (
                        self.displayLayer.status,
                        self.displayLayer.error
                    )
                }
            }()
            
            if status == .failed {
                if let error = error {
                    Logger.shared.log("Display layer in failed state: \(error.localizedDescription)", type: "Error")
                }
                if #available(iOS 18.0, *) {
                    self.displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
                } else {
                    self.displayLayer.flushAndRemoveImage()
                }
            }
            
            if needsFlush {
                if #available(iOS 18.0, *) {
                    self.displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
                } else {
                    self.displayLayer.flushAndRemoveImage()
                }
                self.didFlushForFormatChange = true
            } else if self.didFlushForFormatChange {
                if #available(iOS 18.0, *) {
                    self.displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: false, completionHandler: nil)
                } else {
                    self.displayLayer.flush()
                }
                self.didFlushForFormatChange = false
            }
            
            if self.displayLayer.controlTimebase == nil {
                var timebase: CMTimebase?
                if CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase) == noErr, let timebase {
                    CMTimebaseSetRate(timebase, rate: 1.0)
                    CMTimebaseSetTime(timebase, time: presentationTime)
                    self.displayLayer.controlTimebase = timebase
                } else {
                    Logger.shared.log("Failed to create control timebase", type: "Error")
                }
            }
            
            if shouldNotifyLoadingEnd {
                self.delegate?.renderer(self, didChangeLoading: false)
                Logger.shared.log("First frame enqueued, video ready to display", type: "Info")
            }
            
            if #available(iOS 18.0, *) {
                self.displayLayer.sampleBufferRenderer.enqueue(sample)
            } else {
                self.displayLayer.enqueue(sample)
            }
        }
    }
    
    private func updateFormatDescriptionIfNeeded(for buffer: CVPixelBuffer) -> Bool {
        var didChange = false
        let width = Int32(CVPixelBufferGetWidth(buffer))
        let height = Int32(CVPixelBufferGetHeight(buffer))
        let pixelFormat = CVPixelBufferGetPixelFormatType(buffer)
        
        renderQueueSync {
            var needsRecreate = false
            
            if let description = formatDescription {
                let currentDimensions = CMVideoFormatDescriptionGetDimensions(description)
                let currentPixelFormat = CMFormatDescriptionGetMediaSubType(description)
                
                if currentDimensions.width != width ||
                    currentDimensions.height != height ||
                    currentPixelFormat != pixelFormat {
                    needsRecreate = true
                }
            } else {
                needsRecreate = true
            }
            
            if needsRecreate {
                var newDescription: CMVideoFormatDescription?
                
                let status = CMVideoFormatDescriptionCreateForImageBuffer(
                    allocator: kCFAllocatorDefault,
                    imageBuffer: buffer,
                    formatDescriptionOut: &newDescription
                )
                
                if status == noErr, let newDescription = newDescription {
                    formatDescription = newDescription
                    didChange = true
                    Logger.shared.log("Created new format description: \(width)x\(height), format: \(pixelFormat)", type: "Info")
                } else {
                    Logger.shared.log("Failed to create format description (status: \(status))", type: "Error")
                }
            }
        }
        return didChange
    }
    
    private func renderQueueSync(_ block: () -> Void) {
        if DispatchQueue.getSpecific(key: renderQueueKey) != nil {
            block()
        } else {
            renderQueue.sync(execute: block)
        }
    }
    
    private func currentVideoSize() -> CGSize {
        stateQueue.sync {
            videoSize
        }
    }
    
    private func updateVideoSize(width: Int, height: Int) {
        let size = CGSize(width: max(width, 0), height: max(height, 0))
        stateQueue.async(flags: .barrier) {
            self.videoSize = size
        }
        renderQueue.async { [weak self] in
            guard let self else { return }
            
            if self.poolWidth != width || self.poolHeight != height {
                self.recreatePixelBufferPool(width: max(width, 0), height: max(height, 0))
            }
        }
    }
    
    private func apply(commands: [[String]], on handle: OpaquePointer) {
        for command in commands {
            guard !command.isEmpty else { continue }
            self.command(handle, command)
        }
    }
    
    private func command(_ handle: OpaquePointer, _ args: [String]) {
        guard !args.isEmpty else { return }
        _ = withCStringArray(args) { pointer in
            mpv_command_async(handle, 0, pointer)
        }
    }

    @discardableResult
    private func commandSync(_ handle: OpaquePointer, _ args: [String]) -> Int32 {
        guard !args.isEmpty else { return 0 }
        return withCStringArray(args) { pointer in
            mpv_command(handle, pointer)
        }
    }
    
    private func processEvents() {
        eventQueueGroup.enter()
        let group = eventQueueGroup
        eventQueue.async { [weak self] in
            defer { group.leave() }
            guard let self else { return }
            while !self.isStopping {
                guard let handle = self.mpv else { return }
                guard let eventPointer = mpv_wait_event(handle, 0) else { return }
                let event = eventPointer.pointee
                if event.event_id == MPV_EVENT_NONE { continue }
                self.handleEvent(event)
                if event.event_id == MPV_EVENT_SHUTDOWN { break }
            }
        }
    }
    
    private func handleEvent(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_VIDEO_RECONFIG:
            refreshVideoState()
        case MPV_EVENT_FILE_LOADED:
            if !isReadyToSeek {
                isReadyToSeek = true
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.renderer(self, didBecomeReadyToSeek: true)
                }
            }
        case MPV_EVENT_PROPERTY_CHANGE:
            if let property = event.data?.assumingMemoryBound(to: mpv_event_property.self).pointee.name {
                let name = String(cString: property)
                refreshProperty(named: name)
            }
        case MPV_EVENT_SHUTDOWN:
            Logger.shared.log("mpv shutdown", type: "Warn")
        case MPV_EVENT_LOG_MESSAGE:
            if let logMessagePointer = event.data?.assumingMemoryBound(to: mpv_event_log_message.self) {
                let component = String(cString: logMessagePointer.pointee.prefix)
                let text = String(cString: logMessagePointer.pointee.text)
                let lower = text.lowercased()
                
                // Filter out specific known non-critical filter messages
                if (lower.contains("dynaudnorm") || lower.contains("loudnorm")) && lower.contains("error") {
                    // Skip these specific filter errors - they're expected if not available
                    break
                }
                
                if lower.contains("error") {
                    Logger.shared.log("mpv[\(component)] \(text)", type: "Error")
                } else if lower.contains("warn") || lower.contains("warning") || lower.contains("deprecated") {
                    Logger.shared.log("mpv[\(component)] \(text)", type: "Warn")
                }
            }
        default:
            break
        }
    }
    
    private func refreshVideoState() {
        guard let handle = mpv else { return }
        var width: Int64 = 0
        var height: Int64 = 0
        getProperty(handle: handle, name: "dwidth", format: MPV_FORMAT_INT64, value: &width)
        getProperty(handle: handle, name: "dheight", format: MPV_FORMAT_INT64, value: &height)
        updateVideoSize(width: Int(width), height: Int(height))
    }
    
    private func refreshProperty(named name: String) {
        guard let handle = mpv else { return }
        switch name {
        case "duration":
            var value = Double(0)
            let status = getProperty(handle: handle, name: name, format: MPV_FORMAT_DOUBLE, value: &value)
            if status >= 0 {
                cachedDuration = value
                delegate?.renderer(self, didUpdatePosition: cachedPosition, duration: cachedDuration)
            }
        case "time-pos":
            var value = Double(0)
            let status = getProperty(handle: handle, name: name, format: MPV_FORMAT_DOUBLE, value: &value)
            if status >= 0 {
                cachedPosition = value
                delegate?.renderer(self, didUpdatePosition: cachedPosition, duration: cachedDuration)
            }
        case "pause":
            var flag: Int32 = 0
            let status = getProperty(handle: handle, name: name, format: MPV_FORMAT_FLAG, value: &flag)
            if status >= 0 {
                let newPaused = flag != 0
            } else {
            case "sub-text":
                // Extract embedded subtitle text for manual rendering
                if let text = getStringProperty(handle: handle, name: "sub-text"), !text.isEmpty {
                    currentEmbeddedSubtitleText = text
                } else {
                    currentEmbeddedSubtitleText = nil
                }
                // Force subtitle refresh for back-to-back dialogue
                subtitleRenderCache = nil
                cachedSubtitleText = nil
                lastSubtitleCheckTime = -1.0
                Logger.shared.log("Failed to read sid property (status=\(status))", type: "Warn")
            }
        case "sub-visibility":
            var flag: Int32 = 0
            let status = getProperty(handle: handle, name: name, format: MPV_FORMAT_FLAG, value: &flag)
            if status >= 0 {
                Logger.shared.log("MPV property change: sub-visibility=\(flag)", type: "Info")
            } else {
                Logger.shared.log("Failed to read sub-visibility (status=\(status))", type: "Warn")
            }
        case "sub-text":
            // Extract embedded subtitle text for manual rendering
            if let text = getStringProperty(handle: handle, name: "sub-text"), !text.isEmpty {
                currentEmbeddedSubtitleText = text
            } else {
                currentEmbeddedSubtitleText = nil
            }
            // Force subtitle refresh for back-to-back dialogue
            subtitleRenderCache = nil
            cachedSubtitleText = nil
            lastSubtitleCheckTime = -1.0
            forceSubtitleRender = true
            scheduleRender()
        case "track-list":
            delegate?.rendererDidChangeTracks(self)
        default:
            break
        }
    }
    
    private func getStringProperty(handle: OpaquePointer, name: String) -> String? {
        var result: String?
        name.withCString { pointer in
            if let cString = mpv_get_property_string(handle, pointer) {
                result = String(cString: cString)
                mpv_free(cString)
            }
        }
        return result
    }
    
    @discardableResult
    private func getProperty<T>(handle: OpaquePointer, name: String, format: mpv_format, value: inout T) -> Int32 {
        return name.withCString { pointer in
            return withUnsafeMutablePointer(to: &value) { mutablePointer in
                return mpv_get_property(handle, pointer, format, mutablePointer)
            }
        }
    }
    
    private func createAttributedString(from text: String, style: SubtitleStyle) -> NSAttributedString {
        // Strip ASS tags for simple rendering
        let cleanText = stripASSTags(from: text)
        
        let font = UIFont(name: "Helvetica Neue", size: style.fontSize) ?? UIFont.systemFont(ofSize: style.fontSize, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: style.foregroundColor,
            .strokeColor: style.strokeColor,
            .strokeWidth: -style.strokeWidth
        ]
        
        return NSAttributedString(string: cleanText, attributes: attributes)
    }
    
    private func stripASSTags(from text: String) -> String {
        // Remove ASS override codes like {\tags}
        var result = text
        while let start = result.range(of: "{"), let end = result.range(of: "}", range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound..<end.upperBound)
        }
        // Convert ASS line breaks (\N) to actual newlines
        result = result.replacingOccurrences(of: "\\N", with: "\n")
        result = result.replacingOccurrences(of: "\\n", with: "\n")
        // Clean up any remaining whitespace
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    @inline(__always)
    private func withCStringArray<R>(_ args: [String], body: (UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> R) -> R {
        var cStrings = [UnsafeMutablePointer<CChar>?]()
        cStrings.reserveCapacity(args.count + 1)
        for s in args {
            cStrings.append(strdup(s))
        }
        cStrings.append(nil)
        defer {
            for ptr in cStrings where ptr != nil {
                free(ptr)
            }
        }
        
        return cStrings.withUnsafeMutableBufferPointer { buffer in
            return buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) { rebound in
                return body(UnsafeMutablePointer(mutating: rebound))
            }
        }
    }
    
    // MARK: - Playback Controls
    func play() {
        setProperty(name: "pause", value: "no")
    }
    
    func pausePlayback() {
        setProperty(name: "pause", value: "yes")
    }
    
    func togglePause() {
        if isPaused { play() } else { pausePlayback() }
    }
    
    func seek(to seconds: Double) {
        guard let handle = mpv else { return }
        let clamped = max(0, seconds)
        command(handle, ["seek", String(clamped), "absolute"])
    }
    
    func seek(by seconds: Double) {
        guard let handle = mpv else { return }
        command(handle, ["seek", String(seconds), "relative"])
    }
    
    func setSpeed(_ speed: Double) {
        setProperty(name: "speed", value: String(speed))
    }
    
    func getSpeed() -> Double {
        guard let handle = mpv else { return 1.0 }
        var speed: Double = 1.0
        getProperty(handle: handle, name: "speed", format: MPV_FORMAT_DOUBLE, value: &speed)
        return speed
    }
    
    // MARK: - Audio Track Controls
    func getAudioTracksDetailed() -> [(Int, String, String)] {
        guard let handle = mpv else { return [] }
        
        var result: [(Int, String, String)] = []
        var trackNumber = 1  // For user-friendly numbering
        
        var node = mpv_node()
        let status = mpv_get_property(handle, "track-list", MPV_FORMAT_NODE, &node)
        guard status >= 0 else { 
            Logger.shared.log("Failed to get track-list: status=\(status)", type: "Debug")
            return [] 
        }
        
        defer { mpv_free_node_contents(&node) }
        
        guard node.format == MPV_FORMAT_NODE_ARRAY else { 
            Logger.shared.log("Track-list not in array format: \(node.format)", type: "Debug")
            return [] 
        }
        
        let count = Int(node.u.list?.pointee.num ?? 0)
        Logger.shared.log("Total tracks in stream: \(count)", type: "Debug")
        guard let listPtr = node.u.list?.pointee.values else { return [] }
        
        for i in 0..<count {
            let trackNode = listPtr[i]
            guard trackNode.format == MPV_FORMAT_NODE_MAP else { continue }
            
            var trackId: Int = -1
            var trackType: String = ""
            var trackLang: String = ""
            var trackTitle: String = ""
            var trackCodec: String = ""
            var trackChannels: String = ""
            
            let mapCount = Int(trackNode.u.list?.pointee.num ?? 0)
            guard let keysPtr = trackNode.u.list?.pointee.keys,
                  let valuesPtr = trackNode.u.list?.pointee.values else { continue }
            
            for j in 0..<mapCount {
                if let keyStr = keysPtr[j], let key = String(cString: keyStr, encoding: .utf8) {
                    let value = valuesPtr[j]
                    
                    if key == "id", value.format == MPV_FORMAT_INT64 {
                        trackId = Int(value.u.int64)
                    } else if key == "type", value.format == MPV_FORMAT_STRING,
                              let typeStr = value.u.string.map({ String(cString: $0) }) {
                        trackType = typeStr
                    } else if key == "lang", value.format == MPV_FORMAT_STRING,
                              let langStr = value.u.string.map({ String(cString: $0) }) {
                        trackLang = langStr
                    } else if key == "title", value.format == MPV_FORMAT_STRING,
                              let titleStr = value.u.string.map({ String(cString: $0) }) {
                        trackTitle = titleStr
                    } else if key == "codec", value.format == MPV_FORMAT_STRING,
                              let codecStr = value.u.string.map({ String(cString: $0) }) {
                        trackCodec = codecStr
                    } else if key == "audio-channels", value.format == MPV_FORMAT_STRING,
                              let channelsStr = value.u.string.map({ String(cString: $0) }) {
                        trackChannels = channelsStr
                    }
                }
            }
            
            // Log all tracks, not just audio
            Logger.shared.log("Track[\(i)]: type=\(trackType), id=\(trackId), title='\(trackTitle)', lang='\(trackLang)', codec='\(trackCodec)'", type: "Debug")
            
            if trackType == "audio" && trackId >= 0 {
                let displayName: String
                if !trackTitle.isEmpty {
                    displayName = trackTitle
                } else if !trackLang.isEmpty {
                    // Convert ISO 639-3 language codes to full names
                    let langName = languageCodeToName(trackLang)
                    displayName = langName
                } else {
                    // Use numbered audio track with codec if available
                    if !trackCodec.isEmpty {
                        displayName = "Audio Track \(trackNumber) (\(trackCodec.uppercased()))"
                    } else {
                        displayName = "Audio Track \(trackNumber)"
                    }
                }
                
                // Only add if it's unique - skip duplicates based on display name
                // (duplicates occur when HLS streams include identical audio tracks for each video quality variant)
                let isDuplicate = result.contains { existingTrack in
                    existingTrack.1 == displayName
                }
                
                if !isDuplicate {
                    Logger.shared.log("Added audio track: ID=\(trackId), Display='\(displayName)'", type: "Debug")
                    result.append((trackId, displayName, trackLang))
                    trackNumber += 1
                } else {
                    Logger.shared.log("Skipped duplicate audio track: ID=\(trackId), Display='\(displayName)'", type: "Debug")
                }
            }
        }
        
        Logger.shared.log("getAudioTracks returning \(result.count) tracks", type: "Debug")
        return result
    }

    func getAudioTracks() -> [(Int, String)] {
        return getAudioTracksDetailed().map { ($0.0, $0.1) }
    }
    
    private func languageCodeToName(_ code: String) -> String {
        let languageMap: [String: String] = [
            "eng": "English",
            "jpn": "Japanese",
            "chi": "Chinese",
            "zho": "Chinese",
            "kor": "Korean",
            "fra": "French",
            "deu": "German",
            "ita": "Italian",
            "spa": "Spanish",
            "por": "Portuguese",
            "rus": "Russian",
            "tha": "Thai",
            "ara": "Arabic",
            "hin": "Hindi",
            "pus": "Pashto",
            "tur": "Turkish",
            "pol": "Polish",
            "dut": "Dutch",
            "nld": "Dutch",
            "swe": "Swedish",
            "nor": "Norwegian",
            "dan": "Danish",
            "fin": "Finnish",
            "ces": "Czech",
            "ron": "Romanian",
            "hun": "Hungarian",
            "ell": "Greek",
            "heb": "Hebrew",
            "urd": "Urdu",
            "ben": "Bengali",
            "tam": "Tamil",
            "tel": "Telugu",
            "kan": "Kannada",
            "mal": "Malayalam",
            "mya": "Burmese",
            "khm": "Khmer",
            "lao": "Lao",
            "vie": "Vietnamese",
            "ind": "Indonesian",
            "msa": "Malay",
            "fil": "Filipino",
            "cat": "Catalan",
            "eus": "Basque",
            "glg": "Galician",
            "isl": "Icelandic",
            "bul": "Bulgarian",
            "hrv": "Croatian",
            "srp": "Serbian",
            "slk": "Slovak",
            "slv": "Slovenian",
            "ukr": "Ukrainian",
            "bel": "Belarusian"
        ]
        
        return languageMap[code.lowercased()] ?? code.uppercased()
    }
    
    func setAudioTrack(id: Int) {
        setProperty(name: "aid", value: String(id))
    }
    
    // MARK: - Subtitle Track Controls
    func getSubtitleTracks() -> [(Int, String)] {
        guard let handle = mpv else { return [] }
        
        var result: [(Int, String)] = []
        
        var node = mpv_node()
        let status = mpv_get_property(handle, "track-list", MPV_FORMAT_NODE, &node)
        guard status >= 0 else { return [] }
        
        defer { mpv_free_node_contents(&node) }
        
        guard node.format == MPV_FORMAT_NODE_ARRAY else { return [] }
        
        let count = Int(node.u.list?.pointee.num ?? 0)
        guard let listPtr = node.u.list?.pointee.values else { return [] }
        
        for i in 0..<count {
            let trackNode = listPtr[i]
            guard trackNode.format == MPV_FORMAT_NODE_MAP else { continue }
            
            var trackId: Int = -1
            var trackType: String = ""
            var trackLang: String = ""
            var trackTitle: String = ""
            
            let mapCount = Int(trackNode.u.list?.pointee.num ?? 0)
            guard let keysPtr = trackNode.u.list?.pointee.keys,
                  let valuesPtr = trackNode.u.list?.pointee.values else { continue }
            
            for j in 0..<mapCount {
                if let keyStr = keysPtr[j], let key = String(cString: keyStr, encoding: .utf8) {
                    let value = valuesPtr[j]
                    
                    if key == "id", value.format == MPV_FORMAT_INT64 {
                        trackId = Int(value.u.int64)
                    } else if key == "type", value.format == MPV_FORMAT_STRING,
                              let typeStr = value.u.string.map({ String(cString: $0) }) {
                        trackType = typeStr
                    } else if key == "lang", value.format == MPV_FORMAT_STRING,
                              let langStr = value.u.string.map({ String(cString: $0) }) {
                        trackLang = langStr
                    } else if key == "title", value.format == MPV_FORMAT_STRING,
                              let titleStr = value.u.string.map({ String(cString: $0) }) {
                        trackTitle = titleStr
                    }
                }
            }
            
            if trackType == "sub" && trackId >= 0 {
                let displayName: String
                if !trackTitle.isEmpty {
                    displayName = trackTitle
                } else if !trackLang.isEmpty {
                    // Convert ISO 639-3 language codes to full names
                    let langName = languageCodeToName(trackLang)
                    displayName = langName
                } else {
                    displayName = "Subtitle Track \(trackId)"
                }
                result.append((trackId, displayName))
            }
        }
        
        return result
    }
    
    func setSubtitleTrack(id: Int) {
        Logger.shared.log("MPVSoftwareRenderer: Setting subtitle track to ID \(id)", type: "Info")
        renderQueue.async { [weak self] in
            guard let self, let handle = self.mpv else { return }

            // Set subtitle track and enable visibility
            let sidStatus = self.commandSync(handle, ["set", "sid", String(id)])
            let visStatus = self.commandSync(handle, ["set", "sub-visibility", "yes"])

            // Fallback to property set if command failed
            if sidStatus < 0 {
                _ = self.setPropertyWithStatus(name: "sid", value: String(id))
            }
            if visStatus < 0 {
                _ = self.setPropertyWithStatus(name: "sub-visibility", value: "yes")
            }

            // Read back sid to verify
            var readSid: Int64 = -1
            let readStatus = self.getProperty(handle: handle, name: "sid", format: MPV_FORMAT_INT64, value: &readSid)
            Logger.shared.log("MPVSoftwareRenderer: subtitle track set - id=\(id) sidStatus=\(sidStatus) visStatus=\(visStatus) readSid=\(readSid)", type: "Info")

            // Fallback to first track if requested track failed
            if readStatus < 0 || readSid != Int64(id) {
                let tracks = self.getSubtitleTracks()
                if let first = tracks.first {
                    Logger.shared.log("MPVSoftwareRenderer: fallback to first subtitle track id=\(first.0)", type: "Warn")
                    _ = self.commandSync(handle, ["set", "sid", String(first.0)])
                    _ = self.commandSync(handle, ["set", "sub-visibility", "yes"])
                    readSid = Int64(first.0)
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.renderer(self, subtitleTrackDidChange: Int(readSid >= 0 ? readSid : Int64(id)))
            }
        }
    }
    
    func disableSubtitles() {
        Logger.shared.log("MPVSoftwareRenderer: Disabling subtitles", type: "Info")
        if Thread.isMainThread {
            setProperty(name: "sid", value: "no")
            setProperty(name: "sub-visibility", value: "no")
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.setProperty(name: "sid", value: "no")
                self?.setProperty(name: "sub-visibility", value: "no")
            }
        }
    }

    // Clear cached subtitle render state so newly loaded external subtitles appear immediately
    func refreshSubtitleOverlay() {
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.subtitleRenderCache = nil
            self.cachedSubtitleText = nil
            self.lastSubtitleCheckTime = -1.0
            self.forceSubtitleRender = true
            // Force immediate subtitle check on next render
            self.scheduleRender()
        }
    }
    
    // MARK: - Metal GPU Subtitle Rendering
    
    private func setupMetalPipeline() {
        guard let device = metalDevice else {
            Logger.shared.log("Metal device not available, falling back to CPU rendering", type: "Warn")
            return
        }
        
        metalCommandQueue = device.makeCommandQueue()
        
        // Create render pipeline for subtitle composition
        guard let library = device.makeDefaultLibrary() else {
            Logger.shared.log("Failed to load Metal library with shaders", type: "Error")
            return
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertexShader")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragmentShader")
        
        guard pipelineDescriptor.vertexFunction != nil, pipelineDescriptor.fragmentFunction != nil else {
            Logger.shared.log("Failed to load Metal shader functions", type: "Error")
            return
        }
        
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        do {
            metalPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            Logger.shared.log("Failed to create Metal pipeline: \(error)", type: "Error")
        }
        
        // Create sampler state for texture filtering
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.mipFilter = .linear
        metalSamplerState = device.makeSamplerState(descriptor: samplerDescriptor)
    }
    
    private func renderSubtitleWithMetal(cgImage: CGImage, into pixelBuffer: CVPixelBuffer, style: SubtitleStyle) {
        guard let metalDevice = metalDevice,
              let commandQueue = metalCommandQueue,
              let pipelineState = metalPipelineState,
              let samplerState = metalSamplerState else {
            // Fallback to CPU rendering if Metal not available
            renderSubtitleWithCPU(cgImage: cgImage, into: pixelBuffer, style: style)
            return
        }
        
        let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
        let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
        
        guard bufferWidth > 0, bufferHeight > 0 else { return }
        
        // Create Metal texture from subtitle CGImage
        let ciImage = CIImage(cgImage: cgImage)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let metalTexture = createMetalTextureFromCIImage(ciImage, device: metalDevice, colorSpace: colorSpace) else {
            // Fallback to CPU rendering
            renderSubtitleWithCPU(cgImage: cgImage, into: pixelBuffer, style: style)
            return
        }
        
        // Create Metal texture for pixel buffer
        var pixelBufferTexture: MTLTexture?
        var textureCache: CVMetalTextureCache?
        let cacheStatus = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice, nil, &textureCache)
        
        guard cacheStatus == kCVReturnSuccess, let cache = textureCache else {
            renderSubtitleWithCPU(cgImage: cgImage, into: pixelBuffer, style: style)
            return
        }
        
        var metalTextureRef: CVMetalTexture?
        let texStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            bufferWidth,
            bufferHeight,
            0,
            &metalTextureRef
        )
        
        if texStatus == kCVReturnSuccess, let metalTextureRef = metalTextureRef {
            pixelBufferTexture = CVMetalTextureGetTexture(metalTextureRef)
        }
        
        guard let renderTexture = pixelBufferTexture else {
            // Fallback to CPU rendering
            renderSubtitleWithCPU(cgImage: cgImage, into: pixelBuffer, style: style)
            return
        }
        
        // Create command buffer and render encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: createRenderPassDescriptor(texture: renderTexture)
              ) else {
            return
        }
        
        // Ensure rendering covers the full pixel buffer
        renderEncoder.setViewport(MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(bufferWidth),
            height: Double(bufferHeight),
            znear: 0,
            zfar: 1
        ))
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFragmentTexture(metalTexture, index: 0)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        
        // Draw quad covering subtitle area
        drawSubtitleQuad(encoder: renderEncoder)
        
        renderEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    private func createMetalTextureFromCIImage(_ ciImage: CIImage, device: MTLDevice, colorSpace: CGColorSpace) -> MTLTexture? {
        let ciContext = CIContext(mtlDevice: device)
        
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        let textureLoader = MTKTextureLoader(device: device)
        do {
            return try textureLoader.newTexture(cgImage: cgImage, options: [:])
        } catch {
            Logger.shared.log("Failed to create Metal texture: \(error)", type: "Error")
            return nil
        }
    }
    
    private func createRenderPassDescriptor(texture: MTLTexture) -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .load
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        return descriptor
    }
    
    private func drawSubtitleQuad(encoder: MTLRenderCommandEncoder) {
        let vertices: [Float] = [
            -1.0, -1.0, 0.0, 1.0, 0.0, 1.0,
             1.0, -1.0, 0.0, 1.0, 1.0, 1.0,
            -1.0,  1.0, 0.0, 1.0, 0.0, 0.0,
             1.0,  1.0, 0.0, 1.0, 1.0, 0.0
        ]
        
        guard let device = metalDevice else { return }
        guard let vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.size, options: []) else { return }
        
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
    
    private func renderSubtitleWithCPU(cgImage: CGImage, into pixelBuffer: CVPixelBuffer, style: SubtitleStyle) {
        let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
        let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: bufferWidth,
            height: bufferHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: cachedColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return
        }
        
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let bottomMargin = max(CGFloat(bufferHeight) * 0.08, style.fontSize * 1.4)
        let horizontalMargin = max(CGFloat(bufferWidth) * 0.02, style.fontSize * 0.8)
        let availableWidth = max(CGFloat(bufferWidth) - horizontalMargin * 2.0, 1.0)
        let scale = min(1.0, availableWidth / imageSize.width)
        
        let renderWidth = imageSize.width * scale
        let renderHeight = imageSize.height * scale
        
        var xPosition = (CGFloat(bufferWidth) - renderWidth) / 2.0
        if xPosition < horizontalMargin {
            xPosition = horizontalMargin
        }
        if xPosition + renderWidth > CGFloat(bufferWidth) - horizontalMargin {
            xPosition = max(horizontalMargin, CGFloat(bufferWidth) - horizontalMargin - renderWidth)
        }
        
        let yPosition = CGFloat(bufferHeight) - renderHeight - bottomMargin
        let renderRect = CGRect(x: xPosition, y: yPosition, width: renderWidth, height: renderHeight)
        
        context.draw(cgImage, in: renderRect)
    }
}

