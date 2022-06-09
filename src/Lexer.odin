package zircon

import "core:fmt"
import "core:strings"
import "core:unicode"

Lexer :: struct {
	using location: SourceLocation,
	source:         string,
	rune_reader:    strings.Reader,
}

Lexer_Init :: proc(lexer: ^Lexer, filepath, source: string) {
	lexer.filepath = filepath
	lexer.position = 0
	lexer.line = 1
	lexer.column = 1
	lexer.source = source
	strings.reader_init(&lexer.rune_reader, lexer.source)
}

Lexer_CurrentChar :: proc(lexer: Lexer) -> rune {
	reader_copy := lexer.rune_reader
	chr, _, _ := strings.reader_read_rune(&reader_copy)
	return chr
}

Lexer_NextChar :: proc(lexer: ^Lexer) -> rune {
	chr, size, _ := strings.reader_read_rune(&lexer.rune_reader)
	if chr != 0 {
		lexer.position += uint(size)
		lexer.column += 1
		if chr == '\n' {
			lexer.line += 1
			lexer.column = 1
		}
	}
	return chr
}

Lexer_CurrentToken :: proc(lexer: Lexer) -> (token: Token, error: Maybe(Error)) {
	copy := lexer
	return Lexer_NextToken(&copy)
}

Lexer_NextToken :: proc(lexer: ^Lexer) -> (token: Token, error: Maybe(Error)) {
	for {
		start_location := lexer.location

		if unicode.is_alpha(Lexer_CurrentChar(lexer^)) || Lexer_CurrentChar(lexer^) == '_' {
			for
			    unicode.is_alpha(Lexer_CurrentChar(lexer^)) || unicode.is_number(
				    Lexer_CurrentChar(lexer^),
			    ) || Lexer_CurrentChar(lexer^) == '_' {
				Lexer_NextChar(lexer)
			}

			name := lexer.source[start_location.position:lexer.position]
			if kind, ok := TokenKind_GetKeywordKind(name).?; ok {
				return Token{
					kind = kind,
					location = start_location,
					length = lexer.position - start_location.position,
					data = nil,
				}, nil
			}
			return Token{
				kind = .Name,
				location = start_location,
				length = lexer.position - start_location.position,
				data = name,
			}, nil
		}

		if Lexer_CurrentChar(lexer^) >= '0' && Lexer_CurrentChar(lexer^) <= '9' {
			error = Error {
				location = start_location,
				message  = fmt.aprintf("integer lexing is not implemented :)"),
			}
			return {}, error
		}

		chr := Lexer_NextChar(lexer)
		if chr == ' ' || chr == '\t' || chr == '\r' {
			continue
		}

		if kind, ok := TokenKind_GetDoubleCharKind(chr, Lexer_CurrentChar(lexer^)).?; ok {
			Lexer_NextChar(lexer)
			return Token{
				kind = kind,
				location = start_location,
				length = lexer.position - start_location.position,
				data = nil,
			}, nil
		}

		if kind, ok := TokenKind_GetCharKind(chr).?; ok {
			return Token{
				kind = kind,
				location = start_location,
				length = lexer.position - start_location.position,
				data = nil,
			}, nil
		}

		error = Error {
			location = start_location,
			message  = fmt.aprintf("Unexpected character '%c'", chr),
		}
		return {}, error
	}
}
