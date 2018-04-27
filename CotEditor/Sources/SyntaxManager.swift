//
//  SyntaxManager.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by nakamuxu on 2004-12-24.
//
//  ---------------------------------------------------------------------------
//
//  © 2004-2007 nakamuxu
//  © 2014-2018 1024jp
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import YAML

@objc protocol SyntaxHolder: class {
    
    func changeSyntaxStyle(_ sender: Any?)
    func recolorAll(_ sender: Any?)
}


enum BundledStyleName {
    
    static let none: SyntaxManager.SettingName = NSLocalizedString("None", comment: "syntax style name")
    static let xml: SyntaxManager.SettingName = "XML"
}



// MARK: -

final class SyntaxManager: SettingFileManager {
    
    typealias Setting = SyntaxStyle
    typealias SettingName = String
    typealias StyleDictionary = [String: Any]
    
    
    // MARK: Public Properties
    
    static let shared = SyntaxManager()
    
    
    // MARK: Private Properties
    
    private var styleNames: [SettingName] = []
    
    private let bundledStyleNames: [SettingName]
    private let bundledMap: [SettingName: [String: [String]]]
    
    private var cachedSettings: [SettingName: Setting] = [:]
    
    private var mappingTables: [SyntaxKey: [String: [SettingName]]] = [.extensions: [:],
                                                                       .filenames: [:],
                                                                       .interpreters: [:]]
    
    private let propertyAccessQueue = DispatchQueue(label: "com.coteditor.CotEditor.SyntaxManager.property")  // like @synchronized(self)
    
    
    
    // MARK: -
    // MARK: Lifecycle
    
    override private init() {
        
        // load bundled style list
        let url = Bundle.main.url(forResource: "SyntaxMap", withExtension: "json")!
        let data = try! Data(contentsOf: url)
        let map = try! JSONDecoder().decode([SettingName: [String: [String]]].self, from: data)
        
        self.bundledMap = map
        self.bundledStyleNames = map.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        
        super.init()
        
        // cache user styles
        self.loadUserSettings()
    }
    
    
    
    // MARK: Setting File Manager Methods
    
    /// directory name in both Application Support and bundled Resources
    override var directoryName: String {
        
        return "Syntaxes"
    }
    
    
    /// path extensions for user setting file
    override var filePathExtensions: [String] {
        
        return ["yaml", "yml"]
    }
    
    
    /// name of setting file type
    override var settingFileType: SettingFileType {
        
        return .syntaxStyle
    }
    
    
    /// list of names of setting file name (without extension)
    override var settingNames: [SettingName] {
        
        return self.styleNames
    }
    
    
    /// list of names of setting file name which are bundled (without extension)
    override var bundledSettingNames: [SettingName] {
        
        return self.bundledStyleNames
    }
    
    
    
    // MARK: Public Methods
    
