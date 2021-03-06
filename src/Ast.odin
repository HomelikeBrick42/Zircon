package zircon

import "core:fmt"

Ast :: union #shared_nil {
	^AstFile,
	AstStatement,
}

AstStatement :: union #shared_nil {
	^AstScope,
	^AstDeclaration,
	^AstExternDeclaration,
	^AstAssignment,
	^AstIf,
	^AstWhile,
	AstExpression,
}

AstExpression :: union #shared_nil {
	^AstUnary,
	^AstBinary,
	^AstCall,
	^AstAddressOf,
	^AstDereference,
	^AstName,
	^AstInteger,
	^AstProcedure,
	^AstArray,
	^AstIndex,
	^AstCast,
	^AstTransmute,
	^AstSizeOf,
	^AstTypeOf,
}

AstFile :: struct {
	filepath:          string,
	statements:        [dynamic]AstStatement,
	end_of_file_token: Token,
}

AstScope :: struct {
	open_brace_token:  Token,
	statements:        [dynamic]AstStatement,
	close_brace_token: Token,
}

AstDeclaration :: struct {
	resolved_type:        Type,
	name_token:           Token,
	colon_token:          Token,
	type:                 Maybe(AstExpression),
	colon_or_equal_token: Maybe(Token),
	value:                Maybe(AstExpression),
	resolved_value:       Maybe(Value),
}

IsDeclarationConstant :: proc(decl: ^AstDeclaration) -> bool {
	if colon, ok := decl.colon_or_equal_token.?; ok && colon.kind == .Colon {
		return true
	}
	return false
}

AstExternDeclaration :: struct {
	resolved_type: Type,
	extern_token:  Token,
	name_token:    Token,
	colon_token:   Token,
	type:          AstExpression,
}

AstAssignment :: struct {
	operand:     AstExpression,
	equal_token: Token,
	value:       AstExpression,
}

AstIf :: struct {
	if_token:   Token,
	condition:  AstExpression,
	then_body:  ^AstScope,
	else_token: Token,
	else_body:  Maybe(^AstScope),
}

AstWhile :: struct {
	while_token: Token,
	condition:   AstExpression,
	body:        ^AstScope,
}

UnaryOperatorKind :: enum {
	Invalid,
	Identity,
	Negation,
	LogicalNot,
	Pointer,
}

AstUnary :: struct {
	type:           Type,
	operator_kind:  UnaryOperatorKind,
	operator_token: Token,
	operand:        AstExpression,
}

BinaryOperatorKind :: enum {
	Invalid,
	Addition,
	Subtraction,
	Multiplication,
	Division,
	Equal,
	NotEqual,
}

AstBinary :: struct {
	type:           Type,
	left:           AstExpression,
	operator_kind:  BinaryOperatorKind,
	operator_token: Token,
	right:          AstExpression,
}

AstCall :: struct {
	operand:                 AstExpression,
	open_parenthesis_token:  Token,
	arguments:               [dynamic]AstExpression,
	close_parenthesis_token: Token,
}

AstAddressOf :: struct {
	caret_token: Token,
	operand:     AstExpression,
}

AstDereference :: struct {
	operand:     AstExpression,
	caret_token: Token,
}

AstName :: struct {
	name_token:    Token,
	resolved_decl: Decl,
}

AstInteger :: struct {
	type:          Type,
	integer_token: Token,
}

AstProcedure :: struct {
	type:                    Type,
	proc_token:              Token,
	open_parenthesis_token:  Token,
	parameters:              [dynamic]^AstDeclaration,
	close_parenthesis_token: Token,
	right_arrow_token:       Token,
	return_type:             AstExpression,
	resolved_return_type:    Type,
	body:                    Maybe(^AstScope),
	extern_token:            Maybe(Token),
	extern_string_token:     Maybe(
		Token,
	), // TODO: make this a calculated string value, so it could be computed from other constants at compile time
}

AstArray :: struct {
	type:                       Type,
	open_square_bracket_token:  Token,
	length:                     AstExpression,
	resolved_length:            uint,
	close_square_bracket_token: Token,
	inner_type:                 AstExpression,
	resolved_inner_type:        Type,
}

