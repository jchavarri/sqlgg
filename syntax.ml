(* SQL syntax and RA *)

open Stmt.Raw
open Operators

let resolve columns tables =
  let all = tables >> List.map snd >> List.flatten in
  let scheme name = name >> Tables.get_from tables >> snd in
  let resolve1 = function
    | All -> all
    | AllOf t -> scheme t
    | OneOf (col,t) -> [ RA.Scheme.find (scheme t) col ]
    | One col -> [ RA.Scheme.find all col ]
  in
  columns >> List.map resolve1 >> List.flatten
