//
//  Parser.swift
//
//
//  Created by Gustavo Ordaz on 7/22/20.
//

import TreeSitter


public enum IncludedRangesError: Error {
    case range(uint)
}

public class Parser {
    var parser: OpaquePointer
    
    /// Create a new parser.
    public init() {
        self.parser = ts_parser_new()
    }
    
    deinit {
        ts_parser_delete(parser)
    }
    
    /// Set the language that the parser should use for parsing.
    ///
    /// Returns a Result indicating whether or not the language was successfully
    /// assigned. True means assignment succeeded. False means there was a version
    /// mismatch: the language was generated with an incompatible version of the
    /// Tree-sitter CLI. Check the language's version using [Language::version]
    /// and compare it to this library's [LANGUAGE_VERSION](LANGUAGE_VERSION) and
    /// [MIN_COMPATIBLE_LANGUAGE_VERSION](MIN_COMPATIBLE_LANGUAGE_VERSION) constants.
    @discardableResult
    public func setLanguage(_ language: Language) -> Result<Void, LanguageError> {
        let version = language.version
        
        if version < MIN_COMPATIBLE_LANGUAGE_VERSION || version > LANGUAGE_VERSION {
            return .failure(.version(version))
        }
        
        let res = ts_parser_set_language(parser, language.language)
        
        if res {
            return .success(())
        }
        
        return .failure(.version(version))
    }
    
    /// Get the parser's current language.
    public func language() -> Language? {
        let ptr = ts_parser_language(parser)
        guard let pointer = ptr else { return nil }
        
        return Language(pointer)
    }
    
    public func parse(source: String, oldTree: Tree? = nil) -> Tree? {
        let res = ts_parser_parse_string(
            parser,
            oldTree?.tree,
            source,
            UInt32(source.count)
        )
        
        guard let tree = res else { return .none }
        return Tree(tree)
    }
    
    /// Parse a slice of UTF8 text.
    ///
    /// # Arguments:
    /// * `text` The UTF8-encoded text to parse.
    /// * `old_tree` A previous syntax tree parsed from the same document.
    ///   If the text of the document has changed since `old_tree` was
    ///   created, then you must edit `old_tree` to match the new text using
    ///   [Tree::edit].
    ///
    /// Returns a [Tree] if parsing succeeded, or `None` if:
    ///  * The parser has not yet had a language assigned with [Parser::set_language]
    ///  * The timeout set with [Parser::set_timeout_micros] expired
    ///  * The cancellation flag set with [Parser::set_cancellation_flag] was flipped
    public func parse(text: String, oldTree: Tree? = nil) -> Tree? {
        let bytes = text.utf8CString
        let len = bytes.count
        return parseWith(oldTree: oldTree) { (i, point) in
            i < len ? bytes[Int(i)...] : []
        }
    }
    
    /// Parse UTF8 text provided in chunks by a callback.
    ///
    /// # Arguments:
    /// * `callback` A function that takes a byte offset and position and
    ///   returns a slice of UTF8-encoded text starting at that byte offset
    ///   and position. The slices can be of any length. If the given position
    ///   is at the end of the text, the callback should return an empty slice.
    /// * `old_tree` A previous syntax tree parsed from the same document.
    ///   If the text of the document has changed since `old_tree` was
    ///   created, then you must edit `old_tree` to match the new text using
    ///   [Tree::edit].
    public typealias UTF8StringSlice = ArraySlice<CChar>
    public typealias ParseCallback = (UInt32, TSPoint) -> UTF8StringSlice
    public func parseWith(
        oldTree: Tree? = nil,
        callback: @escaping ParseCallback
    ) -> Tree? {
        typealias Payload = (ParseCallback, UTF8StringSlice?)
        var payload: Payload = (callback, nil)
        
        typealias Read = @convention(c) (
            UnsafeMutableRawPointer?,
            UInt32,
            TSPoint,
            UnsafeMutablePointer<UInt32>?
        ) -> UnsafePointer<Int8>?

        let read: Read = { payload, byteOffset, position, bytesRead in
            var (callback, text) = payload!.load(as: Payload.self)
            text = callback(byteOffset, position)
            
            return text?.withUnsafeBufferPointer {
                bytesRead!.pointee = UInt32($0.count)
                return $0.baseAddress!
            }
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
    /// If the parser previously failed because of a timeout or a cancellation, then
    /// by default, it will resume where it left off on the next call to `parse` or
    /// other parsing functions. If you don't want to resume, and instead intend to
    /// use this parser to parse some other document, you must call `reset` first.
    public func reset() {
        ts_parser_reset(parser)
    }
    
    /// Get the duration in microseconds that parsing is allowed to take.
    ///
    /// This is set via [set_timeout_micros](Parser::set_timeout_micros).
    public func timeoutMicros() -> UInt64 {
        ts_parser_timeout_micros(parser)
    }
    
    /// Set the maximum duration in microseconds that parsing should be allowed to
    /// take before halting.
    ///
    /// If parsing takes longer than this, it will halt early, returning `None`.
    /// See `parse` for more information.
    public func setTimeoutMicros(timeout: UInt64) {
        ts_parser_set_timeout_micros(parser, timeout)
    }

    /// Set the ranges of text that the parser should include when parsing.
    ///
    /// By default, the parser will always include entire documents. This function
    /// allows you to parse only a *portion* of a document but still return a syntax
    /// tree whose ranges match up with the document as a whole. You can also pass
    /// multiple disjoint ranges.
    ///
    /// If `ranges` is empty, then the entire document will be parsed. Otherwise,
    /// the given ranges must be ordered from earliest to latest in the document,
    /// and they must not overlap. That is, the following must hold for all
    /// `i` < `length - 1`:
    /// ```text
    ///     ranges[i].end_byte <= ranges[i + 1].start_byte
    /// ```
    /// If this requirement is not satisfied, method will panic.
    public func setIncludedRanges(_ ranges: [TSRange]) -> Result<Void, IncludedRangesError> {
        var tsRanges = ranges
        let result = withUnsafePointer(to: &tsRanges) {
            ts_parser_set_included_ranges(parser, $0[0], UInt32($0.pointee.count))
        }
        
        if result {
            return .success(())
        } else {
            var prevEndByte: UInt32 = 0
            for (index, range) in tsRanges.enumerated() {
                if range.start_byte < prevEndByte || range.end_byte < range.start_byte {
                    return .failure(.range(uint(index)))
                }
                prevEndByte = range.end_byte
            }
            return .failure(.range(0))
        }
    }

    /// Get the parser's current cancellation flag pointer.
    public func cancellationFlag() -> UnsafePointer<Int> {
        ts_parser_cancellation_flag(parser)
    }

    /// Set the parser's current cancellation flag pointer.
    ///
    /// If a pointer is assigned, then the parser will periodically read from
    /// this pointer during parsing. If it reads a non-zero value, it will halt early,
    /// returning `None`. See [parse](Parser::parse) for more information.
    public func setCancellation(flag: UnsafePointer<Int>?) {
        guard let flag = flag else {
            ts_parser_set_cancellation_flag(parser, nil)
            return
        }
        
        ts_parser_set_cancellation_flag(parser, flag)
    }
}
