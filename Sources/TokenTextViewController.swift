// Copyright © 2017 Hootsuite. All rights reserved.

import Foundation
import CommonUI
import UIKit

/// The delegate used to handle user interaction and enable/disable customization to a `TokenTextViewController`.
public protocol TokenTextViewControllerDelegate: class {

    /// Called when text changes.
    func tokenTextViewControllerDidChange(_ sender: TokenTextViewController)

    /// Whether an edit should be accepted.
    func tokenTextViewController(_ sender: TokenTextViewController, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool

	/// Called when a token was tapped.
	func tokenTextViewController(_ sender: TokenTextViewController, didSelectToken token: Token, inRect rect: CGRect)
	
	/// Called when a token was de-selected.
	func tokenTextViewController(_ sender: TokenTextViewController, didDeselectToken token: Token)

    /// Called when a token was deleted.
    func tokenTextViewController(_ sender: TokenTextViewController, didDeleteToken token: Token)

    /// Called when a token was added.
    func tokenTextViewController(_ sender: TokenTextViewController, didAddToken token: Token)

    /// Called when the formatting is being updated.
    func tokenTextViewController(_ sender: TokenTextViewController, textStorageIsUpdatingFormattingOn text: String, searchRange: NSRange) -> [(attributes: [NSAttributedString.Key: Any], forRange: NSRange)]

    /// Allows display customization of a token.
    func tokenDisplay(for sender: TokenTextViewController, token: Token) -> TokenDisplay?

    /// Whether the last edit should cancel token editing.
    func tokenTextViewController(_ sender: TokenTextViewController, shouldCancelEditingAfterInserting newText: String, inputText: String) -> Bool

    /// Whether content of type type can be pasted in the text view.
    /// This method is called every time some content may be pasted.
    func tokenTextViewController(_: TokenTextViewController, shouldAcceptContentOfType type: PasteboardItemType) -> Bool

    /// Called when media items have been pasted.
    func tokenTextViewController(_: TokenTextViewController, didReceive items: [PasteboardItem])

}

/// Default implementation for some `TokenTextViewControllerDelegate` methods.
public extension TokenTextViewControllerDelegate {
	
    /// Default value of `false`.
    func tokenTextViewController(_: TokenTextViewController, shouldAcceptContentOfType type: PasteboardItemType) -> Bool {
        return false
    }

    /// Empty default implementation.
    func tokenTextViewController(_: TokenTextViewController, didReceive items: [PasteboardItem]) {

    }

    /// Empty default implementation
    func tokenTextViewController(_ sender: TokenTextViewController, didAddToken token: Token) {

    }

}

/// The delegate used to handle text input in a `TokenTextViewController`.
public protocol TokenTextViewControllerInputDelegate: class {

    /// Called whenever the text is updated.
    func tokenTextViewInputTextDidChange(_ sender: TokenTextViewController, inputText: String)

    /// Called when the text is confirmed by the user.
    func tokenTextViewInputTextWasConfirmed(_ sender: TokenTextViewController)

    /// Called when teh text is cancelled by the user.
    func tokenTextViewInputTextWasCanceled(_ sender: TokenTextViewController, reason: TokenTextInputCancellationReason)

}

/// Determines different input cancellation reasons for a `TokenTextViewController`.
public enum TokenTextInputCancellationReason {

    case deleteInput
    case tapOut

}

/// A data structure to hold constants for the `TokenTextViewController`.
public struct TokenTextViewControllerConstants {

    public static let tokenAttributeReference = NSAttributedString.Key(rawValue: "com.hootsuite.tokenID")
	public static let externalID = NSAttributedString.Key(rawValue: "com.hootsuite.externalID")
    static let inputTextAttributeName = NSAttributedString.Key(rawValue: "com.hootsuite.input")
    static let inputTextAttributeAnchorValue = "anchor"
    static let inputTextAttributeTextValue = "text"

}

/// Colors for a token.
public struct TokenDisplay {
	public static let defaultDisplay = TokenDisplay(textColor: .white, backgroundColor: .lightGray)
	public var textColor: UIColor
	public var backgroundColor: UIColor
	public var font: UIFont?
	public var xInset: CGFloat
	public var yInset: CGFloat
	// this doesn't do anything yet.
	public var cornerRadius: CGFloat
	
