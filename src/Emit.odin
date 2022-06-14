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

EmitType_C :: proc(
	type: Type,
	name: string,
	indent: uint,
	buffer: ^strings.Builder,
	emit_proc_type_as_pointer := true,
) {
	switch type in type {
	case ^TypeVoid:
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "void %s", name)
	case ^TypeType:
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "Type %s", name)
	case ^TypeInt:
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "%sint%d_t %s", !type.signed ? "u" : "", type.size * 8, name)
	case ^TypeBool:
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "bool %s", name)
	case ^TypePointer:
		EmitType_C(type.pointer_to, fmt.tprintf("(*%s)", name), indent, buffer)
	case ^TypeProcedure:
		if emit_proc_type_as_pointer {
			EmitType_C(type.return_type, fmt.tprintf("(*%s)", name), indent, buffer)
		} else {
			EmitType_C(type.return_type, name, indent, buffer)
		}
		fmt.sbprintf(buffer, "(")
		for parameter_type in type.parameter_types {
			EmitType_C(parameter_type, "", 0, buffer)
		}
		fmt.sbprintf(buffer, ")")
	case ^TypeArray:
		EmitType_C(type.inner_type, fmt.tprintf("(%s[%d])", name), indent, buffer)
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
	id := GetID()
	EmitType_C(type, fmt.tprintf("_%d", id), indent, buffer)
	switch type in type {
	case ^TypeVoid:
		unreachable()
	case ^TypeType:
		fmt.sbprintf(buffer, " = 0;\n")
	case ^TypeInt:
		fmt.sbprintf(buffer, " = 0;\n")
	case ^TypeBool:
		fmt.sbprintf(buffer, " = false;\n")
	case ^TypePointer:
		fmt.sbprintf(buffer, " = NULL;\n")
	case ^TypeProcedure:
		fmt.sbprintf(buffer, " = NULL;\n")
	case ^TypeArray:
		fmt.sbprintf(buffer, " = {};\n")
	case:
		unreachable()
	}
	return id
}

Extern :: union #shared_nil {
	^AstExternDeclaration,
	^AstProcedure,
}

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

