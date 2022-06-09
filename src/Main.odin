package zircon

import "core:io"
import "core:os"
import "core:fmt"

main :: proc() {
	SetupFormatters()

	program_name := os.args[0]
	if len(os.args) != 3 {
		fmt.eprintf("Usage: %s <command> <file>\n", program_name)
		os.exit(1)
	}

	filepath := os.args[2]
	bytes, ok := os.read_entire_file(filepath)
	if !ok {
		fmt.eprintf("Unable to open file '%s'\n", filepath)
		os.exit(1)
	}
	defer delete(bytes)
	source := string(bytes)

	command := os.args[1]
	switch command {
	case "show_tokens":
		lexer: Lexer
		Lexer_Init(&lexer, filepath, source)
		for {
			token, error := Lexer_NextToken(&lexer)
			if error, ok := error.?; ok {
				fmt.eprintf("%v: %s\n", error.location, error.message)
				os.exit(1)
			}
			fmt.printf("%v: %v\n", token.location, token)
			if token.kind == .EndOfFile do break
		}
	case:
		fmt.eprintf("Unknown command '%s'\n", command)
		os.exit(1)
	}
	return
}

SetupFormatters :: proc() {
	@(static)
	formatters: map[typeid]fmt.User_Formatter
	fmt.set_user_formatters(&formatters)

	WriteSourceLocation :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
		io.write_string(
			fi.writer,
			SourceLocation_ToString(arg.(SourceLocation), context.temp_allocator),
		)
		return true
	}
	fmt.register_user_formatter(SourceLocation, WriteSourceLocation)

	WriteTokenKind :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
		io.write_string(fi.writer, TokenKind_ToString(arg.(TokenKind)))
		return true
	}
	fmt.register_user_formatter(TokenKind, WriteTokenKind)

	WriteToken :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
		io.write_string(fi.writer, Token_ToString(arg.(Token), context.temp_allocator))
		return true
	}
	fmt.register_user_formatter(Token, WriteToken)
}
