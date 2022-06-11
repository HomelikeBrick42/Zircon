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

EmitType_C :: proc(type: Type, name: string, file: os.Handle) {
	switch type in type {
	case ^TypeVoid:
		fmt.fprintf(file, "void %s", name)
	case ^TypeInt:
		fmt.fprintf(file, "int %s", name)
	case ^TypeBool:
		fmt.fprintf(file, "bool %s", name)
	case ^TypePointer:
		if name != "" {
			EmitType_C(type.pointer_to, fmt.tprintf("(*%s)", name), file)
		} else {
			EmitType_C(type.pointer_to, "*", file)
		}
	case ^TypeProcedure:
		fmt.fprintf(file, "void* %s", name)
	case:
		unreachable()
	}
}

EmitAst_C :: proc(ast: Ast, names: ^[dynamic]Scope, file: os.Handle) {
	switch ast in ast {
	case ^AstFile:
		fmt.fprintf(
			file,
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
		name := statement.name_token.data.(string)
		fmt.fprintf(file, "        // declaration of '%s'\n", name)
		fmt.fprintf(file, "        ")
		EmitType_C(statement.resolved_type, fmt.tprintf("_%d", uintptr(statement)), file)
		fmt.fprintf(file, " = _%d;\n", value)
		names[len(names) - 1][name] = statement
	case ^AstAssignment:
		operand := EmitAddressOf_C(statement.operand, names, file)
		value := EmitExpression_C(statement.value, names, file)
		fmt.fprintf(file, "        // assignment\n")
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
					fmt.fprintf(file, "        // get address of '%s'\n", name)
					id := GetID()
					fmt.fprintf(file, "        ")
					EmitType_C(GetPointerType(decl.resolved_type), fmt.tprintf("_%d", id), file)
					fmt.fprintf(file, " = &_%d;\n", uintptr(decl))
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
			fmt.fprintf(file, "        // unary +\n")
			id := GetID()
			fmt.fprintf(file, "        ")
			EmitType_C(expression.type, fmt.tprintf("_%d", id), file)
			fmt.fprintf(file, " = +_%d;\n", operand)
			return id
		case .Negation:
			fmt.fprintf(file, "        // unary -\n")
			id := GetID()
			fmt.fprintf(file, "        ")
			EmitType_C(expression.type, fmt.tprintf("_%d", id), file)
			fmt.fprintf(file, " = -_%d;\n", operand)
			return id
		case .LogicalNot:
			fmt.fprintf(file, "        // unary !\n")
			id := GetID()
			fmt.fprintf(file, "        ")
			EmitType_C(expression.type, fmt.tprintf("_%d", id), file)
			fmt.fprintf(file, " = !_%d;\n", operand)
			return id
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
			fmt.fprintf(file, "        // binary +\n")
			id := GetID()
			fmt.fprintf(file, "        ")
			EmitType_C(expression.type, fmt.tprintf("_%d", id), file)
			fmt.fprintf(file, "  = _%d + _%d;\n", left, right)
			return id
		case .Subtraction:
			fmt.fprintf(file, "        // binary -\n")
			id := GetID()
			fmt.fprintf(file, "        ")
			EmitType_C(expression.type, fmt.tprintf("_%d", id), file)
			fmt.fprintf(file, " = _%d - _%d;\n", left, right)
			return id
		case .Multiplication:
			fmt.fprintf(file, "        // binary *\n")
			id := GetID()
			fmt.fprintf(file, "        ")
			EmitType_C(expression.type, fmt.tprintf("_%d", id), file)
			fmt.fprintf(file, " = _%d * _%d;\n", left, right)
			return id
		case .Division:
			fmt.fprintf(file, "        // binary /\n")
			id := GetID()
			fmt.fprintf(file, "        ")
			EmitType_C(expression.type, fmt.tprintf("_%d", id), file)
			fmt.fprintf(file, " = _%d / _%d;\n", left, right)
			return id
		case .Equal:
			fmt.fprintf(file, "        // binary ==\n")
			id := GetID()
			fmt.fprintf(file, "        ")
			EmitType_C(expression.type, fmt.tprintf("_%d", id), file)
			fmt.fprintf(file, " = _%d == _%d;\n", left, right)
			return id
		case .NotEqual:
			fmt.fprintf(file, "        // binary !=\n")
			id := GetID()
			fmt.fprintf(file, "        ")
			EmitType_C(expression.type, fmt.tprintf("_%d", id), file)
			fmt.fprintf(file, " = _%d != _%d;\n", left, right)
			return id
		case:
			unreachable()
		}
	case ^AstCall:
		operand := EmitExpression_C(expression.operand, names, file)
		ids: [dynamic]uint
		defer delete(ids)
		for argument in expression.arguments {
			append(&ids, EmitExpression_C(argument, names, file))
		}
		fmt.fprintf(file, "        // call\n")
		for id, i in ids {
			fmt.fprintf(file, "        // argument %d\n", i + 1)
			fmt.fprintf(file, "        sp -= sizeof(")
			EmitType_C(GetType(expression.arguments[i]), "", file)
			fmt.fprintf(file, ");\n")
			fmt.fprint(file, "        *(")
			EmitType_C(GetPointerType(GetType(expression.arguments[i])), "", file)
			fmt.fprintf(file, ")sp = _%d;\n", id)
		}
		fmt.fprintf(file, "        // return location\n")
		ret_id := GetID()
		fmt.fprintf(file, "        sp -= sizeof(void*);\n")
		fmt.fprintf(file, "        *(void**)sp = &&_%d;\n", ret_id)
		fmt.fprintf(file, "        goto *_%d;\n", operand)
		fmt.fprintf(file, "        _%d:\n", ret_id)
		id := GetID()
		return_type := GetType(expression.operand).(^TypeProcedure).return_type
		if _, ok := return_type.(^TypeVoid); !ok {
			fmt.fprintf(file, "        // return value\n")
			fmt.fprintf(file, "        ")
			EmitType_C(return_type, fmt.tprintf("_%d", id), file)
			fmt.fprintf(file, " = *(")
			EmitType_C(GetPointerType(return_type), "", file)
			fmt.fprintf(file, ")sp;\n")
			fmt.fprintf(file, "        sp += sizeof(")
			EmitType_C(return_type, "", file)
			fmt.fprintf(file, ");\n")
		}
		fmt.fprintf(file, "        // call cleanup\n")
		fmt.fprintf(file, "        sp += sizeof(void*);\n")
		for id, i in ids {
			fmt.fprintf(file, "        sp += sizeof(")
			EmitType_C(GetType(expression.arguments[i]), "", file)
			fmt.fprintf(file, ");\n")
		}
		return id
	case ^AstName:
		name := expression.name_token.data.(string)
		for i := len(names) - 1; i >= 0; i -= 1 {
			if decl, ok := names[i][name]; ok {
				switch decl in decl {
				case ^AstDeclaration:
					id := GetID()
					fmt.fprintf(file, "        // get '%s'\n", name)
					fmt.fprintf(file, "        ")
					EmitType_C(expression.type, fmt.tprintf("_%d", id), file)
					fmt.fprintf(file, " = _%d;\n", uintptr(decl))
					return id
				case Builtin:
					switch decl {
					case .PrintInt:
						fmt.fprintf(file, "        // get 'print_int'\n")
						id := GetID()
						fmt.fprintf(file, "        void* _%d = &&_print_int;\n", id)
						return id
					case .PrintBool:
						fmt.fprintf(file, "        // get 'print_bool'\n")
						id := GetID()
						fmt.fprintf(file, "        void* _%d = &&_print_bool;\n", id)
						return id
					case .Println:
						fmt.fprintf(file, "        // get 'print_ln'\n")
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
		value := expression.integer_token.data.(u128)
		fmt.fprintf(file, "        // integer %d\n", value)
		id := GetID()
		fmt.fprintf(file, "        ")
		EmitType_C(expression.type, fmt.tprintf("_%d", id), file)
		fmt.fprintf(file, " = %d;\n", value)
		return id
	case:
		unreachable()
	}
}
