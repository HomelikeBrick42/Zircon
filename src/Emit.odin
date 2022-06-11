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

EmitType_C :: proc(type: Type, name: string, buffer: ^strings.Builder) {
	switch type in type {
	case ^TypeVoid:
		fmt.sbprintf(buffer, "void %s", name)
	case ^TypeInt:
		fmt.sbprintf(buffer, "int %s", name)
	case ^TypeBool:
		fmt.sbprintf(buffer, "bool %s", name)
	case ^TypePointer:
		if name != "" {
			EmitType_C(type.pointer_to, fmt.tprintf("(*%s)", name), buffer)
		} else {
			EmitType_C(type.pointer_to, "*", buffer)
		}
	case ^TypeProcedure:
		fmt.sbprintf(buffer, "void* %s", name)
	case:
		unreachable()
	}
}

EmitAst_C :: proc(ast: Ast, names: ^[dynamic]Scope, buffer: ^strings.Builder) {
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
			EmitStatement_C(statement, names, buffer)
		}
		delete(pop(names))
		fmt.sbprintf(buffer, `        return 0;
    }}
}}
`)
	case AstStatement:
		EmitStatement_C(ast, names, buffer)
	case:
		unreachable()
	}
}

EmitStatement_C :: proc(
	statement: AstStatement,
	names: ^[dynamic]Scope,
	buffer: ^strings.Builder,
) {
	switch statement in statement {
	case ^AstScope:
		unimplemented()
	case ^AstDeclaration:
		value := EmitExpression_C(statement.value, names, buffer)
		name := statement.name_token.data.(string)
		fmt.sbprintf(buffer, "        // declaration of '%s'\n", name)
		fmt.sbprintf(buffer, "        ")
		EmitType_C(statement.resolved_type, fmt.tprintf("_%d", uintptr(statement)), buffer)
		fmt.sbprintf(buffer, " = _%d;\n", value)
		names[len(names) - 1][name] = statement
	case ^AstAssignment:
		operand := EmitAddressOf_C(statement.operand, names, buffer)
		value := EmitExpression_C(statement.value, names, buffer)
		fmt.sbprintf(buffer, "        // assignment\n")
		fmt.sbprintf(buffer, "        *_%d = _%d;\n", operand, value)
	case ^AstIf:
		unimplemented()
	case AstExpression:
		EmitExpression_C(statement, names, buffer)
	case:
		unreachable()
	}
}

