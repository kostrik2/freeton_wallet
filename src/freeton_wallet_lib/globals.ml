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

open EzFile.OP

let verbosity = ref 1
let command = "ft"
let about = "ft COMMAND COMMAND-OPTIONS"

let ft_home = match Sys.getenv "FT_HOME" with
  | exception _ -> None
  | dir -> Some dir

let is_alpine = match ft_home with
  | None -> Sys.file_exists "/etc/alpine-release"
  | Some _ -> false

let use_ton_sdk = match Sys.getenv "FT_USE_TONOS" with
  | exception Not_found -> true
  | "no" -> true
  | _ -> false

let ft_dir =
  match ft_home with
  | Some dir -> dir
  | None ->
      let homedir =
        if is_alpine then
          "/user"
        else
          Sys.getenv "HOME"
      in
      homedir // ".ft"

let config_file = ft_dir // "config.json"

let contracts_dir = ft_dir // "contracts"
let code_hash_dir = ft_dir // "code_hash"

let git_dir = ft_dir // "GIT"
let doc_dir = ft_dir // "doc"

let bin_dir =
  if is_alpine then
    "/bin"
  else
    ft_dir // "bin"

let () =
  if is_alpine then
    Unix.chdir "/local"