	public init(textColor: UIColor, backgroundColor: UIColor, font: UIFont? = nil, xInset: CGFloat = 6, yInset: CGFloat = 1, cornerRadius: CGFloat = 20) {
		self.textColor = textColor
		self.backgroundColor = backgroundColor
		self.font = font
		self.xInset = xInset
		self.yInset = yInset
		self.cornerRadius = cornerRadius
	}
}

public typealias TokenReference = String

/// A data structure used to identify a `Token` inside some text.
public struct Token: Equatable {

    /// The id for the internal token storage.
    var tokenRef: TokenReference
	
	/// The external key for tracking the id of the object associated with this token.
	public var externalID: String
	
    /// The text that contains the `Token`.
    public var text: String

    /// The range of text that contains the `Token`.
    public var range: NSRange

}

extension TokenTextViewController {
	public enum Segment {
		case text(String)
		case token(Token)
	}
}

/// Used to display a `UITextView` that creates and responds to `Token`'s as the user types and taps.
open class TokenTextViewController: UIViewController, UITextViewDelegate, NSLayoutManagerDelegate, TokenTextViewTextStorageDelegate, UIGestureRecognizerDelegate {

    /// The delegate used to handle user interaction and enable/disable customization.
    open weak var delegate: TokenTextViewControllerDelegate?

    /// The delegate used to handle text input.
    open weak var inputDelegate: TokenTextViewControllerInputDelegate? {
        didSet {
            if let (inputText, _) = tokenTextStorage.inputTextAndRange() {
                inputDelegate?.tokenTextViewInputTextDidChange(self, inputText: inputText)
            }
        }
    }

    /// The font for the textView.
    open var font = UIFont.preferredFont(forTextStyle: .body) {
        didSet {
            textView.font = font
            tokenTextStorage.font = font
        }
    }
	
	/// A selected token
	public var selectedToken: Token? {
		return tokenTextStorage.selectedToken
	}

    /// Flag for text tokenization when input field loses focus
    public var tokenizeOnLostFocus = false

    fileprivate var tokenTapRecognizer: UITapGestureRecognizer?
    fileprivate var inputModeHandler: TokenTextViewControllerInputModeHandler!
    fileprivate var textTappedHandler: ((UITapGestureRecognizer) -> Void)?
    fileprivate var inputIsSuspended = false

    /// Initializer for `self`.
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
		commonInit()
    }
	
