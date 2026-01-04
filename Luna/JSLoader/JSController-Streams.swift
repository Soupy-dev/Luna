//
//  JSLoader-Streams.swift
//  Sora
//
//  Created by Francesco on 07/08/25.
//

import JavaScriptCore

extension JSController {
    func fetchStreamUrlJS(episodeUrl: String, softsub: Bool = false, module: Service, completion: @escaping ((streams: [String]?, subtitles: [String]?,sources: [[String:Any]]? )) -> Void) {
        if let exception = context.exception {
            Logger.shared.log("JavaScript exception: \(exception)", type: "Error")
            completion((nil, nil,nil))
            return
        }
        
        guard let extractStreamUrlFunction = context.objectForKeyedSubscript("extractStreamUrl") else {
            Logger.shared.log("No JavaScript function extractStreamUrl found", type: "Error")
            completion((nil, nil,nil))
            return
        }
        
        let promiseValue = extractStreamUrlFunction.call(withArguments: [episodeUrl])
        guard let promise = promiseValue else {
            Logger.shared.log("extractStreamUrl did not return a Promise", type: "Error")
            completion((nil, nil,nil))
            return
        }
        
        let thenBlock: @convention(block) (JSValue) -> Void = { [weak self] result in
            guard self != nil else { return }
            
            if result.isNull || result.isUndefined {
                Logger.shared.log("Received null or undefined result from JavaScript", type: "Error")
                DispatchQueue.main.async { completion((nil, nil, nil)) }
                return
            }
            
            if let resultString = result.toString(), resultString == "[object Promise]" {
                Logger.shared.log("Received Promise object instead of resolved value, waiting for proper resolution", type: "Stream")
                return
            }
            
            guard let jsonString = result.toString() else {
                Logger.shared.log("Failed to convert JSValue to string", type: "Error")
                DispatchQueue.main.async { completion((nil, nil, nil)) }
                return
            }
            
            guard let data = jsonString.data(using: .utf8) else {
                Logger.shared.log("Failed to convert string to data", type: "Error")
                DispatchQueue.main.async { completion((nil, nil, nil)) }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    var streamUrls: [String]? = nil
                    var subtitleUrls: [String]? = nil
                    var streamUrlsAndHeaders : [[String:Any]]? = nil
                    var collectedSubtitleUrls: [String] = []

                    func appendSubtitles(from value: Any?) {
                        if let subsArray = value as? [Any] {
                            for item in subsArray {
                                if let s = item as? String {
                                    collectedSubtitleUrls.append(s)
                                } else if let dict = item as? [String: Any] {
                                    if let url = dict["url"] as? String {
                                        collectedSubtitleUrls.append(url)
                                    } else if let file = dict["file"] as? String {
                                        collectedSubtitleUrls.append(file)
                                    }
                                }
                            }
                        } else if let subString = value as? String {
                            collectedSubtitleUrls.append(subString)
                        }
                    }

                    if let streamSources = json["streams"] as? [[String:Any]] {
                        streamUrlsAndHeaders = streamSources
                        Logger.shared.log("Found \(streamSources.count) streams and headers", type: "Stream")
                        for source in streamSources {
                            appendSubtitles(from: source["subtitles"])
                            appendSubtitles(from: source["subtitle"])
                        }
                    } else if let streamSource = json["stream"] as? [String:Any] {
                        streamUrlsAndHeaders = [streamSource]
                        Logger.shared.log("Found single stream with headers", type: "Stream")
                        appendSubtitles(from: streamSource["subtitles"])
                        appendSubtitles(from: streamSource["subtitle"])
                    } else if let streamsArray = json["streams"] as? [String] {
                        streamUrls = streamsArray
                        Logger.shared.log("Found \(streamsArray.count) streams", type: "Stream")
                    } else if let streamUrl = json["stream"] as? String {
                        streamUrls = [streamUrl]
                        Logger.shared.log("Found single stream", type: "Stream")
                    }

                    appendSubtitles(from: json["subtitles"])

                    if !collectedSubtitleUrls.isEmpty {
                        let uniqueSubs = Array(Set(collectedSubtitleUrls))
                        subtitleUrls = uniqueSubs
                        Logger.shared.log("Collected \(uniqueSubs.count) subtitle tracks (including per-stream)", type: "Stream")
                    }

                    Logger.shared.log("Starting stream with \(streamUrls?.count ?? 0) sources and \(subtitleUrls?.count ?? 0) subtitles", type: "Stream")
                    DispatchQueue.main.async {
                        completion((streamUrls, subtitleUrls, streamUrlsAndHeaders))
                    }
                    return
                }
                
                if let streamsArray = try JSONSerialization.jsonObject(with: data, options: []) as? [String] {
                    Logger.shared.log("Starting multi-stream with \(streamsArray.count) sources", type: "Stream")
                    DispatchQueue.main.async { completion((streamsArray, nil, nil)) }
                    return
                }
            } catch {
                Logger.shared.log("JSON parsing error: \(error.localizedDescription)", type: "Error")
            }
            
            // Validate the URL string - don't treat error strings as valid URLs
            if jsonString.lowercased() == "error" || jsonString.lowercased() == "undefined" || jsonString.isEmpty {
                Logger.shared.log("Received invalid stream response: \(jsonString)", type: "Error")
                DispatchQueue.main.async {
                    completion((nil, nil, nil))
                }
                return
            }
            
            // Check if the string is a valid URL format
            if !jsonString.hasPrefix("http://") && !jsonString.hasPrefix("https://") && !jsonString.hasPrefix("blob:") {
                Logger.shared.log("Invalid stream URL format: \(jsonString)", type: "Error")
                DispatchQueue.main.async {
                    completion((nil, nil, nil))
                }
                return
            }
            
            Logger.shared.log("Starting stream from: \(jsonString)", type: "Stream")
            DispatchQueue.main.async {
                completion(([jsonString], nil, nil))
            }
        }
        
        let catchBlock: @convention(block) (JSValue) -> Void = { error in
            let errorMessage = error.toString() ?? "Unknown JavaScript error"
            Logger.shared.log("Promise rejected: \(errorMessage)", type: "Error")
            DispatchQueue.main.async {
                completion((nil, nil, nil))
            }
        }
        
        let thenFunction = JSValue(object: thenBlock, in: context)
        let catchFunction = JSValue(object: catchBlock, in: context)
        
        guard let thenFunction = thenFunction, let catchFunction = catchFunction else {
            Logger.shared.log("Failed to create JSValue objects for Promise handling", type: "Error")
            completion((nil, nil, nil))
            return
        }
        
        promise.invokeMethod("then", withArguments: [thenFunction])
        promise.invokeMethod("catch", withArguments: [catchFunction])
    }
}
