(**************************************************************************)
(*                                                                        *)
(*  Copyright (c) 2021 OCamlPro SAS                                       *)
(*                                                                        *)
(*  All rights reserved.                                                  *)
(*  This file is distributed under the terms of the GNU Lesser General    *)
(*  Public License version 2.1, with the special exception on linking     *)
(*  described in the LICENSE.md file in the root directory.               *)
(*                                                                        *)
(*                                                                        *)
(**************************************************************************)

open Solidity_common
open Solidity_ast
open Solidity_checker_TYPES
open Solidity_exceptions

let error = type_error

open Solidity_primitives.UTILS

let rec list_sub n list =
  if n = 0 then [] else
    match list with
    | [] -> failwith "List.sub"
    | x :: tail ->
        x :: ( list_sub (n-1) tail )

let make_surcharged_fun ~nreq pos expected_args opt result =
  match opt.call_args with
  | None -> assert false (* TODO *)
  | Some (AList list) ->
      let len = List.length list in
      if len <= nreq then
        error pos "Not enough arguments"
      else
      if len > List.length expected_args then
        error pos "Too many arguments"
      else
        Some
          ( make_fun (List.map (fun (_, type_, _optiona) ->
                type_) ( list_sub len expected_args )) result
              MNonPayable )
  | Some (ANamed list) ->
      let expected_args =
        List.mapi (fun i (name, type_, optional) ->
            name, (i, type_, optional, ref false) )
          expected_args
      in
      let nargs = List.length list in
      let map = EzCompat.StringMap.of_list expected_args in
      List.iter (fun (name, _) ->
          match EzCompat.StringMap.find (Ident.to_string name) map with
          | exception Not_found ->
              error pos "Unknown field %S" (Ident.to_string name)
          | (_pos, _expected_type, _optional, found) ->
              found := true
        ) list ;
      let rec iter args n =
        if n = 0 then
          []
        else
          match args with
          | [] -> assert false
          | ( name, (_i, type_, optional, found) ) :: args ->
              if !found then
                ( type_, Some ( Ident.of_string name ) ) ::
                iter args (n-1)
              else
                if optional then
                  iter args n
                else
                  error pos "Missing argument %S" name
      in
      let expected_args = iter expected_args nargs in
      Some ( primitive_fun_named expected_args result MNonPayable )


