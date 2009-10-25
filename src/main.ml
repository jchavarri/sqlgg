(**
  Main
*)

open Printf
open Prelude
open ListMore
open ExtLib

module L = List
module S = String

let repeat f x k =
  let rec loop () =
    match f x with
    | Some z -> k z
    | None -> ()
  in
  loop ()

let parse_one_exn (sql,props) =
    if Config.debug1 () then  prerr_endline sql;
    let (s,p,k) = Parser.parse_stmt sql in
    (* fill VALUES *)
    let (sql,p) = match k with
    | Stmt.Insert (Some s,_) ->
      let module B = Buffer in
      let b = B.create 100 in
      B.add_string b sql;
      B.add_string b " (";
      let params = ref [] in
      s >> List.iter (fun attr ->
        if !params <> [] then B.add_string b ",";
        let name = "@" ^ attr.RA.name in
        let param = ((Some attr.RA.name,(B.length b,B.length b + String.length name)),attr.RA.domain) in
        B.add_string b name;
        params := param :: !params
      );
      B.add_string b ")";
      (B.contents b, p @ (List.rev !params))
    | _ -> (sql,p)
    in
    {Stmt.schema=s; params=p; kind=k; props=Props.set props "sql" sql}

let parse_one x =
  try
    Some (parse_one_exn x)
  with
  | Parser_utils.Error (exn,(line,cnum,tok,tail)) ->
    begin
     let extra = Printexc.to_string exn in
     let sql = fst x in
     Error.log "==> %s" sql;
     if cnum = String.length sql && tok = "" then
       Error.log "Exception %s" extra
     else
       Error.log "Exception %s in %u:%u at \"%s%s\"" extra line cnum tok (String.slice ~last:32 tail);
     None
    end

let parse_one (sql,props as x) =
  match Props.get props "noparse" with
  | Some _ -> Some { Stmt.schema=[]; params=[]; kind=Stmt.Other; props=Props.set props "sql" sql }
  | None -> parse_one x

let get_statements ch =
  let lexbuf = Lexing.from_channel ch in
  let f () = try Sql_lexer.ruleStatement Props.empty lexbuf with _ -> Error.log "lexer failed"; None in
  let rec next () =
    match f () with
    | None -> raise Enum.No_more_elements
    | Some sql ->
      begin match parse_one sql with
      | None -> next ()
      | Some stmt ->
          if not (RA.Schema.is_unique stmt.Stmt.schema) then
            Error.log "Error: this SQL statement will produce rowset with duplicate column names:\n%s\n" (fst sql);
          stmt
      end
  in
  Enum.from next

let with_channel filename f =
  match catch open_in filename with
  | None -> Error.log "cannot open file : %s" filename; f None
  | Some ch -> Std.finally (fun () -> close_in_noerr ch) f (Some ch)

