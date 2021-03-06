package zircon

import "core:fmt"
import "core:slice"
import "core:strings"

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
	array: ^map[uint]TypeArray
	if a, ok := &DefaultArrayTypes[inner_type]; ok {
		array = a
	} else {
		DefaultArrayTypes[inner_type] = {}
		array = &DefaultArrayTypes[inner_type]
	}
	array[length] = TypeArray {
		inner_type = inner_type,
		length     = length,
	}
	return &DefaultArrayTypes[inner_type][length]
}

Type_ToString :: proc(type: Type, allocator := context.allocator) -> string {
	context.allocator = allocator
	switch type in type {
	case ^TypeVoid:
		if type == &DefaultVoidType {
			return fmt.aprintf("void")
		} else {
			return fmt.aprintf("distinct void")
		}
	case ^TypeType:
		if type == &DefaultTypeType {
			return fmt.aprintf("type")
		} else {
			return fmt.aprintf("distinct type")
		}
	case ^TypeInt:
		switch type {
		case &DefaultIntType:
			return fmt.aprintf("int")
		case &DefaultS8Type:
			return fmt.aprintf("s8")
		case &DefaultS16Type:
			return fmt.aprintf("s16")
		case &DefaultS32Type:
			return fmt.aprintf("s32")
		case &DefaultS64Type:
			return fmt.aprintf("s64")
		case &DefaultUIntType:
			return fmt.aprintf("uint")
		case &DefaultU8Type:
			return fmt.aprintf("u8")
		case &DefaultU16Type:
			return fmt.aprintf("u16")
		case &DefaultU32Type:
			return fmt.aprintf("u32")
		case &DefaultU64Type:
			return fmt.aprintf("u64")
		case:
			return fmt.aprintf("distinct %s%d", type.signed ? "s" : "u", type.size * 8)
		}
	case ^TypeBool:
		if type == &DefaultBoolType {
			return fmt.aprintf("bool")
		} else {
			return fmt.aprintf("distinct bool")
		}
	case ^TypePointer:
		return fmt.aprintf("*%s", Type_ToString(type.pointer_to, context.temp_allocator))
	case ^TypeProcedure:
		builder := strings.make_builder()
		strings.write_string(&builder, "proc(")
		for parameter, i in type.parameter_types {
			if i > 0 {
				strings.write_string(&builder, ", ")
			}
			strings.write_string(&builder, "_: ")
			strings.write_string(&builder, Type_ToString(parameter, context.temp_allocator))
		}
		strings.write_string(&builder, ") -> ")
		strings.write_string(&builder, Type_ToString(type.return_type, context.temp_allocator))
		return strings.to_string(builder)
	case ^TypeArray:
		return fmt.aprintf(
			"[%d]%s",
			type.length,
			Type_ToString(type.inner_type),
			context.temp_allocator,
		)
	case:
		unreachable()
	}
}

Type_GetSize :: proc(type: Type) -> uint {
	switch type in type {
	case ^TypeVoid:
		return 0
	case ^TypeType:
		return 8
	case ^TypeInt:
		return type.size
	case ^TypeBool:
		return 1
	case ^TypePointer:
		return 8
	case ^TypeProcedure:
		return 8
	case ^TypeArray:
		return Type_GetSize(type.inner_type) * type.length
	case:
		unreachable()
	}
}