let register_primitives () =

  (* Error handling *)

  register 1
    { prim_name = "assert";
      prim_kind = PrimFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | None ->
           Some (make_fun [TBool] [] MPure)
       | _ -> None);

  register 2
    { prim_name = "require";
      prim_kind = PrimFunction }
    (fun _pos opt t_opt ->
       match t_opt, opt.call_args with
       | None, Some ((AList [_] | ANamed [_])) ->
           Some (make_fun [TBool] [] MPure)
       | None, Some ((AList [_;_] | ANamed [_;_])) ->
           if !for_freeton then
             Some (make_fun [TBool; TUint 256] [] MPure)
           else
             Some (make_fun [TBool; TString LMemory] [] MPure)
       | _ -> None);

  register 3
    { prim_name = "revert";
      prim_kind = PrimFunction }
    (fun _pos opt t_opt ->
       match t_opt, opt.call_args with
       | None, Some ((AList [] | ANamed [])) ->
           Some (make_fun [] [] MPure)
       | None, Some ((AList [_] | ANamed [_])) ->
           Some (make_fun [TString LMemory] [] MPure)
       | _ -> None);

  (* Block/transaction properties *)

  register 4
    { prim_name = "blockhash";
      prim_kind = PrimFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | None ->
           Some (make_fun [TUint 256] [TFixBytes 32] MView)
       | _ -> None);

  register 5
    { prim_name = "gasleft";
      prim_kind = PrimFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | None ->
           Some (make_fun [] [TUint 256] MView)
       | _ -> None);

  register 6
    { prim_name = "block";
      prim_kind = PrimVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | None -> Some (make_var (TMagic (TBlock)))
       | _ -> None);

  register 7
    { prim_name = "coinbase";
      prim_kind = PrimMemberVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMagic (TBlock)) -> Some (make_var (TAddress (true)))
       | _ -> None);

  register 8
    { prim_name = "difficulty";
      prim_kind = PrimMemberVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMagic (TBlock)) -> Some (make_var (TUint 256))
       | _ -> None);

  register 9
    { prim_name = "gaslimit";
      prim_kind = PrimMemberVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMagic (TBlock)) -> Some (make_var (TUint 256))
       | _ -> None);

  register 10
    { prim_name = "number";
      prim_kind = PrimMemberVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMagic (TBlock)) -> Some (make_var (TUint 256))
       | _ -> None);

  register 11
    { prim_name = "timestamp";
      prim_kind = PrimMemberVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMagic (TBlock)) -> Some (make_var (TUint 256))
       | _ -> None);

  register 12
    { prim_name = "msg";
      prim_kind = PrimVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | None -> Some (make_var (TMagic (TMsg)))
       | _ -> None);

  register 13
    { prim_name = "data";
      prim_kind = PrimMemberVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMagic (TMsg)) -> Some (make_var (TBytes (LCalldata)))
       | _ -> None);

  register 14
    { prim_name = "sender";
      prim_kind = PrimMemberVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMagic (TMsg)) -> Some (make_var (TAddress (true)))
       | _ -> None);

  register 15
    { prim_name = "sig";
      prim_kind = PrimMemberVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMagic (TMsg)) -> Some (make_var (TFixBytes 4))
       | _ -> None);

  register 16
    { prim_name = "value";
      prim_kind = PrimMemberVariable }
    (fun pos _opt t_opt ->
       match t_opt with
       | Some (TMagic (TMsg)) when !for_freeton ->
           Some (make_var (TUint 128))
       | Some (TMagic (TMsg)) ->
           Some (make_var (TUint 256))
       | Some (TFunction (fd, _fo)) when is_external fd.function_visibility ->
           error pos "Using \".value(...)\" is deprecated. \
                      Use \"{value: ...}\" instead"
       | Some (TAddress _) when !for_freeton ->
           Some (make_var (TUint 256))
       | _ -> None);

  register 17
    { prim_name = "tx";
      prim_kind = PrimVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | None -> Some (make_var (TMagic (TTx)))
       | _ -> None);

  register 18
    { prim_name = "gasprice";
      prim_kind = PrimMemberVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMagic (TTx)) -> Some (make_var (TUint 256))
       | _ -> None);

  register 19
    { prim_name = "origin";
      prim_kind = PrimMemberVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMagic (TTx)) -> Some (make_var (TAddress (true)))
       | _ -> None);

  (* ABI encoding/decoding *)

  register 20
    { prim_name = "abi";
      prim_kind = PrimVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | None -> Some (make_var (TMagic (TAbi)))
       | _ -> None);

  register 21
    { prim_name = "decode";
      prim_kind = PrimMemberFunction }
    (fun pos opt t_opt ->
       match t_opt with
       | Some (TMagic (TAbi)) ->
           let atl, rtl =
             match make_prim_args pos opt with
             | None -> [], []
             | Some ([TBytes (LMemory|LCalldata); rt] as atl) ->
                 let rtl =
                   match rt with
                   | TTuple (rtl) -> rtl
                   | _ -> [Some (rt)]
                 in
                 let rtl =
                   List.map (function
                       | Some (TType (t)) ->
                           t
                       | Some (_t) ->
                           error pos "The second argument to abi.decode \
                                      has to be a tuple of types"
                       | None ->
                           error pos "Tuple component can not be empty"
                     ) rtl
                 in
                 atl, rtl
             | Some ([t1; _]) ->
                 error pos "The first argument to abi.decode must be \
                            implicitly convertible to bytes memory \
                            or bytes calldata, but is of type %s"
                   (Solidity_type_printer.string_of_type t1)
             | Some (atl) ->
                 error pos "This function takes two arguments, \
                            but %d were provided" (List.length atl)
           in
           Some (make_fun atl rtl MPure)

       | Some ( TAbstract TvmSlice ) when !for_freeton ->
           begin
             match opt.call_args with
             | Some ( AList list ) ->
                 let res =
                   List.mapi (fun i arg ->
                       match arg with
                       | TType type_ -> type_
                       | _ ->
                           error pos
                             "wrong argument %d, should be a type" i
                     )
                     list
                 in

                 Some (make_fun list res MNonPayable)
             | _ ->
                 Printf.eprintf "wrong args (2) \n%!";
                 None
           end
       | _ -> None);

  register 22
    { prim_name = "encode";
      prim_kind = PrimMemberFunction }
    (fun pos opt t_opt ->
       match t_opt with
       | Some (TMagic (TAbi)) ->
           let atl = preprocess_arg_0 pos (make_prim_args pos opt) in
           Some (make_fun atl [TBytes LMemory] MPure)
       | _ -> None);

  register 23
    { prim_name = "encodePacked";
      prim_kind = PrimMemberFunction }
    (fun pos opt t_opt ->
       match t_opt with
       | Some (TMagic (TAbi)) ->
           let atl = preprocess_arg_0 pos (make_prim_args pos opt) in
           Some (make_fun atl [TBytes LMemory] MPure)
       | _ -> None);

  register 24
    { prim_name = "encodeWithSelector";
      prim_kind = PrimMemberFunction }
    (fun pos opt t_opt ->
       match t_opt with
       | Some (TMagic (TAbi)) ->
           let atl = preprocess_arg_1 pos (TFixBytes 4)
               (make_prim_args pos opt) in
           Some (make_fun atl [TBytes LMemory] MPure)
       | _ -> None);

  register 25
    { prim_name = "encodeWithSignature";
      prim_kind = PrimMemberFunction }
    (fun pos opt t_opt ->
       match t_opt with
       | Some (TMagic (TAbi)) ->
           let atl = preprocess_arg_1 pos (TString (LMemory))
               (make_prim_args pos opt) in
           Some (make_fun atl [TBytes LMemory] MPure)
       | _ -> None);


  (* Mathematical/cryptographic functions *)

  register 26
    { prim_name = "addmod";
      prim_kind = PrimFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | None ->
           Some (make_fun [TUint 256; TUint 256; TUint 256] [TUint 256] MPure)
       | _ -> None);

  register 27
    { prim_name = "mulmod";
      prim_kind = PrimFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | None ->
           Some (make_fun [TUint 256; TUint 256; TUint 256] [TUint 256] MPure)
       | _ -> None);

  register 28
    { prim_name = "keccak256";
      prim_kind = PrimFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | None ->
           Some (make_fun [TBytes LMemory] [TFixBytes 32] MPure)
       | _ -> None);

  register 29
    { prim_name = "sha256";
      prim_kind = PrimFunction }
    (fun _pos opt t_opt ->
       match t_opt with
       | None ->
           begin
             match opt.call_args with
             | Some (AList [ TAbstract TvmSlice ]) ->
                 Some (make_fun [TAbstract TvmSlice] [TUint 256] MPure)
             | _ ->
                 Some (make_fun [TBytes LMemory] [TFixBytes 32] MPure)
           end
       | _ -> None);

  register 30
    { prim_name = "ripemd160";
      prim_kind = PrimFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | None ->
           Some (make_fun [TBytes LMemory] [TFixBytes 20] MPure)
       | _ -> None);

  register 31
    { prim_name = "ecrecover";
      prim_kind = PrimFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | None ->
           Some (make_fun
                   [TFixBytes 32; TUint 8; TFixBytes 32; TFixBytes 32]
                   [TAddress (false)] MPure)
       | _ -> None);

  (* Contract related *)

  register 32
    { prim_name = "this";
      prim_kind = PrimVariable }
    (fun _pos opt t_opt ->
       match t_opt, opt.current_contract with
       | None, Some (c) ->
           Some (make_var (TContract (
               c.contract_abs_name, c, false (* super *))))
       | _ ->
           None);

  register 33
    { prim_name = "super";
      prim_kind = PrimVariable }
    (fun _pos opt t_opt ->
       match t_opt, opt.current_contract with
       | None, Some (c) ->
           Some (make_var (TContract (
               c.contract_abs_name, c, true (* super *))))
       | _ ->
           None);

  register 34
    { prim_name = "selfdestruct";
      prim_kind = PrimFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | None ->
           Some (make_fun [TAddress (true)] [] MNonPayable)
       | _ -> None);

  (* Members of address type *)

  register 35
    { prim_name = "balance";
      prim_kind = PrimMemberVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TAddress (_)) when !for_freeton ->
           Some (make_var (TUint 128))
       | Some (TAddress (_)) ->
           Some (make_var (TUint 256))
       | _ -> None);

  register 36
    { prim_name = "transfer";
      prim_kind = PrimMemberFunction }
    (fun pos opt t_opt ->
       match t_opt with
       | Some (TAddress _) when !for_freeton ->
           make_surcharged_fun ~nreq:1 pos
             [ "value", TUint 128, false ;
               "bounce", TBool, true ;
               "flag", TUint 16, true ;
               "body", TAbstract TvmCell, true ;
               (* not yet: "currencies", ExtraCurrencyCollection *)
             ] opt []
       | Some (TAddress (true)) ->
           Some (make_fun [TUint 256] [] MNonPayable)
       | Some (TAddress (false)) ->
           error pos "\"send\" and \"transfer\" are only available \
                      for objects of type \"address payable\", \
                      not \"address\""
       | _ -> None);

  register 37
    { prim_name = "send";
      prim_kind = PrimMemberFunction }
    (fun pos _opt t_opt ->
       match t_opt with
       | Some (TAddress (true)) ->
           Some (make_fun [TUint 256] [TBool] MNonPayable)
       | Some (TAddress (false)) when !for_freeton ->
           Some (make_fun [TUint 256] [TBool] MNonPayable)
       | Some (TAddress (false)) ->
           error pos "\"send\" and \"transfer\" are only available \
                      for objects of type \"address payable\", \
                      not \"address\""
       | _ -> None);

  register 38
    { prim_name = "call";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TAddress (_)) ->
           Some (make_fun [TBytes (LMemory)] [TBool; TBytes (LMemory)] MPayable)
       | _ -> None);

  register 39
    { prim_name = "delegatecall";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TAddress (_)) ->
           Some (make_fun
                   [TBytes (LMemory)] [TBool; TBytes (LMemory)] MNonPayable)
       | _ -> None);

  register 40
    { prim_name = "staticcall";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TAddress (_)) ->
           Some (make_fun [TBytes (LMemory)] [TBool; TBytes (LMemory)] MView)
       | _ -> None);

  (* Type information (members of type) *)

  register 41
    { prim_name = "type";
      prim_kind = PrimFunction }
    (fun pos opt t_opt ->
       match t_opt, make_prim_args pos opt with
       | None, None ->
           Some (make_fun [] [] MPure)
       | None, Some ([TType ((TInt _ | TUint _ | TContract _) as t)]) ->
           Some (make_fun [TType (t)] [TMagic (TMetaType (t))] MPure)
       | None, Some (_) ->
           Some (make_fun [TType (TTuple [])] [] MPure)
       | _ -> None);

  register 42
    { prim_name = "name";
      prim_kind = PrimMemberVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMagic (TMetaType (TContract (_, _, _)))) ->
           Some (make_var (TString (LMemory)))
       | _ -> None);

  register 43
    { prim_name = "creationCode";
      prim_kind = PrimMemberVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMagic (TMetaType (TContract (_, _, _)))) ->
           Some (make_var (TBytes (LMemory)))
       | _ -> None);

  register 44
    { prim_name = "runtimeCode";
      prim_kind = PrimMemberVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMagic (TMetaType (TContract (_, _, _)))) ->
           Some (make_var (TBytes (LMemory)))
       | _ -> None);

  register 45
    { prim_name = "interfaceId";
      prim_kind = PrimMemberVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMagic (TMetaType (TContract (_, _, _)))) ->
           Some (make_var (TFixBytes (4)))
       | _ -> None);

  let infer_int_type pos list =
    let signed = List.exists (function | TInt _ -> true
                                       | TRationalConst (q, _ ) ->
                                           ExtQ.is_neg q
                                       | _ -> false) list
    in
    let length = ref 0 in
    let bad = ref false in
    List.iter (function
        | TUint n ->
            length := max !length
                ( if signed then n+1 else n)
        | TInt n -> length := max n !length
        | TRationalConst (q, _) ->
            let nbits = Z.numbits (Q.num q) in
            length := max !length
                ( if signed then
                    if ExtQ.is_neg q then
                      nbits
                    else
                      1 + nbits
                  else
                    nbits)
        | t ->
            error pos "non integer type %s\n%!"
              (Solidity_type_printer.string_of_type t);
      ) list ;
    if !bad then
      None
    else
      let t =
        if signed then
          TInt !length
        else
          TUint !length
      in
      Some t
  in

  register 46
    { prim_name = "min";
      prim_kind = PrimMemberVariable }
    (fun pos opt t_opt ->
       match t_opt with
       | Some (TMapping ( from_, to_, _loc )) when !for_freeton ->
           Some (make_fun [ ]
                   [ TOptional (TTuple [ Some from_ ;
                                         Some to_ ] ) ] MNonPayable)
       | Some (TMagic (TMetaType (TInt (_) | TUint (_) as t))) ->
           Some (make_var (t))
       | Some (TMagic TMath) when !for_freeton ->
           begin
             match opt.call_args with
             | Some ( AList [] ) -> None
             | Some ( AList list ) ->
                 begin
                   match infer_int_type pos list with
                   | None -> None
                   | Some t ->
                       Some (make_fun
                               ( List.map (fun _ -> t) list )
                               [ t ] MNonPayable )
                 end
             | _ -> None
           end
       | _ -> None);


  register 47
    { prim_name = "max";
      prim_kind = PrimMemberVariable }
    (fun pos opt t_opt ->
       match t_opt with
       | Some (TMagic (TMetaType (TInt (_) | TUint (_) as t))) ->
           Some (make_var (t))
       | Some (TMagic TMath) when !for_freeton ->
           begin
             match opt.call_args with
             | Some ( AList [] ) -> None
             | Some ( AList list ) ->
                 begin
                   match infer_int_type pos list with
                   | None -> None
                   | Some t ->
                       Some (make_fun
                               ( List.map (fun _ -> t) list )
                               [ t ] MNonPayable )
                 end
             | _ -> None
           end
       | _ -> None);

  (* Members of array type *)

  register 48
    { prim_name = "length";
      prim_kind = PrimMemberVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TArray (_) | TBytes (_)) ->
           Some (make_var (TUint 256))
       | Some (TFixBytes (_)) ->
           Some (make_var (TUint 8))
       | _ -> None);

  register 49
    { prim_name = "push";
      prim_kind = PrimMemberFunction }
    (fun _pos opt t_opt ->
       match t_opt, opt.call_args with
       | Some (TArray (t, None, (LStorage _))),
         (None | Some (AList [] | ANamed [])) ->
           (* Note: since push only works on storage arrays,
              the argument has a location of storage ref *)
           let t =
             Solidity_type.change_type_location (LStorage false) t in
           Some (make_fun ~returns_lvalue:true [] [t] MNonPayable)
       | Some (TArray (t, None, (LStorage _))),
         Some (_) ->
           (* Note: since push only works on storage arrays,
              the argument has a location of storage ref *)
           let t =
             Solidity_type.change_type_location (LStorage false) t in
           Some (make_fun [t] [] MNonPayable)
       | Some (TArray (t, _, _)), _ when !for_freeton ->
           Some (make_fun [t] [] MNonPayable)
       | Some (TBytes (LStorage _)),
         (None | Some (AList [] | ANamed [])) ->
           Some (make_fun ~returns_lvalue:true [] [TFixBytes (1)] MNonPayable)
       | Some (TBytes (LStorage _)),
         Some (_) ->
           Some (make_fun [TFixBytes (1)] [] MNonPayable)
       | _ -> None);

  register 50
    { prim_name = "pop";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TArray (_, None, (LStorage _)) | TBytes (LStorage _)) ->
           Some (make_fun [] [] MNonPayable)
       | _ -> None);

  (* Members of function type *)

  register 51
    { prim_name = "address";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TFunction (fd, _fo)) when is_external fd.function_visibility ->
           Some (make_var (TAddress (false)))
       | _ -> None);

  register 52
    { prim_name = "selector";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TFunction (fd, _fo)) when is_external fd.function_visibility ->
           Some (make_var (TFixBytes (4)))
       | _ -> None);

  register 53
    { prim_name = "gas";
      prim_kind = PrimMemberFunction }
    (fun pos _opt t_opt ->
       match t_opt with
       | Some (TFunction (fd, _fo)) when is_external fd.function_visibility ->
           error pos "Using \".gas(...)\" is deprecated. \
                      Use \"{gas: ...}\" instead"
       | _ -> None);

  (* TODO: allow functions with constant arity ? *)
  register 54
    { prim_name = "store";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TAbstract TvmBuilder) when !for_freeton ->
           Some (make_fun [TDots] [] MNonPayable)
       | _ -> None);

  register 55
    { prim_name = "tvm";
      prim_kind = PrimVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | None when !for_freeton -> Some (make_var (TMagic (TTvm)))
       | _ -> None);

  register 56
    { prim_name = "toCell";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TAbstract TvmBuilder) when !for_freeton ->
           Some (make_fun [] [TAbstract TvmCell] MNonPayable)
       | _ -> None);

  register 57
    { prim_name = "hash";
      prim_kind = PrimMemberFunction }
    (fun _pos opt t_opt ->
       match t_opt with
       | Some (TMagic TTvm) when !for_freeton ->
           begin
             match opt.call_args with
             | None -> None
             | Some (AList [
                 TAbstract TvmCell
               | TString _
               | TBytes _
               | TAbstract TvmSlice
               ])
               ->
                 Some (make_fun [TAny] [TUint 256] MNonPayable)
             | _ -> None
           end
       | _ -> None);

  register 58
    { prim_name = "now";
      prim_kind = PrimVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | None when !for_freeton ->
           Some (make_var (TUint 64))
       | _ -> None);

  register 59
    { prim_name = "fetch";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMapping ( from_, to_, _loc )) when !for_freeton ->
           Some (make_fun [ from_ ] [ TOptional to_ ] MNonPayable)
       | _ -> None);

  register 60
    { prim_name = "hasValue";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TOptional _) when !for_freeton ->
           Some (make_fun [] [ TBool ] MNonPayable)
       | _ -> None);

  register 61
    { prim_name = "get";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TOptional to_) when !for_freeton ->
           Some (make_fun [] [ to_ ] MNonPayable)
       | _ -> None);

  register 62
    { prim_name = "accept";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMagic TTvm) when !for_freeton ->
           Some (make_fun [] [] MNonPayable)
       | _ -> None);

  register 63
    { prim_name = "pubkey";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMagic ( TTvm | TMsg )) when !for_freeton ->
           Some (make_fun [] [TUint 256] MNonPayable)
       | _ -> None);

  register 64
    { prim_name = "next";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMapping ( from_, to_, _loc )) when !for_freeton ->
           Some (make_fun [ from_ ]
                   [ TOptional (TTuple [ Some from_ ;
                                         Some to_ ] ) ] MNonPayable)
       | _ -> None);

  register 65
    { prim_name = "toSlice";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some ( TString _ ) when !for_freeton ->
           Some (make_fun [] [ TAbstract TvmSlice ] MNonPayable)
       | Some (TAbstract ( TvmBuilder | TvmCell )) when !for_freeton ->
           Some (make_fun [] [TAbstract TvmSlice] MNonPayable)
       | _ -> None);

  register 66
    { prim_name = "functionId";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some ( TMagic TTvm ) when !for_freeton ->
           (* TODO: only allow constructor and functions *)
           Some (make_fun [ TAny ] [ TUint 32 ] MNonPayable)
       | _ -> None);

  register 67
    { prim_name = "exists";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMapping ( from_, _to, _loc )) when !for_freeton ->
           Some (make_fun [ from_ ] [ TBool ] MNonPayable)
       | _ -> None);

  register 68
    { prim_name = "reset";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some ( TOptional _ ) when !for_freeton ->
           Some (make_fun [] [] MNonPayable)
       | _ -> None);

  register 69
    { prim_name = "storeRef";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TAbstract TvmBuilder) when !for_freeton ->
           Some (make_fun [TDots] [] MNonPayable)
       | _ -> None);

  register 70
    { prim_name = "append";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TString loc | TBytes loc) when !for_freeton ->
           Some (make_fun [TString loc] [] MNonPayable)
       | _ -> None);

  register 71
    { prim_name = "vergrth16";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some ( TMagic TTvm ) when !for_freeton ->
           Some (make_fun [ TString LMemory ] [ TBool ] MNonPayable)
       | _ -> None);

  register 72
    { prim_name = "buildStateInit";
      prim_kind = PrimMemberFunction }
    (fun pos opt t_opt ->
       match t_opt with
       | Some ( TMagic TTvm ) when !for_freeton ->
           make_surcharged_fun ~nreq:1 pos
             [
               "code", TAbstract TvmCell, false ;
               "data", TAbstract TvmCell, true ;
               "splitDepth", TUint 8, true ;
               "pubkey", TUint 256, true ;
               "contr", TDots, true ; (* TODO do better *)
               "varInit", TDots, true ; (* TODO do better *)
             ] opt
             [ TAbstract TvmCell ]
       | _ -> None);

  register 73
    { prim_name = "commit";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some ( TMagic TTvm ) when !for_freeton ->
           Some (make_fun [] [] MNonPayable)
       | _ -> None);

  register 74
    { prim_name = "setcode";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some ( TMagic TTvm ) when !for_freeton ->
           Some (make_fun [TAbstract TvmCell] [] MNonPayable)
       | _ -> None);

  register 75
    { prim_name = "setCurrentCode";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some ( TMagic TTvm ) when !for_freeton ->
           Some (make_fun [TAbstract TvmCell] [] MNonPayable)
       | _ -> None);

  register 76
    { prim_name = "resetStorage";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some ( TMagic TTvm ) when !for_freeton ->
           Some (make_fun [] [] MNonPayable)
       | _ -> None);

  register 77
    { prim_name = "makeAddrStd";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some ( TType (TAddress _ ) ) when !for_freeton ->
           Some (make_fun [ TInt 8 ; TUint 256 ] [ TAddress true ] MNonPayable)
       | _ ->
           None);

  register 78
    { prim_name = "loadRef";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TAbstract TvmSlice) when !for_freeton ->
           Some (make_fun [] [TAbstract TvmCell] MNonPayable)
       | _ -> None);

  register 79
    { prim_name = "format";
      prim_kind = PrimFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | None when !for_freeton ->
           Some (make_fun [ TString LMemory ; TDots ] [TString LMemory ] MNonPayable)
       | _ -> None);

  register 80
    { prim_name = "byteLength";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TString _) when !for_freeton ->
           Some (make_fun [] [TUint 256] MNonPayable)
       | _ -> None);

  register 81
    { prim_name = "rawReserve";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMagic TTvm) when !for_freeton ->
           Some (make_fun [ TUint 256; TUint 8] [] MNonPayable)
       | _ -> None);

  register 82
    { prim_name = "math";
      prim_kind = PrimVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | None when !for_freeton -> Some (make_var (TMagic TMath))
       | _ -> None);

  register 83
    { prim_name = "rnd";
      prim_kind = PrimVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | None when !for_freeton -> Some (make_var (TMagic TRnd))
       | _ -> None);

  register 84
    { prim_name = "set";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TOptional to_) when !for_freeton ->
           Some (make_fun [ to_ ] [] MNonPayable)
       | _ -> None);

  register 85
    { prim_name = "wid";
      prim_kind = PrimMemberVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TAddress (_)) when !for_freeton ->
           Some (make_var (TInt 8))
       | _ -> None);

  register 86
    { prim_name = "encodeBody";
      prim_kind = PrimMemberFunction }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMagic TTvm) when !for_freeton ->
           Some (make_fun [ TDots ] [ TAbstract TvmCell ] MNonPayable)
       | _ -> None);

  register 87
    { prim_name = "muldivmod";
      prim_kind = PrimMemberVariable }
    (fun pos opt t_opt ->
       match t_opt with
       | Some (TMagic TMath) ->
           begin
             match opt.call_args with
             | Some ( AList [] ) -> None
             | Some ( AList list ) ->
                 begin
                   match infer_int_type pos list with
                   | None -> None
                   | Some t ->

                       Some (make_fun [ t; t; t] [ t ; t ] MNonPayable )
                 end
             | _ -> None
           end
       | _ -> None);

  register 88
    { prim_name = "deploy";
      prim_kind = PrimMemberVariable }
    (fun _pos _opt t_opt ->
       match t_opt with
       | Some (TMagic TTvm) ->
           Some (make_fun [
               TAbstract TvmCell; (* stateInit *)
               TAbstract TvmCell; (* payload *)
               TUint 128 ;
               TInt 8
             ]
               [ TAddress true ] MNonPayable )
       | _ -> None);

  let muldiv_kind pos opt t_opt =
    match t_opt with
    | Some (TMagic TMath) ->
        begin
          match opt.call_args with
          | Some ( AList [] ) -> None
          | Some ( AList list ) ->
              begin
                match infer_int_type pos list with
                | None -> None
                | Some t ->
                    Some (make_fun [ t; t; t] [ t ] MNonPayable )
              end
          | _ -> None
        end
    | _ -> None
  in
  register 89
    { prim_name = "muldiv";
      prim_kind = PrimMemberVariable } muldiv_kind ;
  register 90
    { prim_name = "muldivr";
      prim_kind = PrimMemberVariable } muldiv_kind ;
  register 91
    { prim_name = "muldivc";
      prim_kind = PrimMemberVariable } muldiv_kind ;

  ()

