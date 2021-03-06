package zircon

import "core:io"
import "core:os"
import "core:fmt"
import "core:strings"

main :: proc() {
	SetupFormatters()

	program_name := os.args[0]
	if len(os.args) != 3 {
		fmt.eprintf("Usage: %s <command> <file>\n", program_name)
		fmt.eprintf("Commands:\n")
		fmt.eprintf("    show_tokens - prints all of the tokens in the file\n")
		fmt.eprintf("    show_ast    - prints the ast\n")
		fmt.eprintf("    check_ast   - type checks and prints the ast\n")
		fmt.eprintf("    check       - type checks the program\n")
		fmt.eprintf("    emit_c      - emits C code\n")
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
	case "show_ast":
		ast, error := ParseFile(filepath, source)
		if error, ok := error.?; ok {
			fmt.eprintf("%v: %s\n", error.location, error.message)
			os.exit(1)
		}
		DumpAst(ast, 0)
	case "check_ast":
		ast, error := ParseFile(filepath, source)
		if error, ok := error.?; ok {
			fmt.eprintf("%v: %s\n", error.location, error.message)
			os.exit(1)
		}

		names: [dynamic]Scope
		defer {
			for scope in names {
				delete(scope)
			}
			delete(names)
		}

		error = ResolveAst(ast, &names)
		if error, ok := error.?; ok {
			fmt.eprintf("%v: %s\n", error.location, error.message)
			os.exit(1)
		}
		DumpAst(ast, 0)
	case "check":
		ast, error := ParseFile(filepath, source)
		if error, ok := error.?; ok {
			fmt.eprintf("%v: %s\n", error.location, error.message)
			os.exit(1)
		}

		names: [dynamic]Scope
		defer {
			for scope in names {
				delete(scope)
			}
			delete(names)
		}

		error = ResolveAst(ast, &names)
		if error, ok := error.?; ok {
			fmt.eprintf("%v: %s\n", error.location, error.message)
			os.exit(1)
		}
	case "emit_c":
		ast, error := ParseFile(filepath, source)
		if error, ok := error.?; ok {
			fmt.eprintf("%v: %s\n", error.location, error.message)
			os.exit(1)
		}

		names: [dynamic]Scope
		defer {
			for scope in names {
				delete(scope)
			}
			delete(names)
		}

		error = ResolveAst(ast, &names)
		if error, ok := error.?; ok {
			fmt.eprintf("%v: %s\n", error.location, error.message)
			os.exit(1)
		}

		buffer := strings.make_builder()
		defer strings.destroy_builder(&buffer)
		EmitAst_C(ast, 0, &buffer)

		if !os.write_entire_file("output.c", transmute([]byte)strings.to_string(buffer)) {
			fmt.eprintln("Failed to open 'output.c'\n")
			os.exit(1)
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

	WriteType :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
		io.write_string(fi.writer, Type_ToString(arg.(Type), context.temp_allocator))
		return true
	}
	fmt.register_user_formatter(Type, WriteType)
}
