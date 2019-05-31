// Copyright © 2017 Hootsuite. All rights reserved.

import Foundation
import UIKit
import CommonUI
import Common

protocol TokenTextViewTextStorageDelegate: class {
    func textStorageIsUpdatingFormatting(_ sender: TokenTextViewTextStorage, text: String, searchRange: NSRange) -> [(attributes: [NSAttributedString.Key: Any], forRange: NSRange)]?
	func tokenDisplay(_ sender: TokenTextViewTextStorage, tokenRef: TokenReference) -> TokenDisplay?
}

class TokenTextViewTextStorage: NSTextStorage {

    private struct Defaults {
        static let font = UIFont.preferredFont(forTextStyle: .body)
        static let linkColor = UIColor(red: 0.0, green: 174.0/255.0, blue: 239.0/255.0, alpha: 1.0)
        static let textColor = UIColor(white: 36.0/255.0, alpha: 1.0)
		static let textBackgroundColor = UIColor.white
    }

    fileprivate let backingStore = NSMutableAttributedString()
    fileprivate var dynamicTextNeedsUpdate = false

    var font = Defaults.font
    var linkColor = Defaults.linkColor
	var textColor = Defaults.textColor
	var textBackgroundColor = Defaults.textBackgroundColor
    weak var formattingDelegate: TokenTextViewTextStorageDelegate?
	
	var selectedToken: Token?
	
    // MARK: Reading Text

    override var string: String {
        return backingStore.string
    }

    override func attributes(at index: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        return backingStore.attributes(at: index, effectiveRange: range)
    }

    // MARK: Text Editing

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backingStore.replaceCharacters(in: range, with: str)
        edited([.editedCharacters, .editedAttributes], range: range, changeInLength: (str as NSString).length - range.length)
        dynamicTextNeedsUpdate = true
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backingStore.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    override func processEditing() {

        fixDumQuotes()

        if dynamicTextNeedsUpdate {
            dynamicTextNeedsUpdate = false
            performReplacementsForCharacterChangeInRange(editedRange)
        }

        super.processEditing()
    }

    fileprivate func performReplacementsForCharacterChangeInRange(_ changedRange: NSRange) {
        let lineRange = (backingStore.string as NSString).lineRange(for: NSRange(location: NSMaxRange(changedRange), length: 0))
        let extendedRange = NSUnionRange(changedRange, lineRange)
        applyFormattingAttributesToRange(extendedRange)
    }

    func updateFormatting() {
        // Dummy edit to trigger updating all attributes
        self.beginEditing()
        self.edited(.editedAttributes, range: NSRange(location: 0, length: 0), changeInLength: 0)
        self.dynamicTextNeedsUpdate = true
        self.endEditing()
    }

    fileprivate func applyFormattingAttributesToRange(_ searchRange: NSRange) {
		
        // Set default attributes of edited range
        addAttribute(.foregroundColor, value: textColor, range: searchRange)
		addAttribute(.backgroundColor, value: textBackgroundColor, range: searchRange)
        addAttribute(.font, value: font, range: searchRange)
        addAttribute(.kern, value: 0.0, range: searchRange)

        if let (_, range) = inputTextAndRange() {
            addAttribute(.foregroundColor, value: linkColor, range: range)
        }
        if let (_, range) = anchorTextAndRange() {
            addAttribute(.foregroundColor, value: linkColor, range: range)
        }

        enumerateTokenRefs(inRange: searchRange) { (tokenRef, tokenRange) -> ObjCBool in
            var tokenFormattingAttributes = [NSAttributedString.Key: Any]()
			let tokenDisplay = self.formattingDelegate?.tokenDisplay(self, tokenRef: tokenRef)
			tokenFormattingAttributes[.backgroundColor] = tokenDisplay?.backgroundColor
			tokenFormattingAttributes[.foregroundColor] = tokenDisplay?.textColor ?? self.textColor
			tokenFormattingAttributes[.font] = tokenDisplay?.font ?? self.font
            self.addAttributes(tokenFormattingAttributes, range: tokenRange)
            return false
        }

        if let additionalFormats = formattingDelegate?.textStorageIsUpdatingFormatting(self, text: backingStore.string, searchRange: searchRange), !additionalFormats.isEmpty {
            for (formatDict, range) in additionalFormats {
                if !rangeIntersectsToken(range) {
                    addAttributes(formatDict, range: range)
                }
            }
        }
    }