	/// Initializer for `self`.
	public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
		super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
		commonInit()
	}

    /// Initializer for `self`.
    public init() {
        super.init(nibName: nil, bundle: nil)
		commonInit()
    }
	
	private func commonInit() {
		inputModeHandler = TokenTextViewControllerInputModeHandler(tokenTextViewController: self)
		textTappedHandler = normalModeTapHandler
	}

    /// Loads a `PasteMediaTextView` as the base view of `self`.
    override open func loadView() {
        let textStorage = TokenTextViewTextStorage()
        textStorage.formattingDelegate = self
        let layoutManager = TokenTextViewLayoutManager()
        layoutManager.delegate = self
        let container = NSTextContainer(size: CGSize.zero)
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        textStorage.addLayoutManager(layoutManager)
        let textView = PasteMediaTextView(frame: CGRect.zero, textContainer: container)
        textView.delegate = self
        textView.mediaPasteDelegate = self
        textView.isScrollEnabled = true
        tokenTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(TokenTextViewController.textTapped(_:)))
        tokenTapRecognizer!.numberOfTapsRequired = 1
        tokenTapRecognizer!.delegate = self
        textView.addGestureRecognizer(tokenTapRecognizer!)
        self.view = textView
    }

    public var textView: TextView! {
        return (view as! TextView)
    }
	
	public var segments: [Segment] {
		return tokenTextStorage.segments
	}

    fileprivate var tokenTextStorage: TokenTextViewTextStorage {
        return textView.textStorage as! TokenTextViewTextStorage
    }

    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        textView.font = font
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(TokenTextViewController.preferredContentSizeChanged(_:)),
            name: UIContentSizeCategory.didChangeNotification,
            object: nil)
    }

    override open func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: UIContentSizeCategory.didChangeNotification, object: nil)
    }

    @objc func preferredContentSizeChanged(_ notification: Notification) {
        tokenTextStorage.updateFormatting()
    }

    @objc func textTapped(_ recognizer: UITapGestureRecognizer) {
        textTappedHandler?(recognizer)
    }

    // MARK: UIGestureRecognizerDelegate

    /// Enables/disables some gestures to be recognized simultaneously.
    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == tokenTapRecognizer {
            return true
        }
        return false
    }

    // MARK: UITextView variables and functions.

    /// The text contained in the textView.
    open var text: String! {
        get {
            return textView.text
        }

        set {
            textView.text = newValue
        }
    }

    /// The color of the text in the textView.
    open var textColor: UIColor! {
        get {
            return textView.textColor
        }

        set {
            textView.textColor = newValue
        }
    }

    /// The style of the text alignment for the textView.
    open var textAlignment: NSTextAlignment {
        get {
            return textView.textAlignment
        }

        set {
            textView.textAlignment = newValue
        }
    }

    /// The selected range of text in the textView.
    open var selectedRange: NSRange {
        get {
            return textView.selectedRange
        }

        set {
            textView.selectedRange = newValue
        }
    }

    /// The type of keyboard displayed when the user interacts with the textView.
    open var keyboardType: UIKeyboardType {
        get {
            return textView.keyboardType
        }

        set {
            textView.keyboardType = newValue
        }
    }

    /// The edge insets of the textView.
    open var textContainerInset: UIEdgeInsets {
        get {
            return textView.textContainerInset
        }

        set {
            textView.textContainerInset = newValue
        }
    }

    /// Sets the scrolling enabled/disabled state of the textView.
    open var scrollEnabled: Bool {
        get {
            return textView.isScrollEnabled
        }

        set {
            textView.isScrollEnabled = newValue
        }
    }

    /// The line fragment padding for the textView.
    open var lineFragmentPadding: CGFloat {
        get {
            return textView.textContainer.lineFragmentPadding
        }

        set {
            textView.textContainer.lineFragmentPadding = newValue
        }
    }

    /// A rectangle that defines the area for drawing the caret in the textView.
    public var cursorRect: CGRect? {
        if let selectedTextRange = textView.selectedTextRange {
            return textView.caretRect(for: selectedTextRange.start)
        }
        return nil
    }

    /// The accessibility label string for the text view.
    override open var accessibilityLabel: String! {
        get {
            return textView.accessibilityLabel
        }

        set {
            textView.accessibilityLabel = newValue
        }
    }

    /// Assigns the first responder to the textView.
    override open func becomeFirstResponder() -> Bool {
        return textView.becomeFirstResponder()
    }

    /// Resigns the first responder from the textView.
    override open func resignFirstResponder() -> Bool {
        return textView.resignFirstResponder()
    }

    /// Resigns as first responder.
    open func suspendInput() {
        _ = resignFirstResponder()
        inputIsSuspended = true
    }

    /// The text storage object holding the text displayed in this text view.
    open var attributedString: NSAttributedString {
        return textView.textStorage
    }

    // MARK: Text manipulation.

    /// Appends the given text to the textView and repositions the cursor at the end.
    open func appendText(_ text: String) {
        textView.textStorage.append(NSAttributedString(string: text))
        repositionCursorAtEndOfRange()
    }

    /// Adds text to the beginning of the textView and repositions the cursor at the end.
    open func prependText(_ text: String) {
        let cursorLocation = textView.selectedRange.location
        textView.textStorage.insert(NSAttributedString(string: text), at: 0)
        textView.selectedRange = NSRange(location: cursorLocation + (text as NSString).length, length: 0)
        repositionCursorAtEndOfRange()
    }

    /// Replaces the first occurrence of the given string in the textView with another string.
    open func replaceFirstOccurrenceOfString(_ string: String, withString replacement: String) {
        let cursorLocation = textView.selectedRange.location
        let searchRange = textView.textStorage.mutableString.range(of: string)
        if searchRange.length > 0 {
            textView.textStorage.mutableString.replaceCharacters(in: searchRange, with: replacement)
            if cursorLocation > searchRange.location {
                textView.selectedRange = NSRange(location: min(cursorLocation + (replacement as NSString).length - (string as NSString).length, (text as NSString).length), length: 0)
                repositionCursorAtEndOfRange()
            }
        }
    }

    /// Replaces the characters in the given range in the textView with the provided string.
    open func replaceCharactersInRange(_ range: NSRange, withString: String) {
        if !rangeIntersectsToken(range) {
            textView.textStorage.replaceCharacters(in: range, with: withString)
        }
    }

    /// Inserts the given string at the provided index location of the textView.
    open func insertString(_ string: String, atIndex index: Int) {
        textView.textStorage.insert(NSAttributedString(string: string), at: index)
    }

    // MARK: token editing

    /// Adds a token to the textView at the given index and informs the delegate.
    @discardableResult
	open func addToken(_ startIndex: Int, text: String, id: String) -> Token {
        var attrs = createNewTokenAttributes()
		attrs[TokenTextViewControllerConstants.externalID] = id
		let tokenRef = attrs[TokenTextViewControllerConstants.tokenAttributeReference] as! String
		tokenTextStorage.externalTokenIDsByReference[tokenRef] = id
        let attrString = NSAttributedString(string: text, attributes: attrs)
        textView.textStorage.insert(attrString, at: startIndex)
        repositionCursorAtEndOfRange()
        let token = tokenAtLocation(startIndex)!
        delegate?.tokenTextViewControllerDidChange(self)
        delegate?.tokenTextViewController(self, didAddToken: token)
        return token
    }
	
	@discardableResult
	open func replaceToken(_ oldToken: Token, with newText: String, id: String) -> Token {
		let wasSelected: Bool = (oldToken == self.selectedToken)
		self.deleteToken(oldToken.tokenRef)
		let new = self.addToken(selectedRange.location, text: newText, id: id)
//		self.replaceTokenText(oldToken.tokenID, newText: newText)
		if wasSelected {
			// If the deleted token was selected, select the new one.
			self.tokenTextStorage.selectedToken = new
		}
		return new
	}

    /// Updates the formatting of the textView.
    open func updateTokenFormatting() {
        tokenTextStorage.updateFormatting()
    }

    fileprivate func createNewTokenAttributes() -> [NSAttributedString.Key: Any] {
        return [
            TokenTextViewControllerConstants.tokenAttributeReference: UUID().uuidString,
			
        ]
    }

    /// Updates the given `Token`'s text with the provided text and informs the delegate of the change.
    open func updateTokenText(_ tokenRef: TokenReference, newText: String) {
        replaceTokenText(tokenRef, newText: newText)
        repositionCursorAtEndOfRange()
        self.delegate?.tokenTextViewControllerDidChange(self)
    }

    /// Delegates the given `Token` and informs the delegate of the change.
    open func deleteToken(_ tokenRef: TokenReference) {
		let token = self.token(for: tokenRef)!
		tokenTextStorage.externalTokenIDsByReference[token.tokenRef] = nil
        replaceTokenText(tokenRef, newText: "")
        textView.selectedRange = NSRange(location: textView.selectedRange.location-token.text.count, length: 0)
        self.delegate?.tokenTextViewControllerDidChange(self)
		delegate?.tokenTextViewController(self, didDeleteToken: token)
    }

    fileprivate func replaceTokenText(_ tokenToReplaceRef: TokenReference, newText: String) {
        tokenTextStorage.enumerateTokenRefs { (tokenRef, tokenRange) -> ObjCBool in
            if tokenRef == tokenToReplaceRef {
                self.textView.textStorage.replaceCharacters(in: tokenRange, with: newText)
                return true
            }
            return false
        }
    }
	
    fileprivate func repositionCursorAtEndOfRange() {
        let cursorLocation = textView.selectedRange.location
        if let tokenInfo = tokenAtLocation(cursorLocation) {
            textView.selectedRange = NSRange(location: tokenInfo.range.location + tokenInfo.range.length, length: 0)
        }
    }

    /// An array of all the `Token`'s currently in the textView.
    open var tokenList: [Token] {
        return tokenTextStorage.tokenList
    }
	
	public func token(for tokenRef: TokenReference) -> Token? {
		return tokenTextStorage.token(for: tokenRef)
	}

    fileprivate func tokenAtLocation(_ location: Int) -> Token? {
        for token in tokenList {
            if location >= token.range.location && location < token.range.location + token.range.length {
                return token
            }
        }
        return nil
    }

    /// Determines whether the given range intersects with a `Token` currently in the textView.
    open func rangeIntersectsToken(_ range: NSRange) -> Bool {
        return tokenTextStorage.rangeIntersectsToken(range)
    }

    /// Determines whether the given range intersects with a `Token` that is currently being input by the user.
    open func rangeIntersectsTokenInput(_ range: NSRange) -> Bool {
        return tokenTextStorage.rangeIntersectsTokenInput(range)
    }

    fileprivate func cancelEditingAndKeepText() {
        tokenTextStorage.clearEditingAttributes()
        inputDelegate?.tokenTextViewInputTextWasCanceled(self, reason: .tapOut)
    }

    // MARK: Token List editing

    // Create a token from editable text contained from atIndex to toIndex (excluded)
    fileprivate func tokenizeEditableText(at range: NSRange) {
        if range.length != 0 {
            let nsText = text as NSString
            replaceCharactersInRange(range, withString: "")
            let textSubstring = nsText.substring(with: range).trimmingCharacters(in: .whitespaces)
            if !textSubstring.isEmpty {
				addToken(range.location, text: textSubstring, id: textSubstring)
            }
        }
    }

    // Create tokens from all editable text contained in the input field
    public func tokenizeAllEditableText() {
        var nsText = text as NSString

        if tokenList.isEmpty {
            tokenizeEditableText(at: NSRange(location: 0, length: nsText.length))
            return
        }

        // ensure we use a sorted tokenlist (by location)
        let orderedTokenList: [Token] = tokenList.sorted(by: { $0.range.location < $1.range.location })

        // find text discontinuities, characters that do not belong to a token
        var discontinuities: [NSRange] = []

        // find discontinuities before token list
        guard let firstToken = orderedTokenList.first else { return }
        if firstToken.range.location != 0 {
            discontinuities.append(NSRange(location: 0, length: firstToken.range.location))
        }

        // find discontinuities within token list
        for i in 1..<orderedTokenList.count {
            let endPositionPrevious = orderedTokenList[i-1].range.length + orderedTokenList[i-1].range.location
            let startPositionCurrent = orderedTokenList[i].range.location

            if startPositionCurrent != endPositionPrevious {
                // found discontinuity
                discontinuities.append(NSRange(location: endPositionPrevious, length: (startPositionCurrent - endPositionPrevious)))
            }
        }

        // find discontinuities after token list
        guard let lastToken = orderedTokenList.last else { return }
        let lengthAfterTokenList = lastToken.range.location + lastToken.range.length - nsText.length
        if lengthAfterTokenList != 0 {
            discontinuities.append(NSRange(location: (lastToken.range.length + lastToken.range.location), length: (nsText.length - lastToken.range.length - lastToken.range.location)))
        }

        // apply tokens at discontinuities
        for i in (0..<discontinuities.count).reversed() {
            // insert all new chips
            tokenizeEditableText(at: discontinuities[i])
        }

        // move cursor to the end
        nsText = text as NSString
        selectedRange = NSRange(location: nsText.length, length: 0)
    }

    // Create editable text from exisitng token, appended to end of input field
    // This method tokenizes all current editable text prior to making token editable
    public func makeTokenEditableAndMoveToFront(tokenReference: TokenReference) {
        var clickedTokenText = ""

        guard let foundToken = tokenList.first(where: { $0.tokenRef == tokenReference }) else { return }
        clickedTokenText = foundToken.text.trimmingCharacters(in: CharacterSet.whitespaces)
        tokenizeAllEditableText()
        deleteToken(tokenReference)
        appendText(clickedTokenText)

        let nsText = self.text as NSString
        selectedRange = NSRange(location: nsText.length, length: 0)
        _ = becomeFirstResponder()
        delegate?.tokenTextViewControllerDidChange(self)
    }

    // MARK: Input Mode

    ///
    open func switchToInputEditingMode(_ location: Int, text: String, initialInputLength: Int = 0) {
        let attrString = NSAttributedString(string: text, attributes: [TokenTextViewControllerConstants.inputTextAttributeName: TokenTextViewControllerConstants.inputTextAttributeAnchorValue])
        tokenTextStorage.insert(attrString, at: location)
        if initialInputLength > 0 {
            let inputRange = NSRange(location: location + (text as NSString).length, length: initialInputLength)
            tokenTextStorage.addAttributes([TokenTextViewControllerConstants.inputTextAttributeName: TokenTextViewControllerConstants.inputTextAttributeTextValue], range: inputRange)
        }
        textView.selectedRange = NSRange(location: location + (text as NSString).length + initialInputLength, length: 0)
        textView.autocorrectionType = .no
        textView.delegate = inputModeHandler
        textTappedHandler = inputModeTapHandler
        delegate?.tokenTextViewControllerDidChange(self)
        tokenTextStorage.updateFormatting()
    }

    /// Sets the text tap handler with the `normalModeTapHandler` and returns the location of the cursor.
    open func switchToNormalEditingMode() -> Int {
        var location = selectedRange.location
        if let (_, anchorRange) = tokenTextStorage.anchorTextAndRange() {
            location = anchorRange.location
            replaceCharactersInRange(anchorRange, withString: "")
        }
        if let (_, inputRange) = tokenTextStorage.inputTextAndRange() {
            replaceCharactersInRange(inputRange, withString: "")
        }
        textView.delegate = self
        textTappedHandler = normalModeTapHandler
        textView.autocorrectionType = .default
        return location
    }

    fileprivate var normalModeTapHandler: ((UITapGestureRecognizer) -> Void) {
        return { [weak self] recognizer in
            self?.normalModeTap(recognizer: recognizer)
        }
    }

    fileprivate var inputModeTapHandler: ((UITapGestureRecognizer) -> Void) {
        return { [weak self] recognizer in
            self?.inputModeTap(recognizer: recognizer)
        }
    }

    fileprivate func normalModeTap(recognizer: UITapGestureRecognizer) {
        textView.becomeFirstResponder()
        let location: CGPoint = recognizer.location(in: textView)
        if let charIndex = textView.characterIndexAtLocation(location), charIndex < textView.textStorage.length - 1 {
            var range = NSRange(location: 0, length: 0)
			if let _ = textView.attributedText?.attribute(TokenTextViewControllerConstants.tokenAttributeReference, at: charIndex, effectiveRange: &range) as? TokenReference,
				let token = tokenAtLocation(charIndex) {
				// Token was selected
                _ = resignFirstResponder()
                let rect: CGRect = {
                    if let textRange = textView.textRangeFromNSRange(range) {
                        return view.convert(textView.firstRect(for: textRange), from: textView.textInputView)
                    } else {
                        return CGRect(origin: location, size: CGSize.zero)
                    }
                }()
				
				if token == self.selectedToken {
					// Token was tapped again; deselect it.
					tokenTextStorage.selectedToken = nil
					
					delegate?.tokenTextViewController(self, didDeselectToken: token)
				} else {
					tokenTextStorage.selectedToken = token
					delegate?.tokenTextViewController(self, didSelectToken: token, inRect: rect)
				}
			} else {
				if let token = self.selectedToken {
					// Text was tapped; deselect token
					tokenTextStorage.selectedToken = nil
					delegate?.tokenTextViewController(self, didDeselectToken: token)
				}
				self.textView.reloadInputViews()
				// Set cursor at tap point
				self.textView.selectedRange = NSRange(location: charIndex, length: 0)
			}
        }
    }

    fileprivate func inputModeTap(recognizer: UITapGestureRecognizer) {
        guard !inputIsSuspended else {
            inputIsSuspended = false
            return
        }
        let location: CGPoint = recognizer.location(in: textView)

        if
            let charIndex = textView.characterIndexAtLocation(location),
            let (_, inputRange) = tokenTextStorage.inputTextAndRange(),
            let (_, anchorRange) = tokenTextStorage.anchorTextAndRange(),
            charIndex < anchorRange.location || charIndex >= inputRange.location + inputRange.length - 1
        {
            cancelEditingAndKeepText()
        }
    }

    // MARK: UITextViewDelegate

    open func textViewDidChange(_ textView: UITextView) {
        self.delegate?.tokenTextViewControllerDidChange(self)
    }

    open func textViewDidChangeSelection(_ textView: UITextView) {
        if textView.selectedRange.length == 0 {
            // The cursor is being repositioned
            let cursorLocation = textView.selectedRange.location
            let newCursorLocation = clampCursorLocationToToken(cursorLocation)
            if newCursorLocation != cursorLocation {
                textView.selectedRange = NSRange(location: newCursorLocation, length: 0)
            }
        } else {
            // A selection range is being modified
            let adjustedSelectionStart = clampCursorLocationToToken(textView.selectedRange.location)
            let adjustedSelectionLength = max(adjustedSelectionStart, clampCursorLocationToToken(textView.selectedRange.location + textView.selectedRange.length)) - adjustedSelectionStart
            if (adjustedSelectionStart != textView.selectedRange.location) || (adjustedSelectionLength != textView.selectedRange.length) {
                textView.selectedRange = NSRange(location: adjustedSelectionStart, length: adjustedSelectionLength)
            }
        }
    }

    fileprivate func clampCursorLocationToToken(_ cursorLocation: Int) -> Int {
        if let tokenInfo = tokenAtLocation(cursorLocation) {
            let range = tokenInfo.range
            return (cursorLocation > range.location + range.length / 2) ? (range.location + range.length) : range.location
        }
        return cursorLocation
    }

    /// Determines whether the text in the given range should be replaced by the provided string.
    /// Deleting one character, if it is part of a token, should delete the full token.
    /// If the editing range intersects tokens, make sure tokens are fully deleted and delegate called.
    open func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText: String) -> Bool {
        if range.length == 1 && (replacementText as NSString).length == 0 {
            // Deleting one character, if it is part of a token the full token should be deleted
            if let tokenInfo = tokenAtLocation(range.location) {
                deleteToken(tokenInfo.tokenRef)
                textView.selectedRange = NSRange(location: tokenInfo.range.location, length: 0)
                return false
            }
        } else if range.length > 0 {
            // Check if partial overlap or editing range contained in a token, reject edit
            if !tokenTextStorage.isValidEditingRange(range) {
                return false
            }
            // If the editing range intersects tokens, make sure tokens are fully deleted and delegate called
            let intersectingTokenReferences = tokenTextStorage.tokensIntersectingRange(range)
            if !intersectingTokenReferences.isEmpty {
                replaceRangeAndIntersectingTokens(range, intersectingTokenReferences: intersectingTokenReferences, replacementText: replacementText)
                self.delegate?.tokenTextViewControllerDidChange(self)
                return false
            }
        }
		return delegate?.tokenTextViewController(self, shouldChangeTextIn: range, replacementText: replacementText) ?? true
    }

    fileprivate func replaceRangeAndIntersectingTokens(_ range: NSRange, intersectingTokenReferences: [TokenReference], replacementText: String) {
        textView.textStorage.replaceCharacters(in: range, with: replacementText)
        tokenTextStorage.enumerateTokenRefs { (tokenRef, tokenRange) -> ObjCBool in
            if intersectingTokenReferences.contains(tokenRef) {
                self.textView.textStorage.replaceCharacters(in: tokenRange, with: "")
            }
            return false
        }
        textView.selectedRange = NSRange(location: textView.selectedRange.location, length: 0)
        for tokenRef in intersectingTokenReferences {
			if let token = self.token(for: tokenRef) {
				delegate?.tokenTextViewController(self, didDeleteToken: token)
			}
        }
    }

    public func textViewDidEndEditing(_ textView: UITextView) {
        if tokenizeOnLostFocus {
            tokenizeAllEditableText()
        }
    }


    // MARK: NSLayoutManagerDelegate

    open func layoutManager(_ layoutManager: NSLayoutManager, shouldBreakLineByWordBeforeCharacterAt charIndex: Int) -> Bool {
        var effectiveRange = NSRange(location: 0, length: 0)
        if (view as! UITextView).attributedText?.attribute(TokenTextViewControllerConstants.tokenAttributeReference, at: charIndex, effectiveRange: &effectiveRange) is TokenReference {
            return false
        }
        return true
    }

    // MARK: TokenTextViewTextStorageDelegate

    func textStorageIsUpdatingFormatting(_ sender: TokenTextViewTextStorage, text: String, searchRange: NSRange) -> [(attributes: [NSAttributedString.Key: Any], forRange: NSRange)]? {
		return delegate?.tokenTextViewController(self, textStorageIsUpdatingFormattingOn: text, searchRange: searchRange)
    }
	
	func tokenDisplay(_ sender: TokenTextViewTextStorage, tokenRef: TokenReference) -> TokenDisplay? {
		guard let token = self.token(for: tokenRef),
			let tokenDisplay = delegate?.tokenDisplay(for: self, token: token) else {
				return TokenDisplay.defaultDisplay
		}
		return tokenDisplay
	}
}

