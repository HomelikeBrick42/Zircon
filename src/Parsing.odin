package zircon

import "core:fmt"

ParseFile :: proc(filepath, source: string) -> (ast: ^AstFile, error: Maybe(Error)) {
	lexer: Lexer
	Lexer_Init(&lexer, filepath, source)
	file := new(AstFile)
	file.filepath = filepath
	for {
		AllowMultipleNewlines(&lexer)
		if Lexer_CurrentToken(lexer) or_return.kind == .EndOfFile do break
		append(&file.statements, ParseStatement(&lexer) or_return)
		Lexer_ExpectToken(&lexer, .Newline) or_return
		if Lexer_CurrentToken(lexer) or_return.kind == .EndOfFile do break
	}
	file.end_of_file_token = Lexer_ExpectToken(&lexer, .EndOfFile) or_return
	return file, nil
}

ParseScope :: proc(lexer: ^Lexer) -> (ast: ^AstScope, error: Maybe(Error)) {
	scope := new(AstScope)
	scope.open_brace_token = Lexer_ExpectToken(lexer, .OpenBrace) or_return
	for {
		AllowMultipleNewlines(lexer)
		if Lexer_CurrentToken(lexer^) or_return.kind == .CloseBrace do break
		append(&scope.statements, ParseStatement(lexer) or_return)
		Lexer_ExpectToken(lexer, .Newline) or_return
		if Lexer_CurrentToken(lexer^) or_return.kind == .CloseBrace do break
	}
	scope.close_brace_token = Lexer_ExpectToken(lexer, .CloseBrace) or_return
	return scope, nil
}

ParseIf :: proc(lexer: ^Lexer) -> (ast: ^AstIf, error: Maybe(Error)) {
	if_ := new(AstIf)
	if_.if_token = Lexer_ExpectToken(lexer, .If) or_return
	if_.condition = ParseExpression(lexer) or_return
	if_.then_body = ParseScope(lexer) or_return
	if Lexer_CurrentToken(lexer^) or_return.kind == .Else {
		if_.else_token = Lexer_ExpectToken(lexer, .Else) or_return
		if_.else_body = ParseScope(lexer) or_return
	}
	return if_, nil
}

ParseStatement :: proc(lexer: ^Lexer) -> (ast: AstStatement, error: Maybe(Error)) {
	#partial switch Lexer_CurrentToken(lexer^) or_return.kind {
	case .OpenBrace:
		return ParseScope(lexer)
	case .If:
		return ParseIf(lexer)
	case .While:
		while := new(AstWhile)
		while.while_token = Lexer_ExpectToken(lexer, .While) or_return
		while.condition = ParseExpression(lexer) or_return
		while.body = ParseScope(lexer) or_return
		return while, nil
	case .Extern:
		declaration := new(AstExternDeclaration)
		declaration.extern_token = Lexer_ExpectToken(lexer, .Extern) or_return
		declaration.name_token = Lexer_ExpectToken(lexer, .Name) or_return
		declaration.colon_token = Lexer_ExpectToken(lexer, .Colon) or_return
		declaration.type = ParseExpression(lexer) or_return
		return declaration, nil
	case .Name:
		copy := lexer^
		name_token := Lexer_ExpectToken(lexer, .Name) or_return
		if Lexer_CurrentToken(lexer^) or_return.kind == .Colon {
			declaration := new(AstDeclaration)
			declaration.name_token = name_token
			declaration.colon_token = Lexer_ExpectToken(lexer, .Colon) or_return
			if Lexer_CurrentToken(lexer^) or_return.kind != .Equal {
				declaration.type = ParseExpression(lexer) or_return
			}
			if Lexer_CurrentToken(lexer^) or_return.kind == .Equal {
				declaration.equal_token = Lexer_ExpectToken(lexer, .Equal) or_return
				declaration.value = ParseExpression(lexer) or_return
			}
			return declaration, nil
		} else {
			lexer^ = copy
		}
		fallthrough
	case:
		expression := ParseExpression(lexer) or_return
		if Lexer_CurrentToken(lexer^) or_return.kind == .Equal {
			assignment := new(AstAssignment)
			assignment.operand = expression
			assignment.equal_token = Lexer_ExpectToken(lexer, .Equal) or_return
			assignment.value = ParseExpression(lexer) or_return
			return assignment, nil
		}
		return expression, nil
	}
	unreachable()
}

ParseExpression :: proc(lexer: ^Lexer) -> (ast: AstExpression, error: Maybe(Error)) {
	return ParseBinaryExpression(lexer, 0)
}

