package zircon

import "core:os"
import "core:fmt"

GetID :: proc() -> uint {
	@(static)
	id := uint(1)
	new_id := id
	id += 1
	return new_id
}

EmitAst_C :: proc(ast: Ast, names: ^[dynamic]Scope, file: os.Handle) {
	switch ast in ast {
	case ^AstFile:
		fmt.fprintf(
			file,
			`#include <stdio.h>

static char stack[1024 * 1024];
static char* sp = stack + (1024 * 1024);

int main() {{
    goto _main;
    _print_int: {{
        void* retAddress = *(void**)sp;
        int value = *(int*)(sp + sizeof(void*));
        printf("%%d", value);
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
			EmitStatement_C(statement, names, file)
		}
		delete(pop(names))
		fmt.fprintf(file, `        return 0;
    }}
}}
`)
	case AstStatement:
		EmitStatement_C(ast, names, file)
	case:
		unreachable()
	}
}

EmitStatement_C :: proc(
	statement: AstStatement,
	names: ^[dynamic]Scope,
	file: os.Handle,
) {
	switch statement in statement {
	case ^AstDeclaration:
		value := EmitExpression_C(statement.value, names, file)
		fmt.fprintf(file, "        int _%d = _%d;\n", uintptr(statement), value)
		name := statement.name_token.data.(string)
		names[len(names) - 1][name] = statement
	case ^AstAssignment:
		operand := EmitAddressOf_C(statement.operand, names, file)
		value := EmitExpression_C(statement.value, names, file)
		fmt.fprintf(file, "        *_%d = _%d;\n", operand, value)
	case AstExpression:
		EmitExpression_C(statement, names, file)
	case:
		unreachable()
	}
}

EmitAddressOf_C :: proc(
	expression: AstExpression,
	names: ^[dynamic]Scope,
	file: os.Handle,
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
					id := GetID()
					fmt.fprintf(file, "        int* _%d = &_%d;\n", id, uintptr(decl))
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
	file: os.Handle,
) -> uint {
	switch expression in expression {
	case ^AstUnary:
		operand := EmitExpression_C(expression.operand, names, file)
		switch expression.operator_kind {
		case .Invalid:
			unreachable()
		case .Identity:
			id := GetID()
			fmt.fprintf(file, "        int _%d = +_%d;\n", id, operand)
			return id
		case .Negation:
			id := GetID()
			fmt.fprintf(file, "        int _%d = -_%d;\n", id, operand)
			return id
		case .LogicalNot:
			unimplemented()
		case:
			unreachable()
		}
	case ^AstBinary:
		left := EmitExpression_C(expression.left, names, file)
		right := EmitExpression_C(expression.right, names, file)
		switch expression.operator_kind {
		case .Invalid:
			unreachable()
		case .Addition:
			id := GetID()
			fmt.fprintf(file, "        int _%d = _%d + _%d;\n", id, left, right)
			return id
		case .Subtraction:
			id := GetID()
			fmt.fprintf(file, "        int _%d = _%d - _%d;\n", id, left, right)
			return id
		case .Multiplication:
			id := GetID()
			fmt.fprintf(file, "        int _%d = _%d * _%d;\n", id, left, right)
			return id
		case .Division:
			id := GetID()
			fmt.fprintf(file, "        int _%d = _%d / _%d;\n", id, left, right)
			return id
		case .Equal:
			unimplemented()
		case .NotEqual:
			unimplemented()
		case:
			unreachable()
		}
	case ^AstCall:
		operand := EmitExpression_C(expression.operand, names, file)
		ids: [dynamic]uint
		for argument in expression.arguments {
			append(&ids, EmitExpression_C(argument, names, file))
		}
		for id in ids {
			fmt.fprintf(file, "        sp -= sizeof(int);\n")
			fmt.fprintf(file, "        *(int*)sp = _%d;\n", id)
		}
		ret_id := GetID()
		fmt.fprintf(file, "        sp -= sizeof(void*);\n")
		fmt.fprintf(file, "        *(void**)sp = &&_%d;\n", ret_id)
		fmt.fprintf(file, "        goto *_%d;\n", operand)
		fmt.fprintf(file, "        _%d:\n", ret_id)
		fmt.fprintf(file, "        sp += sizeof(void*);\n")
		for id in ids {
			fmt.fprintf(file, "        sp += sizeof(int);\n")
		}
		// TODO: save result to a variable
		return 0
	case ^AstName:
		name := expression.name_token.data.(string)
		for i := len(names) - 1; i >= 0; i -= 1 {
			if decl, ok := names[i][name]; ok {
				switch decl in decl {
				case ^AstDeclaration:
					id := GetID()
					fmt.fprintf(file, "        int _%d = _%d;\n", id, uintptr(decl))
					return id
				case Builtin:
					switch decl {
					case .PrintInt:
						id := GetID()
						fmt.fprintf(file, "        void* _%d = &&_print_int;\n", id)
						return id
					case .Println:
						id := GetID()
						fmt.fprintf(file, "        void* _%d = &&_println;\n", id)
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
		id := GetID()
		fmt.fprintf(file, "        int _%d = %d;\n", id, expression.integer_token.data.(u128))
		return id
	case:
		unreachable()
	}
}