class TokenTextViewControllerInputModeHandler: NSObject, UITextViewDelegate {

    fileprivate weak var tokenTextViewController: TokenTextViewController!

    init(tokenTextViewController: TokenTextViewController) {
        self.tokenTextViewController = tokenTextViewController
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        if let (_, inputRange) = tokenTextViewController.tokenTextStorage.inputTextAndRange() {
            let cursorLocation = textView.selectedRange.location + textView.selectedRange.length
            let adjustedLocation = clampCursorLocationToInputRange(cursorLocation, inputRange: inputRange)
            if adjustedLocation != cursorLocation || textView.selectedRange.length > 0 {
                tokenTextViewController.textView.selectedRange = NSRange(location: adjustedLocation, length: 0)
            }
        } else if let (_, anchorRange) = tokenTextViewController.tokenTextStorage.anchorTextAndRange() {
            let adjustedLocation = anchorRange.location + 1
            if textView.selectedRange.location != adjustedLocation {
                tokenTextViewController.textView.selectedRange = NSRange(location: adjustedLocation, length: 0)
            }
        } else {
            _ = tokenTextViewController.resignFirstResponder()
        }
    }

    fileprivate func clampCursorLocationToInputRange(_ cursorLocation: Int, inputRange: NSRange) -> Int {
        if cursorLocation < inputRange.location {
            return inputRange.location
        }
        if cursorLocation > inputRange.location + inputRange.length {
            return inputRange.location + inputRange.length
        }
        return cursorLocation
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText newText: String) -> Bool {
        if range.length == 0 {
            handleInsertion(range, newText: newText)
        } else if range.length == 1 && newText.isEmpty {
            handleCharacterDeletion(range)
        }
        return false
    }