    /// return style name corresponding to given variables
    func settingName(documentFileName fileName: String, content: String) -> SettingName {
        
        return self.settingName(documentFileName: fileName)
            ?? self.settingName(documentContent: content)
            ?? BundledStyleName.none
    }
    
    
    /// return style name corresponding to file name
    func settingName(documentFileName fileName: String) -> SettingName? {
        
        let mappingTables = self.propertyAccessQueue.sync { self.mappingTables }
        
        if let styleName = mappingTables[.filenames]?[fileName]?.first {
            return styleName
        }
        
        if let pathExtension = fileName.components(separatedBy: ".").last,
            let styleName = mappingTables[.extensions]?[pathExtension]?.first {
            return styleName
        }
        
        return nil
    }
    
    
    /// return style name scanning shebang in document content
    func settingName(documentContent content: String) -> SettingName? {
        
        if let interpreter = content.scanInterpreterInShebang(),
            let styleName = self.propertyAccessQueue.sync(execute: { self.mappingTables })[.interpreters]?[interpreter]?.first {
            return styleName
        }
        
        // check XML declaration
        if content.hasPrefix("<?xml ") {
            return BundledStyleName.xml
        }
        
        return nil
    }
    
    
    /// create SyntaxStyle instance from theme name
    func setting(name: SettingName) -> Setting? {
        
        if name == BundledStyleName.none {
            return SyntaxStyle()
        }
        
        guard let style: SyntaxStyle = {
            if let cachedStyle = self.propertyAccessQueue.sync(execute: { self.cachedSettings[name] }) {
                return cachedStyle
            }
            
            guard let dictionary = self.settingDictionary(name: name) else { return nil }
            
            let style = SyntaxStyle(dictionary: dictionary, name: name)
            
            // store newly loaded style
            self.propertyAccessQueue.sync {
                self.cachedSettings[name] = style
            }
            return style
            }() else { return nil }
        
        // add to recent styles list
        let maximumRecentStyleCount = max(0, UserDefaults.standard[.maximumRecentStyleCount])
        var recentStyleNames = UserDefaults.standard[.recentStyleNames]!
        recentStyleNames.remove(name)
        recentStyleNames.insert(name, at: 0)
        recentStyleNames = Array(recentStyleNames.prefix(maximumRecentStyleCount))
        
        DispatchQueue.main.async {
            UserDefaults.standard[.recentStyleNames] = recentStyleNames  // set in the main thread in case
        }
        
        return style
    }
    
    
    /// style dictionary list corresponding to style name
    func settingDictionary(name: SettingName) -> StyleDictionary? {
        
        if name == BundledStyleName.none {
            return self.blankSettingDictionary
        }
        
        guard let url = self.urlForUsedSetting(name: name) else { return nil }
        
        return try? self.loadSettingDictionary(at: url)
    }
    
    
    /// return bundled version style dictionary or nil if not exists
    func bundledSettingDictionary(name: SettingName) -> StyleDictionary? {
        
        guard let url = self.urlForBundledSetting(name: name) else { return nil }
        
        return try? self.loadSettingDictionary(at: url)
    }
    
    
    /// import setting at passed-in URL
    override func importSetting(fileURL: URL) throws {
        
        if fileURL.pathExtension == "plist" {
            self.importLegacyStyle(fileURL: fileURL)  // ignore succession
        }
        
        try super.importSetting(fileURL: fileURL)
    }
    
    
    /// delete user’s file for the setting name
    override func removeSetting(name: SettingName) throws {
        
        try super.removeSetting(name: name)
        
        // update internal cache
        self.propertyAccessQueue.sync {
            self.cachedSettings[name] = nil
        }
        
        self.updateCache { [weak self] in
            self?.notifySettingUpdate(oldName: name, newName: BundledStyleName.none)
        }
    }
    
    
    /// restore the setting with name
    override func restoreSetting(name: SettingName) throws {
        
        try super.restoreSetting(name: name)
        
        self.propertyAccessQueue.sync {
            self.cachedSettings[name] = nil
        }
        
        self.updateCache { [weak self] in
            self?.notifySettingUpdate(oldName: name, newName: name)
        }
    }
    
    
    /// save setting file
    func save(settingDictionary: StyleDictionary, name: SettingName, oldName: SettingName?) throws {
        
        // create directory to save in user domain if not yet exist
        try self.prepareUserSettingDirectory()
        
        // sanitize -> remove empty mapping dicts
        for key in SyntaxKey.mappingKeys {
            (settingDictionary[key.rawValue] as? NSMutableArray)?.remove([:])
        }
        
        // sort
        let descriptors = [NSSortDescriptor(key: SyntaxDefinitionKey.beginString.rawValue, ascending: true,
                                            selector: #selector(NSString.caseInsensitiveCompare)),
                           NSSortDescriptor(key: SyntaxDefinitionKey.keyString.rawValue, ascending: true,
                                            selector: #selector(NSString.caseInsensitiveCompare))]
        let syntaxDictKeys = SyntaxType.all.map { $0.rawValue } + [SyntaxKey.outlineMenu.rawValue, SyntaxKey.completions.rawValue]
        for key in syntaxDictKeys {
            (settingDictionary[key] as? NSMutableArray)?.sort(using: descriptors)
        }
        
        // save
        let saveURL = self.preparedURLForUserSetting(name: name)
        
        // move old file to new place to overwrite when style name is also changed
        if let oldName = oldName, name != oldName {
            try self.renameSetting(name: oldName, to: name)
        }
        
        // just remove the current custom setting file in the user domain if new style is just the same as bundled one
        // so that application uses bundled one
        if self.isEqualToBundledSetting(settingDictionary, name: name) {
            if saveURL.isReachable {
                try FileManager.default.removeItem(at: saveURL)
                self.propertyAccessQueue.sync {
                    self.cachedSettings[name] = nil
                }
            }
        } else {
            // save file to user domain
            let yamlData = try YAMLSerialization.yamlData(with: settingDictionary, options: kYAMLWriteOptionSingleDocument)
            try yamlData.write(to: saveURL, options: .atomic)
        }
        
        // update internal cache
        self.updateCache { [weak self] in
            if let oldName = oldName {
                self?.notifySettingUpdate(oldName: oldName, newName: name)
            }
        }
    }
    
    
    /// conflicted maps
    var mappingConflicts: [SyntaxKey: [String: [SettingName]]] {
        
        return self.mappingTables.mapValues { $0.filter { $0.value.count > 1 } }
    }
    
    
    /// empty style dictionary
    var blankSettingDictionary: StyleDictionary {
        
        return [
            SyntaxKey.metadata.rawValue: NSMutableDictionary(),
            SyntaxKey.extensions.rawValue: NSMutableArray(),
            SyntaxKey.filenames.rawValue: NSMutableArray(),
            SyntaxKey.interpreters.rawValue: NSMutableArray(),
            SyntaxType.keywords.rawValue: NSMutableArray(),
            SyntaxType.commands.rawValue: NSMutableArray(),
            SyntaxType.types.rawValue: NSMutableArray(),
            SyntaxType.attributes.rawValue: NSMutableArray(),
            SyntaxType.variables.rawValue: NSMutableArray(),
            SyntaxType.values.rawValue: NSMutableArray(),
            SyntaxType.numbers.rawValue: NSMutableArray(),
            SyntaxType.strings.rawValue: NSMutableArray(),
            SyntaxType.characters.rawValue: NSMutableArray(),
            SyntaxType.comments.rawValue: NSMutableArray(),
            SyntaxKey.outlineMenu.rawValue: NSMutableArray(),
            SyntaxKey.completions.rawValue: NSMutableArray(),
            SyntaxKey.commentDelimiters.rawValue: NSMutableDictionary(),
        ]
    }
    
    
    
    // MARK: Private Methods
    
    /// Load StyleDictionary at file URL.
    ///
    /// - parameter fileURL: URL to a setting file.
    /// - throws: CocoaError
    private func loadSettingDictionary(at fileURL: URL) throws -> StyleDictionary {
        
        let data = try Data(contentsOf: fileURL)
        let yaml = try YAMLSerialization.object(withYAMLData: data, options: kYAMLReadOptionMutableContainersAndLeaves)
        
        guard let styleDictionary = yaml as? StyleDictionary else {
            throw CocoaError.error(.fileReadCorruptFile, url: fileURL)
        }
        
        return styleDictionary
    }
    
    
    /// return whether contents of given highlight definition is the same as bundled one
    private func isEqualToBundledSetting(_ style: StyleDictionary, name: SettingName) -> Bool {
        
        guard let bundledStyle = self.bundledSettingDictionary(name: name) else { return false }
        
        return NSDictionary(dictionary: style).isEqual(to: bundledStyle)
    }
    
    
    /// update internal cache data
    override func loadUserSettings() {
        
        // load mapping definitions from style files in user domain
        let mappingKeys = SyntaxKey.mappingKeys.map { $0.rawValue }
        let userMap: [SettingName: [String: [String]]] = self.userSettingFileURLs.reduce(into: [:]) { (dict, url) in
            guard let style = try? self.loadSettingDictionary(at: url) else { return }
            let styleName = self.settingName(from: url)
            
            // create file mapping data
            dict[styleName] = style.filter { mappingKeys.contains($0.key) }
                .mapValues { $0 as? [[String: String]] ?? [] }
                .mapValues { $0.compactMap { $0[SyntaxDefinitionKey.keyString.rawValue] } }
        }
        let map = self.bundledMap.merging(userMap) { (_, new) in new }
        
        // sort styles alphabetically
        self.styleNames = map.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        
        // remove styles not exist
        UserDefaults.standard[.recentStyleNames] = UserDefaults.standard[.recentStyleNames]!.filter { self.styleNames.contains($0) }
        
        // update file mapping tables
        let styleNames = self.bundledStyleNames + self.styleNames.filter { !self.bundledSettingNames.contains($0) }  // postpone bundled styles
        let tables = SyntaxKey.mappingKeys.reduce(into: [:]) { (tables, key) in
            tables[key] = styleNames.reduce(into: [String: [SettingName]]()) { (table, styleName) in
                guard let items = map[styleName]?[key.rawValue] else { return }
                
                for item in items {
                    table[item, default: []].append(styleName)
                }
            }
        }
        self.propertyAccessQueue.sync {
            self.mappingTables = tables
        }
    }
    
}



private extension String {
    
    /// try extracting used language from the shebang line
    func scanInterpreterInShebang() -> String? {
        
        // get first line
        var firstLine: String?
        self.enumerateLines { (line, stop) in
            firstLine = line
            stop = true
        }
        
        guard var shebang = firstLine, shebang.hasPrefix("#!") else { return nil }
        
        // remove #! symbol
        shebang = shebang.replacingOccurrences(of: "^#! *", with: "", options: .regularExpression)
        
        // find interpreter
        let components = shebang.components(separatedBy: " ")
        let interpreter = components.first?.components(separatedBy: "/").last
        
        // use first arg if the path targets env
        if interpreter == "env" {
            return components[safe: 1]
        }
        
        return interpreter
    }
    
}



// MARK: - Migration

extension SyntaxManager {
    
    /// convert CotEditor 1.x format (plist) syntax style definition to CotEditor 2.0 format (yaml) and save to user domain
    @discardableResult
    func importLegacyStyle(fileURL: URL) -> Bool {
        
        guard fileURL.pathExtension == "plist" else { return false }
        
        let coordinator = NSFileCoordinator()
        
        var data: Data?
        coordinator.coordinate(readingItemAt: fileURL, options: .withoutChanges, error: nil) { (newReadingURL) in
            data = try? Data(contentsOf: newReadingURL)
        }
        
        guard
            let plistData = data,
            let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil),
            let style = plist as? [String: Any] else { return false }
        
        // update style format
        let newStyle: [String: Any] = style
            .filter { $0.0 != "styleName" }   // remove lagacy "styleName" key
            .mapKeys { $0.replacingOccurrences(of: "Array", with: "") }  // remove all `Array` suffix from dict keys
        
        guard let yamlData = try? YAMLSerialization.yamlData(with: newStyle, options: kYAMLWriteOptionSingleDocument) else { return false }
        
        let styleName = self.settingName(from: fileURL)
        let destURL = self.preparedURLForUserSetting(name: styleName)
        coordinator.coordinate(writingItemAt: destURL, error: nil) { (newWritingURL) in
            try? yamlData.write(to: newWritingURL, options: .atomic)
        }
        
        return true
    }
    
}
