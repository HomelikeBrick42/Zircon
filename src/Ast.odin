package zircon

import "core:fmt"

Ast :: union #shared_nil {
	^AstFile,
	AstStatement,
}

AstStatement :: union #shared_nil {
	^AstScope,
	^AstDeclaration,
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
	resolved_type: Type,
	name_token:    Token,
	colon_token:   Token,
	type:          Maybe(AstExpression),
	equal_token:   Maybe(Token),
	value:         Maybe(AstExpression),
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

GetType :: proc(expression: AstExpression) -> Type {
	switch expression in expression {
	case ^AstUnary:
		return expression.type
	case ^AstBinary:
		return expression.type
	case ^AstCall:
		return GetType(expression.operand).(^TypeProcedure).return_type
	case ^AstAddressOf:
		return GetPointerType(GetType(expression.operand))
	case ^AstDereference:
		return GetType(expression.operand).(^TypePointer).pointer_to
	case ^AstName:
		return GetDeclType(expression.resolved_decl)
	case ^AstInteger:
		return expression.type
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
			fmt.printf("Name: '%s'\n", ast.name_token.data.(string))
			if ast.resolved_type != nil {
				PrintIndent(indent + 1)
				fmt.println("Resolved Type:")
				DumpType(ast.resolved_type, indent + 2)
			} else if type, ok := ast.type.?; ok {
				PrintIndent(indent + 1)
				fmt.println("Type:")
				DumpAst(AstStatement(type), indent + 2)
			}
			if value, ok := ast.value.?; ok {
				PrintIndent(indent + 1)
				fmt.println("Value:")
				DumpAst(AstStatement(value), indent + 2)
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
