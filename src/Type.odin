package zircon

import "core:fmt"

Type :: union #shared_nil {
	^TypeVoid,
	^TypeInt,
	^TypeBool,
	^TypePointer,
	^TypeProcedure,
}

TypeVoid :: struct {}

TypeInt :: struct {}

TypeBool :: struct {}

TypePointer :: struct {
	pointer_to: Type,
}

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
	case ^TypePointer:
		PrintIndent(indent)
		fmt.println("- Pointer Type")
		PrintIndent(indent + 1)
		fmt.println("Pointer To:")
		DumpType(type.pointer_to, indent + 2)
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
PointerTypes := make(map[Type]TypePointer)
ProcedureTypes := make([dynamic]^TypeProcedure)

GetPointerType :: proc(pointer_to: Type) -> Type {
	if type, ok := &PointerTypes[pointer_to]; ok {
		return type
	}
	PointerTypes[pointer_to] = TypePointer {
		pointer_to = pointer_to,
	}
	return &PointerTypes[pointer_to]
}
