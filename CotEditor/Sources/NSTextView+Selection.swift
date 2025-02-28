//
//  NSTextView+Selection.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2018-02-22.
//
//  ---------------------------------------------------------------------------
//
//  © 2018-2023 1024jp
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

import AppKit

extension NSTextView {
    
    /// The first selected string
    var selectedString: String {
        
        (self.string as NSString).substring(with: self.selectedRange)
    }
    
    
    /// The selected strings.
    var selectedStrings: [String] {
        
        self.selectedRanges
            .map(\.rangeValue)
            .map { (self.string as NSString).substring(with: $0) }
    }
    
    
    /// character just before the given range
    func character(before range: NSRange) -> Unicode.Scalar? {
        
        guard range.lowerBound > 0 else { return nil }
        
        let index = String.UnicodeScalarIndex(utf16Offset: range.lowerBound - 1, in: self.string)
        
        return self.string.unicodeScalars[safe: index]
    }
    
    
    /// character just after the given range
    func character(after range: NSRange) -> Unicode.Scalar? {
        
        let index = String.UnicodeScalarIndex(utf16Offset: range.upperBound, in: self.string)
        
        return self.string.unicodeScalars[safe: index]
    }
    
    
    /// location of the beginning of the current visual line considering indent
    func locationOfBeginningOfLine(for location: Int) -> Int {
        
        let string = self.string as NSString
        let lineRange = string.lineRange(at: location)
        
        if let layoutManager = self.layoutManager, location > 0 {
            // beginning of current visual line
            let visualLineLocation = layoutManager.lineFragmentRange(at: location - 1).location
            
            if lineRange.location < visualLineLocation {
                return visualLineLocation
            }
        }
        
        // column just after indent of paragraph line
        let indentLocation = string.range(of: "^[\t ]*", options: .regularExpression, range: lineRange).upperBound
        
        return (indentLocation < location) ? indentLocation : lineRange.location
    }
    
    
    /// Select the given range with visual feedback.
    ///
    /// - Parameter range: The character range to select.
    func select(range: NSRange) {
        
        self.selectedRange = range
        self.scrollRangeToVisible(range)
        self.window?.makeFirstResponder(self)
    }
}