    fileprivate func handleInsertion(_ range: NSRange, newText: String) {
        if newText == "\n" {
            // Do not insert return, inform delegate
            tokenTextViewController.inputDelegate?.tokenTextViewInputTextWasConfirmed(tokenTextViewController)
            return
        }
        // Insert new text with token attribute
        let attrString = NSAttributedString(string: newText, attributes: [TokenTextViewControllerConstants.inputTextAttributeName: TokenTextViewControllerConstants.inputTextAttributeTextValue])
        tokenTextViewController.textView.textStorage.insert(attrString, at: range.location)
        tokenTextViewController.textView.selectedRange = NSRange(location: range.location + (newText as NSString).length, length: 0)
        if let (inputText, _) = tokenTextViewController.tokenTextStorage.inputTextAndRange() {
            tokenTextViewController.inputDelegate?.tokenTextViewInputTextDidChange(tokenTextViewController, inputText: inputText)
            if let delegate = tokenTextViewController.delegate, delegate.tokenTextViewController(tokenTextViewController, shouldCancelEditingAfterInserting: newText, inputText: inputText) {
                tokenTextViewController.cancelEditingAndKeepText()
            }
        }
    }

    fileprivate func handleCharacterDeletion(_ range: NSRange) {
        if let (_, inputRange) = tokenTextViewController.tokenTextStorage.inputTextAndRange(), let (_, anchorRange) = tokenTextViewController.tokenTextStorage.anchorTextAndRange() {
            if range.location >= anchorRange.location && range.location < anchorRange.location + anchorRange.length {
                // The anchor ("@") is deleted, input is cancelled
                tokenTextViewController.inputDelegate?.tokenTextViewInputTextWasCanceled(tokenTextViewController, reason: .deleteInput)
            } else if range.location >= inputRange.location && range.location < inputRange.location + inputRange.length {
                // Do deletion
                tokenTextViewController.textView.textStorage.replaceCharacters(in: range, with: "")
                tokenTextViewController.textView.selectedRange = NSRange(location: range.location, length: 0)
                if let (inputText, _) = tokenTextViewController.tokenTextStorage.inputTextAndRange() {
                    tokenTextViewController.inputDelegate?.tokenTextViewInputTextDidChange(tokenTextViewController, inputText: inputText)
                }
            }
        } else {
            // Input fully deleted, input is cancelled
            tokenTextViewController.inputDelegate?.tokenTextViewInputTextWasCanceled(tokenTextViewController, reason: .deleteInput)
        }
    }

}

extension UITextView {

    func characterIndexAtLocation(_ location: CGPoint) -> Int? {
        var point = location
        point.x -= self.textContainerInset.left
        point.y -= self.textContainerInset.top
        return self.textContainer.layoutManager?.characterIndex(for: point, in: self.textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
    }

}

extension UITextView {

    func textRangeFromNSRange(_ range: NSRange) -> UITextRange? {
        let beginning = self.beginningOfDocument
        if let start = self.position(from: beginning, offset: range.location),
            let end = self.position(from: start, offset: range.length),
            let textRange = self.textRange(from: start, to: end) {
            return textRange
        } else {
            return nil
        }
    }

}

extension TokenTextViewController: PasteMediaTextViewPasteDelegate {

    func pasteMediaTextView(_: PasteMediaTextView, shouldAcceptContentOfType type: PasteboardItemType) -> Bool {
        return delegate?.tokenTextViewController(self, shouldAcceptContentOfType: type) ?? false
    }

    func pasteMediaTextView(_: PasteMediaTextView, didReceive items: [PasteboardItem]) {
        delegate?.tokenTextViewController(self, didReceive: items)
    }

}
