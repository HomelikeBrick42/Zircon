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
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "Void* %s", name)
	case:
		unreachable()
	}
}

EmitAst_C :: proc(
	ast: Ast,
	names: ^[dynamic]Scope,
	indent: uint,
	buffer: ^strings.Builder,
) {
	switch ast in ast {
	case ^AstFile:
		fmt.sbprintf(
			buffer,
			`#include <stdio.h>

typedef void Void;
typedef size_t Type;
typedef signed long long Int;
typedef _Bool Bool;

static char stack[1024 * 1024];
static char* sp = stack + (1024 * 1024);

int main() {{
    goto _main;
    _print_int: {{
        void* retAddress = *(void**)sp;
        Int value = *(Int*)(sp + sizeof(void*));
        Int numCharacters = (Int)printf("%%lld", value);
        sp -= sizeof(Int);
        *(Int*)sp = numCharacters;
        goto *retAddress;
    }}
    _print_bool: {{
        void* retAddress = *(void**)sp;
        Bool value = *(Bool*)(sp + sizeof(void*));
        Int numCharacters = (Int)printf(value ? "true" : "false");
        sp -= sizeof(Int);
        *(Int*)sp = numCharacters;
        goto *retAddress;
    }}
    _println: {{
        void* retAddress = *(void**)sp;
        printf("\n");
        goto *retAddress;
    }}
    _main: {{
`,
		)
		append(names, Scope{})
		for statement in ast.statements {
			EmitStatement_C(statement, names, indent + 2, buffer)
		}
		delete(pop(names))
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			ast.end_of_file_token.line,
			ast.end_of_file_token.filepath,
		)
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, `        return 0;
    }}
}}
`)
	case AstStatement:
		EmitStatement_C(ast, names, indent, buffer)
	case:
		unreachable()
	}
}

EmitStatement_C :: proc(
	statement: AstStatement,
	names: ^[dynamic]Scope,
	indent: uint,
	buffer: ^strings.Builder,
) {
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
			EmitStatement_C(statement, names, indent + 1, buffer)
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
		value := EmitExpression_C(statement.value, names, indent, buffer)
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
		names[len(names) - 1][name] = statement
	case ^AstAssignment:
		operand := EmitAddressOf_C(statement.operand, names, indent, buffer)
		value := EmitExpression_C(statement.value, names, indent, buffer)
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			statement.equal_token.line,
			statement.equal_token.filepath,
		)
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "*_%d = _%d;\n", operand, value)
	case ^AstIf:
		condition := EmitExpression_C(statement.condition, names, indent, buffer)
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			statement.if_token.line,
			statement.if_token.filepath,
		)
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "if (_%d)\n", condition)
		EmitStatement_C(statement.then_body, names, indent, buffer)
		if else_body, ok := statement.else_body.?; ok {
			fmt.sbprintf(
				buffer,
				"#line %d \"%s\"\n",
				statement.else_token.line,
				statement.else_token.filepath,
			)
			PrintIndent(indent, buffer)
			fmt.sbprintf(buffer, "else\n")
			EmitStatement_C(else_body, names, indent, buffer)
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
		condition := EmitExpression_C(statement.condition, names, indent + 1, buffer)
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			statement.while_token.line,
			statement.while_token.filepath,
		)
		PrintIndent(indent + 1, buffer)
		fmt.sbprintf(buffer, "if (!_%d) break;\n", condition)
		EmitStatement_C(statement.body, names, indent + 1, buffer)
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			statement.while_token.line,
			statement.while_token.filepath,
		)
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "}}\n")
	case AstExpression:
		EmitExpression_C(statement, names, indent, buffer)
	case:
		unreachable()
	}
}

EmitAddressOf_C :: proc(
	expression: AstExpression,
	names: ^[dynamic]Scope,
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
		return EmitExpression_C(expression.operand, names, indent, buffer)
	case ^AstName:
		name := expression.name_token.data.(string)
		for i := len(names) - 1; i >= 0; i -= 1 {
			if decl, ok := names[i][name]; ok {
				switch decl in decl {
				case ^AstDeclaration:
					id := GetID()
					fmt.sbprintf(
						buffer,
						"#line %d \"%s\"\n",
						expression.name_token.line,
						expression.name_token.filepath,
					)
					EmitType_C(
						GetPointerType(decl.resolved_type),
						fmt.tprintf("_%d", id),
						indent,
						buffer,
					)
					fmt.sbprintf(buffer, " = &_%d;\n", uintptr(decl))
					return id
				case Builtin:
					unreachable()
				case:
					unreachable()
				}
			}
		}
		unreachable()
	case ^AstInteger:
		unreachable()
	case:
		unreachable()
	}
}