AstIndex :: struct {
	operand:                    AstExpression,
	open_square_bracket_token:  Token,
	index:                      AstExpression,
	close_square_bracket_token: Token,
}

AstCast :: struct {
	cast_token:              Token,
	open_parenthesis_token:  Token,
	type:                    AstExpression,
	resolved_type:           Type,
	close_parenthesis_token: Token,
	operand:                 AstExpression,
}

AstTransmute :: struct {
	transmute_token:         Token,
	open_parenthesis_token:  Token,
	type:                    AstExpression,
	resolved_type:           Type,
	close_parenthesis_token: Token,
	operand:                 AstExpression,
}

AstSizeOf :: struct {
	integer_type:            Type,
	size_of_token:           Token,
	open_parenthesis_token:  Token,
	type:                    AstExpression,
	resolved_type:           Type,
	close_parenthesis_token: Token,
}

AstTypeOf :: struct {
	type_type:               Type,
	type_of_token:           Token,
	open_parenthesis_token:  Token,
	expression:              AstExpression,
	close_parenthesis_token: Token,
}

GetType :: proc(expression: AstExpression) -> Type {
	switch expression in expression {
	case ^AstUnary:
		return expression.type
	case ^AstBinary:
		return expression.type
	case ^AstCall:
		type := GetType(expression.operand)
		if type == nil do return nil
		return type.(^TypeProcedure).return_type
	case ^AstAddressOf:
		type := GetType(expression.operand)
		if type == nil do return nil
		return GetPointerType(type)
	case ^AstDereference:
		type := GetType(expression.operand)
		if type == nil do return nil
		return type.(^TypePointer).pointer_to
	case ^AstName:
		return GetDeclType(expression.resolved_decl)
	case ^AstInteger:
		return expression.type
	case ^AstProcedure:
		return expression.type
	case ^AstArray:
		return expression.type
	case ^AstIndex:
		type := GetType(expression.operand)
		if type == nil do return nil
		return type.(^TypeArray).inner_type
	case ^AstCast:
		return expression.resolved_type
	case ^AstTransmute:
		return expression.resolved_type
	case ^AstSizeOf:
		return expression.integer_type
	case ^AstTypeOf:
		return expression.type_type
	case:
		unreachable()
	}
}

