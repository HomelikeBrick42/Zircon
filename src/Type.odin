package zircon

import "core:fmt"

Type :: union #shared_nil {
	^TypeVoid,
	^TypeInt,
	^TypeBool,
	^TypeProcedure,
}

TypeVoid :: struct {}

TypeInt :: struct {}

TypeBool :: struct {}

TypeProcedure :: struct {
	parameter_types: [dynamic]Type,
	return_type:     Type,
}

DumpType :: proc(type: Type, indent: uint) {
	PrintIndent :: proc(indent: uint) {
		for _ in 0 ..< indent {
			fmt.print("  ")
		}
	}

	switch type in type {
	case ^TypeVoid:
		PrintIndent(indent)
		fmt.println("- Void Type")
	case ^TypeInt:
		PrintIndent(indent)
		fmt.println("- Int Type")
	case ^TypeBool:
		PrintIndent(indent)
		fmt.println("- Bool Type")
	case ^TypeProcedure:
		PrintIndent(indent)
		fmt.println("- Procedure Type")
		for parameter_type, i in type.parameter_types {
			PrintIndent(indent + 1)
			fmt.printf("Parameter %d Type:\n", i + 1)
			DumpType(parameter_type, indent + 2)
		}
		PrintIndent(indent + 1)
		fmt.println("Return Type:")
		DumpType(type.return_type, indent + 2)
	case:
		unreachable()
	}
}

VoidType := TypeVoid{}
IntType := TypeInt{}
BoolType := TypeBool{}
ProcedureTypes := make([dynamic]^TypeProcedure)
