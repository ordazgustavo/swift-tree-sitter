//
//  Parser.swift
//
//
//  Created by Gustavo Ordaz on 7/22/20.
//

import Foundation
import TreeSitter

public enum IncludedRangesError: Error {
    case range(uint)
}

public class Parser {
    var parser: OpaquePointer
    
    /// Create a new parser.
    public init() {
        parser = ts_parser_new()
    }
    
    deinit {
        ts_parser_delete(parser)
    }
    
    /// Set the language that the parser should use for parsing.
    ///
    /// Returns a Result indicating whether or not the language was successfully
    /// assigned. True means assignment succeeded. False means there was a
    /// version mismatch: the language was generated with an incompatible
    /// version of the Tree-sitter CLI. Check the language's version using
    /// `Language.version()` and compare it to this library's `LANGUAGE_VERSION`
    /// and `MIN_COMPATIBLE_LANGUAGE_VERSION` constants.
    @discardableResult
    public func setLanguage(_ language: Language) -> Result<Void, LanguageError> {
        let version = language.version
        
        if version < MIN_COMPATIBLE_LANGUAGE_VERSION || version > LANGUAGE_VERSION {
            return .failure(.version(version))
        }
        
        guard ts_parser_set_language(parser, language.language) else {
            return .failure(.version(version))
        }
        
        return .success(())
    }
    
    /// Get the parser's current language.
    public func language() -> Language? {
        guard let pointer = ts_parser_language(parser) else { return nil }
        
        return Language(pointer)
    }
    
    /// Parse a whole document
    public func parse(source: String, oldTree: Tree? = nil) -> Tree? {
        let res = ts_parser_parse_string(
            parser,
            oldTree?.tree,
            source,
            CUnsignedInt(source.utf8.count)
        )
        
        guard let tree = res else { return nil }
        return Tree(tree)
    }
    
    /// Parse a slice of UTF8 text.
    ///
    /// If the text of the document has changed since `oldTree` was created,
    /// then you must edit `oldTree` to match the new text using
    /// `Tree.edit(_:)`.
    ///
    /// - Parameters:
    ///   - text: The UTF8-encoded text to parse.
    ///   - oldTree: A previous syntax tree parsed from the same document.
    ///
    /// - Returns: A `Tree` if parsing succeeded, or `nil` if:
    ///     - The parser has not yet had a language assigned with
    ///     `Parser.setLanguage(_:)`
    ///     - The timeout set with `Parser.setTimeoutMicros(timeout:)` expired
    ///     - The cancellation flag set with `Parser.setCancellationFlag` was
    ///     flipped
    public func parse(text: String.UTF8View, oldTree: Tree? = nil) -> Tree? {
        let len = text.count
        return parseWith(oldTree: oldTree) { (i, _) in
            i < len
                ? text[text.index(text.startIndex, offsetBy: Int(i))...]
                : Substring().utf8
        }
    }
    
    public typealias ParseCallback = (CUnsignedInt, TSPoint) -> Substring.UTF8View
    typealias Payload = (ParseCallback, Substring.UTF8View?)
    typealias Read = @convention(c) (
        UnsafeMutableRawPointer?,
        CUnsignedInt,
        TSPoint,
        UnsafeMutablePointer<CUnsignedInt>?
    ) -> UnsafePointer<CChar>?
    