let handle_exception f x =
  try
    Ok ( f x )
  with
  | (
    Solidity_common.GenericError _
  | Solidity_exceptions.SyntaxError _
  | Solidity_exceptions.TypecheckError _
  )  as exn ->
      Error ( Solidity_exceptions.string_of_exn exn )

let parse_file = Solidity_parser.parse_file ~freeton:true
let typecheck_ast =
  Solidity_typechecker.type_program ~init:register_primitives
let string_of_ast = Solidity_printer.string_of_program ~freeton:true

open Solidity_typechecker

(* TODO: use the 'fields' set of fo to detect re-use *)

let type_options_fun opt env pos is_payable fo opts =
  List.fold_left (fun fo (id, e) ->
      let id = strip id in
      let fo, already_set =
        match Ident.to_string id, fo.kind with
        | "value", KExtContractFun when
            not !for_freeton && not is_payable ->
            error pos "Cannot set option \"value\" \
                       on a non-payable function type"
        | "value", KNewContract when
            not !for_freeton && not is_payable ->
            error pos "Cannot set option \"value\", since the \
                       constructor of contract is non-payable"
        | "value", ( KExtContractFun | KNewContract | KReturn ) ->
            expect_expression_type opt env e (TUint 256);
            { fo with value = true }, fo.value
        | "gas", KExtContractFun ->
            expect_expression_type opt env e (TUint 256);
            { fo with gas = true }, fo.gas
        | "salt", KNewContract ->
            expect_expression_type opt env e (TFixBytes 32);
            { fo with salt = true }, fo.salt
        | "gas", KNewContract ->
            error pos "Function call option \"%s\" cannot \
                       be used with \"new\""
              (Ident.to_string id);
        | "salt", KExtContractFun ->
            error pos "Function call option \"%s\" can \
                       only be used with \"new\""
              (Ident.to_string id);
            (* FREETON *)
            (* TODO: check that mandatory fields are provided *)
        | "pubkey", ( KNewContract | KExtContractFun )
           ->
            expect_expression_type opt env e
              ( TOptional (TUint 256));
            fo, false (* TODO *)
        | "code", KNewContract  ->
            expect_expression_type opt env e (TAbstract TvmCell);
            fo, false (* TODO *)
        | "flag", ( KExtContractFun | KNewContract | KReturn )  ->
            expect_expression_type opt env e (TUint 8);
            fo, false (* TODO *)
        | "varInit", KNewContract  ->
            fo, false (* TODO *)
        | "abiVer", KExtContractFun  ->
            expect_expression_type opt env e (TUint 8);
            fo, false (* TODO *)
        | "extMsg", KExtContractFun  ->
            expect_expression_type opt env e TBool ;
            fo, false (* TODO *)
        | "sign", KExtContractFun  ->
            expect_expression_type opt env e TBool ;
            fo, false (* TODO *)
        | "bounce", ( KExtContractFun | KNewContract | KReturn )  ->
            expect_expression_type opt env e TBool ;
            fo, false (* TODO *)
        | "stateInit", KNewContract  ->
            expect_expression_type opt env e (TAbstract TvmCell) ;
            fo, false (* TODO *)
        | "wid", KNewContract  ->
            expect_expression_type opt env e (TInt 8) ;
            fo, false (* TODO *)
        | "time", KExtContractFun  ->
            expect_expression_type opt env e (TUint 64) ;
            fo, false (* TODO *)
        | "expire", KExtContractFun  ->
            expect_expression_type opt env e (TUint 64) ;
            fo, false (* TODO *)
        | "callbackId", KExtContractFun  ->
            expect_expression_type opt env e (TUint 64) ;
            fo, false (* TODO *)
        | "callback", KExtContractFun  ->
            fo, false (* TODO *)
        | "onErrorId", KExtContractFun  ->
            expect_expression_type opt env e (TUint 64) ;
            fo, false (* TODO *)
        | _, KOther ->
            error pos "Function call options can only be set on \
                       external function calls or contract creations"
              (Ident.to_string id);
        | _ ->
            error pos "Unknown option \"%s\". Valid options are \
                       \"salt\", \"value\" and \"gas\""
              (Ident.to_string id);
      in
      if already_set then
        error pos "Option \"%s\" has already been set"
          (Ident.to_string id);
      fo
    ) fo opts

let () =
  Solidity_typechecker.type_options_ref := type_options_fun
