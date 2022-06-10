package zircon

import "core:fmt"

Ast :: union #shared_nil {
	^AstFile,
	AstStatement,
}

AstStatement :: union #shared_nil {
	^AstDeclaration,
	^AstAssignment,
	AstExpression,
}

AstExpression :: union #shared_nil {
	^AstUnary,
	^AstBinary,
	^AstCall,
	^AstName,
	^AstInteger,
}

AstFile :: struct {
	filepath:          string,
	statements:        [dynamic]AstStatement,
	end_of_file_token: Token,
}

AstDeclaration :: struct {
	name_token:  Token,
	colon_token: Token,
	// TODO: add type
	equal_token: Token,
	value:       AstExpression,
}

AstAssignment :: struct {
	operand:     AstExpression,
	equal_token: Token,
	value:       AstExpression,
}

UnaryOperatorKind :: enum {
	Invalid,
	Identity,
	Negation,
	LogicalNot,
}

AstUnary :: struct {
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

AstName :: struct {
	name_token: Token,
}

AstInteger :: struct {
	integer_token: Token,
}

DumpAst :: proc(ast: Ast, indent: uint) {
	PrintIndent :: proc(indent: uint) {
		for _ in 0 ..< indent {
			fmt.print("  ")
		}
	}

	PrintHeader :: proc(title: string, location: SourceLocation, indent: uint) {
		PrintIndent(indent)
		fmt.printf("- %s: %v\n", title, location)
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
			indent,
		)
		PrintIndent(indent + 1)
		fmt.println("Statements:")
		for statement in ast.statements {
			DumpAst(statement, indent + 2)
		}
	case AstStatement:
		switch ast in ast {
		case ^AstDeclaration:
			PrintHeader("Declaration", ast.name_token.location, indent)
			PrintIndent(indent + 1)
			fmt.printf("Name: '%s'\n", ast.name_token.data.(string))
			PrintIndent(indent + 1)
			fmt.println("Value:")
			DumpAst(AstStatement(ast.value), indent + 2)
		case ^AstAssignment:
			PrintHeader("Assignment", ast.equal_token.location, indent)
			PrintIndent(indent + 1)
			fmt.println("Operand:")
			DumpAst(AstStatement(ast.operand), indent + 2)
			PrintIndent(indent + 1)
			fmt.println("Value:")
			DumpAst(AstStatement(ast.value), indent + 2)
		case AstExpression:
			switch ast in ast {
			case ^AstUnary:
				PrintHeader("Unary", ast.operator_token.location, indent)
				PrintIndent(indent + 1)
				fmt.println("Unary Operator:", ast.operator_kind)
				PrintIndent(indent + 1)
				fmt.println("Operand:")
				DumpAst(AstStatement(ast.operand), indent + 2)
			case ^AstBinary:
				PrintHeader("Binary", ast.operator_token.location, indent)
				PrintIndent(indent + 1)
				fmt.println("Binary Operator:", ast.operator_kind)
				PrintIndent(indent + 1)
				fmt.println("Left:")
				DumpAst(AstStatement(ast.left), indent + 2)
				PrintIndent(indent + 1)
				fmt.println("Right:")
				DumpAst(AstStatement(ast.right), indent + 2)
			case ^AstCall:
				PrintHeader("Call", ast.open_parenthesis_token.location, indent)
				PrintIndent(indent + 1)
				fmt.println("Operand:")
				DumpAst(AstStatement(ast.operand), indent + 2)
				for argument, i in ast.arguments {
					PrintIndent(indent + 1)
					fmt.printf("Argument %d:\n", i + 1)
					DumpAst(AstStatement(argument), indent + 2)
				}
			case ^AstName:
				PrintHeader("Name", ast.name_token.location, indent)
				PrintIndent(indent + 1)
				fmt.printf("Value: '%s'\n", ast.name_token.data.(string))
			case ^AstInteger:
				PrintHeader("Integer", ast.integer_token.location, indent)
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
