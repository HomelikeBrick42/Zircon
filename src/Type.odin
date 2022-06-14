package zircon

import "core:fmt"
import "core:slice"

Type :: union #shared_nil {
	^TypeVoid,
	^TypeType,
	^TypeInt,
	^TypeBool,
	^TypePointer,
	^TypeProcedure,
	^TypeArray,
}

TypeVoid :: struct {}

TypeType :: struct {}

TypeInt :: struct {
	size:   uint,
	signed: bool,
}

TypeBool :: struct {}

TypePointer :: struct {
	pointer_to: Type,
}

TypeProcedure :: struct {
	parameter_types: []Type,
	return_type:     Type,
}

TypeArray :: struct {
	inner_type: Type,
	length:     uint,
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
		PrintIndent(indent + 1)
		fmt.println("Size:", type.size)
		PrintIndent(indent + 1)
		fmt.println("Signed:", type.signed)
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
	case ^TypeArray:
		PrintIndent(indent)
		fmt.println("- Array Type")
		PrintIndent(indent + 1)
		fmt.println("Inner Type:")
		DumpType(type.inner_type, indent + 2)
	case:
		unreachable()
	}
}

DefaultVoidType := TypeVoid{}
DefaultTypeType := TypeType{}
DefaultIntType := TypeInt {
	size   = 8,
	signed = true,
}
DefaultS8Type := TypeInt {
	size   = 1,
	signed = true,
}
DefaultS16Type := TypeInt {
	size   = 2,
	signed = true,
}
DefaultS32Type := TypeInt {
	size   = 4,
	signed = true,
}
DefaultS64Type := TypeInt {
	size   = 8,
	signed = true,
}
DefaultUIntType := TypeInt {
	size   = 8,
	signed = false,
}
DefaultU8Type := TypeInt {
	size   = 1,
	signed = false,
}
DefaultU16Type := TypeInt {
	size   = 2,
	signed = false,
}
DefaultU32Type := TypeInt {
	size   = 4,
	signed = false,
}
DefaultU64Type := TypeInt {
	size   = 8,
	signed = false,
}
DefaultBoolType := TypeBool{}
DefaultPointerTypes := make(map[Type]TypePointer)
DefaultProcedureTypes := make([dynamic]^TypeProcedure)
DefaultArrayTypes := make(map[Type]map[uint]TypeArray)

GetPointerType :: proc(pointer_to: Type) -> Type {
	if type, ok := &DefaultPointerTypes[pointer_to]; ok {
		return type
	}
	DefaultPointerTypes[pointer_to] = TypePointer {
		pointer_to = pointer_to,
	}
	return &DefaultPointerTypes[pointer_to]
}

GetProcedureType :: proc(parameter_types: []Type, return_type: Type) -> Type {
	search_loop: for procedure_type in DefaultProcedureTypes {
		if procedure_type.return_type != return_type {
			continue search_loop
		}
		if len(procedure_type.parameter_types) != len(parameter_types) {
			continue search_loop
		}
		for parameter_type, i in parameter_types {
			if procedure_type.parameter_types[i] != parameter_type {
				continue search_loop
			}
		}
		return procedure_type
	}

	procedure_type := new(TypeProcedure)
	procedure_type.parameter_types = slice.clone(parameter_types)
	procedure_type.return_type = return_type
	append(&DefaultProcedureTypes, procedure_type)
	return procedure_type
}

GetArrayType :: proc(inner_type: Type, length: uint) -> Type {
	if array, ok := &DefaultArrayTypes[inner_type]; ok {
		if type, ok := &array[length]; ok {
			return type
		}
	}
	array := &DefaultArrayTypes[inner_type]
	array[length] = TypeArray {
		inner_type = inner_type,
	}
	return &DefaultArrayTypes[inner_type][length]
}
