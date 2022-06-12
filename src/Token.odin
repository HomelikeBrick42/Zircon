package zircon

import "core:fmt"
import "core:strings"

SourceLocation :: struct {
	filepath: string,
	position: uint,
	line:     uint,
	column:   uint,
}

SourceLocation_ToString :: proc(
	location: SourceLocation,
	allocator := context.allocator,
) -> string {
	context.allocator = allocator
	return fmt.aprintf("%s:%d:%d", location.filepath, location.line, location.column)
}

TokenKind :: enum {
	Invalid,

	// Special
	EndOfFile,
	Newline,
	Name,
	Integer,

	// Symbols
	OpenParenthesis,
	CloseParenthesis,
	OpenBrace,
	CloseBrace,
	Colon,
	Comma,
	Equal,

	// Operators
	Plus,
	Minus,
	Asterisk,
	Slash,
	EqualEqual,
	ExclamationMark,
	ExclamationMarkEqual,
	Caret,

	// Keywords
	If,
	Else,
	While,
}

TokenKind_GetKeywordKind :: proc(name: string) -> Maybe(TokenKind) {
	switch name {
	case "if":
		return .If
	case "else":
		return .Else
	case "while":
		return .While
	case:
		return nil
	}
}

TokenKind_GetCharKind :: proc(chr: rune) -> Maybe(TokenKind) {
	switch chr {
	case 0:
		return .EndOfFile
	case '\n':
		return .Newline
	case '(':
		return .OpenParenthesis
	case ')':
		return .CloseParenthesis
	case '{':
		return .OpenBrace
	case '}':
		return .CloseBrace
	case ':':
		return .Colon
	case ',':
		return .Comma
	case '=':
		return .Equal
	case '+':
		return .Plus
	case '-':
		return .Minus
	case '*':
		return .Asterisk
	case '/':
		return .Slash
	case '!':
		return .ExclamationMark
	case '^':
		return .Caret
	case:
		return nil
	}
}

TokenKind_GetDoubleCharKind :: proc(first: rune, second: rune) -> Maybe(TokenKind) {
	switch ([2]rune{first, second}) {
	case {'=', '='}:
		return .EqualEqual
	case {'!', '='}:
		return .ExclamationMarkEqual
	case:
		return nil
	}
}

TokenKind_ToString :: proc(kind: TokenKind) -> string {
	switch kind {
	case .Invalid:
		break
	case .EndOfFile:
		return "{end of file}"
	case .Newline:
		return "{newline}"
	case .Name:
		return "{name}"
	case .Integer:
		return "{integer}"
	case .OpenParenthesis:
		return "("
	case .CloseParenthesis:
		return ")"
	case .OpenBrace:
		return "{"
	case .CloseBrace:
		return "}"
	case .Colon:
		return ":"
	case .Comma:
		return ","
	case .Equal:
		return "="
	case .Plus:
		return "+"
	case .Minus:
		return "-"
	case .Asterisk:
		return "*"
	case .Slash:
		return "/"
	case .EqualEqual:
		return "=="
	case .ExclamationMark:
		return "!"
	case .ExclamationMarkEqual:
		return "!="
	case .Caret:
		return "^"
	case .If:
		return "if"
	case .Else:
		return "else"
	case .While:
		return "while"
	}
	return "{invalid}"
}

Token :: struct {
	kind:           TokenKind,
	using location: SourceLocation,
	length:         uint,
	data:           TokenData,
}

TokenData :: union {
	string,
	u128,
}

Token_ToString :: proc(token: Token, allocator := context.allocator) -> string {
	context.allocator = allocator
	switch token.kind {
	case .Invalid, .EndOfFile, .Newline, .OpenParenthesis, .CloseParenthesis, .OpenBrace, .CloseBrace, .Colon, .Comma, .Equal, .Plus, .Minus, .Asterisk, .Slash, .EqualEqual, .ExclamationMark, .ExclamationMarkEqual, .Caret, .If, .Else, .While:
		break
	case .Name:
		return fmt.aprintf("'%s'", token.data.(string))
	case .Integer:
		return fmt.aprintf("%d", token.data.(u128))
	}
	return strings.clone(TokenKind_ToString(token.kind))
}
