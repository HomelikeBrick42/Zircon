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
		fmt.sbprintf(buffer, "void %s", name)
	case ^TypeInt:
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "int %s", name)
	case ^TypeBool:
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "bool %s", name)
	case ^TypePointer:
		EmitType_C(type.pointer_to, fmt.tprintf("(*%s)", name), indent, buffer)
	case ^TypeProcedure:
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "void* %s", name)
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
#include <stdbool.h>

static char stack[1024 * 1024];
static char* sp = stack + (1024 * 1024);

int main() {{
    goto _main;
    _print_int: {{
        void* retAddress = *(void**)sp;
        int value = *(int*)(sp + sizeof(void*));
        int numCharacters = printf("%%d", value);
        sp -= sizeof(int);
        *(int*)sp = numCharacters;
        goto *retAddress;
    }}
    _print_bool: {{
        void* retAddress = *(void**)sp;
        bool value = *(bool*)(sp + sizeof(void*));
        int numCharacters = printf(value ? "true" : "false");
        sp -= sizeof(int);
        *(int*)sp = numCharacters;
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
		unimplemented()
	case ^AstDeclaration:
		value := EmitExpression_C(statement.value, names, indent, buffer)
		name := statement.name_token.data.(string)
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "// declaration of '%s'\n", name)
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
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, " // assignment\n")
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "*_%d = _%d;\n", operand, value)
	case ^AstIf:
		unimplemented()
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
	case ^AstName:
		name := expression.name_token.data.(string)
		for i := len(names) - 1; i >= 0; i -= 1 {
			if decl, ok := names[i][name]; ok {
				switch decl in decl {
				case ^AstDeclaration:
					PrintIndent(indent, buffer)
					fmt.sbprintf(buffer, "// get address of '%s'\n", name)
					id := GetID()
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
			PrintIndent(indent, buffer)
			fmt.sbprintf(buffer, "// unary +\n")
			id := GetID()
			EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = +_%d;\n", operand)
			return id
		case .Negation:
			PrintIndent(indent, buffer)
			fmt.sbprintf(buffer, "// unary -\n")
			id := GetID()
			EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = -_%d;\n", operand)
			return id
		case .LogicalNot:
			PrintIndent(indent, buffer)
			fmt.sbprintf(buffer, "// unary !\n")
			id := GetID()
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
			PrintIndent(indent, buffer)
			fmt.sbprintf(buffer, "// binary +\n")
			id := GetID()
			EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, "  = _%d + _%d;\n", left, right)
			return id
		case .Subtraction:
			PrintIndent(indent, buffer)
			fmt.sbprintf(buffer, "// binary -\n")
			id := GetID()
			EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = _%d - _%d;\n", left, right)
			return id
		case .Multiplication:
			PrintIndent(indent, buffer)
			fmt.sbprintf(buffer, "// binary *\n")
			id := GetID()
			EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = _%d * _%d;\n", left, right)
			return id
		case .Division:
			PrintIndent(indent, buffer)
			fmt.sbprintf(buffer, "// binary /\n")
			id := GetID()
			EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = _%d / _%d;\n", left, right)
			return id
		case .Equal:
			PrintIndent(indent, buffer)
			fmt.sbprintf(buffer, "// binary ==\n")
			id := GetID()
			EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = _%d == _%d;\n", left, right)
			return id
		case .NotEqual:
			PrintIndent(indent, buffer)
			fmt.sbprintf(buffer, "// binary !=\n")
			id := GetID()
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
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "// call\n")
		for id, i in ids {
			PrintIndent(indent, buffer)
			fmt.sbprintf(buffer, "// argument %d\n", i + 1)
			PrintIndent(indent, buffer)
			fmt.sbprintf(buffer, "sp -= sizeof(")
			EmitType_C(GetType(expression.arguments[i]), "", 0, buffer)
			fmt.sbprintf(buffer, ");\n")
			PrintIndent(indent, buffer)
			fmt.sbprintf(buffer, "*(")
			EmitType_C(GetPointerType(GetType(expression.arguments[i])), "", 0, buffer)
			fmt.sbprintf(buffer, ")sp = _%d;\n", id)
		}
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "// return location\n")
		ret_id := GetID()
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "sp -= sizeof(void*);\n")
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "*(void**)sp = &&_%d;\n", ret_id)
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "goto *_%d;\n", operand)
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "_%d:\n", ret_id)
		id := GetID()
		return_type := GetType(expression.operand).(^TypeProcedure).return_type
		if _, ok := return_type.(^TypeVoid); !ok {
			PrintIndent(indent, buffer)
			fmt.sbprintf(buffer, "// return value\n")
			EmitType_C(return_type, fmt.tprintf("_%d", id), indent, buffer)
			fmt.sbprintf(buffer, " = *(")
			EmitType_C(GetPointerType(return_type), "", 0, buffer)
			fmt.sbprintf(buffer, ")sp;\n")
			PrintIndent(indent, buffer)
			fmt.sbprintf(buffer, "sp += sizeof(")
			EmitType_C(return_type, "", 0, buffer)
			fmt.sbprintf(buffer, ");\n")
		}
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "// call cleanup\n")
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "sp += sizeof(void*);\n")
		for id, i in ids {
			PrintIndent(indent, buffer)
			fmt.sbprintf(buffer, "sp += sizeof(")
			EmitType_C(GetType(expression.arguments[i]), "", 0, buffer)
			fmt.sbprintf(buffer, ");\n")
		}
		return id
	case ^AstName:
		name := expression.name_token.data.(string)
		for i := len(names) - 1; i >= 0; i -= 1 {
			if decl, ok := names[i][name]; ok {
				switch decl in decl {
				case ^AstDeclaration:
					id := GetID()
					PrintIndent(indent, buffer)
					fmt.sbprintf(buffer, "// get '%s'\n", name)
					EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
					fmt.sbprintf(buffer, " = _%d;\n", uintptr(decl))
					return id
				case Builtin:
					switch decl {
					case .PrintInt:
						PrintIndent(indent, buffer)
						fmt.sbprintf(buffer, "// get 'print_int'\n")
						id := GetID()
						PrintIndent(indent, buffer)
						fmt.sbprintf(buffer, "void* _%d = &&_print_int;\n", id)
						return id
					case .PrintBool:
						PrintIndent(indent, buffer)
						fmt.sbprintf(buffer, "// get 'print_bool'\n")
						id := GetID()
						PrintIndent(indent, buffer)
						fmt.sbprintf(buffer, "void* _%d = &&_print_bool;\n", id)
						return id
					case .Println:
						PrintIndent(indent, buffer)
						fmt.sbprintf(buffer, "// get 'print_ln'\n")
						id := GetID()
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
		PrintIndent(indent, buffer)
		fmt.sbprintf(buffer, "// integer %d\n", value)
		id := GetID()
		EmitType_C(expression.type, fmt.tprintf("_%d", id), indent, buffer)
		fmt.sbprintf(buffer, " = %d;\n", value)
		return id
	case:
		unreachable()
	}
}
