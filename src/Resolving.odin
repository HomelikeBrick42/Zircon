package zircon

import "core:fmt"

Decl :: union {
	Builtin,
	^AstDeclaration,
}

Scope :: map[string]Decl

ExpectType :: proc(type: Type, expected: Type, location: SourceLocation) -> Maybe(Error) {
	if type != expected {
		return Error{
			location = location,
			message = fmt.aprintf("Expected type %v, but got type %v", expected, type),
		}
	}
	return nil
}

ResolveAst :: proc(ast: Ast, names: ^[dynamic]Scope) -> Maybe(Error) {
	switch ast in ast {
	case ^AstFile:
		append(names, Scope{})
		for statement in ast.statements {
			ResolveAst(statement, names) or_return
		}
		delete(pop(names))
		return nil
	case AstStatement:
		return ResolveStatement(ast, names)
	case:
		unreachable()
	}
}

ResolveStatement :: proc(
	statement: AstStatement,
	names: ^[dynamic]Scope,
) -> Maybe(Error) {
	switch statement in statement {
	case ^AstDeclaration:
		ResolveExpression(statement.value, names) or_return
		statement.resolved_type = GetType(statement.value)
		name := statement.name_token.data.(string)
		scope := &names[len(names) - 1]
		if _, ok := scope[name]; ok {
			return Error{
				location = statement.name_token.location,
				message = fmt.aprintf("'%v' is already declared", name),
			}
		}
		scope[name] = statement
		return nil
	case ^AstAssignment:
		ResolveExpression(statement.operand, names) or_return
		if !IsAddressable(statement.operand) {
			return Error{
				location = statement.equal_token.location,
				message = fmt.aprintf("Expression is not assignable"),
			}
		}
		ResolveExpression(statement.value, names) or_return
		if GetType(statement.operand) != GetType(statement.value) {
			return Error{
				location = statement.equal_token.location,
				message = fmt.aprintf(
					"Cannot assign type %v to type %v",
					GetType(statement.value),
					GetType(statement.operand),
				),
			}
		}
		return nil
	case AstExpression:
		return ResolveExpression(statement, names)
	case:
		unreachable()
	}
}

IsAddressable :: proc(expression: AstExpression) -> bool {
	switch expression in expression {
	case ^AstUnary:
		return false
	case ^AstBinary:
		return false
	case ^AstCall:
		return false
	case ^AstName:
		return true
	case ^AstInteger:
		return false
	case:
		unreachable()
	}
}

ResolveExpression :: proc(
	expression: AstExpression,
	names: ^[dynamic]Scope,
) -> Maybe(Error) {
	switch expression in expression {
	case ^AstUnary:
		ResolveExpression(expression.operand, names) or_return
		switch expression.operator_kind {
		case .Invalid:
			unreachable()
		case .Identity:
			ExpectType(GetType(expression.operand), &IntType, expression.operator_token) or_return
			expression.type = GetType(expression.operand)
			return nil
		case .Negation:
			ExpectType(GetType(expression.operand), &IntType, expression.operator_token) or_return
			expression.type = GetType(expression.operand)
			return nil
		case .LogicalNot:
			ExpectType(GetType(expression.operand), &BoolType, expression.operator_token) or_return
			expression.type = GetType(expression.operand)
			return nil
		case:
			unreachable()
		}
	case ^AstBinary:
		ResolveExpression(expression.left, names) or_return
		ResolveExpression(expression.right, names) or_return
		switch expression.operator_kind {
		case .Invalid:
			unreachable()
		case .Addition:
			ExpectType(GetType(expression.left), &IntType, expression.operator_token) or_return
			ExpectType(GetType(expression.left), &IntType, expression.operator_token) or_return
			expression.type = GetType(expression.left)
			return nil
		case .Subtraction:
			ExpectType(GetType(expression.left), &IntType, expression.operator_token) or_return
			ExpectType(GetType(expression.left), &IntType, expression.operator_token) or_return
			expression.type = GetType(expression.left)
			return nil
		case .Multiplication:
			ExpectType(GetType(expression.left), &IntType, expression.operator_token) or_return
			ExpectType(GetType(expression.left), &IntType, expression.operator_token) or_return
			expression.type = GetType(expression.left)
			return nil
		case .Division:
			ExpectType(GetType(expression.left), &IntType, expression.operator_token) or_return
			ExpectType(GetType(expression.left), &IntType, expression.operator_token) or_return
			expression.type = GetType(expression.left)
			return nil
		case .Equal:
			ExpectType(
				GetType(expression.left),
				GetType(expression.right),
				expression.operator_token.location,
			) or_return
			expression.type = GetType(expression.left)
			return nil
		case .NotEqual:
			ExpectType(
				GetType(expression.left),
				GetType(expression.right),
				expression.operator_token.location,
			) or_return
			expression.type = GetType(expression.left)
			return nil
		case:
			unreachable()
		}
	case ^AstCall:
		ResolveExpression(expression.operand, names) or_return
		procedure_type, ok := GetType(expression.operand).(^TypeProcedure)
		if !ok {
			return Error{
				location = expression.open_parenthesis_token.location,
				message = fmt.aprintf("Cannot call a %v", Type(procedure_type)),
			}
		}
		if len(procedure_type.parameter_types) != len(expression.arguments) {
			return Error{
				location = expression.close_parenthesis_token.location,
				message = fmt.aprintf(
					"Expected %d arguments but got only %d",
					len(procedure_type.parameter_types),
					len(expression.arguments),
				),
			}
		}
		for argument, i in expression.arguments {
			ResolveExpression(argument, names) or_return
			ExpectType(
				GetType(argument),
				procedure_type.parameter_types[i],
				expression.open_parenthesis_token.location,
			) or_return
		}
		expression.type = procedure_type.return_type
		return nil
	case ^AstName:
		name := expression.name_token.data.(string)
		for i := len(names) - 1; i >= 0; i -= 1 {
			if decl, ok := names[i][name]; ok {
				switch decl in decl {
				case Builtin:
					switch decl {
					case .PrintInt:
						for procedure_type in ProcedureTypes {
							if len(procedure_type.parameter_types) == 1 && procedure_type.parameter_types[0] ==
							   &IntType && procedure_type.return_type == &VoidType {
								expression.type = procedure_type
								return nil
							}
						}
						type := new(TypeProcedure)
						append(&type.parameter_types, &IntType)
						type.return_type = &VoidType
						append(&ProcedureTypes, type)
						expression.type = type
						return nil
					case .Println:
						for procedure_type in ProcedureTypes {
							if len(procedure_type.parameter_types) == 0 && procedure_type.return_type == &VoidType {
								expression.type = procedure_type
								return nil
							}
						}
						type := new(TypeProcedure)
						type.return_type = &VoidType
						append(&ProcedureTypes, type)
						expression.type = type
						return nil
					case:
						unreachable()
					}
				case ^AstDeclaration:
					expression.type = decl.resolved_type
					return nil
				case:
					unreachable()
				}
			}
		}
		return Error{
			location = expression.name_token.location,
			message = fmt.aprintf("'%s' is not declared", name),
		}
	case ^AstInteger:
		expression.type = &IntType
		value := expression.integer_token.data.(u128)
		if value >= cast(u128)max(int) {
			return Error{
				location = expression.integer_token.location,
				message = fmt.aprintf("%d is too big for an int", value),
			}
		}
		return nil
	case:
		unreachable()
	}
}
