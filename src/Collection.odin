package zircon

CollectAllExterns :: proc(ast: Ast, externs: ^map[Extern]bool) {
	CollectAllExternsStatement :: proc(statement: AstStatement, externs: ^map[Extern]bool) {
		switch statement in statement {
		case ^AstScope:
			for statement in statement.statements {
				CollectAllExternsStatement(statement, externs)
			}
		case ^AstDeclaration:
			if type, ok := statement.type.?; ok {
				CollectAllExternsExpression(type, externs)
			}
			if value, ok := statement.value.?; ok {
				CollectAllExternsExpression(value, externs)
			}
		case ^AstExternDeclaration:
			CollectAllExternsExpression(statement.type, externs)
			externs[statement] = true
		case ^AstAssignment:
			CollectAllExternsExpression(statement.operand, externs)
			CollectAllExternsExpression(statement.value, externs)
		case ^AstIf:
			CollectAllExternsExpression(statement.condition, externs)
			CollectAllExternsStatement(statement.then_body, externs)
			if else_body, ok := statement.else_body.?; ok {
				CollectAllExternsStatement(else_body, externs)
			}
		case ^AstWhile:
			CollectAllExternsExpression(statement.condition, externs)
			CollectAllExternsStatement(statement.body, externs)
		case AstExpression:
			CollectAllExternsExpression(statement, externs)
		case:
			unreachable()
		}
	}

	CollectAllExternsExpression :: proc(
		expression: AstExpression,
		externs: ^map[Extern]bool,
	) {
		switch expression in expression {
		case ^AstUnary:
			CollectAllExternsExpression(expression.operand, externs)
		case ^AstBinary:
			CollectAllExternsExpression(expression.left, externs)
			CollectAllExternsExpression(expression.right, externs)
		case ^AstCall:
			CollectAllExternsExpression(expression.operand, externs)
			for argument in expression.arguments {
				CollectAllExternsExpression(argument, externs)
			}
		case ^AstAddressOf:
			CollectAllExternsExpression(expression.operand, externs)
		case ^AstDereference:
			CollectAllExternsExpression(expression.operand, externs)
		case ^AstName:
			// do nothing
			break
		case ^AstInteger:
			// do nothing
			break
		case ^AstProcedure:
			if _, ok := expression.extern_token.?; ok {
				externs[expression] = true
			}
		case ^AstArray:
			CollectAllExternsExpression(expression.length, externs)
			CollectAllExternsExpression(expression.inner_type, externs)
		case:
			unreachable()
		}
	}

	switch ast in ast {
	case ^AstFile:
		for statement in ast.statements {
			CollectAllExternsStatement(statement, externs)
		}
	case AstStatement:
		CollectAllExternsStatement(ast, externs)
	case:
		unreachable()
	}
}