    // TODO: Currently a duplicate from HSTwitterTextColoringTextStorage
    // That class will be deleted when the Unified Mention feature is deployed
    fileprivate func fixDumQuotes() {
        let nsText = backingStore.string as NSString
        nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length),
                options: NSString.EnumerationOptions.byComposedCharacterSequences,
                using: { (substring: String?, substringRange: NSRange, _, _) in
                    if substring == "\"" {
                        if substringRange.location == 0 {
                            self.backingStore.replaceCharacters(in: substringRange, with: "“")
                        } else {
                            let previousCharacter = nsText.substring(with: NSRange(location: substringRange.location - 1, length: 1))
                            if previousCharacter == " " || previousCharacter == "\n" {
                                self.backingStore.replaceCharacters(in: substringRange, with: "“")
                            } else {
                                self.backingStore.replaceCharacters(in: substringRange, with: "”")
                            }
                        }
                    } else if substring == "'" {
                        if substringRange.location == 0 {
                            self.backingStore.replaceCharacters(in: substringRange, with: "‘")
                        } else {
                            let previousCharacter = nsText.substring(with: NSRange(location: substringRange.location - 1, length: 1))
                            if previousCharacter == " " || previousCharacter == "\n" {
                                self.backingStore.replaceCharacters(in: substringRange, with: "‘")
                            } else {
                                self.backingStore.replaceCharacters(in: substringRange, with: "’")
                            }
                        }
                    }
                })
    }

    // MARK: Token utilities
	
	var keysByTokenReference: [TokenReference: Common.Key] = [:]
	
    var tokenList: [Token] {
        var tokenArray: [Token] = []
        enumerateTokenRefs { (tokenRef, tokenRange) -> ObjCBool in
			let key = self.keysByTokenReference[tokenRef]!
			let tokenText = self.attributedSubstring(from: tokenRange).string
			let token = Token(tokenRef: tokenRef, key: key, text: tokenText, range: tokenRange)
            tokenArray.append(token)
            return false
        }
        return tokenArray
    }
	
	func token(for matchingTokenRef: TokenReference) -> Token? {
		var matchingToken: Token?
		enumerateTokenRefs { (tokenRef, tokenRange) -> ObjCBool in
			if tokenRef == matchingTokenRef {
				let key = self.keysByTokenReference[tokenRef]!
				let tokenText = self.attributedSubstring(from: tokenRange).string
				let token = Token(tokenRef: tokenRef, key: key, text: tokenText, range: tokenRange)
				matchingToken = token
				return true
			}
			return false
		}
		return matchingToken
	}
	
	var segments: [TokenTextViewController.Segment] {
		var segments: [TokenTextViewController.Segment] = []
		enumerateAttributes(in: NSRange(location: 0, length: length), options: []) { (attributes, range, stop) in
			let text = self.attributedSubstring(from: range).string
			if let tokenRef = attributes[TokenTextViewControllerConstants.tokenAttributeReference] as? TokenReference {
				guard text != " " else {
					// We're prepending all tokens with a " " for some reason; let's ignore it til we can find out why.
					return
				}
				let key = self.attribute(TokenTextViewControllerConstants.externalID, at: range.location, effectiveRange: nil) as! Common.Key
				let tokenInfo = Token(tokenRef: tokenRef, key: key, text: text, range: range)
				segments.append(.token(tokenInfo))
			} else {
				segments.append(.text(text))
			}
		}
		return segments
	}

    func enumerateTokenRefs(inRange range: NSRange? = nil, withAction action:@escaping (_ tokenRef: TokenReference, _ tokenRange: NSRange) -> ObjCBool) {
        let searchRange = range ?? NSRange(location: 0, length: length)
        enumerateAttribute(TokenTextViewControllerConstants.tokenAttributeReference,
            in: searchRange,
            options: NSAttributedString.EnumerationOptions(rawValue: 0),
            using: { value, range, stop in
				guard let tokenRef = value as? TokenReference else {
					return
				}
				let shouldStop = action(tokenRef, range)
				stop.pointee = shouldStop
        })
    }

    func tokensIntersectingRange(_ range: NSRange) -> [TokenReference] {
        return tokenList.filter {
            NSIntersectionRange(range, $0.range).length > 0
        }.map {
            $0.tokenRef
        }
    }

    func rangeIntersectsToken(_ range: NSRange) -> Bool {
        for tokenInfo in tokenList {
            if NSIntersectionRange(range, tokenInfo.range).length > 0 {
                return true
            }
        }
        return false
    }

    func rangeIntersectsTokenInput(_ range: NSRange) -> Bool {
        if let (_, anchorRange) = anchorTextAndRange(), NSIntersectionRange(range, anchorRange).length > 0 {
            return true
        }
        if let (_, inputRange) = inputTextAndRange(), NSIntersectionRange(range, inputRange).length > 0 {
            return true
        }
        return false
    }

    func isValidEditingRange(_ range: NSRange) -> Bool {
        // We don't allow editing parts of tokens (ranges that partially overlap a token or are contained within a token)
        if range.length == 0 {
            return true
        }
        let editingRangeStart = range.location
        let editingRangeEnd = range.location + range.length - 1
        for tokenInfo in tokenList {
            let tokenRangeStart = tokenInfo.range.location
            let tokenRangeEnd = tokenInfo.range.location + tokenInfo.range.length - 1
            if editingRangeStart > tokenRangeStart && editingRangeStart <  tokenRangeEnd ||
                editingRangeEnd > tokenRangeStart && editingRangeEnd <  tokenRangeEnd {
                    return false
            }
        }
        return true
    }
	
	/// Adds padding around the token.
	func effectiveTokenDisplayText(_ originalText: String) -> String {
		return " \(originalText) "
	}
	
    // MARK: Input mode

    func anchorTextAndRange() -> (String, NSRange)? {
        return attributeTextAndRange(TokenTextViewControllerConstants.inputTextAttributeName, attributeValue: TokenTextViewControllerConstants.inputTextAttributeAnchorValue)
    }

    func inputTextAndRange() -> (String, NSRange)? {
        return attributeTextAndRange(TokenTextViewControllerConstants.inputTextAttributeName, attributeValue: TokenTextViewControllerConstants.inputTextAttributeTextValue)
    }

    fileprivate func attributeTextAndRange(_ attributeName: NSAttributedString.Key, attributeValue: String) -> (String, NSRange)? {
        var result: (String, NSRange)?
        enumerateAttribute(attributeName,
            in: NSRange(location: 0, length: length),
            options: NSAttributedString.EnumerationOptions(rawValue: 0),
            using: { value, range, stop in
                if let value = value as? String, value == attributeValue {
                    result = (self.attributedSubstring(from: range).string, range)
                    stop.pointee = true
                }
        })
        return result
    }

    func clearEditingAttributes() {
        removeAttribute(TokenTextViewControllerConstants.inputTextAttributeName, range: NSRange(location: 0, length: length))
        updateFormatting()
    }

}
