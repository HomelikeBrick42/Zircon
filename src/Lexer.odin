package zircon

import "core:fmt"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

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

		if Lexer_CurrentChar(lexer^) == '#' {
			Lexer_NextChar(lexer)
			for
			    unicode.is_alpha(Lexer_CurrentChar(lexer^)) || unicode.is_number(
				    Lexer_CurrentChar(lexer^),
			    ) || Lexer_CurrentChar(lexer^) == '_' {
				Lexer_NextChar(lexer)
			}

			name := lexer.source[start_location.position + 1:lexer.position]
			if kind, ok := TokenKind_GetDirectiveKind(name).?; ok {
				return Token{
					kind = kind,
					location = start_location,
					length = lexer.position - start_location.position,
					data = nil,
				}, nil
			}
			error = Error {
				location = start_location,
				message  = fmt.aprintf("Unknown directive #%s", name),
			}
			return {}, error
		}

		if Lexer_CurrentChar(lexer^) == '"' {
			Lexer_NextChar(lexer)

			value: [dynamic]rune
			defer delete(value)
			for Lexer_CurrentChar(lexer^) != '"' {
				chr := Lexer_NextChar(lexer)
				if chr == 0 {
					error = Error {
						location = start_location,
						message  = fmt.aprintf("Unclosed string literal"),
					}
					return {}, error
				}
				append(&value, chr)
			}

			assert(Lexer_NextChar(lexer) == '"')
			return Token{
				kind = .String,
				location = start_location,
				length = lexer.position - start_location.position,
				data = utf8.runes_to_string(value[:]),
			}, nil
		}

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
			base := u128(10)
			if Lexer_CurrentChar(lexer^) == '0' {
				Lexer_NextChar(lexer)
				switch Lexer_CurrentChar(lexer^) {
				case 'b':
					Lexer_NextChar(lexer)
					base = 2
				case 'o':
					Lexer_NextChar(lexer)
					base = 8
				case 'd':
					Lexer_NextChar(lexer)
					base = 10
				case 'x':
					Lexer_NextChar(lexer)
					base = 16
				}
			}

			value: u128
			for
			    (Lexer_CurrentChar(lexer^) >= '0' && Lexer_CurrentChar(lexer^) <= '9') || (Lexer_CurrentChar(
				    lexer^,
			    ) >= 'A' && Lexer_CurrentChar(lexer^) <= 'Z') || (Lexer_CurrentChar(lexer^) >= 'a' &&
			    Lexer_CurrentChar(lexer^) <= 'z') || Lexer_CurrentChar(lexer^) == '_' {
				digit_location := lexer.location
				chr := Lexer_NextChar(lexer)

				digit_value: u128
				if chr >= '0' && chr <= '9' {
					digit_value = u128(chr) - '0'
				} else if chr >= 'A' && chr <= 'Z' {
					digit_value = u128(chr) - 'A' + 10
				} else if chr >= 'a' && chr <= 'z' {
					digit_value = u128(chr) - 'a' + 10
				} else {
					unreachable()
				}

				if digit_value >= base {
					error = Error {
						location = digit_location,
						message  = fmt.aprintf(
							"Digit '%c' (%d) is too big for base %d",
							chr,
							digit_value,
							base,
						),
					}
					return {}, error
				}

				value *= base
				value += digit_value
			}

			return Token{
				kind = .Integer,
				location = start_location,
				length = lexer.position - start_location.position,
				data = value,
			}, nil
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

Lexer_ExpectToken :: proc(lexer: ^Lexer, kind: TokenKind) -> (
	token: Token,
	error: Maybe(Error),
) {
	token = Lexer_NextToken(lexer) or_return
	if token.kind != kind {
		error = Error {
			location = token.location,
			message  = fmt.aprintf("Expected %v, but got %v", kind, token),
		}
		return {}, error
	}
	return token, nil
}
