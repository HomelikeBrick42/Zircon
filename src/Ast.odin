package zircon

Ast :: union #shared_nil {
	^AstFile,
	AstStatement,
}

AstStatement :: union #shared_nil {
	^AstDeclaration,
	^AstAssignment,
	AstExpression,
}

AstExpression :: union #shared_nil {
	^AstUnary,
	^AstBinary,
	^AstCall,
	^AstInteger,
}

AstFile :: struct {
	filepath:          string,
	statements:        [dynamic]AstStatement,
	end_of_file_token: Token,
}

AstDeclaration :: struct {
	name_token:   Token,
	colon_token:  Token,
	// TODO: add type
	equals_token: Token,
	value:        AstExpression,
}

AstAssignment :: struct {
	operand:      AstExpression,
	equals_token: Token,
	value:        AstExpression,
}

AstUnary :: struct {
	operator_token: Token,
	operand:        AstExpression,
}

AstBinary :: struct {
	left:           AstExpression,
	operator_token: Token,
	right:          AstExpression,
}

AstCall :: struct {
	operand:                 AstExpression,
	open_parenthesis_token:  Token,
	arguments:               [dynamic]AstExpression,
	close_parenthesis_token: Token,
}

AstInteger :: struct {
	integer_token: Token,
}