ParsePrimaryExpression :: proc(lexer: ^Lexer) -> (
	ast: AstExpression,
	error: Maybe(Error),
) {
	#partial switch Lexer_CurrentToken(lexer^) or_return.kind {
	case .OpenParenthesis:
		Lexer_ExpectToken(lexer, .OpenParenthesis) or_return
		expression := ParseExpression(lexer) or_return
		Lexer_ExpectToken(lexer, .CloseParenthesis) or_return
		return expression, nil
	case .Proc:
		proc_ := new(AstProcedure)
		proc_.proc_token = Lexer_ExpectToken(lexer, .Proc) or_return
		proc_.open_parenthesis_token = Lexer_ExpectToken(lexer, .OpenParenthesis) or_return
		for {
			AllowNewline(lexer) or_return
			if Lexer_CurrentToken(lexer^) or_return.kind == .CloseParenthesis do break
			parameter := new(AstDeclaration)
			parameter.name_token = Lexer_ExpectToken(lexer, .Name) or_return
			parameter.colon_token = Lexer_ExpectToken(lexer, .Colon) or_return
			parameter.type = ParseExpression(lexer) or_return
			append(&proc_.parameters, parameter)
			if Lexer_CurrentToken(lexer^) or_return.kind == .CloseParenthesis do break
			Lexer_ExpectToken(lexer, .Comma) or_return
		}
		proc_.close_parenthesis_token = Lexer_ExpectToken(lexer, .CloseParenthesis) or_return
		proc_.right_arrow_token = Lexer_ExpectToken(lexer, .RightArrow) or_return
		proc_.return_type = ParseExpression(lexer) or_return
		if Lexer_CurrentToken(lexer^) or_return.kind == .Extern {
			proc_.extern_token = Lexer_ExpectToken(lexer, .Extern) or_return
			proc_.extern_string_token = Lexer_ExpectToken(lexer, .String) or_return
		}
		return proc_, nil
	case .Name:
		name := new(AstName)
		name.name_token = Lexer_ExpectToken(lexer, .Name) or_return
		return name, nil
	case .Integer:
		integer := new(AstInteger)
		integer.integer_token = Lexer_ExpectToken(lexer, .Integer) or_return
		return integer, nil
	case:
		token := Lexer_NextToken(lexer) or_return
		error = Error {
			location = token.location,
			message  = fmt.aprintf("Unexpected token %v", token),
		}
		return {}, error
	}
}

ParseBinaryExpression :: proc(lexer: ^Lexer, parent_precedence: uint) -> (
	ast: AstExpression,
	error: Maybe(Error),
) {
	GetUnaryPrecedence :: proc(kind: TokenKind) -> (
		precedence: uint,
		unary_operator_kind: UnaryOperatorKind,
	) {
		#partial switch kind {
		case .Plus:
			return 4, .Identity
		case .Minus:
			return 4, .Negation
		case .ExclamationMark:
			return 4, .LogicalNot
		case .Caret:
			return 4, .Invalid
		case .Asterisk:
			return 4, .Pointer
		case:
			return 0, .Invalid
		}
	}

	GetBinaryPrecedence :: proc(kind: TokenKind) -> (
		precedence: uint,
		binary_operator_kind: BinaryOperatorKind,
	) {
		#partial switch kind {
		case .Asterisk:
			return 3, .Multiplication
		case .Slash:
			return 3, .Division
		case .Plus:
			return 2, .Addition
		case .Minus:
			return 2, .Subtraction
		case .EqualEqual:
			return 1, .Equal
		case .ExclamationMarkEqual:
			return 1, .NotEqual
		case:
			return 0, .Invalid
		}
	}

	left: AstExpression
	if unary_precedence, kind := GetUnaryPrecedence(
		   Lexer_CurrentToken(lexer^) or_return.kind,
	   ); unary_precedence > 0 {
		#partial switch Lexer_CurrentToken(lexer^) or_return.kind {
		case .Caret:
			address_of := new(AstAddressOf)
			address_of.caret_token = Lexer_ExpectToken(lexer, .Caret) or_return
			address_of.operand = ParseBinaryExpression(lexer, unary_precedence) or_return
			left = address_of
		case:
			unary := new(AstUnary)
			unary.operator_kind = kind
			unary.operator_token = Lexer_NextToken(lexer) or_return
			unary.operand = ParseBinaryExpression(lexer, unary_precedence) or_return
			left = unary
		}
	} else {
		left = ParsePrimaryExpression(lexer) or_return
	}

	loop: for {
		#partial switch Lexer_CurrentToken(lexer^) or_return.kind {
		case .OpenParenthesis:
			call := new(AstCall)
			call.operand = left
			call.open_parenthesis_token = Lexer_ExpectToken(lexer, .OpenParenthesis) or_return
			for {
				AllowNewline(lexer) or_return
				if Lexer_CurrentToken(lexer^) or_return.kind == .CloseParenthesis do break
				append(&call.arguments, ParseExpression(lexer) or_return)
				if Lexer_CurrentToken(lexer^) or_return.kind == .CloseParenthesis do break
				Lexer_ExpectToken(lexer, .Comma) or_return
			}
			call.close_parenthesis_token = Lexer_ExpectToken(lexer, .CloseParenthesis) or_return
			left = call
		case .Caret:
			dereference := new(AstDereference)
			dereference.operand = left
			dereference.caret_token = Lexer_ExpectToken(lexer, .Caret) or_return
			left = dereference
		case:
			binary_precedence, kind := GetBinaryPrecedence(
				Lexer_CurrentToken(lexer^) or_return.kind,
			)
			if kind == .Invalid || binary_precedence <= parent_precedence do break loop

			binary := new(AstBinary)
			binary.left = left
			binary.operator_kind = kind
			binary.operator_token = Lexer_NextToken(lexer) or_return
			binary.right = ParseBinaryExpression(lexer, binary_precedence) or_return
			left = binary
		}
	}

	return left, nil
}

AllowNewline :: proc(lexer: ^Lexer) -> (error: Maybe(Error)) {
	if Lexer_CurrentToken(lexer^) or_return.kind == .Newline {
		Lexer_NextToken(lexer)
	}
	return nil
}

AllowMultipleNewlines :: proc(lexer: ^Lexer) -> (error: Maybe(Error)) {
	for Lexer_CurrentToken(lexer^) or_return.kind == .Newline {
		Lexer_NextToken(lexer)
	}
	return nil
}