EmitExpression_C :: proc(
	expression: AstExpression,
	names: ^[dynamic]Scope,
	indent: uint,
	buffer: ^strings.Builder,
) -> uint {
	switch expression in expression {
	case ^AstUnary:
		operand := EmitExpression_C(expression.operand, names, indent, buffer)
		switch expression.operator_kind {
		case .Invalid:
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
		left := EmitExpression_C(expression.left, names, indent, buffer)
		right := EmitExpression_C(expression.right, names, indent, buffer)
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
		operand := EmitExpression_C(expression.operand, names, indent, buffer)
		ids: [dynamic]uint
		defer delete(ids)
		for argument in expression.arguments {
			append(&ids, EmitExpression_C(argument, names, indent, buffer))
		}
		for id, i in ids {
			fmt.sbprintf(
				buffer,
				"#line %d \"%s\"\n",
				expression.open_parenthesis_token.line,
				expression.open_parenthesis_token.filepath,
			)
			PrintIndent(indent, buffer)
			fmt.sbprintf(buffer, "sp -= sizeof(")
			EmitType_C(GetType(expression.arguments[i]), "", 0, buffer)
			fmt.sbprintf(buffer, ");\n")
			fmt.sbprintf(
				buffer,
				"#line %d \"%s\"\n",
				expression.open_parenthesis_token.line,
				expression.open_parenthesis_token.filepath,
			)
			PrintIndent(indent, buffer)
			fmt.sbprintf(buffer, "*(")
			EmitType_C(GetPointerType(GetType(expression.arguments[i])), "", 0, buffer)
			fmt.sbprintf(buffer, ")sp = _%d;\n", id)
		}
		ret_id := GetID()
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			expression.open_parenthesis_token.line,
			expression.open_parenthesis_token.filepath,
		)
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "sp -= sizeof(void*);\n")
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			expression.open_parenthesis_token.line,
			expression.open_parenthesis_token.filepath,
		)
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "*(void**)sp = &&_%d;\n", ret_id)
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			expression.open_parenthesis_token.line,
			expression.open_parenthesis_token.filepath,
		)
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "goto *_%d;\n", operand)
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			expression.open_parenthesis_token.line,
			expression.open_parenthesis_token.filepath,
		)
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "_%d:\n", ret_id)
		id := GetID()
		return_type := GetType(expression.operand).(^TypeProcedure).return_type
		if _, ok := return_type.(^TypeVoid); !ok {
			fmt.sbprintf(
				buffer,
				"#line %d \"%s\"\n",
				expression.open_parenthesis_token.line,
				expression.open_parenthesis_token.filepath,
			)
			EmitType_C(return_type, fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = *(")
			EmitType_C(GetPointerType(return_type), "", 0, buffer)
			fmt.sbprintf(buffer, ")sp;\n")
			fmt.sbprintf(
				buffer,
				"#line %d \"%s\"\n",
				expression.open_parenthesis_token.line,
				expression.open_parenthesis_token.filepath,
			)
			PrintIndent(indent, buffer)
			fmt.sbprintf(buffer, "sp += sizeof(")
			EmitType_C(return_type, "", 0, buffer)
			fmt.sbprintf(buffer, ");\n")
		}
		fmt.sbprintf(
			buffer,
			"#line %d \"%s\"\n",
			expression.close_parenthesis_token.line,
			expression.close_parenthesis_token.filepath,
		)
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "sp += sizeof(void*);\n")
		for id, i in ids {
			fmt.sbprintf(
				buffer,
				"#line %d \"%s\"\n",
				expression.close_parenthesis_token.line,
				expression.close_parenthesis_token.filepath,
			)
			PrintIndent(indent, buffer)
			fmt.sbprintf(buffer, "sp += sizeof(")
			EmitType_C(GetType(expression.arguments[i]), "", 0, buffer)
			fmt.sbprintf(buffer, ");\n")
		}
		return id
	case ^AstAddressOf:
		return EmitAddressOf_C(expression.operand, names, indent, buffer)
	case ^AstDereference:
		operand := EmitExpression_C(expression.operand, names, indent, buffer)
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
		name := expression.name_token.data.(string)
		for i := len(names) - 1; i >= 0; i -= 1 {
			if decl, ok := names[i][name]; ok {
				switch decl in decl {
				case ^AstDeclaration:
					id := GetID()
					fmt.sbprintf(
						buffer,
						"#line %d \"%s\"\n",
						expression.name_token.line,
						expression.name_token.filepath,
					)
					EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
					fmt.sbprintf(buffer, " = _%d;\n", uintptr(decl))
					return id
				case Builtin:
					switch decl {
					case .PrintInt:
						id := GetID()
						fmt.sbprintf(
							buffer,
							"#line %d \"%s\"\n",
							expression.name_token.line,
							expression.name_token.filepath,
						)
						PrintIndent(indent, buffer)
						fmt.sbprintf(buffer, "void* _%d = &&_print_int;\n", id)
						return id
					case .PrintBool:
						id := GetID()
						fmt.sbprintf(
							buffer,
							"#line %d \"%s\"\n",
							expression.name_token.line,
							expression.name_token.filepath,
						)
						PrintIndent(indent, buffer)
						fmt.sbprintf(buffer, "void* _%d = &&_print_bool;\n", id)
						return id
					case .Println:
						id := GetID()
						fmt.sbprintf(
							buffer,
							"#line %d \"%s\"\n",
							expression.name_token.line,
							expression.name_token.filepath,
						)
						PrintIndent(indent, buffer)
						fmt.sbprintf(buffer, "void* _%d = &&_println;\n", id)
						return id
					case:
						unreachable()
					}
				case:
					unreachable()
				}
			}
		}
		unreachable()
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
