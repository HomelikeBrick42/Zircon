package zircon

import "core:os"
import "core:fmt"
import "core:strings"

GetID :: proc() -> uint {
	@(static)
	id := uint(1)
	new_id := id
	id += 1
	return new_id
}

@(private = "file")
PrintIndent :: proc(indent: uint, buffer: ^strings.Builder) {
	for _ in 0 ..< indent {
		fmt.sbprint(buffer, "    ")
	}
}

EmitType_C :: proc(type: Type, name: string, indent: uint, buffer: ^strings.Builder) {
	switch type in type {
	case ^TypeVoid:
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "Void %s", name)
	case ^TypeType:
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "Type %s", name)
	case ^TypeInt:
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "Int %s", name)
	case ^TypeBool:
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "Bool %s", name)
	case ^TypePointer:
		EmitType_C(type.pointer_to, fmt.tprintf("(*%s)", name), indent, buffer)
	case ^TypeProcedure:
		EmitType_C(type.return_type, fmt.tprintf("(*%s)", name), indent, buffer)
		fmt.sbprintf(buffer, "(")
		for parameter_type in type.parameter_types {
			EmitType_C(parameter_type, "", 0, buffer)
		}
		fmt.sbprintf(buffer, ")")
	case:
		unreachable()
	}
}

EmitDefaultValue :: proc(
	type: Type,
	indent: uint,
	location: SourceLocation,
	buffer: ^strings.Builder,
) -> uint {
	fmt.sbprintf(buffer, "#line %d \"%s\"\n", location.line, location.filepath)
	PrintIndent(indent, buffer)
	id := GetID()
	switch type in type {
	case ^TypeVoid:
		unreachable()
	case ^TypeType:
		fmt.sbprintf(buffer, "Type _%d = 0;\n", id)
	case ^TypeInt:
		fmt.sbprintf(buffer, "Int _%d = 0;\n", id)
	case ^TypeBool:
		fmt.sbprintf(buffer, "Bool _%d = 0;\n", id)
	case ^TypePointer:
		fmt.sbprintf(buffer, "Void* _%d = NULL;\n", id)
	case ^TypeProcedure:
		fmt.sbprintf(buffer, "Void* _%d = NULL;\n", id)
	case:
		unreachable()
	}
	return id
}

EmitAst_C :: proc(ast: Ast, indent: uint, buffer: ^strings.Builder) {
	switch ast in ast {
	case ^AstFile:
		fmt.sbprintf(
			buffer,
			`#include <stdio.h>

typedef void Void;
typedef size_t Type;
typedef signed long long Int;
typedef _Bool Bool;

Int _builtin_print_int(Int value) {{
    return (Int)printf("%%lld", value);
}}

Int _builtin_print_bool(Bool value) {{
    return (Int)printf(value ? "true" : "false");
}}

Void _builtin_println() {{
    printf("\n");
}}

int main() {{
`,
		)
		for statement in ast.statements {
			EmitStatement_C(statement, indent + 1, buffer)
		}
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			ast.end_of_file_token.line,
			ast.end_of_file_token.filepath,
		)
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "return 0;\n")
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			ast.end_of_file_token.line,
			ast.end_of_file_token.filepath,
		)
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "}}\n")
	case AstStatement:
		EmitStatement_C(ast, indent, buffer)
	case:
		unreachable()
	}
}

EmitStatement_C :: proc(statement: AstStatement, indent: uint, buffer: ^strings.Builder) {
	switch statement in statement {
	case ^AstScope:
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			statement.open_brace_token.line,
			statement.open_brace_token.filepath,
		)
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "{{\n")
		for statement in statement.statements {
			EmitStatement_C(statement, indent + 1, buffer)
		}
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			statement.close_brace_token.line,
			statement.close_brace_token.filepath,
		)
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "}}\n")
	case ^AstDeclaration:
		value: uint
		if val, ok := statement.value.?; ok {
			value = EmitExpression_C(val, indent, buffer)
		} else {
			value = EmitDefaultValue(
				statement.resolved_type,
				indent,
				statement.name_token.location,
				buffer,
			)
		}
		name := statement.name_token.data.(string)
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			statement.name_token.line,
			statement.name_token.filepath,
		)
		EmitType_C(
			statement.resolved_type,
			fmt.tprintf("_%d", uintptr(statement)),
			indent,
			buffer,
		)
		fmt.sbprintf(buffer, " = _%d;\n", value)
	case ^AstAssignment:
		operand := EmitAddressOf_C(statement.operand, indent, buffer)
		value := EmitExpression_C(statement.value, indent, buffer)
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			statement.equal_token.line,
			statement.equal_token.filepath,
		)
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "*_%d = _%d;\n", operand, value)
	case ^AstIf:
		condition := EmitExpression_C(statement.condition, indent, buffer)
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			statement.if_token.line,
			statement.if_token.filepath,
		)
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "if (_%d)\n", condition)
		EmitStatement_C(statement.then_body, indent, buffer)
		if else_body, ok := statement.else_body.?; ok {
			fmt.sbprintf(
				buffer,
				"#line %d \"%s\"\n",
				statement.else_token.line,
				statement.else_token.filepath,
			)
			PrintIndent(indent, buffer)
			fmt.sbprintf(buffer, "else\n")
			EmitStatement_C(else_body, indent, buffer)
		}
	case ^AstWhile:
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			statement.while_token.line,
			statement.while_token.filepath,
		)
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "for (;;)\n")
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			statement.while_token.line,
			statement.while_token.filepath,
		)
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "{{\n")
		condition := EmitExpression_C(statement.condition, indent + 1, buffer)
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			statement.while_token.line,
			statement.while_token.filepath,
		)
		PrintIndent(indent + 1, buffer)
		fmt.sbprintf(buffer, "if (!_%d) break;\n", condition)
		EmitStatement_C(statement.body, indent + 1, buffer)
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			statement.while_token.line,
			statement.while_token.filepath,
		)
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "}}\n")
	case AstExpression:
		EmitExpression_C(statement, indent, buffer)
	case:
		unreachable()
	}
}

