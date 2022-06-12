package zircon

import "core:fmt"

Builtin :: enum {
	PrintInt,
	PrintBool,
	Println,
}

Value :: union {
	Builtin,
	Type,
	^Value,
	int,
	bool,
}

EvalAst :: proc(ast: Ast, names: ^[dynamic]map[string]Value) {
	switch ast in ast {
	case ^AstFile:
		append(names, map[string]Value{})
		for statement in ast.statements {
			EvalStatement(statement, names)
		}
		delete(pop(names))
	case AstStatement:
		EvalStatement(ast, names)
	case:
		unreachable()
	}
}

EvalStatement :: proc(statement: AstStatement, names: ^[dynamic]map[string]Value) {
	switch statement in statement {
	case ^AstScope:
		append(names, map[string]Value{})
		for statement in statement.statements {
			EvalStatement(statement, names)
		}
		delete(pop(names))
	case ^AstDeclaration:
		value := EvalExpression(statement.value, names)
		name := statement.name_token.data.(string)
		names[len(names) - 1][name] = value
	case ^AstAssignment:
		operand := EvalAddressOf(statement.operand, names)
		value := EvalExpression(statement.value, names)
		operand^ = value
	case ^AstIf:
		condition := EvalExpression(statement.condition, names)
		if condition.(bool) {
			EvalStatement(statement.then_body, names)
		} else if else_body, ok := statement.else_body.?; ok {
			EvalStatement(else_body, names)
		}
	case ^AstWhile:
		for {
			condition := EvalExpression(statement.condition, names)
			if !condition.(bool) do break
			EvalStatement(statement.body, names)
		}
	case AstExpression:
		EvalExpression(statement, names)
	case:
		unreachable()
	}
}

EvalExpression :: proc(
	expression: AstExpression,
	names: ^[dynamic]map[string]Value,
) -> Value {
	switch expression in expression {
	case ^AstUnary:
		operand := EvalExpression(expression.operand, names)
		switch expression.operator_kind {
		case .Invalid:
			unreachable()
		case .Identity:
			return +operand.(int)
		case .Negation:
			return -operand.(int)
		case .LogicalNot:
			return !operand.(bool)
		case:
			unreachable()
		}
	case ^AstBinary:
		left := EvalExpression(expression.left, names)
		right := EvalExpression(expression.right, names)
		switch expression.operator_kind {
		case .Invalid:
			unreachable()
		case .Addition:
			return left.(int) + right.(int)
		case .Subtraction:
			return left.(int) - right.(int)
		case .Multiplication:
			return left.(int) * right.(int)
		case .Division:
			return left.(int) / right.(int)
		case .Equal:
			return left == right
		case .NotEqual:
			return left != right
		case:
			unreachable()
		}
	case ^AstAddressOf:
		return EvalAddressOf(expression.operand, names)
	case ^AstDereference:
		return EvalExpression(expression.operand, names).(^Value)^
	case ^AstCall:
		operand := EvalExpression(expression.operand, names)
		switch operand.(Builtin) {
		case .PrintInt:
			value := EvalExpression(expression.arguments[0], names)
			return fmt.print(value.(int))
		case .PrintBool:
			value := EvalExpression(expression.arguments[0], names)
			return fmt.print(value.(bool))
		case .Println:
			fmt.println()
			return nil
		case:
			unreachable()
		}
	case ^AstName:
		name := expression.name_token.data.(string)
		for i := len(names) - 1; i >= 0; i -= 1 {
			if value, ok := names[i][name]; ok {
				return value
			}
		}
		unreachable()
	case ^AstInteger:
		return int(expression.integer_token.data.(u128))
	case:
		unreachable()
	}
}

EvalAddressOf :: proc(
	expression: AstExpression,
	names: ^[dynamic]map[string]Value,
) -> ^Value {
	switch expression in expression {
	case ^AstUnary:
		unreachable()
	case ^AstBinary:
		unreachable()
	case ^AstCall:
		unreachable()
	case ^AstAddressOf:
		unreachable()
	case ^AstDereference:
		return EvalExpression(expression.operand, names).(^Value)
	case ^AstName:
		name := expression.name_token.data.(string)
		for i := len(names) - 1; i >= 0; i -= 1 {
			if value, ok := &names[i][name]; ok {
				return value
			}
		}
		unreachable()
	case ^AstInteger:
		unreachable()
	case:
		unreachable()
	}
}
