package zircon

import "core:fmt"

Type :: union #shared_nil {
	^TypeVoid,
	^TypeType,
	^TypeInt,
	^TypeBool,
	^TypePointer,
	^TypeProcedure,
}

TypeVoid :: struct {}

TypeType :: struct {}

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
	case ^TypeType:
		PrintIndent(indent)
		fmt.println("- Type Type")
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

DefaultVoidType := TypeVoid{}
DefaultTypeType := TypeType{}
DefaultIntType := TypeInt{}
DefaultBoolType := TypeBool{}
DefaultPointerTypes := make(map[Type]TypePointer)
DefaultProcedureTypes := make([dynamic]^TypeProcedure)

GetPointerType :: proc(pointer_to: Type) -> Type {
	if type, ok := &DefaultPointerTypes[pointer_to]; ok {
		return type
	}
	DefaultPointerTypes[pointer_to] = TypePointer {
		pointer_to = pointer_to,
	}
	return &DefaultPointerTypes[pointer_to]
}
