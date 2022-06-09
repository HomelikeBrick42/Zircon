package zircon

import "core:io"
import "core:fmt"

main :: proc() {
	SetupFormatters()
}

SetupFormatters :: proc() {
	@(static)
	formatters: map[typeid]fmt.User_Formatter
	fmt.set_user_formatters(&formatters)

	WriteTokenKind :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
		_, err := io.write_string(fi.writer, TokenKind_ToString(arg.(TokenKind)))
		return err != nil
	}
	fmt.register_user_formatter(typeid_of(TokenKind), WriteTokenKind)

	WriteToken :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
		_, err := io.write_string(
			fi.writer,
			Token_ToString(arg.(Token), context.temp_allocator),
		)
		return err != nil
	}
	fmt.register_user_formatter(typeid_of(Token), WriteToken)
}
