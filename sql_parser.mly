/* 
  $Id$

  Simple SQL parser
  TODO: simplify, it captures many unnecessary details
*/


%{
  open Printf
  open Sql
  open ListMore
  open Stmt.Raw
  open Operators

(*  module Raw = Stmt.Raw*)
%}

%token <int> INTEGER
%token <string> IDENT COMMENT
%token <Stmt.Raw.parameter> PARAM
%token LPAREN RPAREN COMMA EOF DOT
%token IGNORE REPLACE ABORT FAIL ROLLBACK
%token SELECT INSERT OR INTO REPLACE CREATE_TABLE UPDATE TABLE VALUES WHERE FROM ASTERISK DISTINCT ALL 
       LIMIT ORDER_BY DESC ASC EQUAL DELETE_FROM DEFAULT OFFSET SET JOIN LIKE_OP
       EXCL TILDE NOT FUNCTION TEST_NULL BETWEEN AND ESCAPE
%token NOT_NULL UNIQUE PRIMARY_KEY AUTOINCREMENT ON_CONFLICT
%token PLUS MINUS DIVIDE PERCENT
%token T_INTEGER T_BLOB T_TEXT

%start input
%type <unit> input

%%

input: statement EOF { $1 } ;

/*
input: collection EOF { List.rev $1 } ;

collection: statement { [$1] }
          | collection statement { $2::$1 } ;
*/

statement: CREATE_TABLE IDENT LPAREN column_defs RPAREN
              { Tables.add ($2,List.rev $4) }
         | select_core maybe_order maybe_limit
              { RA.Scheme.print $1 }
         /*| insert_cmd IDENT LPAREN columns RPAREN VALUES
              { Raw.Insert (Raw.Cols (List.rev $4)), $2, [] }
         | insert_cmd IDENT VALUES
              { Raw.Insert Raw.All, $2, [] }
         | UPDATE IDENT SET set_columns maybe_where
              { Raw.Update $4, $2, List.filter_valid [$5] }
         | DELETE_FROM IDENT maybe_where
              { Raw.Delete, $2, List.filter_valid [$3] }*/ ;

select_core: SELECT select_type results FROM table_list maybe_where 
              { Syntax.resolve $3 $5 } ;

table_list: table { [$1] }
          | table_list join_op table join_args { $3::$1 } ;

table: IDENT { Tables.get $1 } ;
join_op: COMMA { }
       | JOIN { } ;
join_args: { } ;

insert_cmd: INSERT OR conflict_algo INTO {}
          | INSERT INTO {}
          | REPLACE INTO {} ;

update_cmd: UPDATE {}
          | UPDATE OR conflict_algo {} ;

select_type: /* */  { }
           | DISTINCT { }
           | ALL { } ;

maybe_limit: LIMIT PARAM { [Some ("limit",Type.Int)] }
           | LIMIT INTEGER { [None] }
           | LIMIT PARAM COMMA PARAM { [Some ("offset",Type.Int); Some ("limit",Type.Int)] }
           | LIMIT INTEGER COMMA PARAM { [Some ("limit",Type.Int)] }
           | LIMIT PARAM COMMA INTEGER { [Some ("offset",Type.Int)] }
           | LIMIT INTEGER COMMA INTEGER { [None] }
           | LIMIT PARAM OFFSET PARAM { [Some ("limit",Type.Int); Some ("offset",Type.Int)] }
           | LIMIT INTEGER OFFSET PARAM { [Some ("offset",Type.Int)] }
           | LIMIT PARAM OFFSET INTEGER { [Some ("limit",Type.Int)] }
           | LIMIT INTEGER OFFSET INTEGER { [None] }
           | /* */ { [None] } ;

maybe_order: ORDER_BY IDENT order_type { }
           | /* */ { } ;

order_type: DESC { }
          | ASC { }
          | /* */ { } ;

maybe_where: WHERE IDENT EQUAL PARAM { Some ($2,Type.Int) }
           | /* */  { None } ;

results: columns { List.rev $1 } ;

columns: column1 { [$1] }
       | columns COMMA column1 { $3::$1 } ;

column1: IDENT { One $1 }
       | IDENT DOT IDENT { OneOf ($3,$1) }
       | IDENT DOT ASTERISK { AllOf $1 }
       | ASTERISK { All } ;
/*        | IDENT LPAREN IDENT RPAREN { $1 } ; */

column_defs: column_def1 { [$1] }
           | column_defs COMMA column_def1 { $3::$1 } ;

column_def1: IDENT sql_type { RA.Scheme.attr $1 $2 }
           | IDENT sql_type column_def_extra { RA.Scheme.attr $1 $2 } ;

column_def_extra: column_def_extra1 { [$1] }
                | column_def_extra column_def_extra1 { $2::$1 } ;

column_def_extra1: PRIMARY_KEY { Some Constraint.PrimaryKey }
                 | NOT_NULL { Some Constraint.NotNull }
                 | UNIQUE { Some Constraint.Unique }
                 | AUTOINCREMENT { Some Constraint.Autoincrement }
                 | ON_CONFLICT conflict_algo { Some (Constraint.OnConflict $2) } ;
                 | DEFAULT INTEGER { None }
/*
set_columns: set_columns1 { Raw.Cols (List.filter_valid (List.rev $1)) } ;

set_columns1: set_column { [$1] }
           | set_columns1 COMMA set_column { $3::$1 } ;

set_column: IDENT EQUAL expr { match $3 with | 1 -> Some $1 | x -> assert (0=x); None } ;
*/

expr:
      expr binary_op expr { $1 @ $3 }
    | expr LIKE_OP expr maybe_escape { $1 @ $3 @ $4 }
    | unary_op expr { $2 }
    | LPAREN expr RPAREN { $2 }
    | IDENT { [] } 
    | IDENT DOT IDENT { [] }
    | IDENT DOT IDENT DOT IDENT { [] }
    | INTEGER { [] }
    | PARAM { [$1] }
    | FUNCTION LPAREN func_params RPAREN { $3 } 
    | expr TEST_NULL { $1 }
    | expr BETWEEN expr AND expr { $1 @ $3 @ $5 }
;
expr_list_rev: expr { [$1] }
             | expr_list_rev COMMA expr { $3::$1 } ;
expr_list: expr_list_rev { $1 >> List.rev >> List.flatten } ;
func_params: expr_list { $1 }
           | ASTERISK { [] } ;
maybe_escape: { [] } 
            | ESCAPE expr { $2 } ; 
binary_op: PLUS { }
         | MINUS { }
         | ASTERISK { }
         | DIVIDE { } ;
unary_op: EXCL { }
        | PLUS { }
        | MINUS { }
        | TILDE { }
        | NOT { } ;

conflict_algo: IGNORE { Constraint.Ignore } 
             | REPLACE { Constraint.Replace }
             | ABORT { Constraint.Abort }
             | FAIL { Constraint.Fail } 
             | ROLLBACK { Constraint.Rollback } ;

sql_type: T_INTEGER  { Type.Int }
        | T_BLOB { Type.Blob }
        | T_TEXT { Type.Text } ;

%%