DumpAst :: proc(ast: Ast, indent: uint) {
	PrintIndent :: proc(indent: uint) {
		for _ in 0 ..< indent {
			fmt.print("  ")
		}
	}

	PrintHeader :: proc(title: string, location: SourceLocation, type: Type, indent: uint) {
		PrintIndent(indent)
		fmt.println("-", title)
		PrintIndent(indent + 1)
		fmt.println("Location:", location)
		if type != nil {
			PrintIndent(indent + 1)
			fmt.println("Type:")
			DumpType(type, indent + 2)
		}
	}

	switch ast in ast {
	case ^AstFile:
		PrintHeader(
			"File",
			SourceLocation{
				filepath = ast.end_of_file_token.filepath,
				position = 0,
				line = 1,
				column = 1,
			},
			nil,
			indent,
		)
		if len(ast.statements) > 0 {
			PrintIndent(indent + 1)
			fmt.println("Statements:")
			for statement in ast.statements {
				DumpAst(statement, indent + 2)
			}
		}
	case AstStatement:
		switch ast in ast {
		case ^AstScope:
			PrintHeader("Scope", ast.open_brace_token.location, nil, indent)
			if len(ast.statements) > 0 {
				PrintIndent(indent + 1)
				fmt.println("Statements:")
				for statement in ast.statements {
					DumpAst(statement, indent + 2)
				}
			}
		case ^AstDeclaration:
			PrintHeader("Declaration", ast.name_token.location, nil, indent)
			PrintIndent(indent + 1)
			fmt.printf("Constant: %s\n", IsDeclarationConstant(ast) ? "true" : "false")
			PrintIndent(indent + 1)
			fmt.printf("Name: '%s'\n", ast.name_token.data.(string))
			if type, ok := ast.type.?; ok {
				PrintIndent(indent + 1)
				fmt.println("Type:")
				DumpAst(AstStatement(type), indent + 2)
			}
			if ast.resolved_type != nil {
				PrintIndent(indent + 1)
				fmt.println("Resolved Type:")
				DumpType(ast.resolved_type, indent + 2)
			}
			if value, ok := ast.value.?; ok {
				PrintIndent(indent + 1)
				fmt.println("Value:")
				DumpAst(AstStatement(value), indent + 2)
			}
		case ^AstExternDeclaration:
			PrintHeader("Declaration", ast.name_token.location, nil, indent)
			PrintIndent(indent + 1)
			fmt.printf("Name: '%s'\n", ast.name_token.data.(string))
			PrintIndent(indent + 1)
			fmt.println("Type:")
			DumpAst(AstStatement(ast.type), indent + 2)
			if ast.resolved_type != nil {
				PrintIndent(indent + 1)
				fmt.println("Resolved Type:")
				DumpType(ast.resolved_type, indent + 2)
			}
		case ^AstAssignment:
			PrintHeader("Assignment", ast.equal_token.location, nil, indent)
			PrintIndent(indent + 1)
			fmt.println("Operand:")
			DumpAst(AstStatement(ast.operand), indent + 2)
			PrintIndent(indent + 1)
			fmt.println("Value:")
			DumpAst(AstStatement(ast.value), indent + 2)
		case ^AstIf:
			PrintHeader("If", ast.if_token.location, nil, indent)
			PrintIndent(indent + 1)
			fmt.println("Condition:")
			DumpAst(AstStatement(ast.condition), indent + 2)
			PrintIndent(indent + 1)
			fmt.println("Then:")
			DumpAst(AstStatement(ast.then_body), indent + 2)
			if else_body, ok := ast.else_body.?; ok {
				PrintIndent(indent + 1)
				fmt.println("Else:")
				DumpAst(AstStatement(else_body), indent + 2)
			}
		case ^AstWhile:
			PrintHeader("While", ast.while_token.location, nil, indent)
			PrintIndent(indent + 1)
			fmt.println("Condition:")
			DumpAst(AstStatement(ast.condition), indent + 2)
			PrintIndent(indent + 1)
			fmt.println("Body:")
			DumpAst(AstStatement(ast.body), indent + 2)
		case AstExpression:
			switch ast in ast {
			case ^AstUnary:
				PrintHeader("Unary", ast.operator_token.location, ast.type, indent)
				PrintIndent(indent + 1)
				fmt.println("Unary Operator:", ast.operator_kind)
				PrintIndent(indent + 1)
				fmt.println("Operand:")
				DumpAst(AstStatement(ast.operand), indent + 2)
			case ^AstBinary:
				PrintHeader("Binary", ast.operator_token.location, ast.type, indent)
				PrintIndent(indent + 1)
				fmt.println("Binary Operator:", ast.operator_kind)
				PrintIndent(indent + 1)
				fmt.println("Left:")
				DumpAst(AstStatement(ast.left), indent + 2)
				PrintIndent(indent + 1)
				fmt.println("Right:")
				DumpAst(AstStatement(ast.right), indent + 2)
			case ^AstAddressOf:
				PrintHeader("Address Of", ast.caret_token.location, GetType(ast), indent)
				PrintIndent(indent + 1)
				fmt.println("Operand:")
				DumpAst(AstStatement(ast.operand), indent + 2)
			case ^AstDereference:
				PrintHeader("Dereference", ast.caret_token.location, GetType(ast), indent)
				PrintIndent(indent + 1)
				fmt.println("Operand:")
				DumpAst(AstStatement(ast.operand), indent + 2)
			case ^AstCall:
				PrintHeader("Call", ast.open_parenthesis_token.location, GetType(ast), indent)
				PrintIndent(indent + 1)
				fmt.println("Operand:")
				DumpAst(AstStatement(ast.operand), indent + 2)
				for argument, i in ast.arguments {
					PrintIndent(indent + 1)
					fmt.printf("Argument %d:\n", i + 1)
					DumpAst(AstStatement(argument), indent + 2)
				}
			case ^AstName:
				PrintHeader("Name", ast.name_token.location, GetType(ast), indent)
				PrintIndent(indent + 1)
				fmt.printf("Value: '%s'\n", ast.name_token.data.(string))
			case ^AstInteger:
				PrintHeader("Integer", ast.integer_token.location, ast.type, indent)
				PrintIndent(indent + 1)
				fmt.println("Value:", ast.integer_token.data.(u128))
			case ^AstProcedure:
				PrintHeader("Procedure", ast.open_parenthesis_token.location, GetType(ast), indent)
				for parameter, i in ast.parameters {
					PrintIndent(indent + 1)
					fmt.printf("Parameter %d:\n", i + 1)
					DumpAst(AstStatement(parameter), indent + 2)
				}
				PrintIndent(indent + 1)
				fmt.println("Return Type:")
				DumpAst(AstStatement(ast.return_type), indent + 2)
				if ast.resolved_return_type != nil {
					PrintIndent(indent + 1)
					fmt.println("Resolved Return Type:")
					DumpType(ast.resolved_return_type, indent + 2)
				}
				PrintIndent(indent + 1)
				fmt.println("#extern:", ast.extern_token != nil)
			case ^AstArray:
				PrintHeader("Array", ast.open_square_bracket_token.location, GetType(ast), indent)
				PrintIndent(indent + 1)
				fmt.println("Length:")
				DumpAst(AstStatement(ast.length), indent + 2)
				if ast.resolved_inner_type != nil {
					PrintIndent(indent + 1)
					fmt.println("Resolved Length:", ast.resolved_length)
				}
				PrintIndent(indent + 1)
				fmt.println("Inner Type:")
				DumpAst(AstStatement(ast.inner_type), indent + 2)
				if ast.resolved_inner_type != nil {
					PrintIndent(indent + 1)
					fmt.println("Resolved Inner Type:")
					DumpType(ast.resolved_inner_type, indent + 2)
				}
			case ^AstIndex:
				PrintHeader("Index", ast.open_square_bracket_token.location, GetType(ast), indent)
				PrintIndent(indent + 1)
				fmt.println("Operand:")
				DumpAst(AstStatement(ast.operand), indent + 2)
				PrintIndent(indent + 1)
				fmt.println("Index:")
				DumpAst(AstStatement(ast.index), indent + 2)
			case ^AstCast:
				PrintHeader("Cast", ast.cast_token.location, GetType(ast), indent)
				PrintIndent(indent + 1)
				fmt.println("Type:")
				DumpAst(AstStatement(ast.type), indent + 2)
				if ast.resolved_type != nil {
					PrintIndent(indent + 1)
					fmt.println("Resolved Type:")
					DumpType(ast.resolved_type, indent + 2)
				}
				PrintIndent(indent + 1)
				fmt.println("Operand:")
				DumpAst(AstStatement(ast.operand), indent + 2)
			case ^AstTransmute:
				PrintHeader("Transmute", ast.transmute_token.location, GetType(ast), indent)
				PrintIndent(indent + 1)
				fmt.println("Type:")
				DumpAst(AstStatement(ast.type), indent + 2)
				if ast.resolved_type != nil {
					PrintIndent(indent + 1)
					fmt.println("Resolved Type:")
					DumpType(ast.resolved_type, indent + 2)
				}
				PrintIndent(indent + 1)
				fmt.println("Operand:")
				DumpAst(AstStatement(ast.operand), indent + 2)
			case ^AstSizeOf:
				PrintHeader("Size Of", ast.size_of_token.location, GetType(ast), indent)
				PrintIndent(indent + 1)
				fmt.println("Type:")
				DumpAst(AstStatement(ast.type), indent + 2)
				if ast.resolved_type != nil {
					PrintIndent(indent + 1)
					fmt.println("Resolved Type:")
					DumpType(ast.resolved_type, indent + 2)
				}
			case ^AstTypeOf:
				PrintHeader("Type Of", ast.type_of_token.location, GetType(ast), indent)
				PrintIndent(indent + 1)
				fmt.println("Expression:")
				DumpAst(AstStatement(ast.expression), indent + 2)
			case:
				unreachable()
			}
		case:
			unreachable()
		}
	case:
		unreachable()
	}
}
