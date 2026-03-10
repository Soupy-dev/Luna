//
//  KanzenRunnerController.swift
//  Kanzen
//
//  Created by Dawud Osman on 12/05/2025.
//
import Foundation
import JavaScriptCore

class KanzenRunnerController {
    private let moduleRunner: KanzenModuleRunner
    init(moduleRunner: KanzenModuleRunner) {
        self.moduleRunner = moduleRunner
    }
    
    func loadScript(_script: String) throws
    {
        try moduleRunner.loadScript(_script)
    }
    
    func extractImages(params:Any,completion: @escaping ([String]?) -> Void)
    {
        moduleRunner.extractImages(params: params)
        {
            jsResult, error in
            guard let result = jsResult?.toArray() as? [String] else {
                completion(nil)
                return
            }
            completion(result)
        }
    }
    
    func extractChapters(params:Any, completion: @escaping (Any?) -> Void )
    {
        Logger.shared.log("RunnerController.extractChapters: called with params=\(params)", type: "Debug")
        moduleRunner.extractChapters(params: params){
            jsResult, error in
            if let error = error {
                Logger.shared.log("RunnerController.extractChapters: JS error: \(error.localizedDescription)", type: "Error")
                completion(nil)
                return
            }
            guard let jsResult = jsResult else {
                Logger.shared.log("RunnerController.extractChapters: jsResult is nil", type: "Error")
                completion(nil)
                return
            }
            Logger.shared.log("RunnerController.extractChapters: jsResult isArray=\(jsResult.isArray), isObject=\(jsResult.isObject), isString=\(jsResult.isString), isUndefined=\(jsResult.isUndefined), isNull=\(jsResult.isNull)", type: "Debug")
            // Try dictionary first (Kanzen format: {language: [[name, [data...]]]})
            if let result = jsResult.toDictionary() as? [String:Any] {
                Logger.shared.log("RunnerController.extractChapters: parsed as dictionary with \(result.count) keys: \(Array(result.keys))", type: "Debug")
                completion(result)
                return
            }
            Logger.shared.log("RunnerController.extractChapters: toDictionary failed, trying toArray", type: "Debug")
            // Try array (Sora format: [{number, title, href}, ...])
            if let result = jsResult.toArray() as? [[String:Any]] {
                Logger.shared.log("RunnerController.extractChapters: parsed as array with \(result.count) elements", type: "Debug")
                if let first = result.first {
                    Logger.shared.log("RunnerController.extractChapters: first element keys: \(Array(first.keys))", type: "Debug")
                }
                completion(result)
                return
            }
            Logger.shared.log("RunnerController.extractChapters: toArray failed, trying JSON string", type: "Debug")
            // Try JSON string fallback
            if let jsonString = jsResult.toString() {
                Logger.shared.log("RunnerController.extractChapters: toString preview: \(jsonString.prefix(300))", type: "Debug")
                if let data = jsonString.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data) {
                    Logger.shared.log("RunnerController.extractChapters: JSON parse succeeded, type=\(type(of: parsed))", type: "Debug")
                    completion(parsed)
                    return
                }
            }
            Logger.shared.log("RunnerController.extractChapters: all parsing failed, returning nil", type: "Error")
            completion(nil)
        }
    }
    
    func extractDetails(params:Any, completion: @escaping ([String:Any]?)-> Void)
    {
       
        moduleRunner.extractDetails(params: params)
        {
            jsResult, error in
            guard let result = jsResult?.toDictionary() as? [String:Any] else
            {
                completion(nil)
                return
            }
            completion(result)
        }
    }
    
    func extractText(params:Any, completion: @escaping (String?) -> Void)
    {
        Logger.shared.log("RunnerController.extractText: called with params type=\(type(of: params)), value=\(params)", type: "Debug")
        moduleRunner.extractText(params: params)
        {
            jsResult, error in
            if let error = error {
                Logger.shared.log("RunnerController.extractText: error: \(error.localizedDescription)", type: "Error")
                completion(nil)
                return
            }
            guard let jsResult = jsResult else {
                Logger.shared.log("RunnerController.extractText: jsResult is nil", type: "Error")
                completion(nil)
                return
            }
            Logger.shared.log("RunnerController.extractText: isString=\(jsResult.isString), isUndefined=\(jsResult.isUndefined), isNull=\(jsResult.isNull)", type: "Debug")
            guard let result = jsResult.toString() else {
                Logger.shared.log("RunnerController.extractText: toString returned nil", type: "Error")
                completion(nil)
                return
            }
            let preview = result.prefix(200)
            Logger.shared.log("RunnerController.extractText: result length=\(result.count), preview=\(preview)", type: "Debug")
            completion(result)
        }
    }
    
    func searchInput(_input: String,page:Int = 0, completion: @escaping ([[String:Any]]?) -> Void)
    {
        moduleRunner.searchResults(input: _input,page: page)
        {
            jsResult,error in
            guard let result = jsResult?.toArray() as? [[String:Any]] else {
                completion(nil)
                return
            }
            completion(result)
            
        }
    }
}