    /// Parse UTF8 text provided in chunks by a callback.
    ///
    /// - Parameters:
    ///   - oldTree: A previous syntax tree parsed from the same document.
    ///   If the text of the document has changed since `oldTree` was
    ///   created, then you must edit `oldTree` to match the new text using
    ///   `Tree.edit(_:)`.
    ///   - callback: A function that takes a byte offset and position and
    ///   returns a slice of UTF8-encoded text starting at that byte offset
    ///   and position. The slices can be of any length. If the given position
    ///   is at the end of the text, the callback should return an empty slice.
    ///
    /// - Returns: A `Tree` if parsing succeeded, or `nil`
    public func parseWith(
        oldTree: Tree? = nil,
        callback: @escaping ParseCallback
    ) -> Tree? {
        var payload: Payload = (callback, nil)

        let read: Read = { payload, byteOffset, position, bytesRead in
            var (callback, text) = payload!.load(as: Payload.self)
            text = callback(byteOffset, position)
            bytesRead?.pointee = CUnsignedInt(text!.count)
            return (String(text!) as NSString?)?.utf8String
        }

        let cInput = withUnsafeMutableBytes(of: &payload) {
            TSInput(
                payload: $0.baseAddress,
                read: read,
                encoding: TSInputEncodingUTF8
            )
        }

        let cNewTree = ts_parser_parse(parser, oldTree?.tree, cInput)
        guard let newTree = cNewTree else { return .none }
        return Tree(newTree)
    }
    
    /// Instruct the parser to start the next parse from the beginning.
    ///
    /// If the parser previously failed because of a timeout or a cancellation,
    /// then by default, it will resume where it left off on the next call to
    /// `parse` or other parsing functions. If you don't want to resume, and
    /// instead intend to use this parser to parse some other document, you must
    ///  call `reset` first.
    public func reset() {
        ts_parser_reset(parser)
    }
    
    /// Get the duration in microseconds that parsing is allowed to take.
    ///
    /// This is set via `Parser.setTimeoutMicros(timeout:)`.
    public func timeoutMicros() -> UInt64 {
        ts_parser_timeout_micros(parser)
    }
    
    /// Set the maximum duration in microseconds that parsing should be allowed
    /// to take before halting.
    ///
    /// If parsing takes longer than this, it will halt early, returning `None`.
    /// See `parse` for more information.
    public func setTimeoutMicros(timeout: CUnsignedLongLong) {
        ts_parser_set_timeout_micros(parser, timeout)
    }

    /// Set the ranges of text that the parser should include when parsing.
    ///
    /// By default, the parser will always include entire documents. This
    /// function allows you to parse only a *portion* of a document but still
    /// return a syntax tree whose ranges match up with the document as a whole.
    /// You can also pass multiple disjoint ranges.
    ///
    /// If `ranges` is empty, then the entire document will be parsed.
    /// Otherwise, the given ranges must be ordered from earliest to latest in
    /// the document, and they must not overlap. That is, the following must
    /// hold for all `i < length - 1`:
    /// ```
    /// ranges[i].endByte <= ranges[i + 1].startByte
    /// ```
    ///
    /// If this requirement is not satisfied, method will panic.
    public func setIncluded(
        ranges: [STSRange]
    ) -> Result<Void, IncludedRangesError> {
        let tsRanges = ranges.map(\.rawRange)
        
        guard ts_parser_set_included_ranges(
                parser,
                tsRanges,
                CUnsignedInt(tsRanges.count)
        ) else {
            var prevEndByte: CUnsignedInt = 0
            for (index, range) in tsRanges.enumerated() {
                if range.start_byte < prevEndByte || range.end_byte < range.start_byte {
                    return .failure(.range(CUnsignedInt(index)))
                }
                prevEndByte = range.end_byte
            }
            return .failure(.range(0))
        }
        
        return .success(())
    }

    /// Get the parser's current cancellation flag pointer.
    public func cancellationFlag() -> Int {
        ts_parser_cancellation_flag(parser).pointee
    }

    /// Set the parser's current cancellation flag pointer.
    ///
    /// If a pointer is assigned, then the parser will periodically read from
    /// this pointer during parsing. If it reads a non-zero value, it will halt
    /// early, returning `None`. See `Parser.parse(source:oldTree:)` for more
    /// information.
    public func setCancellation(flag: inout Int?) {
        guard flag == nil else {
            ts_parser_set_cancellation_flag(parser, nil)
            return
        }
        
        ts_parser_set_cancellation_flag(parser, &flag!)
    }
}