EmitAddressOf_C :: proc(
	expression: AstExpression,
	names: ^[dynamic]Scope,
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
					fmt.sbprintf(buffer, "        // get address of '%s'\n", name)
					id := GetID()
					fmt.sbprintf(buffer, "        ")
					EmitType_C(GetPointerType(decl.resolved_type), fmt.tprintf("_%d", id), buffer)
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
	buffer: ^strings.Builder,
) -> uint {
	switch expression in expression {
	case ^AstUnary:
		operand := EmitExpression_C(expression.operand, names, buffer)
		switch expression.operator_kind {
		case .Invalid:
			unreachable()
		case .Identity:
			fmt.sbprintf(buffer, "        // unary +\n")
			id := GetID()
			fmt.sbprintf(buffer, "        ")
			EmitType_C(expression.type, fmt.tprintf("_%d", id), buffer)
			fmt.sbprintf(buffer, " = +_%d;\n", operand)
			return id
		case .Negation:
			fmt.sbprintf(buffer, "        // unary -\n")
			id := GetID()
			fmt.sbprintf(buffer, "        ")
			EmitType_C(expression.type, fmt.tprintf("_%d", id), buffer)
			fmt.sbprintf(buffer, " = -_%d;\n", operand)
			return id
		case .LogicalNot:
			fmt.sbprintf(buffer, "        // unary !\n")
			id := GetID()
			fmt.sbprintf(buffer, "        ")
			EmitType_C(expression.type, fmt.tprintf("_%d", id), buffer)
			fmt.sbprintf(buffer, " = !_%d;\n", operand)
			return id
		case:
			unreachable()
		}
	case ^AstBinary:
		left := EmitExpression_C(expression.left, names, buffer)
		right := EmitExpression_C(expression.right, names, buffer)
		switch expression.operator_kind {
		case .Invalid:
			unreachable()
		case .Addition:
			fmt.sbprintf(buffer, "        // binary +\n")
			id := GetID()
			fmt.sbprintf(buffer, "        ")
			EmitType_C(expression.type, fmt.tprintf("_%d", id), buffer)
			fmt.sbprintf(buffer, "  = _%d + _%d;\n", left, right)
			return id
		case .Subtraction:
			fmt.sbprintf(buffer, "        // binary -\n")
			id := GetID()
			fmt.sbprintf(buffer, "        ")
			EmitType_C(expression.type, fmt.tprintf("_%d", id), buffer)
			fmt.sbprintf(buffer, " = _%d - _%d;\n", left, right)
			return id
		case .Multiplication:
			fmt.sbprintf(buffer, "        // binary *\n")
			id := GetID()
			fmt.sbprintf(buffer, "        ")
			EmitType_C(expression.type, fmt.tprintf("_%d", id), buffer)
			fmt.sbprintf(buffer, " = _%d * _%d;\n", left, right)
			return id
		case .Division:
			fmt.sbprintf(buffer, "        // binary /\n")
			id := GetID()
			fmt.sbprintf(buffer, "        ")
			EmitType_C(expression.type, fmt.tprintf("_%d", id), buffer)
			fmt.sbprintf(buffer, " = _%d / _%d;\n", left, right)
			return id
		case .Equal:
			fmt.sbprintf(buffer, "        // binary ==\n")
			id := GetID()
			fmt.sbprintf(buffer, "        ")
			EmitType_C(expression.type, fmt.tprintf("_%d", id), buffer)
			fmt.sbprintf(buffer, " = _%d == _%d;\n", left, right)
			return id
		case .NotEqual:
			fmt.sbprintf(buffer, "        // binary !=\n")
			id := GetID()
			fmt.sbprintf(buffer, "        ")
			EmitType_C(expression.type, fmt.tprintf("_%d", id), buffer)
			fmt.sbprintf(buffer, " = _%d != _%d;\n", left, right)
			return id
		case:
			unreachable()
		}
	case ^AstCall:
		operand := EmitExpression_C(expression.operand, names, buffer)
		ids: [dynamic]uint
		defer delete(ids)
		for argument in expression.arguments {
			append(&ids, EmitExpression_C(argument, names, buffer))
		}
		fmt.sbprintf(buffer, "        // call\n")
		for id, i in ids {
			fmt.sbprintf(buffer, "        // argument %d\n", i + 1)
			fmt.sbprintf(buffer, "        sp -= sizeof(")
			EmitType_C(GetType(expression.arguments[i]), "", buffer)
			fmt.sbprintf(buffer, ");\n")
			fmt.sbprintf(buffer, "        *(")
			EmitType_C(GetPointerType(GetType(expression.arguments[i])), "", buffer)
			fmt.sbprintf(buffer, ")sp = _%d;\n", id)
		}
		fmt.sbprintf(buffer, "        // return location\n")
		ret_id := GetID()
		fmt.sbprintf(buffer, "        sp -= sizeof(void*);\n")
		fmt.sbprintf(buffer, "        *(void**)sp = &&_%d;\n", ret_id)
		fmt.sbprintf(buffer, "        goto *_%d;\n", operand)
		fmt.sbprintf(buffer, "        _%d:\n", ret_id)
		id := GetID()
		return_type := GetType(expression.operand).(^TypeProcedure).return_type
		if _, ok := return_type.(^TypeVoid); !ok {
			fmt.sbprintf(buffer, "        // return value\n")
			fmt.sbprintf(buffer, "        ")
			EmitType_C(return_type, fmt.tprintf("_%d", id), buffer)
			fmt.sbprintf(buffer, " = *(")
			EmitType_C(GetPointerType(return_type), "", buffer)
			fmt.sbprintf(buffer, ")sp;\n")
			fmt.sbprintf(buffer, "        sp += sizeof(")
			EmitType_C(return_type, "", buffer)
			fmt.sbprintf(buffer, ");\n")
		}
		fmt.sbprintf(buffer, "        // call cleanup\n")
		fmt.sbprintf(buffer, "        sp += sizeof(void*);\n")
		for id, i in ids {
			fmt.sbprintf(buffer, "        sp += sizeof(")
			EmitType_C(GetType(expression.arguments[i]), "", buffer)
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
					fmt.sbprintf(buffer, "        // get '%s'\n", name)
					fmt.sbprintf(buffer, "        ")
					EmitType_C(expression.type, fmt.tprintf("_%d", id), buffer)
					fmt.sbprintf(buffer, " = _%d;\n", uintptr(decl))
					return id
				case Builtin:
					switch decl {
					case .PrintInt:
						fmt.sbprintf(buffer, "        // get 'print_int'\n")
						id := GetID()
						fmt.sbprintf(buffer, "        void* _%d = &&_print_int;\n", id)
						return id
					case .PrintBool:
						fmt.sbprintf(buffer, "        // get 'print_bool'\n")
						id := GetID()
						fmt.sbprintf(buffer, "        void* _%d = &&_print_bool;\n", id)
						return id
					case .Println:
						fmt.sbprintf(buffer, "        // get 'print_ln'\n")
						id := GetID()
						fmt.sbprintf(buffer, "        void* _%d = &&_println;\n", id)
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
		fmt.sbprintf(buffer, "        // integer %d\n", value)
		id := GetID()
		fmt.sbprintf(buffer, "        ")
		EmitType_C(expression.type, fmt.tprintf("_%d", id), buffer)
		fmt.sbprintf(buffer, " = %d;\n", value)
		return id
	case:
		unreachable()
	}
}
