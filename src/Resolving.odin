package zircon

import "core:fmt"

Builtin :: enum {
	Void,
	Type,
	Int,
	S8,
	S16,
	S32,
	S64,
	UInt,
	U8,
	U16,
	U32,
	U64,
	Bool,
}

Decl :: union {
	Builtin,
	^AstDeclaration,
	^AstExternDeclaration,
}

GetDeclType :: proc(decl: Decl) -> Type {
	switch decl in decl {
	case Builtin:
		switch decl {
		case .Void, .Type, .Int, .S8, .S16, .S32, .S64, .UInt, .U8, .U16, .U32, .U64, .Bool:
			return &DefaultTypeType
		case:
			unreachable()
		}
	case ^AstDeclaration:
		return decl.resolved_type
	case ^AstExternDeclaration:
		return decl.resolved_type
	case:
		return nil
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

ExpectTypeKind :: proc(
	type: Type,
	$expected_kind: typeid,
	location: SourceLocation,
) -> Maybe(Error) {
	if _, ok := type.(^expected_kind); !ok {
		return Error{
			location = location,
			message = fmt.aprintf("Expected %v, but got type %v", typeid_of(expected_kind), type),
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
			ResolveExpression(type, names, &DefaultTypeType) or_return
			if !IsConstant(type) {
				return Error{
					location = statement.name_token.location,
					message = fmt.aprintf("Declaration type must be a constant"),
				}
			}
			ExpectTypeKind(GetType(type), TypeType, statement.colon_token.location) or_return

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
			ResolveExpression(value, names, statement.resolved_type) or_return
			if statement.resolved_type != nil {
				ExpectType(
					statement.resolved_type,
					GetType(value),
					statement.colon_or_equal_token.?.location,
				) or_return
			} else {
				statement.resolved_type = GetType(value)
			}
			if statement.colon_or_equal_token.?.kind == .Colon {
				if !IsConstant(value) {
					return Error{
						location = statement.colon_or_equal_token.?.location,
						message = fmt.aprintf("Value must be a constant"),
					}
				}
				names: [dynamic]EvalScope
				defer {
					for scope in names {
						delete(scope)
					}
					delete(names)
				}
				statement.resolved_value = EvalExpression(value, &names)
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
	case ^AstExternDeclaration:
		ResolveExpression(statement.type, names, &DefaultTypeType) or_return
		if !IsConstant(statement.type) {
			return Error{
				location = statement.name_token.location,
				message = fmt.aprintf("Declaration type must be a constant"),
			}
		}
		ExpectTypeKind(
			GetType(statement.type),
			TypeType,
			statement.colon_token.location,
		) or_return

		{
			names: [dynamic]EvalScope
			defer {
				for scope in names {
					delete(scope)
				}
				delete(names)
			}
			statement.resolved_type = EvalExpression(statement.type, &names).(Type)
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
		ResolveExpression(statement.operand, names, nil) or_return
		if !IsAddressable(statement.operand) {
			return Error{
				location = statement.equal_token.location,
				message = fmt.aprintf("Expression is not assignable"),
			}
		}
		ResolveExpression(statement.value, names, GetType(statement.operand)) or_return
		ExpectType(
			GetType(statement.value),
			GetType(statement.operand),
			statement.equal_token.location,
		) or_return
		return nil
	case ^AstIf:
		ResolveExpression(statement.condition, names, &DefaultBoolType) or_return
		ExpectTypeKind(
			GetType(statement.condition),
			TypeBool,
			statement.if_token.location,
		) or_return
		ResolveStatement(statement.then_body, names) or_return
		if else_body, ok := statement.else_body.?; ok {
			ResolveStatement(else_body, names) or_return
		}
		return nil
	case ^AstWhile:
		ResolveExpression(statement.condition, names, &DefaultBoolType) or_return
		ExpectTypeKind(
			GetType(statement.condition),
			TypeBool,
			statement.while_token.location,
		) or_return
		ResolveStatement(statement.body, names) or_return
		return nil
	case AstExpression:
		return ResolveExpression(statement, names, nil)
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
		switch decl in expression.resolved_decl {
		case Builtin:
			return false
		case ^AstDeclaration:
			return !IsDeclarationConstant(decl)
		case ^AstExternDeclaration:
			return true
		case:
			unreachable()
		}
	case ^AstInteger:
		return false
	case ^AstProcedure:
		return false
	case ^AstArray:
		return false
	case ^AstIndex:
		return IsAddressable(expression.operand)
	case ^AstCast:
		return false
	case ^AstTransmute:
		return false
	case ^AstSizeOf:
		return false
	case ^AstTypeOf:
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
		switch decl in expression.resolved_decl {
		case Builtin:
			return true
		case ^AstDeclaration:
			return IsDeclarationConstant(decl)
		case ^AstExternDeclaration:
			return false
		case:
			unreachable()
		}
	case ^AstInteger:
		return true
	case ^AstProcedure:
		_, ok := expression.type.(^TypeType)
		return ok
	case ^AstArray:
		return true
	case ^AstIndex:
		return IsConstant(expression.operand) && IsConstant(expression.index)
	case ^AstCast:
		return IsConstant(expression.operand)
	case ^AstTransmute:
		return false
	case ^AstSizeOf:
		return true
	case ^AstTypeOf:
		return true
	case:
		unreachable()
	}
}

ResolveExpression :: proc(
	expression: AstExpression,
	names: ^[dynamic]Scope,
	suggested_type: Type,
) -> Maybe(Error) {
	switch expression in expression {
	case ^AstUnary:
		ResolveExpression(expression.operand, names, suggested_type) or_return
		switch expression.operator_kind {
		case .Invalid:
			unreachable()
		case .Pointer:
			ExpectTypeKind(
				GetType(expression.operand),
				TypeType,
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
			ExpectTypeKind(
				GetType(expression.operand),
				TypeInt,
				expression.operator_token,
			) or_return
			expression.type = GetType(expression.operand)
			return nil
		case .Negation:
			ExpectTypeKind(
				GetType(expression.operand),
				TypeInt,
				expression.operator_token,
			) or_return
			if !GetType(expression.operand).(^TypeInt).signed {
				return Error{
					location = expression.operator_token.location,
					message = fmt.aprintf("Cannot negate an unsigned integer"),
				}
			}
			expression.type = GetType(expression.operand)
			return nil
		case .LogicalNot:
			ExpectTypeKind(
				GetType(expression.operand),
				TypeBool,
				expression.operator_token,
			) or_return
			expression.type = GetType(expression.operand)
			return nil
		case:
			unreachable()
		}
	case ^AstBinary:
		ResolveExpression(expression.left, names, suggested_type) or_return
		ResolveExpression(expression.right, names, GetType(expression.left)) or_return
		switch expression.operator_kind {
		case .Invalid:
			unreachable()
		case .Addition:
			ExpectTypeKind(GetType(expression.left), TypeInt, expression.operator_token) or_return
			ExpectTypeKind(GetType(expression.left), TypeInt, expression.operator_token) or_return
			ExpectType(
				GetType(expression.right),
				GetType(expression.left),
				expression.operator_token,
			) or_return
			expression.type = GetType(expression.left)
			return nil
		case .Subtraction:
			ExpectTypeKind(GetType(expression.left), TypeInt, expression.operator_token) or_return
			ExpectTypeKind(GetType(expression.left), TypeInt, expression.operator_token) or_return
			ExpectType(
				GetType(expression.right),
				GetType(expression.left),
				expression.operator_token,
			) or_return
			expression.type = GetType(expression.left)
			return nil
		case .Multiplication:
			ExpectTypeKind(GetType(expression.left), TypeInt, expression.operator_token) or_return
			ExpectTypeKind(GetType(expression.left), TypeInt, expression.operator_token) or_return
			ExpectType(
				GetType(expression.right),
				GetType(expression.left),
				expression.operator_token,
			) or_return
			expression.type = GetType(expression.left)
			return nil
		case .Division:
			ExpectTypeKind(GetType(expression.left), TypeInt, expression.operator_token) or_return
			ExpectTypeKind(GetType(expression.left), TypeInt, expression.operator_token) or_return
			ExpectType(
				GetType(expression.right),
				GetType(expression.left),
				expression.operator_token,
			) or_return
			expression.type = GetType(expression.left)
			return nil
		case .Equal:
			ExpectType(
				GetType(expression.right),
				GetType(expression.left),
				expression.operator_token.location,
			) or_return
			expression.type = &DefaultBoolType
			return nil
		case .NotEqual:
			ExpectType(
				GetType(expression.right),
				GetType(expression.left),
				expression.operator_token.location,
			) or_return
			expression.type = &DefaultBoolType
			return nil
		case:
			unreachable()
		}
	case ^AstCall:
		ResolveExpression(expression.operand, names, nil) or_return
		ExpectTypeKind(
			GetType(expression.operand),
			TypeProcedure,
			expression.open_parenthesis_token.location,
		) or_return
		procedure_type := GetType(expression.operand).(^TypeProcedure)
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
			ResolveExpression(argument, names, procedure_type.parameter_types[i]) or_return
			ExpectType(
				GetType(argument),
				procedure_type.parameter_types[i],
				expression.open_parenthesis_token.location,
			) or_return
		}
		return nil
	case ^AstAddressOf:
		ResolveExpression(expression.operand, names, nil) or_return
		if !IsAddressable(expression.operand) {
			return Error{
				location = expression.caret_token.location,
				message = fmt.aprintf("Expression is not addressable"),
			}
		}
		return nil
	case ^AstDereference:
		ResolveExpression(expression.operand, names, nil) or_return
		ExpectTypeKind(
			GetType(expression.operand),
			TypePointer,
			expression.caret_token.location,
		) or_return
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
		case "s8":
			expression.resolved_decl = Builtin.S8
			return nil
		case "s16":
			expression.resolved_decl = Builtin.S16
			return nil
		case "s32":
			expression.resolved_decl = Builtin.S32
			return nil
		case "s64":
			expression.resolved_decl = Builtin.S64
			return nil
		case "uint":
			expression.resolved_decl = Builtin.UInt
			return nil
		case "u8":
			expression.resolved_decl = Builtin.U8
			return nil
		case "u16":
			expression.resolved_decl = Builtin.U16
			return nil
		case "u32":
			expression.resolved_decl = Builtin.U32
			return nil
		case "u64":
			expression.resolved_decl = Builtin.U64
			return nil
		case "bool":
			expression.resolved_decl = Builtin.Bool
			return nil
		case:
			return Error{
				location = expression.name_token.location,
				message = fmt.aprintf("'%s' is not declared", name),
			}
		}
	case ^AstInteger:
		if type, ok := suggested_type.(^TypeInt); ok {
			expression.type = type
		} else {
			expression.type = &DefaultIntType
		}
		value := expression.integer_token.data.(u128)
		type := GetType(expression).(^TypeInt)
		if type.signed {
			switch type.size {
			case 1:
				if value >= cast(u128)max(i8) {
					return Error{
						location = expression.integer_token.location,
						message = fmt.aprintf("%d is too big for %v", expression.type),
					}
				}
			case 2:
				if value >= cast(u128)max(i16) {
					return Error{
						location = expression.integer_token.location,
						message = fmt.aprintf("%d is too big for %v", expression.type),
					}
				}
			case 4:
				if value >= cast(u128)max(i32) {
					return Error{
						location = expression.integer_token.location,
						message = fmt.aprintf("%d is too big for %v", expression.type),
					}
				}
			case 8:
				if value >= cast(u128)max(i64) {
					return Error{
						location = expression.integer_token.location,
						message = fmt.aprintf("%d is too big for %v", expression.type),
					}
				}
			case:
				unreachable()
			}
		} else {
			switch type.size {
			case 1:
				if value >= cast(u128)max(u8) {
					return Error{
						location = expression.integer_token.location,
						message = fmt.aprintf("%d is too big for %v", expression.type),
					}
				}
			case 2:
				if value >= cast(u128)max(u16) {
					return Error{
						location = expression.integer_token.location,
						message = fmt.aprintf("%d is too big for %v", expression.type),
					}
				}
			case 4:
				if value >= cast(u128)max(u32) {
					return Error{
						location = expression.integer_token.location,
						message = fmt.aprintf("%d is too big for %v", expression.type),
					}
				}
			case 8:
				if value >= cast(u128)max(u64) {
					return Error{
						location = expression.integer_token.location,
						message = fmt.aprintf("%d is too big for %v", expression.type),
					}
				}
			case:
				unreachable()
			}
		}
		return nil
	case ^AstProcedure:
		append(names, Scope{})
		for parameter in expression.parameters {
			ResolveStatement(parameter, names) or_return
		}
		delete(pop(names))

		ResolveExpression(expression.return_type, names, &DefaultTypeType) or_return
		if !IsConstant(expression.return_type) {
			return Error{
				location = expression.right_arrow_token.location,
				message = fmt.aprintf("Return type must be a constant"),
			}
		}
		ExpectTypeKind(
			GetType(expression.return_type),
			TypeType,
			expression.right_arrow_token.location,
		) or_return

		{
			names: [dynamic]EvalScope
			defer {
				for scope in names {
					delete(scope)
				}
				delete(names)
			}
			expression.resolved_return_type = EvalExpression(expression.return_type, &names).(Type)
		}

		if _, ok := expression.extern_token.?; ok {
			parameter_types: [dynamic]Type
			defer delete(parameter_types)
			for parameter in expression.parameters {
				append(&parameter_types, parameter.resolved_type)
			}
			expression.type = GetProcedureType(parameter_types[:], expression.resolved_return_type)
		} else {
			if type, ok := suggested_type.(^TypeType); ok {
				expression.type = type
			} else {
				expression.type = &DefaultTypeType
			}
		}

		return nil
	case ^AstArray:
		ResolveExpression(expression.length, names, &DefaultIntType) or_return
		ResolveExpression(expression.inner_type, names, &DefaultTypeType) or_return

		{
			names: [dynamic]EvalScope
			defer {
				for scope in names {
					delete(scope)
				}
				delete(names)
			}

			length := Value_GetInteger(EvalExpression(expression.length, &names))
			if length < 0 {
				return Error{
					location = expression.open_square_bracket_token.location,
					message = fmt.aprintf("Array size cannot be negative"),
				}
			}
			expression.resolved_length = uint(length)
			expression.resolved_inner_type = EvalExpression(expression.inner_type, &names).(Type)
		}

		if type, ok := suggested_type.(^TypeType); ok {
			expression.type = type
		} else {
			expression.type = &DefaultTypeType
		}

		return nil
	case ^AstIndex:
		ResolveExpression(expression.operand, names, nil) or_return
		ResolveExpression(expression.index, names, &DefaultIntType) or_return
		ExpectTypeKind(
			GetType(expression.operand),
			TypeArray,
			expression.open_square_bracket_token,
		) or_return
		ExpectTypeKind(
			GetType(expression.index),
			TypeInt,
			expression.open_square_bracket_token,
		) or_return
		return nil
	case ^AstCast:
		ResolveExpression(expression.type, names, &DefaultTypeType) or_return
		if !IsConstant(expression.type) {
			return Error{
				location = expression.cast_token.location,
				message = fmt.aprintf("Cast type must be a constant"),
			}
		}
		ExpectTypeKind(
			GetType(expression.type),
			TypeType,
			expression.cast_token.location,
		) or_return

		{
			names: [dynamic]EvalScope
			defer {
				for scope in names {
					delete(scope)
				}
				delete(names)
			}
			expression.resolved_type = EvalExpression(expression.type, &names).(Type)
		}

		ResolveExpression(expression.operand, names, expression.resolved_type) or_return

		valid_cast := false
		if _, ok := expression.resolved_type.(^TypeInt); ok {
			if _, ok := GetType(expression.operand).(^TypeInt); ok {
				valid_cast = true
			}
		}

		if !valid_cast {
			return Error{
				location = expression.cast_token.location,
				message = fmt.aprintf(
					"Cannot cast type %v to type %v",
					GetType(expression.operand),
					expression.resolved_type,
				),
			}
		}

		return nil
	case ^AstTransmute:
		ResolveExpression(expression.type, names, &DefaultTypeType) or_return
		if !IsConstant(expression.type) {
			return Error{
				location = expression.transmute_token.location,
				message = fmt.aprintf("Transmute type must be a constant"),
			}
		}
		ExpectTypeKind(
			GetType(expression.type),
			TypeType,
			expression.transmute_token.location,
		) or_return

		{
			names: [dynamic]EvalScope
			defer {
				for scope in names {
					delete(scope)
				}
				delete(names)
			}
			expression.resolved_type = EvalExpression(expression.type, &names).(Type)
		}

		ResolveExpression(expression.operand, names, expression.resolved_type) or_return

		if Type_GetSize(GetType(expression.operand)) != Type_GetSize(expression.resolved_type) {
			return Error{
				location = expression.transmute_token.location,
				message = fmt.aprintf("Cannot transmute types because they have different sizes"),
			}
		}

		return nil
	case ^AstSizeOf:
		ResolveExpression(expression.type, names, &DefaultTypeType) or_return
		if !IsConstant(expression.type) {
			return Error{
				location = expression.size_of_token.location,
				message = fmt.aprintf("SizeOf type must be a constant"),
			}
		}
		ExpectTypeKind(
			GetType(expression.type),
			TypeType,
			expression.size_of_token.location,
		) or_return

		{
			names: [dynamic]EvalScope
			defer {
				for scope in names {
					delete(scope)
				}
				delete(names)
			}
			expression.resolved_type = EvalExpression(expression.type, &names).(Type)
		}

		if type, ok := suggested_type.(^TypeInt); ok {
			expression.integer_type = type
		} else {
			expression.integer_type = &DefaultIntType
		}

		return nil
	case ^AstTypeOf:
		ResolveExpression(expression.expression, names, nil) or_return

		if type, ok := suggested_type.(^TypeType); ok {
			expression.type_type = type
		} else {
			expression.type_type = &DefaultTypeType
		}

		return nil
	case:
		unreachable()
	}
}
