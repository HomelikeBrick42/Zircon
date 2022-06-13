package zircon

import "core:fmt"

Builtin :: enum {
	Void,
	Type,
	Int,
	Bool,
	PrintInt,
	PrintBool,
	Println,
}

Decl :: union {
	Builtin,
	^AstDeclaration,
}

GetDeclType :: proc(decl: Decl) -> Type {
	switch decl in decl {
	case Builtin:
		switch decl {
		case .Void, .Type, .Int, .Bool:
			return &DefaultTypeType
		case .PrintInt:
			return GetProcedureType({Type(&DefaultIntType)}, &DefaultIntType)
		case .PrintBool:
			return GetProcedureType({Type(&DefaultBoolType)}, &DefaultIntType)
		case .Println:
			return GetProcedureType({}, &DefaultVoidType)
		case:
			unreachable()
		}
	case ^AstDeclaration:
		return decl.resolved_type
	case:
		unreachable()
	}
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
	case ^AstScope:
		append(names, Scope{})
		for statement in statement.statements {
			ResolveAst(statement, names) or_return
		}
		delete(pop(names))
		return nil
	case ^AstDeclaration:
		if type, ok := statement.type.?; ok {
			ResolveExpression(type, names) or_return
			if !IsConstant(type) {
				return Error{
					location = statement.name_token.location,
					message = fmt.aprintf("Declaration type must be a constant"),
				}
			}
			ExpectType(GetType(type), &DefaultTypeType, statement.colon_token.location) or_return

			names: [dynamic]EvalScope
			defer {
				for scope in names {
					delete(scope)
				}
				delete(names)
			}
			statement.resolved_type = EvalExpression(type, &names).(Type)
		}
		if value, ok := statement.value.?; ok {
			ResolveExpression(value, names) or_return
			if statement.resolved_type != nil {
				ExpectType(
					statement.resolved_type,
					GetType(value),
					statement.equal_token.?.location,
				) or_return
			} else {
				statement.resolved_type = GetType(value)
			}
		}
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
	case ^AstIf:
		ResolveExpression(statement.condition, names) or_return
		ExpectType(
			GetType(statement.condition),
			&DefaultBoolType,
			statement.if_token.location,
		) or_return
		ResolveStatement(statement.then_body, names) or_return
		if else_body, ok := statement.else_body.?; ok {
			ResolveStatement(else_body, names) or_return
		}
		return nil
	case ^AstWhile:
		ResolveExpression(statement.condition, names) or_return
		ExpectType(
			GetType(statement.condition),
			&DefaultBoolType,
			statement.while_token.location,
		) or_return
		ResolveStatement(statement.body, names) or_return
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
	case ^AstAddressOf:
		return false
	case ^AstDereference:
		return true
	case ^AstName:
		_, ok := expression.resolved_decl.(Builtin)
		return !ok
	case ^AstInteger:
		return false
	case:
		unreachable()
	}
}

IsConstant :: proc(expression: AstExpression) -> bool {
	switch expression in expression {
	case ^AstUnary:
		return IsConstant(expression.operand)
	case ^AstBinary:
		return IsConstant(expression.left) && IsConstant(expression.right)
	case ^AstCall:
		return false
	case ^AstAddressOf:
		return false
	case ^AstDereference:
		return false
	case ^AstName:
		_, ok := expression.resolved_decl.(Builtin)
		return ok
	case ^AstInteger:
		return true
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
		case .Pointer:
			ExpectType(
				GetType(expression.operand),
				&DefaultTypeType,
				expression.operator_token,
			) or_return
			if !IsConstant(expression.operand) {
				return Error{
					location = expression.operator_token.location,
					message = fmt.aprintf("Type is not a constant"),
				}
			}
			expression.type = GetType(expression.operand)
			return nil
		case .Identity:
			ExpectType(
				GetType(expression.operand),
				&DefaultIntType,
				expression.operator_token,
			) or_return
			expression.type = GetType(expression.operand)
			return nil
		case .Negation:
			ExpectType(
				GetType(expression.operand),
				&DefaultIntType,
				expression.operator_token,
			) or_return
			expression.type = GetType(expression.operand)
			return nil
		case .LogicalNot:
			ExpectType(
				GetType(expression.operand),
				&DefaultBoolType,
				expression.operator_token,
			) or_return
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
			ExpectType(
				GetType(expression.left),
				&DefaultIntType,
				expression.operator_token,
			) or_return
			ExpectType(
				GetType(expression.left),
				&DefaultIntType,
				expression.operator_token,
			) or_return
			expression.type = GetType(expression.left)
			return nil
		case .Subtraction:
			ExpectType(
				GetType(expression.left),
				&DefaultIntType,
				expression.operator_token,
			) or_return
			ExpectType(
				GetType(expression.left),
				&DefaultIntType,
				expression.operator_token,
			) or_return
			expression.type = GetType(expression.left)
			return nil
		case .Multiplication:
			ExpectType(
				GetType(expression.left),
				&DefaultIntType,
				expression.operator_token,
			) or_return
			ExpectType(
				GetType(expression.left),
				&DefaultIntType,
				expression.operator_token,
			) or_return
			expression.type = GetType(expression.left)
			return nil
		case .Division:
			ExpectType(
				GetType(expression.left),
				&DefaultIntType,
				expression.operator_token,
			) or_return
			ExpectType(
				GetType(expression.left),
				&DefaultIntType,
				expression.operator_token,
			) or_return
			expression.type = GetType(expression.left)
			return nil
		case .Equal:
			ExpectType(
				GetType(expression.left),
				GetType(expression.right),
				expression.operator_token.location,
			) or_return
			expression.type = &DefaultBoolType
			return nil
		case .NotEqual:
			ExpectType(
				GetType(expression.left),
				GetType(expression.right),
				expression.operator_token.location,
			) or_return
			expression.type = &DefaultBoolType
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
		return nil
	case ^AstAddressOf:
		ResolveExpression(expression.operand, names) or_return
		if !IsAddressable(expression.operand) {
			return Error{
				location = expression.caret_token.location,
				message = fmt.aprintf("Expression is not addressable"),
			}
		}
		return nil
	case ^AstDereference:
		ResolveExpression(expression.operand, names) or_return
		if _, ok := GetType(expression.operand).(^TypePointer); !ok {
			return Error{
				location = expression.caret_token.location,
				message = fmt.aprintf("Cannot dereference a %v", GetType(expression.operand)),
			}
		}
		return nil
	case ^AstName:
		name := expression.name_token.data.(string)
		for i := len(names) - 1; i >= 0; i -= 1 {
			if decl, ok := names[i][name]; ok {
				expression.resolved_decl = decl
				return nil
			}
		}
		switch name {
		case "void":
			expression.resolved_decl = Builtin.Void
			return nil
		case "type":
			expression.resolved_decl = Builtin.Type
			return nil
		case "int":
			expression.resolved_decl = Builtin.Int
			return nil
		case "bool":
			expression.resolved_decl = Builtin.Bool
			return nil
		case "print_int":
			expression.resolved_decl = Builtin.PrintInt
			return nil
		case "print_bool":
			expression.resolved_decl = Builtin.PrintBool
			return nil
		case "println":
			expression.resolved_decl = Builtin.Println
			return nil
		case:
			return Error{
				location = expression.name_token.location,
				message = fmt.aprintf("'%s' is not declared", name),
			}
		}
	case ^AstInteger:
		expression.type = &DefaultIntType
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