EmitAst_C :: proc(ast: Ast, indent: uint, buffer: ^strings.Builder) {
	switch ast in ast {
	case ^AstFile:
		fmt.sbprintf(
			buffer,
			`#include <stdint.h>
#include <stdbool.h>

typedef uint64_t Type;

static void _builtin_main(void);

int main(int argc, char** argv) {{
    _builtin_main();
    return 0;
}}
`,
		)
		externs: map[Extern]bool
		defer delete(externs)
		CollectAllExterns(ast, &externs)
		if len(externs) > 0 {
			fmt.sbprintf(buffer, "\n")
			for extern, ok in externs {
				if ok {
					switch extern in extern {
					case ^AstExternDeclaration:
						PrintIndent(indent, buffer)
						fmt.sbprintf(buffer, "extern ")
						EmitType_C(extern.resolved_type, extern.name_token.data.(string), 0, buffer)
						fmt.sbprintf(buffer, ";\n")
					case ^AstProcedure:
						EmitType_C(
							GetType(extern),
							extern.extern_string_token.?.data.(string),
							indent,
							buffer,
							false,
						)
						fmt.sbprintf(buffer, ";\n")
					case:
						unreachable()
					}
				}
			}
		}
		fmt.sbprintf(buffer, "\n")
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "static void _builtin_main(void) {{\n")
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
			fmt.tprintf("%s_%d", name, uintptr(statement)),
			indent,
			buffer,
		)
		fmt.sbprintf(buffer, " = _%d;\n", value)
	case ^AstExternDeclaration:
		// do nothing
		break
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
			fmt.sbprintf(buffer, " = &%s_%d;\n", decl.name_token.data.(string), uintptr(decl))
			return id
		case ^AstExternDeclaration:
			unimplemented()
		case:
			unreachable()
		}
	case ^AstInteger:
		unreachable()
	case ^AstProcedure:
		unreachable()
	case ^AstArray:
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
			case .S8:
				id := GetID()
				fmt.sbprintf(
					buffer,
					"#line %d \"%s\"\n",
					expression.name_token.line,
					expression.name_token.filepath,
				)
				EmitType_C(GetType(expression), fmt.tprintf("_%d", id), indent, buffer)
				fmt.sbprintf(buffer, " = %d;\n", uintptr(&DefaultS8Type))
				return id
			case .S16:
				id := GetID()
				fmt.sbprintf(
					buffer,
					"#line %d \"%s\"\n",
					expression.name_token.line,
					expression.name_token.filepath,
				)
				EmitType_C(GetType(expression), fmt.tprintf("_%d", id), indent, buffer)
				fmt.sbprintf(buffer, " = %d;\n", uintptr(&DefaultS16Type))
				return id
			case .S32:
				id := GetID()
				fmt.sbprintf(
					buffer,
					"#line %d \"%s\"\n",
					expression.name_token.line,
					expression.name_token.filepath,
				)
				EmitType_C(GetType(expression), fmt.tprintf("_%d", id), indent, buffer)
				fmt.sbprintf(buffer, " = %d;\n", uintptr(&DefaultS32Type))
				return id
			case .S64:
				id := GetID()
				fmt.sbprintf(
					buffer,
					"#line %d \"%s\"\n",
					expression.name_token.line,
					expression.name_token.filepath,
				)
				EmitType_C(GetType(expression), fmt.tprintf("_%d", id), indent, buffer)
				fmt.sbprintf(buffer, " = %d;\n", uintptr(&DefaultS64Type))
				return id
			case .UInt:
				id := GetID()
				fmt.sbprintf(
					buffer,
					"#line %d \"%s\"\n",
					expression.name_token.line,
					expression.name_token.filepath,
				)
				EmitType_C(GetType(expression), fmt.tprintf("_%d", id), indent, buffer)
				fmt.sbprintf(buffer, " = %d;\n", uintptr(&DefaultUIntType))
				return id
			case .U8:
				id := GetID()
				fmt.sbprintf(
					buffer,
					"#line %d \"%s\"\n",
					expression.name_token.line,
					expression.name_token.filepath,
				)
				EmitType_C(GetType(expression), fmt.tprintf("_%d", id), indent, buffer)
				fmt.sbprintf(buffer, " = %d;\n", uintptr(&DefaultU8Type))
				return id
			case .U16:
				id := GetID()
				fmt.sbprintf(
					buffer,
					"#line %d \"%s\"\n",
					expression.name_token.line,
					expression.name_token.filepath,
				)
				EmitType_C(GetType(expression), fmt.tprintf("_%d", id), indent, buffer)
				fmt.sbprintf(buffer, " = %d;\n", uintptr(&DefaultU16Type))
				return id
			case .U32:
				id := GetID()
				fmt.sbprintf(
					buffer,
					"#line %d \"%s\"\n",
					expression.name_token.line,
					expression.name_token.filepath,
				)
				EmitType_C(GetType(expression), fmt.tprintf("_%d", id), indent, buffer)
				fmt.sbprintf(buffer, " = %d;\n", uintptr(&DefaultU32Type))
				return id
			case .U64:
				id := GetID()
				fmt.sbprintf(
					buffer,
					"#line %d \"%s\"\n",
					expression.name_token.line,
					expression.name_token.filepath,
				)
				EmitType_C(GetType(expression), fmt.tprintf("_%d", id), indent, buffer)
				fmt.sbprintf(buffer, " = %d;\n", uintptr(&DefaultU64Type))
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
			fmt.sbprintf(buffer, " = %s_%d;\n", decl.name_token.data.(string), uintptr(decl))
			return id
		case ^AstExternDeclaration:
			id := GetID()
			fmt.sbprintf(
				buffer,
				"#line %d \"%s\"\n",
				expression.name_token.line,
				expression.name_token.filepath,
			)
			EmitType_C(GetType(expression), fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = %s;\n", decl.name_token.data.(string))
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
	case ^AstProcedure:
		if type, ok := expression.type.(^TypeType); ok {
			id := GetID()
			fmt.sbprintf(
				buffer,
				"#line %d \"%s\"\n",
				expression.proc_token.line,
				expression.proc_token.filepath,
			)
			EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = %d;\n", uintptr(type))
			return id
		} else {
			name := expression.extern_string_token.?.data.(string)
			id := GetID()
			fmt.sbprintf(
				buffer,
				"#line %d \"%s\"\n",
				expression.proc_token.line,
				expression.proc_token.filepath,
			)
			EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = &%s;\n", name)
			return id
		}
	case ^AstArray:
		id := GetID()
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			expression.open_square_bracket_token.line,
			expression.open_square_bracket_token.filepath,
		)
		EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
		fmt.sbprintf(buffer, " = %d;\n", uintptr(expression.type.(^TypeArray)))
		return id
	case:
		unreachable()
	}
}