EmitAddressOf_C :: proc(
	expression: AstExpression,
	indent: uint,
	buffer: ^strings.Builder,
) -> uint {
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
		return EmitExpression_C(expression.operand, indent, buffer)
	case ^AstName:
		switch decl in expression.resolved_decl {
		case Builtin:
			unreachable()
		case ^AstDeclaration:
			id := GetID()
			fmt.sbprintf(
				buffer,
				"#line %d \"%s\"\n",
				expression.name_token.line,
				expression.name_token.filepath,
			)
			EmitType_C(GetPointerType(decl.resolved_type), fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = &_%d;\n", uintptr(decl))
			return id
		case:
			unreachable()
		}
	case ^AstInteger:
		unreachable()
	case:
		unreachable()
	}
}

EmitExpression_C :: proc(
	expression: AstExpression,
	indent: uint,
	buffer: ^strings.Builder,
) -> uint {
	switch expression in expression {
	case ^AstUnary:
		operand := EmitExpression_C(expression.operand, indent, buffer)
		switch expression.operator_kind {
		case .Invalid:
			unreachable()
		case .Pointer:
			unreachable()
		case .Identity:
			id := GetID()
			fmt.sbprintf(
				buffer,
				"#line %d \"%s\"\n",
				expression.operator_token.line,
				expression.operator_token.filepath,
			)
			EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = +_%d;\n", operand)
			return id
		case .Negation:
			id := GetID()
			fmt.sbprintf(
				buffer,
				"#line %d \"%s\"\n",
				expression.operator_token.line,
				expression.operator_token.filepath,
			)
			EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = -_%d;\n", operand)
			return id
		case .LogicalNot:
			id := GetID()
			fmt.sbprintf(
				buffer,
				"#line %d \"%s\"\n",
				expression.operator_token.line,
				expression.operator_token.filepath,
			)
			EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = !_%d;\n", operand)
			return id
		case:
			unreachable()
		}
	case ^AstBinary:
		left := EmitExpression_C(expression.left, indent, buffer)
		right := EmitExpression_C(expression.right, indent, buffer)
		switch expression.operator_kind {
		case .Invalid:
			unreachable()
		case .Addition:
			id := GetID()
			fmt.sbprintf(
				buffer,
				"#line %d \"%s\"\n",
				expression.operator_token.line,
				expression.operator_token.filepath,
			)
			EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, "  = _%d + _%d;\n", left, right)
			return id
		case .Subtraction:
			id := GetID()
			fmt.sbprintf(
				buffer,
				"#line %d \"%s\"\n",
				expression.operator_token.line,
				expression.operator_token.filepath,
			)
			EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = _%d - _%d;\n", left, right)
			return id
		case .Multiplication:
			id := GetID()
			fmt.sbprintf(
				buffer,
				"#line %d \"%s\"\n",
				expression.operator_token.line,
				expression.operator_token.filepath,
			)
			EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = _%d * _%d;\n", left, right)
			return id
		case .Division:
			id := GetID()
			fmt.sbprintf(
				buffer,
				"#line %d \"%s\"\n",
				expression.operator_token.line,
				expression.operator_token.filepath,
			)
			EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = _%d / _%d;\n", left, right)
			return id
		case .Equal:
			id := GetID()
			fmt.sbprintf(
				buffer,
				"#line %d \"%s\"\n",
				expression.operator_token.line,
				expression.operator_token.filepath,
			)
			EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = _%d == _%d;\n", left, right)
			return id
		case .NotEqual:
			id := GetID()
			fmt.sbprintf(
				buffer,
				"#line %d \"%s\"\n",
				expression.operator_token.line,
				expression.operator_token.filepath,
			)
			EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = _%d != _%d;\n", left, right)
			return id
		case:
			unreachable()
		}
	case ^AstCall:
		operand := EmitExpression_C(expression.operand, indent, buffer)
		ids: [dynamic]uint
		defer delete(ids)
		for argument in expression.arguments {
			append(&ids, EmitExpression_C(argument, indent, buffer))
		}
		id := GetID()
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			expression.open_parenthesis_token.line,
			expression.open_parenthesis_token.filepath,
		)
		if _, ok := GetType(expression).(^TypeVoid); !ok {
			EmitType_C(GetType(expression), fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = ")
		} else {
			PrintIndent(indent, buffer)
		}
		fmt.sbprintf(buffer, "_%d(", operand)
		for parameter, i in ids {
			if i > 0 {
				fmt.sbprintf(buffer, ", ")
			}
			fmt.sbprintf(buffer, "_%d", parameter)
		}
		fmt.sbprintf(buffer, ");\n")
		return id
	case ^AstAddressOf:
		return EmitAddressOf_C(expression.operand, indent, buffer)
	case ^AstDereference:
		operand := EmitExpression_C(expression.operand, indent, buffer)
		id := GetID()
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			expression.caret_token.line,
			expression.caret_token.filepath,
		)
		EmitType_C(GetType(expression), fmt.tprintf("_%d", id), indent, buffer)
		fmt.sbprintf(buffer, " = *_%d;\n", operand)
		return id
	case ^AstName:
		switch decl in expression.resolved_decl {
		case Builtin:
			switch decl {
			case .Void:
				id := GetID()
				fmt.sbprintf(
					buffer,
					"#line %d \"%s\"\n",
					expression.name_token.line,
					expression.name_token.filepath,
				)
				EmitType_C(GetType(expression), fmt.tprintf("_%d", id), indent, buffer)
				fmt.sbprintf(buffer, " = %d;\n", uintptr(&DefaultVoidType))
				return id
			case .Type:
				id := GetID()
				fmt.sbprintf(
					buffer,
					"#line %d \"%s\"\n",
					expression.name_token.line,
					expression.name_token.filepath,
				)
				EmitType_C(GetType(expression), fmt.tprintf("_%d", id), indent, buffer)
				fmt.sbprintf(buffer, " = %d;\n", uintptr(&DefaultTypeType))
				return id
			case .Int:
				id := GetID()
				fmt.sbprintf(
					buffer,
					"#line %d \"%s\"\n",
					expression.name_token.line,
					expression.name_token.filepath,
				)
				EmitType_C(GetType(expression), fmt.tprintf("_%d", id), indent, buffer)
				fmt.sbprintf(buffer, " = %d;\n", uintptr(&DefaultIntType))
				return id
			case .Bool:
				id := GetID()
				fmt.sbprintf(
					buffer,
					"#line %d \"%s\"\n",
					expression.name_token.line,
					expression.name_token.filepath,
				)
				EmitType_C(GetType(expression), fmt.tprintf("_%d", id), indent, buffer)
				fmt.sbprintf(buffer, " = %d;\n", uintptr(&DefaultBoolType))
				return id
			case .PrintInt:
				id := GetID()
				fmt.sbprintf(
					buffer,
					"#line %d \"%s\"\n",
					expression.name_token.line,
					expression.name_token.filepath,
				)
				EmitType_C(GetType(expression), fmt.tprintf("_%d", id), indent, buffer)
				fmt.sbprintf(buffer, " = &_builtin_print_int;\n")
				return id
			case .PrintBool:
				id := GetID()
				fmt.sbprintf(
					buffer,
					"#line %d \"%s\"\n",
					expression.name_token.line,
					expression.name_token.filepath,
				)
				EmitType_C(GetType(expression), fmt.tprintf("_%d", id), indent, buffer)
				fmt.sbprintf(buffer, " = &_builtin_print_bool;\n")
				return id
			case .Println:
				id := GetID()
				fmt.sbprintf(
					buffer,
					"#line %d \"%s\"\n",
					expression.name_token.line,
					expression.name_token.filepath,
				)
				EmitType_C(GetType(expression), fmt.tprintf("_%d", id), indent, buffer)
				fmt.sbprintf(buffer, " = &_builtin_println;\n")
				return id
			case:
				unreachable()
			}
		case ^AstDeclaration:
			id := GetID()
			fmt.sbprintf(
				buffer,
				"#line %d \"%s\"\n",
				expression.name_token.line,
				expression.name_token.filepath,
			)
			EmitType_C(GetType(expression), fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = _%d;\n", uintptr(decl))
			return id
		case:
			unreachable()
		}
	case ^AstInteger:
		value := expression.integer_token.data.(u128)
		id := GetID()
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			expression.integer_token.line,
			expression.integer_token.filepath,
		)
		EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
		fmt.sbprintf(buffer, " = %d;\n", value)
		return id
	case:
		unreachable()
	}
}
