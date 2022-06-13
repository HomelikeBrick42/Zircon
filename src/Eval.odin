package zircon

import "core:fmt"

BuiltinProcedure :: enum {
	PrintInt,
	PrintBool,
	Println,
}

Value :: union {
	Type,
	^Value,
	int,
	bool,
	BuiltinProcedure,
}

EvalScope :: map[^AstDeclaration]Value

GetDefaultValue :: proc(type: Type) -> Value {
	switch type in type {
	case ^TypeVoid:
		return nil
	case ^TypeType:
		return Type(nil)
	case ^TypeInt:
		return 0
	case ^TypeBool:
		return false
	case ^TypePointer:
		return (^Value)(nil)
	case ^TypeProcedure:
		return nil
	case:
		unreachable()
	}
}

EvalAst :: proc(ast: Ast, names: ^[dynamic]EvalScope) {
	switch ast in ast {
	case ^AstFile:
		append(names, EvalScope{})
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

EvalStatement :: proc(statement: AstStatement, names: ^[dynamic]EvalScope) {
	switch statement in statement {
	case ^AstScope:
		append(names, EvalScope{})
		for statement in statement.statements {
			EvalStatement(statement, names)
		}
		delete(pop(names))
	case ^AstDeclaration:
		value: Value
		if val, ok := statement.value.?; ok {
			value = EvalExpression(val, names)
		} else {
			value = GetDefaultValue(statement.resolved_type)
		}
		name := statement.name_token.data.(string)
		names[len(names) - 1][statement] = value
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

EvalExpression :: proc(expression: AstExpression, names: ^[dynamic]EvalScope) -> Value {
	switch expression in expression {
	case ^AstUnary:
		operand := EvalExpression(expression.operand, names)
		switch expression.operator_kind {
		case .Invalid:
			unreachable()
		case .Pointer:
			return GetPointerType(operand.(Type))
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
		unimplemented()
	case ^AstName:
		switch decl in expression.resolved_decl {
		case Builtin:
			switch decl {
			case .Void:
				return Type(&DefaultVoidType)
			case .Type:
				return Type(&DefaultTypeType)
			case .Int:
				return Type(&DefaultIntType)
			case .Bool:
				return Type(&DefaultBoolType)
			case .PrintInt:
				unimplemented()
			case .PrintBool:
				unimplemented()
			case .Println:
				unimplemented()
			case:
				unreachable()
			}
		case ^AstDeclaration:
			for i := len(names) - 1; i >= 0; i -= 1 {
				if value, ok := names[i][decl]; ok {
					return value
				}
			}
			unreachable()
		case:
			unreachable()
		}
	case ^AstInteger:
		return int(expression.integer_token.data.(u128))
	case:
		unreachable()
	}
}

EvalAddressOf :: proc(expression: AstExpression, names: ^[dynamic]EvalScope) -> ^Value {
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
		switch decl in expression.resolved_decl {
		case Builtin:
			unreachable()
		case ^AstDeclaration:
			for i := len(names) - 1; i >= 0; i -= 1 {
				if value, ok := &names[i][decl]; ok {
					return value
				}
			}
			unreachable()
		case:
			unreachable()
		}
	case ^AstInteger:
		unreachable()
	case:
		unreachable()
	}
}
