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

val save : Types.config -> unit
val config : unit -> Types.config
val sandbox_keys : Types.key list

val print : unit -> unit

val set_temporary_switch : string -> unit
val set_switch : Types.config -> string -> unit

val current_network : Types.config -> Types.network
val current_node : Types.config -> Types.node
val loaded : unit -> bool

val load_wallet : Types.network -> unit

val repos : Types.config -> Types.repos
val default_repos : Types.repos

val known_networks : Types.network list
