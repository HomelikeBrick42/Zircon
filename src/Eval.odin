package zircon

import "core:fmt"

Builtin :: enum {
	PrintInt,
	PrintBool,
	Println,
}

Value :: union {
	Builtin,
	int,
	bool,
}

EvalAst :: proc(ast: Ast, names: ^[dynamic]map[string]Value) -> Maybe(Error) {
	switch ast in ast {
	case ^AstFile:
		append(names, map[string]Value{})
		for statement in ast.statements {
			EvalStatement(statement, names) or_return
		}
		delete(pop(names))
		return nil
	case AstStatement:
		return EvalStatement(ast, names)
	case:
		unreachable()
	}
}

EvalStatement :: proc(
	statement: AstStatement,
	names: ^[dynamic]map[string]Value,
) -> Maybe(Error) {
	switch statement in statement {
	case ^AstDeclaration:
		value := EvalExpression(statement.value, names) or_return
		name := statement.name_token.data.(string)
		scope := &names[len(names) - 1]
		if _, ok := scope[name]; ok {
			return Error{
				location = statement.name_token.location,
				message = fmt.aprintf("'%v' is already declared", name),
			}
		}
		scope[name] = value
		return nil
	case ^AstAssignment:
		operand := EvalAddressOf(statement.operand, names) or_return
		value := EvalExpression(statement.value, names) or_return
		operand^ = value
		return nil
	case AstExpression:
		_, error := EvalExpression(statement, names)
		return error
	case:
		unreachable()
	}
}

EvalExpression :: proc(expression: AstExpression, names: ^[dynamic]map[string]Value) -> (
	value: Value,
	error: Maybe(Error),
) {
	switch expression in expression {
	case ^AstUnary:
		operand := EvalExpression(expression.operand, names) or_return
		switch expression.operator_kind {
		case .Invalid:
			unreachable()
		case .Identity:
			return +operand.(int), nil
		case .Negation:
			return -operand.(int), nil
		case .LogicalNot:
			return !operand.(bool), nil
		case:
			unreachable()
		}
	case ^AstBinary:
		left := EvalExpression(expression.left, names) or_return
		right := EvalExpression(expression.right, names) or_return
		switch expression.operator_kind {
		case .Invalid:
			unreachable()
		case .Addition:
			return left.(int) + right.(int), nil
		case .Subtraction:
			return left.(int) - right.(int), nil
		case .Multiplication:
			return left.(int) * right.(int), nil
		case .Division:
			return left.(int) / right.(int), nil
		case .Equal:
			return left.(int) == right.(int), nil
		case .NotEqual:
			return left.(int) != right.(int), nil
		case:
			unreachable()
		}
	case ^AstCall:
		operand := EvalExpression(expression.operand, names) or_return
		switch operand.(Builtin) {
		case .PrintInt:
			if len(expression.arguments) != 1 {
				error = Error {
					location = expression.open_parenthesis_token.location,
					message  = fmt.aprintf("'print_int' expects 1 argument"),
				}
				return nil, error
			}
			value := EvalExpression(expression.arguments[0], names) or_return
			fmt.print(value.(int))
			return nil, nil
		case .PrintBool:
			if len(expression.arguments) != 1 {
				error = Error {
					location = expression.open_parenthesis_token.location,
					message  = fmt.aprintf("'print_bool' expects 1 argument"),
				}
				return nil, error
			}
			value := EvalExpression(expression.arguments[0], names) or_return
			fmt.print(value.(bool))
			return nil, nil
		case .Println:
			if len(expression.arguments) != 0 {
				error = Error {
					location = expression.open_parenthesis_token.location,
					message  = fmt.aprintf("'println' expects 0 argument"),
				}
				return nil, error
			}
			fmt.println()
			return nil, nil
		case:
			unreachable()
		}
	case ^AstName:
		name := expression.name_token.data.(string)
		for i := len(names) - 1; i >= 0; i -= 1 {
			if value, ok := names[i][name]; ok {
				return value, nil
			}
		}
		error = Error {
			location = expression.name_token.location,
			message  = fmt.aprintf("'%s' is not declared", name),
		}
		return nil, error
	case ^AstInteger:
		value := expression.integer_token.data.(u128)
		if value >= cast(u128)max(int) {
			error = Error {
				location = expression.integer_token.location,
				message  = fmt.aprintf("%d is too big for an int", value),
			}
			return nil, error
		}
		return int(value), nil
	case:
		unreachable()
	}
}

EvalAddressOf :: proc(expression: AstExpression, names: ^[dynamic]map[string]Value) -> (
	value: ^Value,
	error: Maybe(Error),
) {
	switch expression in expression {
	case ^AstUnary:
		error = Error {
			location = expression.operator_token.location,
			message  = fmt.aprintf(
				"Unary operator %v is not addressable",
				expression.operator_kind,
			),
		}
		return nil, error
	case ^AstBinary:
		error = Error {
			location = expression.operator_token.location,
			message  = fmt.aprintf(
				"Binary operator %v is not addressable",
				expression.operator_kind,
			),
		}
		return nil, error
	case ^AstCall:
		error = Error {
			location = expression.open_parenthesis_token.location,
			message  = fmt.aprintf("A call is not addressable"),
		}
		return nil, error
	case ^AstName:
		name := expression.name_token.data.(string)
		for i := len(names) - 1; i >= 0; i -= 1 {
			if value, ok := &names[i][name]; ok {
				return value, nil
			}
		}
		error = Error {
			location = expression.name_token.location,
			message  = fmt.aprintf("'%s' is not declared", name),
		}
		return nil, error
	case ^AstInteger:
		error = Error {
			location = expression.integer_token.location,
			message  = fmt.aprintf("An integer is not addressable", value),
		}
		return nil, error
	case:
		unreachable()
	}
}
